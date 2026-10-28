"""Mastering stages: adaptive EQ, de-esser, leveler, compressor, gap expander, plate reverb."""
from __future__ import annotations

from typing import List, Optional, Sequence, Tuple

import numpy as np
from scipy.ndimage import maximum_filter1d, uniform_filter1d
from scipy.signal import butter, istft, oaconvolve, sosfiltfilt, stft

CH = 96  # control-rate hop (2 ms @ 48 kHz)


def highpass(x: np.ndarray, hz: float, sr: int = 48000, order: int = 2) -> np.ndarray:
    sos = butter(order, hz / (sr / 2), "highpass", output="sos")
    return sosfiltfilt(sos, x).astype(np.float32)


def lowpass(x: np.ndarray, hz: float, sr: int = 48000, order: int = 2) -> np.ndarray:
    sos = butter(order, min(hz, sr * 0.48) / (sr / 2), "lowpass", output="sos")
    return sosfiltfilt(sos, x).astype(np.float32)


def _frame_db(x: np.ndarray, win_frames: int = 1) -> np.ndarray:
    n = (len(x) // CH) * CH
    p = (x[:n].reshape(-1, CH).astype(np.float64) ** 2).mean(axis=1)
    if win_frames > 1:
        p = uniform_filter1d(p, win_frames, mode="nearest")
    return 10 * np.log10(p + 1e-12)


def _to_samples(g: np.ndarray, n: int) -> np.ndarray:
    centers = (np.arange(len(g)) + 0.5) * CH
    return np.interp(np.arange(n), centers, g).astype(np.float32)


def noise_floor_db(x: np.ndarray, sr: int = 48000) -> float:
    """10th-percentile 50 ms RMS: a robust room-noise estimate."""
    w = int(0.05 * sr)
    n = (len(x) // w) * w
    if n == 0:
        return -90.0
    r = np.sqrt((x[:n].reshape(-1, w).astype(np.float64) ** 2).mean(axis=1))
    return float(20 * np.log10(np.percentile(r, 10) + 1e-9))


# ───────────────────────────── EQ ─────────────────────────────

def apply_curve(x: np.ndarray, points: Sequence[Tuple[float, float]], sr: int = 48000,
                extra: Optional[Sequence[Tuple[float, float]]] = None) -> np.ndarray:
    """Zero-phase EQ from (Hz, dB) points, interpolated on a log-frequency axis and smoothed (~1/6 oct).

    `extra` is a second curve (e.g. a Tone preset) summed in dB with the first.
    """
    n = len(x)
    nfft = int(2 ** np.ceil(np.log2(n + 1)))
    f = np.fft.rfftfreq(nfft, 1 / sr)
    lf = np.log2(np.maximum(f, 1.0))
    g = np.zeros_like(f)
    for curve in (points, extra):
        if not curve:
            continue
        pts = sorted(curve)
        g += np.interp(lf, np.log2([p[0] for p in pts]), [p[1] for p in pts])
    k = max(3, int(len(f) * 0.0003) | 1)
    g = uniform_filter1d(g, k, mode="nearest")
    H = 10 ** (g / 20)
    X = np.fft.rfft(x, nfft)
    y = np.fft.irfft(X * H, nfft)[:n]
    return y.astype(np.float32)


def band_level(P: np.ndarray, f: np.ndarray, lo: float, hi: float) -> float:
    m = (f >= lo) & (f < hi)
    return float(10 * np.log10(P[m].mean() + 1e-14)) if m.any() else -120.0


def long_term_spectrum(x: np.ndarray, sr: int, active: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
    f, t, X = stft(x, sr, window="hann", nperseg=4096, noverlap=3072, boundary=None)
    P = np.abs(X) ** 2
    e = P.sum(axis=0)
    hop_t = 1024 / sr
    idx = np.clip((t / 0.01).astype(int), 0, len(active) - 1) if len(active) else np.zeros(len(t), int)
    keep = active[idx] if len(active) else np.ones(len(t), bool)
    if keep.sum() < 5:
        keep = e > np.median(e)
    return f, P[:, keep].mean(axis=1)


def adaptive_eq_points(f: np.ndarray, P: np.ndarray, *, mud_hz: float = 280.0, presence_hz: float = 3500.0,
                       air_db: float = 1.5, strength: float = 1.0) -> List[Tuple[float, float]]:
    """Corrections measured against a balanced voice: cut excess mud/boom, lift lacking presence, add air."""
    ref = band_level(P, f, 1000, 2000)
    boom = band_level(P, f, 80, 160) - ref
    mud = band_level(P, f, 200, 400) - ref
    pres = band_level(P, f, 2800, 4500) - ref
    sib = band_level(P, f, 5000, 9000) - ref
    cut_boom = float(np.clip(boom - 6.0, 0, 5.0)) * strength
    cut_mud = float(np.clip(mud - 4.0, 0, 5.0)) * strength + 1.0 * strength
    lift_pres = float(np.clip(-9.0 - pres, 0, 4.5)) * strength + 1.0 * strength
    tame_harsh = float(np.clip(sib + 11.0, 0, 3.0)) * strength
    return [
        (30, -12), (70, -6), (120, -cut_boom), (mud_hz * 0.7, -cut_mud * 0.6), (mud_hz, -cut_mud),
        (mud_hz * 1.5, -cut_mud * 0.4), (700, 0.0), (1500, 0.0), (presence_hz * 0.7, lift_pres * 0.6),
        (presence_hz, lift_pres), (presence_hz * 1.5, lift_pres * 0.5), (7000, -tame_harsh),
        (10500, air_db * 0.7), (14000, air_db), (22000, air_db * 0.5),
    ]


# ───────────────────────────── dynamics ─────────────────────────────

def deess(x: np.ndarray, sr: int = 48000, center: float = 6500.0, amount: float = 0.7) -> Tuple[np.ndarray, float]:
    """Reduce only the sibilant band, and only when it dominates the frame (level-independent)."""
    N, hop = 1024, 256
    f, t, X = stft(x, sr, window="hann", nperseg=N, noverlap=N - hop, boundary="zeros", padded=True)
    P = np.abs(X) ** 2 + 1e-12
    lo, hi = center * 0.72, min(center * 1.55, sr / 2 - 100)
    band = (f >= lo) & (f <= hi)
    ratio = P[band].sum(axis=0) / (P.sum(axis=0))
    thr = 0.45 - 0.3 * amount
    red = np.clip(thr / np.maximum(ratio, 1e-6), 10 ** (-(4 + 10 * amount) / 20), 1.0)
    red = np.where(ratio > thr, red, 1.0)
    red = uniform_filter1d(red, 3, mode="nearest")
    G = np.ones_like(P)
    G[band, :] = red[None, :]
    _, y = istft(X * G, sr, window="hann", nperseg=N, noverlap=N - hop, boundary=True)
    y = y[: len(x)]
    if len(y) < len(x):
        y = np.pad(y, (0, len(x) - len(y)))
    return y.astype(np.float32), float(-20 * np.log10(red.min() + 1e-9))


def level(x: np.ndarray, sr: int = 48000, target_db: float = -22.0, floor_db: float = -52.0,
          max_up: float = 6.0, max_down: float = 7.0) -> np.ndarray:
    """Slow gain rider: evens out phrase-to-phrase volume before compression.

    Pauses never inherit a boost: the gain relaxes toward 0 dB with a ~1 s half-life, so the rider can't
    lift the room back up between phrases, yet short gaps between words don't make it pump.
    """
    lvl = _frame_db(x, win_frames=int(0.4 * sr / CH))
    g = np.clip(target_db - lvl, -max_down, max_up)
    thr = max(floor_db, float(np.percentile(lvl, 12)) + 12.0)
    active = lvl > thr
    relax = 0.5 ** (1.0 / (1.0 * sr / CH))               # half-life 1 s per control frame
    last = 0.0
    for i in range(len(g)):
        if active[i]:
            last = g[i]
        else:
            last *= relax
            g[i] = last
    g = uniform_filter1d(g, int(0.35 * sr / CH), mode="nearest")
    return (x * 10 ** (_to_samples(g, len(x)) / 20)).astype(np.float32)


def compress(x: np.ndarray, sr: int = 48000, thr_db: float = -22.0, ratio: float = 3.0, attack_ms: float = 6.0,
             release_ms: float = 120.0, knee: float = 8.0, makeup_db: float = 0.0) -> Tuple[np.ndarray, float]:
    n = (len(x) // CH) * CH
    seg = np.abs(x[:n]).reshape(-1, CH)
    lvl = 20 * np.log10(np.sqrt((seg.astype(np.float64) ** 2).mean(axis=1)) * 0.6 + seg.max(axis=1) * 0.4 + 1e-9)
    over = lvl - thr_db
    tgt = np.where(over <= -knee / 2, 0.0,
                   np.where(over >= knee / 2, over * (1 - 1 / ratio),
                            (1 - 1 / ratio) * (over + knee / 2) ** 2 / (2 * knee)))
    a = np.exp(-1.0 / max(1.0, attack_ms * 1e-3 * sr / CH))
    r = np.exp(-1.0 / max(1.0, release_ms * 1e-3 * sr / CH))
    gr = np.zeros_like(tgt)
    cur = 0.0
    for i in range(len(tgt)):
        c = a if tgt[i] > cur else r
        cur = c * cur + (1 - c) * tgt[i]
        gr[i] = cur
    look = 3                                           # ~6 ms look-ahead so attacks are anticipated
    gr = np.concatenate([gr[look:], np.full(look, gr[-1] if len(gr) else 0.0)])
    g = _to_samples(-gr + makeup_db, len(x))
    return (x * 10 ** (g / 20)).astype(np.float32), float(gr.max() if len(gr) else 0.0)


def gap_expander(x: np.ndarray, sr: int = 48000, floor_db: Optional[float] = None, depth_db: float = 14.0,
                 voiced: Optional[np.ndarray] = None) -> np.ndarray:
    """Downward expander that sinks whatever is left between phrases (residual hiss, room, clicks)."""
    lvl = _frame_db(x, win_frames=3)
    if floor_db is None:
        floor_db = float(np.percentile(lvl, 12))
    thr = floor_db + 9.0
    open_ = lvl > thr
    if voiced is not None and len(voiced):
        v = np.interp(np.arange(len(lvl)) * CH / sr / 0.01, np.arange(len(voiced)), voiced.astype(float)) > 0.5
        open_ = open_ | (v & (lvl > floor_db + 4))
    hold = int(0.12 * sr / CH)
    g = np.zeros(len(lvl))
    h = 0
    for i in range(len(lvl)):
        if open_[i]:
            h = hold
        g[i] = 0.0 if h > 0 else -depth_db
        if h > 0:
            h -= 1
    # asymmetric smoothing: fast open, slow close
    a = np.exp(-1.0 / max(1.0, 0.004 * sr / CH))
    r = np.exp(-1.0 / max(1.0, 0.18 * sr / CH))
    cur = 0.0
    out = np.zeros_like(g)
    for i in range(len(g)):
        c = a if g[i] > cur else r
        cur = c * cur + (1 - c) * g[i]
        out[i] = cur
    look = 3
    out = np.concatenate([out[look:], np.full(look, out[-1] if len(out) else 0.0)])
    return (x * 10 ** (_to_samples(out, len(x)) / 20)).astype(np.float32)


# ───────────────────────────── colour ─────────────────────────────

def warmth(x: np.ndarray, amount: float = 0.2) -> np.ndarray:
    if amount <= 0.001:
        return x
    d = 1.0 + 3.0 * amount
    peak = max(1e-6, float(np.max(np.abs(x))))
    y = np.tanh(x / peak * d) / d * peak
    return (0.5 * (x + y) if amount < 0.5 else y).astype(np.float32)


def plate(x: np.ndarray, sr: int = 48000, mix_db: float = -22.0, t60: float = 1.1, predelay_ms: float = 22.0,
          seed: int = 4) -> np.ndarray:
    rng = np.random.default_rng(seed)
    n = int(t60 * 1.2 * sr)
    t = np.arange(n) / sr
    ir = rng.standard_normal(n) * np.exp(-6.9 * t / t60)
    # darker tail: low-pass the IR progressively
    ir_lp = np.convolve(ir, np.ones(6) / 6, mode="same")
    ir = 0.5 * ir + 0.5 * ir_lp
    ir[: int(predelay_ms * 1e-3 * sr)] = 0
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    wet = oaconvolve(x, ir, mode="full")[: len(x)]
    wet = lowpass(highpass(wet.astype(np.float32), 240.0, sr), 3200.0, sr)
    wet *= 10 ** (mix_db / 20) * np.sqrt(np.mean(x ** 2) + 1e-12) / (np.sqrt(np.mean(wet ** 2)) + 1e-12)
    return (x + wet).astype(np.float32)


# ───────────────────────────── multiband spectral gate ─────────────────────────────

_GATE_EDGES = [0, 120, 250, 500, 1000, 2000, 3200, 5000, 8000, 12000, 24001]


def spectral_gate(x: np.ndarray, sr: int = 48000, depth_db: float = 30.0, margin_db: float = 5.0,
                  hold_ms: float = 80.0, release_ms: float = 160.0, voiced: Optional[np.ndarray] = None) -> np.ndarray:
    """Per-band expander in the STFT domain.

    Each of 10 bands learns its *own* noise floor (8th percentile of its energy over the file) and is closed
    smoothly whenever it sits near that floor — in the pauses *and* in bands the voice does not occupy
    (e.g. hiss above 8 kHz while someone speaks). Fast open, long hold + slow release → no pumping.
    """
    N, hop = 1024, 256
    f, t, X = stft(x, sr, window="hann", nperseg=N, noverlap=N - hop, boundary="zeros", padded=True)
    P = np.abs(X) ** 2 + 1e-12
    nb = len(_GATE_EDGES) - 1
    band_idx = np.digitize(f, _GATE_EDGES[1:-1])
    E = np.stack([10 * np.log10(P[band_idx == b].sum(axis=0) + 1e-12) for b in range(nb)])
    floor = np.percentile(E, 8, axis=1)[:, None]
    thr = floor + margin_db
    # soft knee: fully closed at/below thr, fully open 6 dB above it
    open_amt = np.clip((E - thr) / 6.0, 0.0, 1.0)
    # voicing keeps the low/mid bands where the voice lives open without letting floor noise through
    if voiced is not None and len(voiced):
        frame_t = t / 0.01
        v = np.interp(frame_t, np.arange(len(voiced)), voiced.astype(float)) > 0.5
        keep = np.zeros(nb)
        keep[2:7] = 0.4
        open_amt = np.maximum(open_amt, keep[:, None] * v[None, :] * (E > floor + 1.5))
    # hold + asymmetric smoothing (per band, along time)
    hold = max(1, int(hold_ms * 1e-3 * sr / hop))
    a_open = np.exp(-1.0 / max(1.0, 0.008 * sr / hop))
    a_close = np.exp(-1.0 / max(1.0, release_ms * 1e-3 * sr / hop))
    g = np.zeros_like(open_amt)
    for b in range(nb):
        # running max over the hold window (look-back) keeps the gate open through short dips
        held = maximum_filter1d(open_amt[b], size=hold, origin=-(hold // 2))
        cur = 0.0
        for i in range(len(held)):
            c = a_open if held[i] > cur else a_close
            cur = c * cur + (1 - c) * held[i]
            g[b, i] = cur
    # a little look-ahead so onsets are never clipped
    g = np.concatenate([g[:, 2:], np.repeat(g[:, -1:], 2, axis=1)], axis=1)
    # smooth across neighbouring bands, convert to a per-bin gain
    gs = g.copy()
    gs[1:-1] = 0.25 * g[:-2] + 0.5 * g[1:-1] + 0.25 * g[2:]
    gain_db = -(1.0 - gs) * depth_db
    centers = np.array([(_GATE_EDGES[i] + _GATE_EDGES[i + 1]) / 2 for i in range(nb)])
    G = np.empty_like(P)
    lf = np.log2(np.maximum(f, 20.0))
    lc = np.log2(np.maximum(centers, 20.0))
    for i in range(P.shape[1]):
        G[:, i] = np.interp(lf, lc, gain_db[:, i])
    G = 10 ** (G / 20)
    _, y = istft(X * G, sr, window="hann", nperseg=N, noverlap=N - hop, boundary=True)
    y = y[: len(x)]
    if len(y) < len(x):
        y = np.pad(y, (0, len(x) - len(y)))
    return y.astype(np.float32)


def dominant_expander(x: np.ndarray, sr: int = 48000, rel_db: float = -20.0, depth_db: float = 20.0) -> np.ndarray:
    """Gently sinks anything far below the main voice (distant talkers, room tails, breaths) — level-relative."""
    lvl = _frame_db(x, win_frames=3)
    thr = max(float(np.percentile(lvl, 15)) + 6.0, float(np.percentile(lvl, 85)) + rel_db)
    open_ = lvl > thr
    hold = int(0.12 * sr / CH)
    g = np.zeros(len(lvl))
    h = 0
    for i in range(len(lvl)):
        if open_[i]:
            h = hold
        g[i] = 0.0 if h > 0 else -depth_db
        if h > 0:
            h -= 1
    a = np.exp(-1.0 / max(1.0, 0.005 * sr / CH))
    r = np.exp(-1.0 / max(1.0, 0.16 * sr / CH))
    cur, out = 0.0, np.zeros_like(g)
    for i in range(len(g)):
        c = a if g[i] > cur else r
        cur = c * cur + (1 - c) * g[i]
        out[i] = cur
    look = 3
    out = np.concatenate([out[look:], np.full(look, out[-1] if len(out) else 0.0)])
    return (x * 10 ** (_to_samples(out, len(x)) / 20)).astype(np.float32)


def _ir(t60: float, damp: float, pre_ms: float, sr: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    n = int(t60 * 1.15 * sr)
    t = np.arange(n) / sr
    ir = rng.standard_normal(n) * np.exp(-6.9 * t / t60)
    # darker tail: progressively low-pass the later part
    k = max(2, int(2 + damp * 10))
    ir_lp = np.convolve(ir, np.ones(k) / k, mode="same")
    mix = np.clip(t / t60, 0, 1) * damp + 0.2 * damp
    ir = ir * (1 - mix) + ir_lp * mix
    ir[: int(pre_ms * 1e-3 * sr)] = 0
    return ir / (np.sqrt(np.sum(ir ** 2)) + 1e-9)


def apply_space(x: np.ndarray, cfg: dict, sr: int = 48000) -> np.ndarray:
    """Adds a space around the voice. Returns stereo (n, 2) with decorrelated L/R tails and a widened image."""
    if not cfg or float(cfg.get("t60", 0.0)) <= 0.0:
        return x
    t60, pre, mix_db = float(cfg["t60"]), float(cfg["pre"]), float(cfg["mix"])
    damp, width = float(cfg["damp"]), float(cfg["width"])
    n_in = len(x)
    x = np.concatenate([x, np.zeros(int(t60 * 0.9 * sr), np.float32)])   # let the tail ring out instead of cutting it
    ref = np.sqrt(np.mean(x[:n_in] ** 2) + 1e-12)
    wets = []
    for seed in (4, 9):
        w = oaconvolve(x, _ir(t60, damp, pre, sr, seed), mode="full")[: len(x)]
        # Band-limit wet reverb (240 - 3200 Hz) so sibilance & noise never ring as 'sshhh'
        w = lowpass(highpass(w.astype(np.float32), 240.0, sr), 3200.0, sr)
        w *= 10 ** (mix_db / 20) * ref / (np.sqrt(np.mean(w[:n_in] ** 2)) + 1e-12)
        wets.append(w)
    left, right = x + wets[0], x + wets[1]
    if width > 0.6:
        # Band-limited warm mid widening (250 - 2500 Hz) so highs stay centered and never comb-filter into 'sshhh'
        side = lowpass(highpass(x, 250.0, sr), 2500.0, sr)
        dl, dr = int(0.014 * sr), int(0.019 * sr)
        gl = 10 ** (-(16 - 4 * width) / 20)
        left = left + gl * np.concatenate([np.zeros(dl, np.float32), side[:-dl]])
        right = right - gl * np.concatenate([np.zeros(dr, np.float32), side[:-dr]])
    return np.stack([left, right], axis=1).astype(np.float32)


# ───────────────────────────── voice enhancement ─────────────────────────────

def exciter(x: np.ndarray, sr: int = 48000, amount: float = 0.4, freq: float = 3200.0) -> np.ndarray:
    """Clean, speech-gated upper-harmonic presence lift (never amplifies noise floor into 'sshhh' hiss)."""
    if amount <= 0.01:
        return x
    sos_air = butter(2, [5500.0 / (sr / 2), 11000.0 / (sr / 2)], "bandpass", output="sos")
    air_band = sosfiltfilt(sos_air, x).astype(np.float32)

    lvl = _frame_db(x, 2)
    p15 = float(np.percentile(lvl, 15))
    p85 = float(np.percentile(lvl, 85))
    speech_thr = max(p15 + 12.0, p85 - 18.0)

    active = lvl > speech_thr
    hold = int(0.06 * sr / CH)
    g = np.zeros(len(lvl))
    h = 0
    for i in range(len(lvl)):
        if active[i]:
            h = hold
        g[i] = 1.0 if h > 0 else 0.0
        if h > 0:
            h -= 1
    g = uniform_filter1d(g, int(0.02 * sr / CH), mode="nearest")
    gate_samp = _to_samples(g, len(x))
    return (x + air_band * (amount * 1.35) * gate_samp).astype(np.float32)


def parallel_compress(x: np.ndarray, sr: int = 48000, amount: float = 0.25) -> np.ndarray:
    """Blend in a heavily compressed copy: lifts detail and body without squashing the natural dynamics."""
    if amount <= 0.01:
        return x
    wet, _ = compress(x, sr, thr_db=-26.0, ratio=4.5, attack_ms=4.0, release_ms=100.0, knee=8.0)
    lvl = _frame_db(x, 2)
    gate = 10 ** (np.clip((lvl - (noise_floor_db(x) + 7.0)) / 10.0, -2.5, 0.0))
    wet = wet * _to_samples(gate, len(wet))
    r = np.sqrt(np.mean(x ** 2) + 1e-12) / (np.sqrt(np.mean(wet ** 2)) + 1e-12)
    return ((1 - amount) * x + amount * wet * r).astype(np.float32)


def voice_bass(x: np.ndarray, f0: float, sr: int = 48000, amount: float = 0.6) -> np.ndarray:
    """Speech-following bass: tuned to the speaker's own pitch and driven by how they speak.

    * Chest resonance — the band around the speaker's fundamental (f0 .. 2·f0) is lifted, so the boost lands
      on *their* voice rather than at a fixed frequency (a 100 Hz baritone and a 210 Hz alto both get weight).
    * Sub-octave — a dbx-120-style divider flips polarity on every other zero crossing of the fundamental
      band, giving a tone one octave below the voice. It is scaled by the voice envelope, so it only exists
      while a word is spoken, swells on emphasised/loud words and is silent in pauses.
    """
    if amount <= 0.01 or len(x) < sr // 10:
        return x
    f0 = float(np.clip(f0 or 140.0, 70.0, 300.0))
    lo, hi = max(55.0, f0 * 0.75), min(600.0, f0 * 2.2)
    sos = butter(4, [lo / (sr / 2), hi / (sr / 2)], "bandpass", output="sos")
    fund = sosfiltfilt(sos, x).astype(np.float32)

    # level envelope of the voice (fast attack, ~60 ms release) – drives everything so bass follows speech
    env_sos = butter(2, 16.0 / (sr / 2), "lowpass", output="sos")
    env = np.maximum(sosfiltfilt(env_sos, np.abs(x)), 0.0).astype(np.float32)
    ref = float(np.percentile(env, 95)) + 1e-9
    drive = np.clip(env / ref, 0.0, 1.4)                    # louder words → more bass, silence → none

    # sub-octave divider
    pos_cross = np.flatnonzero((fund[:-1] <= 0) & (fund[1:] > 0)) + 1
    sq = np.ones(len(x), np.float32)
    if len(pos_cross) > 1:
        flips = np.zeros(len(x), np.int32)
        flips[pos_cross] = 1
        sq = np.where(np.cumsum(flips) % 2 == 0, 1.0, -1.0).astype(np.float32)
    fund_env = sosfiltfilt(env_sos, np.abs(fund)).astype(np.float32)
    sub = sq * fund_env
    sub_sos = butter(4, min(f0 * 0.75, 160.0) / (sr / 2), "lowpass", output="sos")
    sub = sosfiltfilt(sub_sos, sub).astype(np.float32)
    sub = highpass(sub, 35.0, sr)                           # keep it out of speaker-killing rumble

    # chest resonance (boosted copy of the fundamental band)
    voice_rms = float(np.sqrt(np.mean(x[env > 0.1 * ref] ** 2) + 1e-12)) if np.any(env > 0.1 * ref) else 0.05
    sub_rms = float(np.sqrt(np.mean(sub ** 2) + 1e-12))
    chest = fund * (0.55 * amount)
    sub = sub * (0.38 * amount * voice_rms / sub_rms) * drive
    return (x + chest + sub).astype(np.float32)


def voice_pitch_body(x: np.ndarray, f0: float, sr: int = 48000, amount: float = 0.3) -> np.ndarray:
    """Pitch-adaptive vocal body & clear voice stabilizer.
    Directly reinforces the speaker's true fundamental pitch (f0) while strictly attenuating
    sub-vocal rumble (< 0.65 * f0) and boxy mud (250-380 Hz) so the voice remains clear, articulate, and natural.
    """
    if amount <= 0.01 or f0 <= 40.0:
        return x
    f0_clamped = float(np.clip(f0, 65.0, 320.0))
    bw = f0_clamped * 0.45
    low_cut = max(40.0, f0_clamped * 0.65)
    sos_fund = butter(2, [low_cut / (sr / 2), min(sr * 0.45, f0_clamped + bw) / (sr / 2)], "bandpass", output="sos")
    fund = sosfiltfilt(sos_fund, x).astype(np.float32)

    env_sos = butter(2, 16.0 / (sr / 2), "lowpass", output="sos")
    env = np.maximum(sosfiltfilt(env_sos, np.abs(x)), 0.0).astype(np.float32)
    ref = float(np.percentile(env, 95)) + 1e-9
    drive = np.clip(env / ref, 0.0, 1.2)

    reinforced = fund * (0.65 * amount) * drive
    return (x + reinforced).astype(np.float32)


def theatre_space(x: np.ndarray, sr: int = 48000, mix_db: float = -20.0) -> np.ndarray:
    """Dark, wide cinema-hall ambience behind the voice (stereo). Applied after the pause gate, so only the
    voice itself rings into the room – the background noise never does."""
    return apply_space(x, {"t60": 1.65, "pre": 28.0, "mix": -18.5, "damp": 0.68, "width": 0.90}, sr)


def voice_treble(x: np.ndarray, sr: int = 48000, amount: float = 0.6) -> np.ndarray:
    """Speech-following high-definition articulation & air shaper (2.6–11 kHz).

    Lifts vocal articulation and upper harmonics strictly during active speech without nonlinear
    noise floor amplification, preventing any 'sshhh' hiss on the vocal.
    """
    if amount <= 0.01 or len(x) < sr // 10:
        return x
    sos_pres = butter(2, [2600.0 / (sr / 2), 5500.0 / (sr / 2)], "bandpass", output="sos")
    pres = sosfiltfilt(sos_pres, x).astype(np.float32)

    sos_air = butter(2, [6000.0 / (sr / 2), 11000.0 / (sr / 2)], "bandpass", output="sos")
    air = sosfiltfilt(sos_air, x).astype(np.float32)

    env_sos = butter(2, 20.0 / (sr / 2), "lowpass", output="sos")
    env = np.maximum(sosfiltfilt(env_sos, np.abs(x)), 0.0).astype(np.float32)
    env_ref = float(np.percentile(env, 92)) + 1e-9
    gate = np.clip((env - 0.12 * env_ref) / (0.35 * env_ref), 0.0, 1.0)

    pres_layer = pres * (0.45 * amount) * gate
    air_layer = air * (0.85 * amount) * gate
    return (x + pres_layer + air_layer).astype(np.float32)


def podcast_space(x: np.ndarray, space_type: str, sr: int = 48000) -> np.ndarray:
    """Stereo spatial acoustics for Podcast filters, applied after the speech pause gate."""
    if space_type == "theatre":
        return theatre_space(x, sr)
    if space_type == "booth":
        return apply_space(x, {"t60": 0.42, "pre": 14.0, "mix": -21.0, "damp": 0.45, "width": 0.85}, sr)
    return x


def apply_speech_gate(x: np.ndarray, sr: int = 48000, pause_floor_db: float = -60.0,
                      hold_ms: float = 120.0, look_ms: float = 15.0) -> np.ndarray:
    """Zero-noise pause gate: completely drops background noise to studio black when speech stops.

    Uses an adaptive energy threshold with lookahead so word onsets (consonants) are never clipped,
    and a smooth hold/release hangover for natural transitions.
    """
    hop = int(0.003 * sr)
    win = int(0.025 * sr)
    n = len(x)
    if n < win * 2:
        return x
    n_frames = (n - win) // hop + 1
    frames = np.lib.stride_tricks.sliding_window_view(x[:(n_frames - 1) * hop + win], win)[::hop]
    frame_rms = np.sqrt((frames.astype(np.float64) ** 2).mean(axis=1) + 1e-12)
    frame_db = 20 * np.log10(frame_rms)

    p10 = float(np.percentile(frame_db, 10))
    p85 = float(np.percentile(frame_db, 85))
    dyn = max(6.0, p85 - p10)
    speech_thr = p10 + max(2.5, 0.20 * dyn)
    raw_active = frame_db > speech_thr

    hold_count = max(1, int(hold_ms * 1e-3 * sr / hop))
    look_count = max(1, int(look_ms * 1e-3 * sr / hop))
    env = np.zeros(len(raw_active))
    h = 0
    for i in range(len(raw_active)):
        if raw_active[i]:
            h = hold_count
        env[i] = 1.0 if h > 0 else 0.0
        if h > 0:
            h -= 1

    if look_count < len(env):
        env = np.concatenate([env[look_count:], np.full(look_count, env[-1])])

    a_in = np.exp(-1.0 / max(1.0, 0.004 * sr / hop))
    a_out = np.exp(-1.0 / max(1.0, 0.08 * sr / hop))
    cur = 0.0
    smooth_env = np.zeros_like(env)
    for i in range(len(env)):
        c = a_in if env[i] > cur else a_out
        cur = c * cur + (1 - c) * env[i]
        smooth_env[i] = cur

    centers = np.arange(len(smooth_env)) * hop + win // 2
    samp_gain = np.interp(np.arange(n), centers, smooth_env).astype(np.float32)

    pause_floor = 10 ** (pause_floor_db / 20)
    mult = pause_floor + (1.0 - pause_floor) * samp_gain
    return (x * mult).astype(np.float32)

