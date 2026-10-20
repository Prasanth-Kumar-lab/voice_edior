"""Pipeline tests on synthetic material (run: python -m unittest discover -s tests). Uses DeepFilterNet if installed."""
import os
import sys
import unittest

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from app import loudness as ld  # noqa: E402
from app.audio_io import read_audio, write_wav  # noqa: E402
from app.pipelines import enhance  # noqa: E402
from app.pitch import analyze_voice  # noqa: E402

SR = 48000


def synth_voice(f0: float, secs: float = 10.0, seed: int = 1, harmonics: int = 19):
    """Syllables of a harmonic voice with vibrato and formant-ish tilt, separated by pauses."""
    n = int(secs * SR)
    y = np.zeros(n)
    mask = np.zeros(n, bool)
    t0 = 0.6
    k = 0
    while t0 < secs - 1.0:
        dur = 0.5 + 0.1 * (k % 3)
        i0, i1 = int(t0 * SR), int((t0 + dur) * SR)
        tt = np.arange(i1 - i0) / SR
        ph = 2 * np.pi * np.cumsum(f0 + 3 * np.sin(2 * np.pi * 5.5 * tt)) / SR
        env = np.minimum(1, np.minimum(tt / 0.03, (dur - tt) / 0.06))
        s = sum((1 / h ** 1.1) * np.sin(h * ph) for h in range(1, harmonics + 1))
        y[i0:i1] += s * env
        mask[i0:i1] = True
        t0 += dur + 0.45
        k += 1
    return (y / np.max(np.abs(y)) * 0.3).astype(np.float32), mask


def noisy(f0: float, snr_db: float = 14.0, harmonics: int = 19):
    v, mask = synth_voice(f0, harmonics=harmonics)
    rng = np.random.default_rng(3)
    t = np.arange(len(v)) / SR
    hiss = rng.standard_normal(len(v))
    hum = sum(np.sin(2 * np.pi * 50 * k * t) / k for k in range(1, 5))
    n = hiss / hiss.std() + 0.5 * hum / hum.std()
    n *= np.sqrt(np.mean(v[mask] ** 2)) * 10 ** (-snr_db / 20) / n.std()
    return (v + n).astype(np.float32), v, mask


def level_db(x, m):
    return 10 * np.log10(np.mean(x[m] ** 2) + 1e-12)


class PipelineTests(unittest.TestCase):
    def test_podcast_cleans_background_and_hits_broadcast_loudness(self):
        x, _, mask = noisy(130.0)
        y, rep = enhance("podcast", x, SR)
        far = ~np.convolve(mask.astype(float), np.ones(14400), "same").astype(bool)   # >150 ms from any voice
        drop = (level_db(x, far) - level_db(x, mask)) - (level_db(y, far) - level_db(y, mask))
        self.assertGreater(drop, 25.0, f"background only {drop:.1f} dB cleaner relative to the voice")
        # The synthetic voice is far peakier than speech, so the -1 dBTP ceiling may cap loudness slightly below target.
        self.assertAlmostEqual(rep["lufs_out"], -16.0, delta=2.5)
        self.assertLessEqual(rep["true_peak_db"], -0.9)
        self.assertEqual(y.ndim, 1)

    def test_vocals_detect_pitch_and_master_for_streaming(self):
        x, _, _ = noisy(220.0)
        y, rep = enhance("vocals", x, SR)
        self.assertEqual(rep["voice_type"], "alto")
        self.assertAlmostEqual(rep["f0_median_hz"], 220.0, delta=8.0)
        self.assertAlmostEqual(rep["lufs_out"], -14.0, delta=0.6)
        self.assertLessEqual(rep["true_peak_db"], -0.9)

    def test_voice_types(self):
        for f0, expect in ((95.0, "bass"), (130.0, "baritone"), (170.0, "tenor"), (220.0, "alto"), (280.0, "mezzo"), (400.0, "soprano")):
            v, _ = synth_voice(f0, 6.0)
            self.assertEqual(analyze_voice(v)["voice_type"], expect, f"{f0} Hz")

    def test_tone_presets_shape_the_spectrum(self):
        x, _, _ = noisy(200.0, 30.0)

        def tilt(tone):
            y, _ = enhance("vocals", x, SR, eq=tone)
            sp = np.abs(np.fft.rfft(y)) ** 2
            f = np.fft.rfftfreq(len(y), 1 / SR)
            return 10 * np.log10(sp[(f > 80) & (f < 400)].sum()) - 10 * np.log10(sp[(f > 6000) & (f < 16000)].sum())

        natural, warm, bright = tilt("natural"), tilt("warm"), tilt("bright")
        self.assertGreater(warm, natural, "Warm should carry more low end than Natural")
        self.assertLess(bright, natural, "Bright should carry more highs than Natural")

    def test_space_presets_are_stereo_and_dry_is_mono(self):
        x, _, _ = noisy(200.0, 30.0)
        dry, _ = enhance("vocals", x, SR, space="dry")
        self.assertEqual(dry.ndim, 1)
        for space in ("room", "plate", "hall", "wide"):
            y, rep = enhance("vocals", x, SR, space=space)
            self.assertEqual(y.ndim, 2, space)
            self.assertEqual(y.shape[1], 2)
            self.assertAlmostEqual(rep["lufs_out"], -14.0, delta=0.8, msg=space)
            self.assertLessEqual(rep["true_peak_db"], -0.9, space)
            self.assertGreater(len(y), len(dry), "reverb tail should extend the file")

    def test_podcast_enhance_levels_add_air_and_stay_loud_and_safe(self):
        x, _, _ = noisy(130.0, 30.0, harmonics=60)

        def air(level):
            y, rep = enhance("podcast", x, SR, level=level)
            sp = np.abs(np.fft.rfft(y)) ** 2
            f = np.fft.rfftfreq(len(y), 1 / SR)
            self.assertLessEqual(rep["true_peak_db"], -0.9, level)
            return 10 * np.log10(sp[(f > 6000) & (f < 16000)].sum() / sp[(f > 150) & (f < 5000)].sum())

        natural, enhanced, mx = air("natural"), air("enhanced"), air("max")
        self.assertGreater(enhanced, natural + 1.0, "Enhanced should add air over Natural")
        self.assertGreater(mx, enhanced, "Studio Max should be brighter than Enhanced")

    def test_podcast_tone_filters_shape_the_spectrum(self):
        x, _, _ = noisy(130.0, 30.0, harmonics=40)

        def tilt(tone):
            y, _ = enhance("podcast", x, SR, eq=tone)
            if y.ndim == 2:
                y = y.mean(axis=1)
            sp = np.abs(np.fft.rfft(y)) ** 2
            f = np.fft.rfftfreq(len(y), 1 / SR)
            return 10 * np.log10(sp[(f > 55) & (f < 250)].sum()) - 10 * np.log10(sp[(f > 2800) & (f < 12000)].sum())

        general, ultra_bass, crystal = tilt("general_bass"), tilt("ultra_bass"), tilt("crystal_treble")
        self.assertGreater(ultra_bass, general, "Ultra Bass should carry more low end than General + Bass")
        self.assertLess(crystal, general, "Crystal Treble should carry more treble than General + Bass")
        theatrical, rep = enhance("podcast", x, SR, eq="theatrical")
        self.assertEqual(theatrical.ndim, 2, "Theatrical should output stereo cinema-hall depth")
        self.assertTrue(rep.get("stereo"), "Theatrical report should mark stereo=True")

    def test_limiter_never_exceeds_ceiling(self):
        x = (0.9 * np.sin(2 * np.pi * 300 * np.arange(SR * 3) / SR)).astype(np.float32)
        y = ld.limit(x * 3.0, -1.0)
        self.assertLessEqual(ld.true_peak_db(y), -0.9)

    def test_wav_roundtrip_mono_and_stereo(self):
        x = (0.2 * np.sin(2 * np.pi * 440 * np.arange(SR) / SR)).astype(np.float32)
        for arr in (x, np.stack([x, x * 0.5], axis=1)):
            y, sr = read_audio(write_wav(arr, SR))
            self.assertEqual(sr, SR)
            self.assertEqual(len(y), len(x))


if __name__ == "__main__":
    unittest.main()
