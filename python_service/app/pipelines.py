"""Premium enhancement pipelines.

* podcast — "Enhance Speech" style: neural noise removal, room-echo removal, adaptive studio EQ,
  de-essing, leveling and broadcast loudness (-16 LUFS).
* vocals  — pitch-aware: the fundamental of the performance steers the low cut, mud/presence EQ,
  de-ess frequency and compression, then light plate reverb and streaming loudness (-14 LUFS).
"""
from __future__ import annotations

from typing import Callable, Dict, Tuple

import numpy as np

from . import denoise as dn
from . import loudness as ld
from . import polish as pl
from .audio_io import SR, resample
from .dereverb import dereverb
from .pitch import analyze_voice
from .presets import level_cfg, podcast_tone_cfg, podcast_tone_curve, space_cfg, tone_curve

Progress = Callable[[str, float], None]


def _noop(stage: str, frac: float) -> None:  # noqa: ARG001
    return None


def _snr_spread(x: np.ndarray, sr: int = SR) -> float:
    """Level spread between loud speech (p90) and the room floor (p10) over 50 ms frames, in dB."""
    w = int(0.05 * sr)
    n = (len(x) // w) * w
    if n == 0:
        return 0.0
    r = 20 * np.log10(np.sqrt((x[:n].reshape(-1, w).astype(np.float64) ** 2).mean(axis=1)) + 1e-9)
    return float(np.percentile(r, 90) - np.percentile(r, 10))


def _prep(x: np.ndarray, sr: int) -> np.ndarray:
    x = resample(x.astype(np.float32), sr, SR)
    x = x - float(np.mean(x))
    peak = float(np.max(np.abs(x))) if len(x) else 0.0
    if peak > 1e-6 and peak < 0.2:                    # very quiet takes: bring up before analysis
        x = x * (0.5 / peak)
    return x


def enhance_podcast(x_in: np.ndarray, sr: int, cb: Progress = _noop, tone: str = "general_bass",
                    level: str = "enhanced") -> Tuple[np.ndarray, Dict[str, object]]:
    lv = level_cfg(level)
    report: Dict[str, object] = {"mode": "podcast", "tone": tone, "level": level}
    cb("Analyzing recording", 0.04)
    x = _prep(x_in, sr)
    report["noise_floor_in_db"] = round(pl.noise_floor_db(x), 1)
    report["spread_in_db"] = round(_snr_spread(x), 1)
    report["lufs_in"] = round(ld.integrated_lufs(x), 1)

    cb("Removing background noise", 0.12)
    x = pl.highpass(x, 75.0)
    x, engine = dn.denoise(x, strength=1.0, atten_lim_db=None, post_filter=True)
    report["engine"] = engine

    cb("Deep clean", 0.34)
    x = dereverb(x, amount=0.55, t60=0.45)

    va = analyze_voice(x)
    vo = va["track"]["voiced"]
    tcfg = podcast_tone_cfg(tone)
    report["f0_median_hz"] = round(float(va.get("f0_median") or 0.0), 1)

    cb("Studio voice EQ", 0.62)
    active = pl._frame_db(x, 3) > (pl.noise_floor_db(x) + 14)
    # control-rate frames are 2 ms; the LTAS helper indexes 10 ms voiced frames
    act10 = active[: (len(active) // 5) * 5].reshape(-1, 5).mean(axis=1) > 0.5
    f, P = pl.long_term_spectrum(x, SR, act10)
    presence = float(lv["presence"])
    boost = [(2000, 0.0), (3500, presence), (5000, presence * 0.8), (8000, presence * 0.3), (12000, 0.0)] if presence else []
    prox = float(lv["prox"])                          # close-mic body: gentle low-mid warmth
    body = [(90, 0.0), (160, prox), (260, prox * 0.6), (500, 0.0)] if prox else []
    x = pl.apply_curve(x, pl.adaptive_eq_points(f, P, mud_hz=260, presence_hz=3300, air_db=1.2, strength=1.0),
                       SR, extra=podcast_tone_curve(tone) + boost + body)

    bass = float(tcfg.get("bass", 0.0))
    if bass > 0:
        cb("Adding voice-tuned bass", 0.68)
        x = pl.voice_bass(x, report["f0_median_hz"], SR, amount=bass)
        report["bass"] = bass

    treble = float(tcfg.get("treble", 0.0))
    if treble > 0:
        cb("Adding crisp treble & air", 0.71)
        x = pl.voice_treble(x, SR, amount=treble)
        report["treble"] = treble

    cb("Leveling", 0.74)
    x = pl.level(x, SR, target_db=-22.0)
    x, gr = pl.compress(x, SR, thr_db=-25.0, ratio=float(lv["ratio"]), attack_ms=10, release_ms=180)
    report["compressor_peak_gr_db"] = round(gr, 1)

    cb("Enhancing the voice", 0.8)
    x = pl.parallel_compress(x, SR, amount=float(lv["parallel"]))
    x = pl.exciter(x, SR, amount=float(lv["exciter"]))
    w_amt = float(tcfg.get("warmth", 0.0))
    if w_amt > 0:
        x = pl.warmth(x, w_amt)
    x, sib = pl.deess(x, SR, center=6500, amount=0.75)   # last, so generated highs never make "s" sounds harsh

    # Final clean comes *after* the dynamics: leveling and compression lift whatever is left in the pauses,
    # so the gate has to be the last thing that touches the background.
    cb("Final clean", 0.84)
    x = pl.spectral_gate(x, depth_db=32.0, margin_db=5.0, hold_ms=80.0, release_ms=160.0, voiced=vo)
    x = pl.dominant_expander(x, rel_db=-22.0, depth_db=20.0)
    x = pl.apply_speech_gate(x, SR, pause_floor_db=-60.0, hold_ms=130.0, look_ms=15.0)

    sp_type = str(tcfg.get("space", "theatre" if tcfg.get("theatre") else ""))
    if sp_type:
        cb("Cinema-hall depth" if sp_type == "theatre" else "Studio acoustic space", 0.88)
        x = pl.podcast_space(x, sp_type, SR)             # after the gate: only the voice rings into the space
        report["stereo"] = True

    cb("Mastering to -16 LUFS", 0.92)
    x = ld.normalize_lufs(x, -16.0, ceiling_db=-1.0)
    report["lufs_out"] = round(ld.integrated_lufs(x), 1)
    report["true_peak_db"] = round(ld.true_peak_db(x), 2)
    mono_ref = x.mean(axis=1) if x.ndim == 2 else x
    report["noise_floor_out_db"] = round(pl.noise_floor_db(mono_ref), 1)
    report["spread_out_db"] = round(_snr_spread(mono_ref), 1)
    cb("Done", 1.0)
    return x, report


def vocal_profile(a: Dict[str, object]) -> Dict[str, float]:
    f0 = float(a.get("f0_median") or 0.0) or 180.0
    p10 = float(a.get("f0_p10") or 0.0) or f0 * 0.8
    return {
        "hpf": float(np.clip(0.55 * p10, 60, 140)),
        "mud_hz": float(np.clip(f0 * 1.8, 220, 360)),
        "presence_hz": float(np.clip(2600 + 4 * f0, 3000, 4800)),
        "deess_hz": float(np.clip(5200 + 7 * f0, 5500, 8500)),
        "air_db": 1.5 if f0 < 200 else 2.2,
        "warmth": 0.12 if f0 > 200 else 0.2,
    }


def enhance_vocals(x_in: np.ndarray, sr: int, cb: Progress = _noop, eq: str = "natural",
                   space: str = "dry") -> Tuple[np.ndarray, Dict[str, object]]:
    report: Dict[str, object] = {"mode": "vocals", "tone": eq, "space": space}
    cb("Analyzing pitch", 0.04)
    x = _prep(x_in, sr)
    report["noise_floor_in_db"] = round(pl.noise_floor_db(x), 1)
    report["spread_in_db"] = round(_snr_spread(x), 1)
    report["lufs_in"] = round(ld.integrated_lufs(x), 1)
    a = analyze_voice(x)
    prof = vocal_profile(a)
    report.update({
        "f0_median_hz": round(float(a["f0_median"]), 1), "voice_type": a["voice_type"],
        "voiced_ratio": round(float(a["voiced_ratio"]), 2), "profile": {k: round(v, 1) for k, v in prof.items()},
    })
    voiced = a["track"]["voiced"]

    cb("Removing background noise", 0.14)
    x = pl.highpass(x, prof["hpf"])
    x, engine = dn.denoise(x, strength=0.9, atten_lim_db=None, post_filter=False)
    report["engine"] = engine

    cb("Removing room tail", 0.44)
    x = dereverb(x, amount=0.2, t60=0.5)

    cb("Shaping the voice", 0.56)
    act = voiced if len(voiced) else None
    f, P = pl.long_term_spectrum(x, SR, act if act is not None else np.ones(1, bool))
    x = pl.apply_curve(x, pl.adaptive_eq_points(f, P, mud_hz=prof["mud_hz"], presence_hz=prof["presence_hz"],
                                                air_db=prof["air_db"], strength=1.0), SR, extra=tone_curve(eq))

    cb("De-essing", 0.68)
    x, sib = pl.deess(x, SR, center=prof["deess_hz"], amount=0.75)

    cb("Dynamics", 0.76)
    x = pl.level(x, SR, target_db=-21.0, max_up=7.0, max_down=6.0)
    lvl = pl._frame_db(x, 5)
    act_lvl = lvl[lvl > pl.noise_floor_db(x) + 12]
    dyn = float(np.percentile(act_lvl, 95) - np.percentile(act_lvl, 10)) if len(act_lvl) > 20 else 15.0
    ratio = float(np.clip(2.0 + (dyn - 12) / 6.0, 2.0, 4.5))
    thr = float(np.percentile(act_lvl, 55)) if len(act_lvl) > 20 else -24.0
    x, gr = pl.compress(x, SR, thr_db=thr, ratio=ratio, attack_ms=10, release_ms=130)
    report.update({"compressor_ratio": round(ratio, 1), "compressor_peak_gr_db": round(gr, 1)})

    cb("Final clean", 0.84)
    x = pl.spectral_gate(x, depth_db=20.0, margin_db=6.0, hold_ms=140.0, release_ms=260.0, voiced=voiced)
    x = pl.dominant_expander(x, rel_db=-28.0, depth_db=10.0)

    cb("Adding polish", 0.88)
    x = pl.warmth(x, prof["warmth"])
    x = pl.apply_space(x, space_cfg(space), SR)       # Dry (default) keeps the background completely clean

    cb("Mastering to -14 LUFS", 0.94)
    x = ld.normalize_lufs(x, -14.0, ceiling_db=-1.0)
    report["lufs_out"] = round(ld.integrated_lufs(x), 1)
    report["true_peak_db"] = round(ld.true_peak_db(x), 2)
    report["noise_floor_out_db"] = round(pl.noise_floor_db(x), 1)
    report["spread_out_db"] = round(_snr_spread(x), 1)
    cb("Done", 1.0)
    return x, report


def enhance(mode: str, x: np.ndarray, sr: int, cb: Progress = _noop, eq: str = "natural",
            space: str = "dry", level: str = "enhanced") -> Tuple[np.ndarray, Dict[str, object]]:
    if mode == "vocals":
        return enhance_vocals(x, sr, cb, eq=eq, space=space)
    return enhance_podcast(x, sr, cb, tone=eq if eq != "natural" else "general_bass", level=level)
