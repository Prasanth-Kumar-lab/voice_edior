"""Noise removal: DeepFilterNet3 (neural) with a built-in spectral fallback so the service always works."""
from __future__ import annotations

import threading
from typing import Optional, Tuple

import numpy as np
from scipy.signal import istft, stft

_lock = threading.Lock()
_df = {"loaded": False, "model": None, "state": None, "enhance": None, "torch": None, "pf": None}


def _load_df() -> bool:
    with _lock:
        if _df["loaded"]:
            return _df["model"] is not None
        _df["loaded"] = True
        try:
            import torch
            from df.enhance import enhance, init_df

            torch.set_num_threads(max(1, min(4, torch.get_num_threads())))
            model, state, _ = init_df(log_level="ERROR")
            _df.update(model=model, state=state, enhance=enhance, torch=torch)
            try:  # post-filter variant: stronger suppression of what the network leaves behind
                pm, ps, _ = init_df(post_filter=True, log_level="ERROR")
                _df["pf"] = (pm, ps)
            except Exception:  # noqa: BLE001
                _df["pf"] = None
            return True
        except Exception:  # noqa: BLE001 - torch / deepfilternet not installed
            return False


def neural_available() -> bool:
    return _load_df()


def deep_denoise(x48: np.ndarray, atten_lim_db: Optional[float] = None, post_filter: bool = False) -> np.ndarray:
    """DeepFilterNet3 at 48 kHz. `atten_lim_db` caps how far noise may be pushed down (keeps ambience natural)."""
    torch = _df["torch"]
    model, state = (_df["pf"] if post_filter and _df["pf"] else (_df["model"], _df["state"]))
    chunk = 48000 * 90
    out = np.zeros_like(x48)
    pos = 0
    while pos < len(x48):
        seg = x48[pos : pos + chunk + 48000]
        t = torch.from_numpy(seg.astype(np.float32))[None]
        y = _df["enhance"](model, state, t, pad=True, atten_lim_db=atten_lim_db)[0].numpy()
        y = y[: len(seg)]
        take = min(chunk, len(x48) - pos)
        out[pos : pos + take] = y[:take]
        pos += take
    return out


def remove_transient_pins(x: np.ndarray, threshold: float = 4.2) -> np.ndarray:
    """Removes pin noises, tiny clicks, and sharp mic pops without softening speech transients."""
    if len(x) < 32:
        return x
    from scipy.signal import medfilt
    try:
        med = medfilt(x, 5)
        diff = x - med
        std = float(np.median(np.abs(diff)) * 1.4826 + 1e-9)
        spikes = np.abs(diff) > threshold * std
        if np.any(spikes):
            out = x.copy()
            out[spikes] = med[spikes]
            return out
    except Exception:
        pass
    return x


def spectral_denoise(x: np.ndarray, amount: float = 0.95, sr: int = 48000) -> np.ndarray:
    """Multi-stage vocal isolator & denoiser: pin/click suppressor, stationary + non-stationary
    music/noise reduction, decision-directed Wiener filtering, and high-band anti-'sshhh' suppression.
    """
    x = remove_transient_pins(x)

    # 1. Dual-pass noise & background music profiling via noisereduce if available
    try:
        import noisereduce as nr
        win = int(0.04 * sr)
        n = (len(x) // win) * win
        if n >= win * 4:
            rms = np.sqrt((x[:n].reshape(-1, win).astype(np.float64) ** 2).mean(axis=1))
            p25 = float(np.percentile(rms, 25))
            noise_seg = x[:n].reshape(-1, win)[rms <= max(p25, 1e-6)].flatten()
            y_noise = noise_seg if len(noise_seg) >= win else None
            x = nr.reduce_noise(
                y=x,
                sr=sr,
                y_noise=y_noise,
                stationary=True,
                prop_decrease=min(1.0, 0.94 + 0.05 * amount),
            )
            x = nr.reduce_noise(
                y=x,
                sr=sr,
                stationary=False,
                prop_decrease=min(0.95, 0.78 + 0.15 * amount),
            )
    except Exception:
        pass

    # 2. High-resolution STFT Wiener filter + high-band spectral flatness ('sshhh') suppressor
    N, hop = 1024, 256
    B = N // 2 + 1
    f, t, X = stft(x, sr, window="hann", nperseg=N, noverlap=N - hop, boundary="zeros", padded=True)
    P = np.abs(X) ** 2 + 1e-11
    nf = P.shape[1]

    # Identify non-vocal frames from vocal core energy (120 - 3600 Hz)
    v_mask = (f >= 120.0) & (f <= 3600.0)
    hi_mask = (f >= 3800.0) & (f <= 12000.0)
    v_db = 10.0 * np.log10(P[v_mask].mean(axis=0) + 1e-12)
    p20, p85 = float(np.percentile(v_db, 20)), float(np.percentile(v_db, 85))
    speech_thr = max(p20 + 4.5, p85 - 20.0)
    non_vocal = v_db <= speech_thr

    if np.sum(non_vocal) >= 4:
        global_floor = np.percentile(P[:, non_vocal], 65, axis=1)
    else:
        global_floor = np.percentile(P, 22, axis=1)

    # High-band spectral flatness per frame (detects white-noise 'sshhh' hiss above 3.8 kHz)
    P_hi = P[hi_mask] + 1e-12
    flat_hi = np.exp(np.mean(np.log(P_hi), axis=0)) / (np.mean(P_hi, axis=0) + 1e-12)
    flat_hi = np.clip(flat_hi, 0.0, 1.0)

    Ps = np.empty_like(P)
    Ps[:, 0] = P[:, 0]
    for i in range(1, nf):
        Ps[:, i] = 0.65 * Ps[:, i - 1] + 0.35 * P[:, i]
    V, U = 50, 12
    sub_min = []
    cur = Ps[:, 0].copy()
    noise = np.empty_like(P)
    from scipy.ndimage import median_filter

    for i in range(nf):
        cur = np.minimum(cur, Ps[:, i])
        m = cur
        for q in sub_min:
            m = np.minimum(m, q)
        if (i + 1) % V == 0:
            sub_min.append(cur.copy())
            cur = Ps[:, i].copy()
            sub_min = sub_min[-U:]
        m = np.minimum(m, median_filter(m, size=9, mode="nearest"))
        noise[:, i] = np.maximum(global_floor * 2.2, 3.2 * m)

    beta = 1.8 + 2.5 * amount
    floor = 10 ** (-(16 + 34 * amount) / 20)
    G = np.ones_like(P)
    gp = np.ones(B)
    gam_prev = np.ones(B)
    hi_bins = f >= 3800.0
    ultra_bins = f >= 12000.0

    for i in range(nf):
        over_sub = np.where(hi_bins, 1.8 + 2.5 * flat_hi[i], 1.0)
        gam = P[:, i] / np.maximum(noise[:, i] * over_sub, 1e-11)
        xi = 0.95 * gp * gp * gam_prev + 0.05 * np.maximum(gam - 1, 0)
        g = np.maximum(xi / (xi + beta), floor)
        # Suppress 'sshhh' hiss in high band when flat/noise-like
        hiss_atten = np.clip(1.0 - 0.78 * flat_hi[i], 0.10, 1.0)
        g = np.where(hi_bins, g * hiss_atten, g)
        g = np.where(ultra_bins, g * 0.15, g)
        g = np.convolve(np.pad(g, 1, mode="edge"), [0.25, 0.5, 0.25], "valid")
        G[:, i] = g
        gp, gam_prev = g, gam
    _, y = istft(X * G, sr, window="hann", nperseg=N, noverlap=N - hop, boundary=True)
    y = y[: len(x)]
    if len(y) < len(x):
        y = np.pad(y, (0, len(x) - len(y)))
    return y.astype(np.float32)


def denoise(x48: np.ndarray, strength: float = 1.0, atten_lim_db: Optional[float] = None,
            post_filter: bool = False) -> Tuple[np.ndarray, str]:
    if neural_available():
        y = deep_denoise(x48, atten_lim_db, post_filter)
        return y, "DeepFilterNet3"
    return spectral_denoise(x48, amount=min(1.0, 0.7 + 0.3 * strength)), "spectral"

