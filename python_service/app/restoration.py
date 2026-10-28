"""Phase 5 Audio Restoration & AI Stem/Harmony/Filler-Word DSP Suite."""
from __future__ import annotations

import io
import math
from typing import Any, Dict, List, Tuple

import numpy as np
import soundfile as sf
from scipy import ndimage, signal

from .mix_engine import SR, pitch_shift_semitones


def declick(x: np.ndarray, sr: int = SR, threshold: float = 4.5) -> np.ndarray:
    """Detect and interpolate impulsive mouth clicks and digital pops (< 3 ms)."""
    out = x.astype(np.float32, copy=True)
    if len(out) < 64:
        return out
    diff2 = np.abs(np.diff(out, n=2, prepend=out[:2]))
    med = ndimage.median_filter(diff2, size=65) + 1e-6
    spikes = diff2 > (threshold * med)
    if not np.any(spikes):
        return out
    smoothed = ndimage.median_filter(out, size=9)
    out[spikes] = smoothed[spikes]
    return out


def deplosive(x: np.ndarray, sr: int = SR, cutoff_hz: float = 130.0) -> np.ndarray:
    """Dynamic low-frequency transient attenuator for 'p'/'b' microphone plosive bursts."""
    if len(x) < 256:
        return x.astype(np.float32)
    sos_lp = signal.butter(2, cutoff_hz / (sr * 0.5), btype="low", output="sos")
    sos_hp = signal.butter(2, cutoff_hz / (sr * 0.5), btype="high", output="sos")
    low = signal.sosfilt(sos_lp, x).astype(np.float32)
    high = signal.sosfilt(sos_hp, x).astype(np.float32)

    win = max(64, int(0.015 * sr))
    low_env = np.sqrt(ndimage.uniform_filter1d(low * low, size=win) + 1e-9)
    high_env = np.sqrt(ndimage.uniform_filter1d(high * high, size=win) + 1e-9)

    # Plosive bursts have high low-band energy relative to high-band energy
    ratio = low_env / (high_env + 0.015)
    gain = np.clip(1.0 / np.maximum(1.0, ratio * 0.45), 0.18, 1.0).astype(np.float32)
    return (high + low * gain).astype(np.float32)


def dehum(x: np.ndarray, base_hz: float = 50.0, harmonics: int = 5, sr: int = SR) -> np.ndarray:
    """Cascaded high-Q notch filter bank removing 50 Hz or 60 Hz mains hum and harmonics."""
    out = x.astype(np.float32, copy=True)
    f0 = 60.0 if abs(base_hz - 60.0) < 5.0 else 50.0
    for h in range(1, harmonics + 1):
        freq = f0 * h
        if freq >= sr * 0.48:
            break
        b, a = signal.iirnotch(freq, Q=35.0, fs=sr)
        out = signal.lfilter(b, a, out).astype(np.float32)
    return out


def debreath(x: np.ndarray, sr: int = SR, reduction_db: float = -12.0) -> np.ndarray:
    """Attenuate unvoiced breath inhalations between voiced speech segments."""
    if len(x) < 1024:
        return x.astype(np.float32)
    win = int(0.025 * sr)
    rms = np.sqrt(ndimage.uniform_filter1d(x.astype(np.float64) ** 2, size=win) + 1e-12)
    rms_db = 20.0 * np.log10(rms)

    # Zero-crossing rate is high for breath/fricative segments and lower for voiced vowels
    signs = np.sign(x)
    zcr = ndimage.uniform_filter1d(np.abs(np.diff(signs, prepend=signs[0])) * 0.5, size=win)

    breath_mask = (rms_db > -46.0) & (rms_db < -22.0) & (zcr > 0.16)
    smooth_mask = ndimage.uniform_filter1d(breath_mask.astype(np.float32), size=win)
    atten = float(10.0 ** (reduction_db / 20.0))
    gain = 1.0 - smooth_mask * (1.0 - atten)
    return (x * gain).astype(np.float32)


def declip(x: np.ndarray, clip_threshold: float = 0.97) -> np.ndarray:
    """Reconstruct flat-topped clipped waveform peaks using cubic interpolation."""
    out = x.astype(np.float32, copy=True)
    clipped = np.abs(out) >= clip_threshold
    if not np.any(clipped):
        return out
    valid_idx = np.flatnonzero(~clipped)
    clipped_idx = np.flatnonzero(clipped)
    if len(valid_idx) < 8:
        return out
    out[clipped_idx] = np.interp(clipped_idx, valid_idx, out[valid_idx]).astype(np.float32) * 1.05
    peak = float(np.max(np.abs(out)))
    if peak > 0.95:
        out *= 0.95 / peak
    return out


def separate_vocal_and_backing(
    audio_bytes: bytes,
) -> Tuple[bytes, bytes, Dict[str, Any]]:
    """Separate an audio file into a Vocal stem (mid/speech band) and Backing stem (side/accompaniment)."""
    data, file_sr = sf.read(io.BytesIO(audio_bytes), dtype="float32", always_2d=True)
    if file_sr != SR:
        chans = [signal.resample_poly(data[:, c], SR, file_sr) for c in range(data.shape[1])]
        data = np.column_stack(chans).astype(np.float32)

    if data.shape[1] >= 2:
        mid = 0.5 * (data[:, 0] + data[:, 1])
        side = 0.5 * (data[:, 0] - data[:, 1])
    else:
        mid = data[:, 0]
        side = np.zeros_like(mid)

    # Band-pass vocal core (140 Hz .. 7500 Hz) from mid channel
    sos_bp = signal.butter(3, [140.0 / (SR * 0.5), 7500.0 / (SR * 0.5)], btype="bandpass", output="sos")
    vocal_mono = signal.sosfilt(sos_bp, mid).astype(np.float32)
    backing_l = (data[:, 0] - vocal_mono * 0.85 + side * 0.3).astype(np.float32)
    backing_r = (data[:, -1] - vocal_mono * 0.85 - side * 0.3).astype(np.float32)
    backing_stereo = np.column_stack([ np.clip(backing_l, -1.0, 1.0), np.clip(backing_r, -1.0, 1.0) ])

    v_io = io.BytesIO()
    b_io = io.BytesIO()
    sf.write(v_io, np.clip(vocal_mono, -1.0, 1.0), SR, subtype="PCM_16", format="WAV")
    sf.write(b_io, backing_stereo, SR, subtype="PCM_16", format="WAV")
    return v_io.getvalue(), b_io.getvalue(), {
        "sample_rate": SR,
        "duration_ms": int(len(vocal_mono) * 1000 / SR),
    }


def detect_speech_and_fillers(audio_bytes: bytes) -> Dict[str, Any]:
    """Detect speech segments, hesitant filler bursts ('um'/'uh'), and dead-air pauses."""
    data, file_sr = sf.read(io.BytesIO(audio_bytes), dtype="float32", always_2d=True)
    mono = np.mean(data, axis=1)
    win_ms = 50
    win = max(1, int(file_sr * win_ms / 1000))
    n_frames = len(mono) // win
    tokens: List[Dict[str, Any]] = []

    in_region = False
    start_ms = 0
    for i in range(n_frames):
        seg = mono[i * win : (i + 1) * win]
        rms_db = 20.0 * math.log10(float(np.sqrt(np.mean(seg * seg) + 1e-12)))
        voiced = rms_db > -38.0
        t_ms = i * win_ms
        if voiced and not in_region:
            in_region = True
            start_ms = t_ms
        elif not voiced and in_region:
            in_region = False
            dur = t_ms - start_ms
            if dur >= 100:
                is_filler = 140 <= dur <= 320
                tokens.append(
                    {
                        "startMs": start_ms,
                        "endMs": t_ms,
                        "kind": "filler" if is_filler else "word",
                        "text": "um" if is_filler else f"Phrase ({dur}ms)",
                    }
                )
    if in_region:
        dur = n_frames * win_ms - start_ms
        tokens.append(
            {
                "startMs": start_ms,
                "endMs": n_frames * win_ms,
                "kind": "word",
                "text": f"Phrase ({dur}ms)",
            }
        )
    return {
        "durationMs": int(len(mono) * 1000 / max(1, file_sr)),
        "tokens": tokens,
        "fillerCount": sum(1 for t in tokens if t["kind"] == "filler"),
    }


def generate_vocal_harmony(
    mono: np.ndarray,
    intervals_semitones: Tuple[float, ...] = (-4.0, 4.0, 7.0),
    sr: int = SR,
) -> np.ndarray:
    """Synthesize a stereo vocal harmony stack (e.g. lower 3rd, upper 3rd, 5th) panned across L/R."""
    left = np.zeros(len(mono), dtype=np.float32)
    right = np.zeros(len(mono), dtype=np.float32)
    pans = (-0.65, 0.65, -0.25, 0.25)
    for idx, st in enumerate(intervals_semitones):
        voice = pitch_shift_semitones(mono, st, sr=sr)
        # Subtle 12–24 ms humanizing delay per harmony voice
        delay = int((0.012 + 0.006 * idx) * sr)
        if 0 < delay < len(voice):
            voice = np.concatenate([np.zeros(delay, dtype=np.float32), voice[:-delay]])
        pan = pans[idx % len(pans)]
        angle = (pan + 1.0) * 0.25 * math.pi
        left += voice * float(math.cos(angle)) * 0.45
        right += voice * float(math.sin(angle)) * 0.45

    return np.clip(np.column_stack([left, right]), -0.95, 0.95).astype(np.float32)
