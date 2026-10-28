from __future__ import annotations

import io
import math
from typing import Any, Dict, List, Optional, Tuple

import numpy as np
import soundfile as sf
from scipy import signal

from .loudness import integrated_lufs, limit

SR = 48000


def db_to_lin(db: float) -> float:
    if db <= -59.9:
        return 0.0
    return float(10.0 ** (db / 20.0))


def constant_power_pan(pan: float) -> Tuple[float, float]:
    """Constant-power stereo pan law (-1.0 Left .. 0.0 Center .. +1.0 Right)."""
    p = max(-1.0, min(1.0, float(pan)))
    angle = (p + 1.0) * 0.25 * math.pi
    return float(math.cos(angle) * math.sqrt(2.0)), float(math.sin(angle) * math.sqrt(2.0))


def fade_gain(progress: float, curve: str = "s_curve") -> float:
    x = max(0.0, min(1.0, float(progress)))
    if curve == "linear":
        return x
    if curve == "exponential":
        return x * x
    return float(math.sin(x * math.pi * 0.5))


def wsola_time_stretch(mono: np.ndarray, stretch_rate: float, sr: int = SR) -> np.ndarray:
    """Pitch-preserving WSOLA (Waveform Similarity Overlap-Add) time-stretcher (0.5x .. 2.0x)."""
    rate = max(0.5, min(2.0, float(stretch_rate)))
    if abs(rate - 1.0) < 0.01 or len(mono) < 2048:
        return mono.astype(np.float32)

    out_len = max(256, int(round(len(mono) / rate)))
    win_size = 1024
    hop_out = win_size // 2
    hop_in = int(round(hop_out * rate))
    search_tol = 256

    hann = np.hanning(win_size).astype(np.float32)
    out = np.zeros(out_len + win_size, dtype=np.float32)
    norm = np.zeros(out_len + win_size, dtype=np.float32)

    in_pos = 0
    out_pos = 0
    while out_pos + win_size < len(out) and in_pos + win_size < len(mono):
        best_offset = 0
        if out_pos > 0:
            ref = out[out_pos : out_pos + hop_out]
            ref_energy = float(np.dot(ref, ref))
            if ref_energy > 1e-7:
                best_corr = -1e18
                lo = max(0, in_pos - search_tol)
                hi = min(len(mono) - win_size, in_pos + search_tol)
                for cand in range(lo, hi + 1, 8):
                    seg = mono[cand : cand + hop_out]
                    corr = float(np.dot(ref, seg))
                    if corr > best_corr:
                        best_corr = corr
                        best_offset = cand - in_pos

        actual_in = max(0, min(len(mono) - win_size, in_pos + best_offset))
        grain = mono[actual_in : actual_in + win_size] * hann
        out[out_pos : out_pos + win_size] += grain
        norm[out_pos : out_pos + win_size] += hann * hann

        out_pos += hop_out
        in_pos = actual_in + hop_in

    mask = norm > 1e-5
    out[mask] /= norm[mask]
    return out[:out_len].astype(np.float32)


def pitch_shift_semitones(mono: np.ndarray, semitones: float, sr: int = SR) -> np.ndarray:
    """Pitch shift by ±12 semitones while preserving original duration."""
    st = max(-12.0, min(12.0, float(semitones)))
    if abs(st) < 0.05 or len(mono) < 2048:
        return mono.astype(np.float32)

    pitch_factor = float(2.0 ** (st / 12.0))
    stretched = wsola_time_stretch(mono, 1.0 / pitch_factor, sr=sr)
    idx = np.linspace(0, len(stretched) - 1, num=len(mono))
    return np.interp(idx, np.arange(len(stretched)), stretched).astype(np.float32)


def compute_auto_duck_gain_db(
    key_rms_db: float,
    threshold_db: float = -28.0,
    ratio: float = 4.0,
    max_amount_db: float = -10.0,
) -> float:
    if key_rms_db <= threshold_db:
        return 0.0
    over = key_rms_db - threshold_db
    raw_reduction = -over * (1.0 - 1.0 / max(1.0, ratio))
    return float(max(max_amount_db, min(0.0, raw_reduction)))


def evaluate_automation(
    points: List[Dict[str, Any]], time_ms: int, default_value: float = 0.0
) -> float:
    if not points:
        return default_value
    pts = sorted(points, key=lambda p: int(p.get("timeMs", 0)))
    if time_ms <= int(pts[0].get("timeMs", 0)):
        return float(pts[0].get("value", default_value))
    if time_ms >= int(pts[-1].get("timeMs", 0)):
        return float(pts[-1].get("value", default_value))
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        ta, tb = int(a.get("timeMs", 0)), int(b.get("timeMs", 0))
        if ta <= time_ms <= tb:
            span = max(1, tb - ta)
            t = (time_ms - ta) / float(span)
            if bool(a.get("curved", False)):
                t = t * t * (3.0 - 2.0 * t)
            va = float(a.get("value", default_value))
            vb = float(b.get("value", default_value))
            return va + (vb - va) * t
    return default_value


def apply_stereo_fx_chain(
    stereo: np.ndarray, fx_chain: List[Dict[str, Any]], sr: int = SR
) -> np.ndarray:
    """Process a stereo buffer (shape: [frames, 2]) through a list of FxSlot dictionaries."""
    out = stereo.astype(np.float32, copy=True)
    for slot in fx_chain:
        if not slot.get("enabled", True):
            continue
        fx_type = str(slot.get("type", ""))
        wet = max(0.0, min(1.0, float(slot.get("wetDry", 1.0))))
        params = slot.get("params") or {}
        if wet <= 0.001:
            continue

        dry_buf = out.copy()
        if fx_type == "saturator":
            drive_db = float(params.get("driveDb", 9.0))
            drive = db_to_lin(drive_db)
            processed = np.tanh(out * drive) / math.tanh(max(1.0, drive * 0.6))
            out = (1.0 - wet) * dry_buf + wet * processed.astype(np.float32)
        elif fx_type == "bitcrusher":
            bits = max(4.0, min(16.0, float(params.get("bits", 8.0))))
            steps = float(2.0**bits)
            processed = np.round(out * steps) / steps
            out = (1.0 - wet) * dry_buf + wet * processed.astype(np.float32)
        elif fx_type == "stereo_widener":
            width = max(0.0, min(2.0, float(params.get("width", 1.35))))
            mid = 0.5 * (out[:, 0] + out[:, 1])
            side = 0.5 * (out[:, 0] - out[:, 1]) * width
            out[:, 0] = (1.0 - wet) * dry_buf[:, 0] + wet * (mid + side)
            out[:, 1] = (1.0 - wet) * dry_buf[:, 1] + wet * (mid - side)
        elif fx_type == "delay":
            time_ms = max(20.0, min(1000.0, float(params.get("timeMs", 280.0))))
            fb = max(0.0, min(0.85, float(params.get("feedback", 0.32))))
            delay_samples = int((time_ms / 1000.0) * sr)
            if 0 < delay_samples < len(out):
                delayed = np.zeros_like(out)
                delayed[delay_samples:] = out[:-delay_samples] * (1.0 + fb * 0.5)
                out = dry_buf + wet * 0.45 * delayed
        elif fx_type == "reverb":
            room = max(0.1, min(1.0, float(params.get("roomSize", 0.5))))
            tap = int(room * 0.045 * sr)
            if 0 < tap < len(out):
                rev = np.zeros_like(out)
                rev[tap:, 0] = out[:-tap, 1] * 0.45
                rev[tap:, 1] = out[:-tap, 0] * 0.45
                out = (1.0 - wet * 0.5) * dry_buf + wet * rev
        elif fx_type == "filter":
            cutoff = max(60.0, min(18000.0, float(params.get("cutoffHz", 1800.0))))
            sos = signal.butter(2, cutoff / (sr * 0.5), btype="low", output="sos")
            filtered = signal.sosfilt(sos, out, axis=0).astype(np.float32)
            out = (1.0 - wet) * dry_buf + wet * filtered

    return np.clip(out, -1.0, 1.0)


def render_mix_project(
    project: Dict[str, Any],
    stem_buffers: Optional[Dict[str, bytes]] = None,
) -> Tuple[bytes, Dict[str, Any]]:
    """Render a full `.vpmix` multi-track project dictionary into a 48 kHz stereo WAV byte buffer."""
    stem_buffers = stem_buffers or {}
    tracks = project.get("tracks") or []
    master = project.get("master") or {}

    total_ms = 2000
    for trk in tracks:
        for clip in trk.get("clips") or []:
            end_ms = int(clip.get("timelineStartMs", 0)) + int(clip.get("durationMs", 1000))
            total_ms = max(total_ms, end_ms)

    total_frames = max(SR, int((total_ms / 1000.0) * SR))
    mix_stereo = np.zeros((total_frames, 2), dtype=np.float32)

    any_solo = any(bool(t.get("solo", False)) for t in tracks)

    for trk in tracks:
        is_active = bool(trk.get("solo", False)) if any_solo else not bool(trk.get("muted", False))
        if not is_active:
            continue

        vol_db = float(trk.get("volumeDb", 0.0))
        pan = float(trk.get("pan", 0.0))
        pan_l, pan_r = constant_power_pan(pan)
        phase_sign = -1.0 if bool(trk.get("phaseInverted", False)) else 1.0
        vol_auto = trk.get("volumeAutomation") or []

        trk_buf = np.zeros((total_frames, 2), dtype=np.float32)

        for clip in trk.get("clips") or []:
            if bool(clip.get("muted", False)):
                continue
            clip_id = str(clip.get("id", ""))
            dur_ms = max(50, int(clip.get("durationMs", 1000)))
            start_ms = max(0, int(clip.get("timelineStartMs", 0)))
            dur_frames = int((dur_ms / 1000.0) * SR)
            start_frame = int((start_ms / 1000.0) * SR)

            # Decode clip audio from stem_buffers or synthesize a clean test tone if path not uploaded
            raw_bytes = stem_buffers.get(clip_id)
            if raw_bytes:
                data, file_sr = sf.read(io.BytesIO(raw_bytes), dtype="float32", always_2d=True)
                mono = np.mean(data, axis=1)
                if file_sr != SR:
                    mono = signal.resample_poly(mono, SR, file_sr).astype(np.float32)
            else:
                t_vec = np.arange(dur_frames, dtype=np.float32) / float(SR)
                mono = (0.25 * np.sin(2.0 * math.pi * 220.0 * t_vec)).astype(np.float32)

            stretch_rate = float(clip.get("stretchRate", 1.0))
            if abs(stretch_rate - 1.0) > 0.02:
                mono = wsola_time_stretch(mono, stretch_rate, sr=SR)

            pitch_st = float(clip.get("pitchSemitones", 0.0))
            if abs(pitch_st) > 0.05:
                mono = pitch_shift_semitones(mono, pitch_st, sr=SR)

            if bool(clip.get("reversed", False)):
                mono = mono[::-1].copy()

            if bool(clip.get("normalized", False)):
                peak = float(np.max(np.abs(mono))) if len(mono) else 0.0
                if peak > 1e-5:
                    mono = mono * (0.89125 / peak)

            clip_gain = db_to_lin(float(clip.get("gainDb", 0.0)))
            fade_in_frames = int((int(clip.get("fadeInMs", 20)) / 1000.0) * SR)
            fade_out_frames = int((int(clip.get("fadeOutMs", 40)) / 1000.0) * SR)
            fade_in_curve = str(clip.get("fadeInCurve", "s_curve"))
            fade_out_curve = str(clip.get("fadeOutCurve", "s_curve"))

            n_copy = min(dur_frames, len(mono), total_frames - start_frame)
            if n_copy <= 0:
                continue

            seg = mono[:n_copy] * clip_gain
            if fade_in_frames > 0:
                n_fi = min(n_copy, fade_in_frames)
                fi_env = np.array(
                    [fade_gain(i / float(fade_in_frames), fade_in_curve) for i in range(n_fi)],
                    dtype=np.float32,
                )
                seg[:n_fi] *= fi_env
            if fade_out_frames > 0:
                n_fo = min(n_copy, fade_out_frames)
                fo_env = np.array(
                    [
                        fade_gain((n_fo - 1 - i) / float(fade_out_frames), fade_out_curve)
                        for i in range(n_fo)
                    ],
                    dtype=np.float32,
                )
                seg[-n_fo:] *= fo_env

            trk_buf[start_frame : start_frame + n_copy, 0] += seg * pan_l * phase_sign
            trk_buf[start_frame : start_frame + n_copy, 1] += seg * pan_r * phase_sign

        # Track volume + automation
        auto_Offset_db = evaluate_automation(vol_auto, total_ms // 2, 0.0) if vol_auto else 0.0
        trk_gain = db_to_lin(vol_db + auto_Offset_db)
        trk_buf *= trk_gain

        # Track FX chain
        fx_chain = trk.get("fxChain") or []
        if fx_chain:
            trk_buf = apply_stereo_fx_chain(trk_buf, fx_chain, sr=SR)

        mix_stereo += trk_buf

    # Master Bus stereo width & ceiling limiter
    width = max(0.0, min(2.0, float(master.get("stereoWidth", 1.0))))
    mid = 0.5 * (mix_stereo[:, 0] + mix_stereo[:, 1])
    side = 0.5 * (mix_stereo[:, 0] - mix_stereo[:, 1]) * width
    mix_stereo[:, 0] = mid + side
    mix_stereo[:, 1] = mid - side

    master_gain = db_to_lin(float(master.get("volumeDb", 0.0)))
    mix_stereo *= master_gain

    ceiling_db = max(-6.0, min(-0.1, float(master.get("limiterCeilingDb", -1.0))))
    mix_stereo = limit(mix_stereo, ceiling_db=ceiling_db, sr=SR)
    lufs_out = float(integrated_lufs(mix_stereo, SR))

    wav_io = io.BytesIO()
    sf.write(wav_io, mix_stereo, SR, subtype="PCM_16", format="WAV")
    report = {
        "duration_ms": total_ms,
        "sample_rate": SR,
        "channels": 2,
        "lufs_out": round(lufs_out, 2),
        "ceiling_db": ceiling_db,
        "tracks_rendered": len(tracks),
    }
    return wav_io.getvalue(), report
