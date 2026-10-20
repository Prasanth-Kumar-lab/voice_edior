"""Late-reverberation suppression (Habets-style exponential decay model) for room-echo removal."""
from __future__ import annotations

import numpy as np
from scipy.signal import istft, stft


def dereverb(x: np.ndarray, sr: int = 48000, amount: float = 0.5, t60: float = 0.5) -> np.ndarray:
    if amount <= 0.01:
        return x
    N, hop = 1024, 256
    f, t, X = stft(x, sr, window="hann", nperseg=N, noverlap=N - hop, boundary="zeros", padded=True)
    P = np.abs(X) ** 2 + 1e-10
    D = max(1, int(0.045 * sr / hop))                 # early/late boundary ~45 ms
    delta = 3 * np.log(10) / t60                       # amplitude decay rate
    decay = np.exp(-2 * delta * D * hop / sr)          # power decay across D frames
    Ps = np.empty_like(P)
    Ps[:, 0] = P[:, 0]
    for i in range(1, P.shape[1]):
        Ps[:, i] = 0.6 * Ps[:, i - 1] + 0.4 * P[:, i]
    late = np.zeros_like(P)
    late[:, D:] = decay * Ps[:, :-D]
    earlier = np.zeros_like(P)
    earlier[:, D:] = Ps[:, :-D]
    # Only energy that is *falling* relative to D frames ago can be a reverberant tail. Sustained
    # vowels (level steady or rising) are left completely alone.
    falling = np.clip((0.85 - Ps / np.maximum(earlier, 1e-12)) / 0.5, 0.0, 1.0)
    falling[:, :D] = 0.0
    g_min = 10 ** (-(4 + 14 * amount) / 20)
    G = np.maximum(1 - (0.6 + 1.2 * amount) * late / P, g_min)
    G = 1.0 - falling * (1.0 - np.minimum(G, 1.0))
    # smooth the gain a little across time/frequency to avoid musical noise
    from scipy.ndimage import uniform_filter

    G = uniform_filter(G, size=(3, 3), mode="nearest")
    _, y = istft(X * G, sr, window="hann", nperseg=N, noverlap=N - hop, boundary=True)
    y = y[: len(x)]
    if len(y) < len(x):
        y = np.pad(y, (0, len(x) - len(y)))
    return y.astype(np.float32)
