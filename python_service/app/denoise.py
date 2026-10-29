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

    # 2. High-resolution 2048-bin STFT Harmonic + Inter-Harmonic Valley + Anti-Bike Vocal Isolator
    N, hop = 2048, 512
    B = N // 2 + 1
    f, t, X = stft(x, sr, window="hann", nperseg=N, noverlap=N - hop, boundary="zeros", padded=True)
    P = np.abs(X) ** 2 + 1e-12
    amp = np.sqrt(P)
    nf = P.shape[1]
    bin_hz = float(sr) / N

    sub_mask = (f >= 20.0) & (f <= 95.0)
    v_mask = (f >= 95.0) & (f <= 3600.0)
    form_mask = (f >= 280.0) & (f <= 2800.0)
    hi_mask = (f >= 3800.0) & (f <= 11500.0)

    mean_sub = P[sub_mask].mean(axis=0) + 1e-12
    mean_v = P[v_mask].mean(axis=0) + 1e-12
    mean_form = P[form_mask].mean(axis=0) + 1e-12
    mean_cons = P[(f >= 2400.0) & (f <= 11000.0)].mean(axis=0) + 1e-12

    v_db = 10.0 * np.log10(mean_v)
    cons_ratio = mean_cons / (mean_sub + 0.25 * mean_v + 1e-12)

    # High-band spectral flatness per frame (detects white-noise 'sshhh' hiss above 3.8 kHz)
    P_hi = P[hi_mask] + 1e-12
    flat_hi = np.clip(np.exp(np.mean(np.log(P_hi), axis=0)) / (np.mean(P_hi, axis=0) + 1e-12), 0.0, 1.0)

    # Vectorized Harmonic Comb + Formant HNR Pitch Detector (distinguishes human voice from passing bikes)
    cand_f0_bins = np.arange(max(3.0, 75.0 / bin_hz), min(22.0, 460.0 / bin_hz), 0.25)
    best_scores = np.zeros(nf, dtype=np.float64)
    best_f_scores = np.zeros(nf, dtype=np.float64)
    inst_f0_bin = np.full(nf, 150.0 / bin_hz, dtype=np.float64)

    v_hi_bin = int(3600.0 / bin_hz)
    form_lo_bin = int(280.0 / bin_hz)
    form_hi_bin = int(2800.0 / bin_hz)

    # Local 3-bin max/min across frequency for peak/valley lookup
    from scipy.ndimage import maximum_filter1d, median_filter, minimum_filter1d
    amp_peak = maximum_filter1d(amp, size=3, axis=0)
    amp_val = minimum_filter1d(amp, size=3, axis=0)

    for step in cand_f0_bins:
        max_h = min(14, int(v_hi_bin / step))
        if max_h < 2:
            continue
        h_idx = np.arange(1, max_h + 1)
        hk = np.clip(np.round(h_idx * step).astype(int), 1, B - 2)
        vk = np.clip(np.round((h_idx + 0.5) * step).astype(int), 1, B - 2)

        h_sum = amp_peak[hk].sum(axis=0)
        v_sum = amp_val[vk].sum(axis=0)
        score = h_sum / (v_sum + 1e-6)

        f_sel = (hk >= form_lo_bin) & (hk <= form_hi_bin)
        if np.any(f_sel):
            f_score = amp_peak[hk[f_sel]].sum(axis=0) / (amp_val[vk[f_sel]].sum(axis=0) + 1e-6)
        else:
            f_score = score * 0.5

        combined = 0.55 * score + 0.45 * f_score
        better = combined > best_scores
        best_scores = np.where(better, combined, best_scores)
        best_f_scores = np.where(better, f_score, best_f_scores)
        inst_f0_bin = np.where(better, step, inst_f0_bin)

    rumble_ratio = mean_sub / (mean_form + 1e-12)
    bike_penalty = np.where(
        (rumble_ratio > 3.5) & (best_f_scores < 2.2),
        0.20,
        np.where((rumble_ratio > 1.8) & (best_f_scores < 1.7), 0.45, 1.0),
    )
    raw_harm = np.clip((best_scores - 1.45) / 1.65, 0.0, 1.0) * bike_penalty
    smooth_f0_bin = median_filter(inst_f0_bin, size=3)
    smooth_harm = np.convolve(np.pad(raw_harm, 1, mode="edge"), [0.25, 0.5, 0.25], "valid")

    p15, p85 = float(np.percentile(v_db, 15)), float(np.percentile(v_db, 85))
    dyn_range = max(8.0, p85 - p15)
    speech_thr = max(p15 + 4.5, p85 - min(22.0, dyn_range * 0.68))

    # Strict vocal frame classification (never opens on loud non-harmonic bike/traffic noise!)
    voiced_vowel = (v_db > speech_thr) & (smooth_harm > 0.23)
    # Attach brief unvoiced consonants only within 3 frames (~32 ms) of a confirmed voiced vowel
    near_vowel = maximum_filter1d(voiced_vowel.astype(int), size=7) > 0
    is_vocal = voiced_vowel | (near_vowel & (v_db > speech_thr - 3.5) & (cons_ratio > 0.45) & (flat_hi < 0.78))
    non_vocal = ~is_vocal

    if np.sum(non_vocal) >= 3:
        global_floor = np.percentile(P[:, non_vocal], 65, axis=1)
    else:
        global_floor = np.percentile(P, 20, axis=1)

    # Interpolate non-vocal noise across vocal words (tracks passing bikes & close-to-vocal noise!)
    nv_indices = np.where(non_vocal)[0]
    noise_interp = np.empty_like(P)
    if len(nv_indices) >= 2:
        t_all = np.arange(nf)
        for k in range(B):
            noise_interp[k] = np.interp(t_all, nv_indices, P[k, nv_indices])
    elif len(nv_indices) == 1:
        noise_interp[:] = P[:, nv_indices[0] : nv_indices[0] + 1]
    else:
        noise_interp[:] = global_floor[:, None]

    # Tight syllable gate: 1-frame look-ahead + 3-frame hold (32 ms) so zero noise trails after words
    hold_frames = max(2, int(0.032 * sr / hop))
    raw_gate = maximum_filter1d(is_vocal.astype(np.float64), size=hold_frames, origin=-(hold_frames // 2))
    raw_gate = np.concatenate([raw_gate[1:], raw_gate[-1:]])
    frame_gate = np.zeros(nf, dtype=np.float64)
    g_cur = 0.0
    for i in range(nf):
        coef = 0.25 if raw_gate[i] > g_cur else 0.62
        g_cur = coef * g_cur + (1.0 - coef) * raw_gate[i]
        frame_gate[i] = g_cur

    beta = 2.2 + 2.5 * amount
    active_floor = 10 ** (-(22 + 28 * amount) / 20)
    pause_floor = 10 ** (-68.0 / 20)
    G = np.ones_like(P)
    gp = np.ones(B)
    gam_prev = np.ones(B)
    hi_bins = f >= 3800.0
    ultra_bins = f >= 12000.0
    k_arr = np.arange(B, dtype=np.float64)
    P_min3 = minimum_filter1d(P, size=3, axis=0)

    for i in range(nf):
        f0b = smooth_f0_bin[i]
        harm_str = smooth_harm[i]
        v_gate = frame_gate[i]

        # Simultaneous inter-harmonic valley noise at (m + 0.5) * f0
        if f0b >= 2.5:
            m_low = np.maximum(0.0, np.floor(k_arr / f0b - 0.5))
            vb1 = np.clip(np.round((m_low + 0.5) * f0b).astype(int), 1, B - 2)
            vb2 = np.clip(np.round((m_low + 1.5) * f0b).astype(int), 1, B - 2)
            valley_noise = 0.5 * (P_min3[vb1, i] + P_min3[vb2, i])
            valley_noise = np.where(v_mask, valley_noise, global_floor)
        else:
            valley_noise = global_floor

        sub_cut_bin = max(int(20.0 / bin_hz), int(0.82 * f0b))
        base_noise = np.maximum(global_floor, np.maximum(noise_interp[:, i] * 0.85, valley_noise * 1.35))
        over_sub = np.where(
            k_arr < sub_cut_bin,
            8.0,
            np.where(hi_bins, 4.5 + 4.5 * flat_hi[i], 3.2),
        )
        gam = P[:, i] / np.maximum(base_noise * over_sub, 1e-12)
        xi = 0.92 * gp * gp * gam_prev + 0.08 * np.maximum(gam - 1.0, 0.0)
        g = np.maximum(xi / (xi + beta), active_floor)

        # Sub-fundamental rumble cut (< 0.82 * f0)
        sub_roll = np.clip(k_arr / max(1, sub_cut_bin), 0.0, 1.0) ** 2 * 0.04
        g = np.where(k_arr < sub_cut_bin, g * sub_roll, g)

        # Harmonic comb mask: strip simultaneous bike/music/noise between vocal harmonics
        if f0b >= 2.5:
            nearest_harm = np.round(k_arr / f0b) * f0b
            dist = np.abs(k_arr - nearest_harm) / f0b
            comb_str = max(0.35, harm_str)
            norm_dist = np.clip((dist - 0.16) / 0.34, 0.0, 1.0)
            valley_atten = 1.0 - 0.85 * comb_str * norm_dist
            in_comb = (k_arr >= sub_cut_bin) & (k_arr <= v_hi_bin) & (dist > 0.16)
            g = np.where(in_comb, g * valley_atten, g)

        # Per-bin spectral envelope gate (closes unused frequency bands during speech)
        bin_open = np.clip(xi / 1.6, 0.05, 1.0) ** 2
        g = np.where(xi < 1.6, g * bin_open, g)

        # Suppress 'sshhh' hiss in high band when flat/noise-like
        hiss_atten = np.clip(1.0 - 0.85 * flat_hi[i], 0.06, 1.0) * (gam / (1.2 + gam))
        g = np.where(hi_bins, g * hiss_atten, g)
        g = np.where(ultra_bins, g * 0.12, g)

        final_g = np.clip(pause_floor + (g - pause_floor) * v_gate, pause_floor, 1.0)
        final_g = np.convolve(np.pad(final_g, 1, mode="edge"), [0.25, 0.5, 0.25], "valid")
        G[:, i] = final_g
        gp, gam_prev = final_g, gam
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

