"""Unit tests for Phase 3 Python multi-track Mix Engine (mix_engine.py & /mix/render)."""
from __future__ import annotations

import json
import math
import os
import sys
import unittest

os.environ["VP_IN_MEMORY_DB"] = "1"
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import numpy as np  # noqa: E402
from starlette.requests import Request  # noqa: E402

from app.jobs import store  # noqa: E402
from app.main import api_mix_render  # noqa: E402
from app.mix_engine import (  # noqa: E402
    SR,
    apply_stereo_fx_chain,
    compute_auto_duck_gain_db,
    constant_power_pan,
    evaluate_automation,
    fade_gain,
    pitch_shift_semitones,
    render_mix_project,
    wsola_time_stretch,
)
from app.pipelines import clean_stage_cache, style_from_cache  # noqa: E402
from app.restoration import (  # noqa: E402
    debreath,
    declick,
    declip,
    dehum,
    deplosive,
    detect_speech_and_fillers,
    generate_vocal_harmony,
    separate_vocal_and_backing,
)


def _mock_request(ip: str = "127.0.0.1") -> Request:
    scope = {
        "type": "http",
        "method": "POST",
        "path": "/mix/render",
        "headers": [],
        "client": (ip, 51000),
    }
    return Request(scope)


class MixEnginePythonTest(unittest.TestCase):
    def test_constant_power_pan_law(self) -> None:
        l_center, r_center = constant_power_pan(0.0)
        self.assertAlmostEqual(l_center, 1.0, places=4)
        self.assertAlmostEqual(r_center, 1.0, places=4)

        for pan in (-1.0, -0.5, 0.0, 0.5, 1.0):
            gl, gr = constant_power_pan(pan)
            self.assertAlmostEqual(gl * gl + gr * gr, 2.0, places=4)

    def test_fade_curves(self) -> None:
        for curve in ("linear", "exponential", "s_curve"):
            self.assertAlmostEqual(fade_gain(0.0, curve), 0.0, places=5)
            self.assertAlmostEqual(fade_gain(1.0, curve), 1.0, places=5)
            mid = fade_gain(0.5, curve)
            self.assertGreater(mid, 0.0)
            self.assertLess(mid, 1.0)

    def test_wsola_time_stretch_and_pitch_shift(self) -> None:
        t = np.arange(SR, dtype=np.float32) / float(SR)
        sine = (0.5 * np.sin(2.0 * math.pi * 220.0 * t)).astype(np.float32)

        half_speed = wsola_time_stretch(sine, 0.5, sr=SR)
        double_speed = wsola_time_stretch(sine, 2.0, sr=SR)
        self.assertAlmostEqual(len(half_speed), SR * 2, delta=128)
        self.assertAlmostEqual(len(double_speed), SR // 2, delta=128)

        shifted = pitch_shift_semitones(sine, 5.0, sr=SR)
        self.assertEqual(len(shifted), len(sine))

    def test_auto_duck_and_automation_interpolation(self) -> None:
        self.assertAlmostEqual(compute_auto_duck_gain_db(-45.0, -28.0, 4.0, -12.0), 0.0)
        duck = compute_auto_duck_gain_db(-16.0, -28.0, 4.0, -12.0)
        self.assertLess(duck, -5.0)
        self.assertGreaterEqual(duck, -12.0)

        pts = [
            {"timeMs": 0, "value": 0.0, "curved": False},
            {"timeMs": 1000, "value": -10.0, "curved": False},
        ]
        self.assertAlmostEqual(evaluate_automation(pts, 500), -5.0, places=3)

    def test_stereo_fx_chain_and_mix_render_endpoint(self) -> None:
        stereo = np.ones((4800, 2), dtype=np.float32) * 0.25
        fx = [
            {"type": "saturator", "enabled": True, "wetDry": 0.5, "params": {"driveDb": 6.0}},
            {"type": "bitcrusher", "enabled": True, "wetDry": 0.5, "params": {"bits": 8.0}},
            {"type": "stereo_widener", "enabled": True, "wetDry": 1.0, "params": {"width": 1.4}},
            {"type": "reverb", "enabled": True, "wetDry": 0.3, "params": {"roomSize": 0.5}},
            {"type": "delay", "enabled": True, "wetDry": 0.3, "params": {"timeMs": 40.0}},
        ]
        processed = apply_stereo_fx_chain(stereo, fx, sr=SR)
        self.assertEqual(processed.shape, (4800, 2))
        self.assertTrue(np.all(np.isfinite(processed)))

        project = {
            "schemaVersion": 1,
            "name": "Server Parity Mix",
            "master": {"volumeDb": 0.0, "stereoWidth": 1.1, "limiterCeilingDb": -1.0},
            "tracks": [
                {
                    "id": "trk_1",
                    "name": "Voice",
                    "volumeDb": 0.0,
                    "pan": -0.2,
                    "clips": [
                        {
                            "id": "c1",
                            "name": "Take 1",
                            "timelineStartMs": 0,
                            "durationMs": 1000,
                            "gainDb": 1.5,
                        }
                    ],
                }
            ],
        }
        wav_bytes, report = render_mix_project(project)
        self.assertTrue(wav_bytes.startswith(b"RIFF"))
        self.assertEqual(report["sample_rate"], SR)

        resp = api_mix_render(
            request=_mock_request(),
            payload={"project": project, "return_json": True},
            user=None,
        )
        self.assertEqual(resp.status_code, 200)
        body = json.loads(resp.body.decode("utf-8"))
        self.assertEqual(body["status"], "complete")
        self.assertGreater(body["wav_size_bytes"], 48000)

    def test_two_stage_clean_style_cache_and_cancel(self) -> None:
        t = np.arange(SR * 2, dtype=np.float32) / float(SR)
        speech = (0.3 * np.sin(2.0 * math.pi * 180.0 * t)).astype(np.float32)
        cache = clean_stage_cache("podcast", speech, SR, voice_isolation=True)
        self.assertIn("clean_48", cache)

        y_styled, report = style_from_cache(cache, eq="general_bass", level="enhanced", strength=0.6)
        self.assertEqual(len(y_styled), len(speech))
        self.assertTrue(report.get("cached_restyle"))
        self.assertAlmostEqual(float(report.get("strength", 0.0)), 0.6, places=2)

        # Verify unknown job cancel returns False
        self.assertFalse(store.cancel("nonexistent_job_id"))

    def test_phase5_restoration_and_ai_tools(self) -> None:
        t = np.arange(SR, dtype=np.float32) / float(SR)
        sig = (0.3 * np.sin(2.0 * math.pi * 220.0 * t)).astype(np.float32)
        # Inject an impulse click and hard clipping
        clicked = sig.copy()
        clicked[1200] = 0.99
        cleaned = declick(clicked, sr=SR)
        self.assertLess(abs(float(cleaned[1200])), 0.90)

        plosive_clean = deplosive(sig, sr=SR)
        self.assertEqual(len(plosive_clean), len(sig))

        hum_clean = dehum(sig, base_hz=50.0, sr=SR)
        self.assertEqual(len(hum_clean), len(sig))

        breath_clean = debreath(sig, reduction_db=-12.0, sr=SR)
        self.assertEqual(len(breath_clean), len(sig))

        clipped = np.clip(sig * 5.0, -0.96, 0.96).astype(np.float32)
        declipped = declip(clipped, clip_threshold=0.95)
        self.assertEqual(len(declipped), len(sig))

        from app.audio_io import write_wav

        wav_bytes = write_wav(sig, sr=SR)
        vocal_wav, backing_wav, meta = separate_vocal_and_backing(wav_bytes)
        self.assertTrue(vocal_wav.startswith(b"RIFF"))
        self.assertTrue(backing_wav.startswith(b"RIFF"))
        self.assertEqual(meta["sample_rate"], SR)

        segs = detect_speech_and_fillers(wav_bytes)
        self.assertGreaterEqual(len(segs["tokens"]), 1)

        harmony = generate_vocal_harmony(sig, intervals_semitones=(-4.0, 4.0, 7.0), sr=SR)
        self.assertEqual(harmony.shape, (len(sig), 2))


if __name__ == "__main__":
    unittest.main()
