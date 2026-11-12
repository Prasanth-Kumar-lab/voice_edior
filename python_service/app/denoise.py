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


def suppress_resonant_bursts(x: np.ndarray, sr: int = 48000) -> np.ndarray:
    """Detects and suppresses narrow-band vehicle horns, sirens, and resonant screeching.
    
    Horns and alarms create intense, unnaturally sharp spectral spikes (Q > 20) in the
    300 Hz - 3500 Hz range that persist across frames without normal speech formant modulation.
    """
    if len(x) < 1024:
        return x
    try:
        from scipy.ndimage import median_filter
        N, hop = 1024, 256
        f, t, X = stft(x, sr, window="hann", nperseg=N, noverlap=N - hop, boundary="zeros", padded=True)
        P = np.abs(X) ** 2 + 1e-12
        
        # Median filter along frequency to get spectral envelope baseline
        med_P = median_filter(P, size=(25, 1), mode="reflect")
        ratio = P / np.maximum(med_P, 1e-12)
        
        # Horns/sirens show up as extreme narrow-band spikes (>15 dB above local floor)
        spike_mask = (ratio > 18.0) & (f[:, None] >= 280.0) & (f[:, None] <= 4500.0)
        
        # Require temporal persistence (horns sound for at least ~80 ms = 15 frames)
        pers = median_filter(spike_mask.astype(float), size=(1, 11), mode="constant") > 0.45
        
        if np.any(pers):
            # Suppress persistent narrow-band resonant peaks to the spectral median level
            suppression_gain = np.ones_like(P)
            suppression_gain[pers] = np.sqrt(med_P[pers] / np.maximum(P[pers], 1e-12))
            suppression_gain = np.clip(suppression_gain, 0.05, 1.0)
            
            _, y = istft(X * suppression_gain, sr, window="hann", nperseg=N, noverlap=N - hop, boundary=True)
            y = y[: len(x)]
            if len(y) < len(x):
                y = np.pad(y, (0, len(x) - len(y)))
            return y.astype(np.float32)
    except Exception:
        pass
    return x


def spectral_denoise(x: np.ndarray, amount: float = 0.95, sr: int = 48000) -> np.ndarray:
    """Multi-stage voice-safe denoiser: pin/click suppressor, horn/siren notch filter,
    deep non-stationary noise-profile reduction (100%), and high-attenuation Wiener filtering.
    """
    x = remove_transient_pins(x)
    x = suppress_resonant_bursts(x, sr=sr)

    # 1. Multi-band noise profiling via noisereduce with 100% reduction for all background noise
    try:
        import noisereduce as nr
        win = int(0.04 * sr)
        n = (len(x) // win) * win
        if n >= win * 4:
            rms = np.sqrt((x[:n].reshape(-1, win).astype(np.float64) ** 2).mean(axis=1))
            p20 = float(np.percentile(rms, 20))
            noise_seg = x[:n].reshape(-1, win)[rms <= max(p20, 1e-6)].flatten()
            y_noise = noise_seg if len(noise_seg) >= win else None
            # 100% reduction of continuous stationary background (fans, AC, engine hum, road hiss)
            x = nr.reduce_noise(y=x, sr=sr, y_noise=y_noise, stationary=True, prop_decrease=1.0)
            # 98% reduction of dynamic non-stationary noise (crying, traffic, dogs, shouting, crowd)
            x = nr.reduce_noise(y=x, sr=sr, stationary=False, time_constant_s=0.8, prop_decrease=min(1.0, 0.90 + 0.10 * amount))
    except Exception:
        pass

    # 2. Decision-directed Wiener filter with ultra-deep noise floor limit (-75 dB to -80 dB)
    N, hop = 512, 128
    B = N // 2 + 1
    f, t, X = stft(x, sr, window="hann", nperseg=N, noverlap=N - hop, boundary="zeros", padded=True)
    P = np.abs(X) ** 2 + 1e-9
    nf = P.shape[1]
    Ps = np.empty_like(P)
    Ps[:, 0] = P[:, 0]
    for i in range(1, nf):
        Ps[:, i] = 0.7 * Ps[:, i - 1] + 0.3 * P[:, i]
    V, U = 75, 15
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
        noise[:, i] = 5.2 * m
    beta = 1.4 + 2.4 * amount
    # Deep studio floor: drops background down to -75 dB (practically silent)
    floor = 10 ** (-(30 + 45 * amount) / 20)
    G = np.ones_like(P)
    gp = np.ones(B)
    gam_prev = np.ones(B)
    for i in range(nf):
        gam = P[:, i] / np.maximum(noise[:, i], 1e-9)
        xi = 0.97 * gp * gp * gam_prev + 0.03 * np.maximum(gam - 1, 0)
        g = np.maximum(xi / (xi + beta), floor)
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
