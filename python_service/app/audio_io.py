"""Audio file helpers. The pipeline always works on mono float32 at 48 kHz."""
from __future__ import annotations

import io
from typing import Tuple

import numpy as np
from scipy.signal import resample_poly
from math import gcd

SR = 48000


def read_audio(data: bytes) -> Tuple[np.ndarray, int]:
    """Decode WAV/FLAC/OGG bytes to mono float32 + original sample rate."""
    try:
        import soundfile as sf

        x, sr = sf.read(io.BytesIO(data), dtype="float32", always_2d=True)
    except Exception:  # noqa: BLE001 - fall back to scipy for plain PCM WAV
        from scipy.io import wavfile

        sr, raw = wavfile.read(io.BytesIO(data))
        x = raw.astype(np.float32)
        if raw.dtype == np.int16:
            x /= 32768.0
        elif raw.dtype == np.int32:
            x /= 2147483648.0
        elif raw.dtype == np.uint8:
            x = (x - 128.0) / 128.0
        x = x.reshape(len(x), -1)
    return x.mean(axis=1).astype(np.float32), int(sr)


def resample(x: np.ndarray, src: int, dst: int) -> np.ndarray:
    if src == dst:
        return x
    g = gcd(src, dst)
    return resample_poly(x, dst // g, src // g).astype(np.float32)


def write_wav(x: np.ndarray, sr: int = SR, bits: int = 16) -> bytes:
    """Encode mono (n,) or stereo (n, 2) float audio as PCM WAV (TPDF dither for 16-bit)."""
    buf = io.BytesIO()
    x = np.clip(x, -1.0, 1.0)
    try:
        import soundfile as sf

        if bits == 16:
            rng = np.random.default_rng(0)
            d = (rng.random(x.shape) - rng.random(x.shape)) / 32768.0
            x = np.clip(x + d, -1.0, 1.0)
        sf.write(buf, x, sr, format="WAV", subtype="PCM_16" if bits == 16 else "PCM_24")
    except Exception:  # noqa: BLE001
        from scipy.io import wavfile

        wavfile.write(buf, sr, (x * 32767.0).astype(np.int16))
    return buf.getvalue()
