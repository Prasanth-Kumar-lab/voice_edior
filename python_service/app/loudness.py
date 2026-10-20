"""ITU-R BS.1770 loudness and a look-ahead true-peak limiter."""
from __future__ import annotations

import numpy as np
from scipy.ndimage import minimum_filter1d, uniform_filter1d
from scipy.signal import lfilter, resample_poly

# K-weighting at 48 kHz (BS.1770-4)
_B1 = [1.53512485958697, -2.69169618940638, 1.19839281085285]
_A1 = [1.0, -1.69065929318241, 0.73248077421585]
_B2 = [1.0, -2.0, 1.0]
_A2 = [1.0, -1.99004745483398, 0.99007225036621]


def integrated_lufs(x: np.ndarray, sr: int = 48000) -> float:
    if sr != 48000:
        raise ValueError("loudness expects 48 kHz")
    chans = [x] if x.ndim == 1 else [x[:, c] for c in range(x.shape[1])]
    ks = [lfilter(_B2, _A2, lfilter(_B1, _A1, c.astype(np.float64))) for c in chans]
    block = int(0.4 * sr)
    hop = int(0.1 * sr)
    if len(ks[0]) < block:
        return -70.0
    sq = sum(k * k for k in ks)          # BS.1770: channel powers add
    y = ks[0]
    c = np.concatenate([[0.0], np.cumsum(sq)])
    starts = np.arange(0, len(y) - block + 1, hop)
    ms = (c[starts + block] - c[starts]) / block
    lk = -0.691 + 10 * np.log10(ms + 1e-12)
    keep = lk > -70
    if not keep.any():
        return -70.0
    rel = -0.691 + 10 * np.log10(np.mean(ms[keep]) + 1e-12) - 10
    keep = lk > rel
    if not keep.any():
        return -70.0
    return float(-0.691 + 10 * np.log10(np.mean(ms[keep]) + 1e-12))


def true_peak_db(x: np.ndarray) -> float:
    up = resample_poly(x, 4, 1, axis=0)
    return float(20 * np.log10(np.max(np.abs(up)) + 1e-12))


def limit(x: np.ndarray, ceiling_db: float = -1.0, sr: int = 48000, lookahead_ms: float = 12.0,
          oversample: bool = True) -> np.ndarray:
    """Transparent look-ahead limiter; the result never exceeds the ceiling (inter-sample peaks included).

    gain = moving-average( running-min( ceiling / peak ) ). Because the averaging window equals the min
    window, the smoothed gain is always <= the gain required at every sample.
    """
    ceil = 10 ** (ceiling_db / 20)
    L = max(2, int(lookahead_ms * 1e-3 * sr))
    if x.ndim == 2:                                   # linked stereo: one gain curve for both channels
        mono_peak = np.max(np.abs(x), axis=1)
        g = limit(mono_peak.astype(np.float32), ceiling_db, sr, lookahead_ms, oversample) / np.maximum(mono_peak, 1e-9)
        return np.clip(x * g[:, None], -ceil, ceil).astype(np.float32)
    peak = np.abs(x).astype(np.float64)
    if oversample:                                    # catch inter-sample peaks too
        up = np.abs(resample_poly(x, 4, 1))
        n4 = (len(up) // 4) * 4
        up_peak = np.maximum.reduceat(up[:n4], np.arange(0, n4, 4))
        m = min(len(peak), len(up_peak))
        peak[:m] = np.maximum(peak[:m], up_peak[:m])
    g = np.minimum(1.0, ceil / np.maximum(peak, 1e-9))
    g = minimum_filter1d(g, size=2 * L + 1, mode="nearest")
    g = uniform_filter1d(g, size=2 * L + 1, mode="nearest")
    return np.clip(x * g, -ceil, ceil).astype(np.float32)


def normalize_lufs(x: np.ndarray, target: float, ceiling_db: float = -1.0, sr: int = 48000) -> np.ndarray:
    """Converges on the target loudness *through* the limiter (peaky material needs more gain than a single
    pass gives), then finishes with one inter-sample-peak-safe limiter pass."""
    cur = integrated_lufs(x, sr)
    if cur <= -69:
        return x
    gain_db = target - cur
    y = x
    for _ in range(5):
        y = limit(x * 10 ** (gain_db / 20), ceiling_db - 0.3, sr, oversample=False)
        err = target - integrated_lufs(y, sr)
        if abs(err) < 0.2:
            break
        gain_db += err * 1.1
    return limit(y, ceiling_db, sr)
