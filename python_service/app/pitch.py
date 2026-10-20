"""Pitch tracking (YIN) and voice-type analysis. Runs on 16 kHz audio, 10 ms hop."""
from __future__ import annotations

from typing import Dict

import numpy as np
from scipy.signal import resample_poly

_SR = 16000
_W = 512            # integration window (32 ms)
_HOP = 160          # 10 ms


def track_pitch(x48: np.ndarray, fmin: float = 65.0, fmax: float = 900.0) -> Dict[str, np.ndarray]:
    x = resample_poly(x48.astype(np.float64), 1, 3)
    n_frames = max(0, (len(x) - 2 * _W) // _HOP + 1)
    if n_frames < 3:
        return {"f0": np.zeros(0), "voiced": np.zeros(0, bool), "rms": np.zeros(0)}
    idx = np.arange(2 * _W)[None, :] + _HOP * np.arange(n_frames)[:, None]
    fr = x[idx]
    cs = np.concatenate([np.zeros((n_frames, 1)), np.cumsum(fr * fr, axis=1)], axis=1)
    tau_min = int(_SR / fmax)
    tau_max = min(int(_SR / fmin), _W - 1)
    A = np.fft.rfft(fr[:, :_W], 2 * _W, axis=1)
    B = np.fft.rfft(fr, 2 * _W, axis=1)
    r = np.fft.irfft(np.conj(A) * B, 2 * _W, axis=1)[:, : tau_max + 2]
    e0 = cs[:, _W][:, None]
    taus = np.arange(tau_max + 2)
    e_tau = cs[:, _W + taus] - cs[:, taus]
    d = e0 + e_tau - 2 * r
    d[:, 0] = 0
    cum = np.cumsum(d[:, 1:], axis=1)
    dn = np.ones_like(d)
    dn[:, 1:] = d[:, 1:] * taus[1:][None, :] / np.maximum(cum, 1e-12)

    rms = np.sqrt(np.mean(fr[:, :_W] ** 2, axis=1))
    f0 = np.zeros(n_frames)
    voiced = np.zeros(n_frames, bool)
    sub = dn[:, tau_min : tau_max + 1]
    below = sub < 0.15
    has = below.any(axis=1)
    first = np.where(has, below.argmax(axis=1), 0) + tau_min
    # descend to the local minimum after the first threshold crossing
    for i in np.nonzero(has)[0]:
        t = first[i]
        while t + 1 <= tau_max and dn[i, t + 1] < dn[i, t]:
            t += 1
        first[i] = t
    glob = sub.argmin(axis=1) + tau_min
    weak = (~has) & (sub.min(axis=1) < 0.28)
    tau = np.where(has, first, glob)
    ok = (has | weak) & (rms > 0.004)
    for i in np.nonzero(ok)[0]:
        t = int(tau[i])
        if 1 <= t < tau_max:
            a, b, c = dn[i, t - 1], dn[i, t], dn[i, t + 1]
            den = a - 2 * b + c
            shift = 0.5 * (a - c) / den if abs(den) > 1e-12 else 0.0
            f0[i] = _SR / (t + np.clip(shift, -1, 1))
            voiced[i] = True
    # drop isolated voiced frames, median-smooth octave jumps
    for i in range(1, n_frames - 1):
        if voiced[i] and not voiced[i - 1] and not voiced[i + 1]:
            voiced[i] = False
            f0[i] = 0
    return {"f0": f0, "voiced": voiced, "rms": rms}


def analyze_voice(x48: np.ndarray) -> Dict[str, object]:
    t = track_pitch(x48)
    f0, voiced = t["f0"], t["voiced"]
    if voiced.sum() < 20:
        return {"f0_median": 0.0, "f0_p10": 0.0, "f0_p90": 0.0, "voiced_ratio": 0.0, "voice_type": "unknown",
                "singing_score": 0.0, "track": t}
    v = f0[voiced]
    med = float(np.median(v))
    p10, p90 = float(np.percentile(v, 10)), float(np.percentile(v, 90))
    # voice type from the median fundamental (coarse, used only to steer EQ / de-ess / HPF)
    if med < 105:
        vt = "bass"
    elif med < 145:
        vt = "baritone"
    elif med < 190:
        vt = "tenor"
    elif med < 240:
        vt = "alto"
    elif med < 330:
        vt = "mezzo"
    else:
        vt = "soprano"
    # sustained, stable pitch + wide range suggests singing; flat talking has high frame-to-frame jitter
    cents = 1200 * np.abs(np.diff(np.log2(np.maximum(v, 1.0))))
    stable = float(np.mean(cents < 30))
    return {"f0_median": med, "f0_p10": p10, "f0_p90": p90, "voiced_ratio": float(voiced.mean()),
            "voice_type": vt, "singing_score": stable, "track": t}
