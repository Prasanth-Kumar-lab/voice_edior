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
from .presets import podcast_chain_cfg, podcast_tone_cfg, podcast_tone_curve, space_cfg, tone_curve

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


def _pitch_hpf_hz(va: Dict[str, object], factor: float) -> float:
    """Low cut that follows the speaker's own lowest pitch: removes everything under the voice, never the voice."""
    f0 = float(va.get("f0_median") or 0.0) or 150.0
    p10 = float(va.get("f0_p10") or 0.0) or f0 * 0.8
    return float(np.clip(factor * p10, 70.0, 140.0))


def _podcast_eq_points(x: np.ndarray, ch: Dict[str, float]):
    """Measured corrective EQ (cuts boom/mud, lifts missing presence) on the active speech only."""
    active = pl._frame_db(x, 3) > (pl.noise_floor_db(x) + 14)
    # control-rate frames are 2 ms; the LTAS helper indexes 10 ms voiced frames
    act10 = active[: (len(active) // 5) * 5].reshape(-1, 5).mean(axis=1) > 0.5
    f, P = pl.long_term_spectrum(x, SR, act10)
    return pl.adaptive_eq_points(f, P, mud_hz=260, presence_hz=3300, air_db=1.2, strength=1.0)


def _podcast_extra_curve(tone: str, ch: Dict[str, float]):
    """Filter character curve + its own presence lift (+ close-mic body for Theatrical only)."""
    presence = ch["presence"]
    boost = [(2000, 0.0), (3500, presence), (5000, presence * 0.8), (8000, presence * 0.3), (12000, 0.0)] if presence else []
    prox = ch["prox"]
    body = [(90, 0.0), (160, prox), (260, prox * 0.6), (500, 0.0)] if prox else []
    return podcast_tone_curve(tone) + boost + body


def enhance_podcast(x_in: np.ndarray, sr: int, cb: Progress = _noop, tone: str = "general_bass",
                    level: str = "enhanced") -> Tuple[np.ndarray, Dict[str, object]]:
    ch = podcast_chain_cfg(tone, level=level)
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

    if ch["hpf_f0"] > 0:                                   # bass-free filters: clean low cut tuned to the voice
        hpf = _pitch_hpf_hz(va, ch["hpf_f0"])
        x = pl.highpass(x, hpf)
        report["pitch_hpf_hz"] = round(hpf, 1)

    cb("Studio voice EQ", 0.62)
    x = pl.apply_curve(x, _podcast_eq_points(x, ch), SR, extra=_podcast_extra_curve(tone, ch))

    bass = float(tcfg.get("bass", 0.0)) if tcfg.get("theatre") else 0.0
    if bass > 0:
        cb("Adding theatrical cinema bass", 0.68)
        x = pl.voice_bass(x, report["f0_median_hz"], SR, amount=bass)
        report["bass"] = bass

    treble = float(tcfg.get("treble", 0.0))
    if level == "natural":
        treble = 0.0
    elif level == "max":
        treble = min(1.0, treble * 1.4 + 0.2)
    if treble > 0:
        cb("Adding crisp treble & air", 0.71)
        x = pl.voice_treble(x, SR, amount=treble)
        report["treble"] = treble

    cb("Leveling", 0.74)
    x = pl.level(x, SR, target_db=-22.0)
    x, gr = pl.compress(x, SR, thr_db=-25.0, ratio=ch["ratio"], attack_ms=10, release_ms=180)
    report["compressor_peak_gr_db"] = round(gr, 1)

    cb("Enhancing the voice", 0.8)
    x = pl.parallel_compress(x, SR, amount=ch["parallel"])
    x = pl.exciter(x, SR, amount=ch["exciter"])
    w_amt = float(tcfg.get("warmth", 0.0))
    if w_amt > 0:
        x = pl.warmth(x, w_amt)
    x, sib = pl.deess(x, SR, center=ch["deess_hz"], amount=ch["deess"])   # last: generated highs never get harsh

    # Final clean comes *after* the dynamics: leveling and compression lift whatever is left in the pauses,
    # so the gate has to be the last thing that touches the background.
    cb("Final clean", 0.84)
    x = pl.spectral_gate(x, depth_db=36.0, margin_db=5.5, hold_ms=80.0, release_ms=150.0, voiced=vo)
    x = pl.dominant_expander(x, rel_db=-20.0, depth_db=24.0)
    x = pl.apply_speech_gate(x, SR, pause_floor_db=-66.0, hold_ms=120.0, look_ms=15.0)
    x, _ = pl.deess(x, SR, center=ch["deess_hz"], amount=min(0.95, ch["deess"] + 0.08))

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
    x, engine = dn.denoise(x, strength=1.0, atten_lim_db=None, post_filter=True)
    report["engine"] = engine

    cb("Removing room tail", 0.44)
    x = dereverb(x, amount=0.35, t60=0.5)

    cb("Shaping the voice", 0.56)
    act = voiced if len(voiced) else None
    f, P = pl.long_term_spectrum(x, SR, act if act is not None else np.ones(1, bool))
    x = pl.apply_curve(x, pl.adaptive_eq_points(f, P, mud_hz=prof["mud_hz"], presence_hz=prof["presence_hz"],
                                                air_db=prof["air_db"], strength=1.0), SR, extra=tone_curve(eq))

    cb("De-essing", 0.68)
    x, sib = pl.deess(x, SR, center=prof["deess_hz"], amount=0.85)

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
    x = pl.spectral_gate(x, depth_db=34.0, margin_db=5.5, hold_ms=120.0, release_ms=200.0, voiced=voiced)
    x = pl.dominant_expander(x, rel_db=-24.0, depth_db=20.0)
    x = pl.apply_speech_gate(x, SR, pause_floor_db=-64.0, hold_ms=130.0, look_ms=15.0)
    x, _ = pl.deess(x, SR, center=prof["deess_hz"], amount=0.88)

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


def enhance(
    mode: str,
    x: np.ndarray,
    sr: int,
    cb: Progress = _noop,
    eq: str = "natural",
    space: str = "dry",
    level: str = "enhanced",
    strength: float = 1.0,
    voice_isolation: bool = False,
) -> Tuple[np.ndarray, Dict[str, object]]:
    dry_48 = _prep(x, sr)
    if voice_isolation:
        # Aggressive pre-isolation pass for noisy cafés / traffic before main pipeline
        dry_isolated, _ = dn.denoise(dry_48, strength=1.0, atten_lim_db=None, post_filter=True)
        work_x = pl.spectral_gate(dry_isolated, depth_db=36.0, margin_db=7.0, hold_ms=70.0, release_ms=140.0)
    else:
        work_x = x

    if mode == "vocals":
        y, report = enhance_vocals(work_x, sr if not voice_isolation else SR, cb, eq=eq, space=space)
    else:
        y, report = enhance_podcast(
            work_x,
            sr if not voice_isolation else SR,
            cb,
            tone=eq if eq != "natural" else "general_bass",
            level=level,
        )

    report["voice_isolation"] = bool(voice_isolation)
    blend = float(np.clip(strength, 0.0, 1.0))
    report["strength"] = round(blend, 2)
    if blend < 0.999:
        # Loudness-matched dry/wet blend
        target_lufs = float(report.get("lufs_out", -16.0))
        dry_matched = ld.normalize_lufs(dry_48, target_lufs, ceiling_db=-1.0)
        if y.ndim == 2 and dry_matched.ndim == 1:
            dry_matched = np.column_stack([dry_matched, dry_matched])
        n = min(len(y), len(dry_matched))
        y[:n] = (1.0 - blend) * dry_matched[:n] + blend * y[:n]

    return y, report


def clean_stage_cache(
    mode: str, x_in: np.ndarray, sr: int, cb: Progress = _noop, voice_isolation: bool = False
) -> Dict[str, object]:
    """Run and cache Stage 1 (Clean: resample, HPF, neural/spectral denoise, dereverb, pitch analysis)."""
    cb("Analyzing recording", 0.05)
    x = _prep(x_in, sr)
    lufs_in = round(ld.integrated_lufs(x), 1)
    floor_in = round(pl.noise_floor_db(x), 1)
    spread_in = round(_snr_spread(x), 1)

    if voice_isolation:
        x_iso, _ = dn.denoise(x, strength=1.0, atten_lim_db=None, post_filter=True)
        work_x = pl.spectral_gate(x_iso, depth_db=44.0, margin_db=8.5, hold_ms=65.0, release_ms=130.0)
    else:
        work_x = x

    va = analyze_voice(work_x)
    voiced = va["track"]["voiced"]
    prof = vocal_profile(va) if mode == "vocals" else {"hpf": 75.0}

    cb("Removing background noise", 0.25)
    x_clean = pl.highpass(work_x, float(prof["hpf"]))
    x_clean, engine = dn.denoise(
        x_clean,
        strength=1.0,
        atten_lim_db=None,
        post_filter=True,
    )

    cb("Removing room echo", 0.55)
    x_clean = dereverb(
        x_clean,
        amount=0.55 if mode == "podcast" else 0.25,
        t60=0.45 if mode == "podcast" else 0.5,
    )
    return {
        "mode": mode,
        "dry_48": x,
        "clean_48": x_clean,
        "engine": engine,
        "va": va,
        "prof": prof,
        "lufs_in": lufs_in,
        "floor_in": floor_in,
        "spread_in": spread_in,
        "voice_isolation": voice_isolation,
    }


def style_from_cache(
    cache: Dict[str, object],
    eq: str = "natural",
    space: str = "dry",
    level: str = "enhanced",
    strength: float = 1.0,
) -> Tuple[np.ndarray, Dict[str, object]]:
    """Run Stage 2 (Style: EQ, tone, compression, space, LUFS, dry/wet strength) in <1s from cached clean audio."""
    mode = str(cache.get("mode", "podcast"))
    x_clean = np.array(cache["clean_48"], dtype=np.float32, copy=True)
    dry_48 = np.array(cache["dry_48"], dtype=np.float32, copy=False)
    va = cache["va"]  # type: ignore[index]
    voiced = va["track"]["voiced"]  # type: ignore[index]

    report: Dict[str, object] = {
        "mode": mode,
        "tone": eq,
        "space": space,
        "level": level,
        "engine": cache.get("engine", "spectral"),
        "lufs_in": cache.get("lufs_in", -24.0),
        "noise_floor_in_db": cache.get("floor_in", -50.0),
        "spread_in_db": cache.get("spread_in", 15.0),
        "f0_median_hz": round(float(va.get("f0_median") or 0.0), 1),  # type: ignore[union-attr]
        "voice_type": va.get("voice_type", "unknown"),  # type: ignore[union-attr]
        "voice_isolation": bool(cache.get("voice_isolation", False)),
        "cached_restyle": True,
    }

    if mode == "vocals":
        prof = cache["prof"]  # type: ignore[index]
        act = voiced if len(voiced) else np.ones(1, bool)
        f, P = pl.long_term_spectrum(x_clean, SR, act)
        x = pl.apply_curve(
            x_clean,
            pl.adaptive_eq_points(
                f, P, mud_hz=prof["mud_hz"], presence_hz=prof["presence_hz"], air_db=prof["air_db"], strength=1.0
            ),
            SR,
            extra=tone_curve(eq),
        )
        x, _ = pl.deess(x, SR, center=prof["deess_hz"], amount=0.85)
        x = pl.level(x, SR, target_db=-21.0, max_up=7.0, max_down=6.0)
        x, gr = pl.compress(x, SR, thr_db=-24.0, ratio=2.8, attack_ms=10, release_ms=130)
        report["compressor_peak_gr_db"] = round(gr, 1)
        x, _ = pl.deess(x, SR, center=prof["deess_hz"], amount=0.80)
        x = pl.spectral_gate(x, depth_db=34.0, margin_db=5.5, hold_ms=110.0, release_ms=200.0, voiced=voiced)
        x = pl.dominant_expander(x, rel_db=-22.0, depth_db=22.0)
        x = pl.apply_speech_gate(x, SR, pause_floor_db=-64.0, hold_ms=140.0, look_ms=15.0)
        x = pl.warmth(x, prof["warmth"])
        x = pl.apply_space(x, space_cfg(space), SR)
        x = ld.normalize_lufs(x, -14.0, ceiling_db=-1.0)
    else:
        tone = eq if eq != "natural" else "general_bass"
        ch = podcast_chain_cfg(tone, level=level)
        tcfg = podcast_tone_cfg(tone)
        if ch["hpf_f0"] > 0:
            x_clean = pl.highpass(x_clean, _pitch_hpf_hz(va, ch["hpf_f0"]))  # type: ignore[arg-type]
        x = pl.apply_curve(x_clean, _podcast_eq_points(x_clean, ch), SR, extra=_podcast_extra_curve(tone, ch))
        bass = float(tcfg.get("bass", 0.0)) if tcfg.get("theatre") else 0.0
        if bass > 0:
            x = pl.voice_bass(x, float(report["f0_median_hz"]), SR, amount=bass)
        treble = float(tcfg.get("treble", 0.0))
        if level == "natural":
            treble = 0.0
        elif level == "max":
            treble = min(1.0, treble * 1.4 + 0.2)
        if treble > 0:
            x = pl.voice_treble(x, SR, amount=treble)
        x = pl.level(x, SR, target_db=-22.0)
        x, gr = pl.compress(x, SR, thr_db=-25.0, ratio=ch["ratio"], attack_ms=10, release_ms=180)
        report["compressor_peak_gr_db"] = round(gr, 1)
        x = pl.parallel_compress(x, SR, amount=ch["parallel"])
        x = pl.exciter(x, SR, amount=ch["exciter"])
        w_amt = float(tcfg.get("warmth", 0.0))
        if w_amt > 0:
            x = pl.warmth(x, w_amt)
        x, _ = pl.deess(x, SR, center=ch["deess_hz"], amount=ch["deess"])
        x = pl.spectral_gate(x, depth_db=36.0, margin_db=5.5, hold_ms=80.0, release_ms=150.0, voiced=voiced)
        x = pl.dominant_expander(x, rel_db=-20.0, depth_db=24.0)
        x = pl.apply_speech_gate(x, SR, pause_floor_db=-66.0, hold_ms=120.0, look_ms=15.0)
        x, _ = pl.deess(x, SR, center=ch["deess_hz"], amount=min(0.95, float(ch["deess"]) + 0.08))
        sp_type = str(tcfg.get("space", "theatre" if tcfg.get("theatre") else ""))
        if sp_type:
            x = pl.podcast_space(x, sp_type, SR)
            report["stereo"] = True
        x = ld.normalize_lufs(x, -16.0, ceiling_db=-1.0)

    blend = float(np.clip(strength, 0.0, 1.0))
    report["strength"] = round(blend, 2)
    if blend < 0.999:
        target_lufs = -14.0 if mode == "vocals" else -16.0
        dry_matched = ld.normalize_lufs(dry_48, target_lufs, ceiling_db=-1.0)
        if x.ndim == 2 and dry_matched.ndim == 1:
            dry_matched = np.column_stack([dry_matched, dry_matched])
        n = min(len(x), len(dry_matched))
        x[:n] = (1.0 - blend) * dry_matched[:n] + blend * x[:n]

    mono_ref = x.mean(axis=1) if x.ndim == 2 else x
    report["lufs_out"] = round(ld.integrated_lufs(x), 1)
    report["true_peak_db"] = round(ld.true_peak_db(x), 2)
    report["noise_floor_out_db"] = round(pl.noise_floor_db(mono_ref), 1)
    report["spread_out_db"] = round(_snr_spread(mono_ref), 1)
    return x, report
