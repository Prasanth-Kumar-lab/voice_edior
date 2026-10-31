"""Pick-and-go presets for Vocals: Tone (equalizer) and Space (surround). No sliders for the user to fiddle with."""
from __future__ import annotations

from typing import Dict, List, Tuple

Curve = List[Tuple[float, float]]

# Tone presets are *added* to the pitch-adaptive base EQ, so every one still follows the singer's voice.
TONES: Dict[str, Dict[str, object]] = {
    "natural": {
        "label": "Natural", "blurb": "Your voice, cleaned and balanced with warm body",
        "curve": [(60, 0.0), (140, 2.0), (260, 1.0), (1000, 0.0)],
    },
    "smooth": {
        "label": "Smooth", "blurb": "Silky, softens harshness with warm low-mids",
        "curve": [(60, 0.0), (140, 2.5), (240, 1.5), (400, 0.5), (2500, -1.0), (3500, -2.0), (4800, -1.5), (7000, -1.5), (12000, -0.5)],
    },
    "warm": {
        "label": "Warm", "blurb": "Fuller, rounder, intimate chest resonance",
        "curve": [(60, 0.5), (140, 3.5), (260, 2.0), (1000, 0.5), (3000, -0.5), (5500, -1.0), (10000, -2.0)],
    },
    "bright": {
        "label": "Bright", "blurb": "Airy, forward, sparkly with balanced low-end",
        "curve": [(60, -1.0), (140, 1.5), (260, 0.5), (1000, 0.5), (3500, 1.5), (8000, 2.2), (13000, 2.5), (18000, 1.5)],
    },
    "deep": {
        "label": "Deep", "blurb": "Rich weight and warm body in the low end",
        "curve": [(50, 1.5), (130, 4.0), (250, 2.5), (600, 0.5), (3000, 0.5), (9000, -1.0)],
    },
    "radio": {
        "label": "Radio", "blurb": "Punchy mid-range, broadcast feel with clear voice base",
        "curve": [(70, -1.5), (150, 1.5), (800, 1.5), (2000, 2.2), (4000, 1.8), (8000, -0.5), (14000, -2.5)],
    },
    "dolby": {
        "label": "Dolby Spatial", "blurb": "Immersive 3D vocal aura · pristine harmonic air · wide spatial depth",
        "curve": [(60, -0.5), (140, 3.0), (260, 1.8), (600, -0.6), (1200, 0.5), (2800, 1.8), (5500, 1.6), (8500, 2.2), (13000, 2.5), (17000, 1.0)],
    },
}

# Space presets: reverb time (s), pre-delay (ms), wet level re voice (dB), damping (0 bright .. 1 dark), stereo width (0..1)
SPACES: Dict[str, Dict[str, object]] = {
    "dry": {"label": "Dry", "blurb": "Clean, no space", "t60": 0.0},
    "room": {"label": "Studio Room", "blurb": "Close and natural", "t60": 0.45, "pre": 12.0, "mix": -23.0, "damp": 0.35, "width": 0.5},
    "plate": {"label": "Plate", "blurb": "Classic vocal shine", "t60": 1.1, "pre": 22.0, "mix": -21.0, "damp": 0.3, "width": 0.7},
    "hall": {"label": "Hall", "blurb": "Big and cinematic", "t60": 2.0, "pre": 35.0, "mix": -20.0, "damp": 0.55, "width": 0.9},
    "wide": {"label": "Surround", "blurb": "Wide immersive stereo field", "t60": 1.0, "pre": 18.0, "mix": -19.0, "damp": 0.3, "width": 1.0},
    "dolby": {"label": "Dolby Atmos", "blurb": "Signature 3D immersive surround field", "t60": 1.3, "pre": 20.0, "mix": -18.5, "damp": 0.40, "width": 1.0},
}


def tone_curve(tone: str) -> Curve:
    return list(TONES.get(tone, TONES["natural"])["curve"])  # type: ignore[arg-type]


def space_cfg(space: str) -> Dict[str, object]:
    return SPACES.get(space, SPACES["dry"])


# ───────────────────────────── Podcast ─────────────────────────────

PODCAST_TONES: Dict[str, Dict[str, object]] = {
    # Every Podcast filter is a complete, self-contained chain (EQ + dynamics + colour + de-ess).
    # Balanced warm low-end foundation (120-250 Hz) and clear articulate vocal highs.
    #
    #   chain keys: exciter (generated air), parallel (density), presence (extra 2-6 kHz dB), ratio (compressor),
    #               prox (close-mic low-mid body), deess_hz / deess (sibilance control),
    #               hpf_f0 (low cut = hpf_f0 x the speaker's lowest pitch).

    # Studio Clarity: neutral, pristine broadcast microphone — honest, articulate, warm and full
    "general_bass": {
        "label": "Studio Clarity",
        "blurb": "Natural broadcast warmth & clarity · rich vocal body · articulate speech",
        "curve": [(50, -3.5), (130, 2.5), (260, 1.5), (700, 0.5), (1800, 1.0), (3200, 1.8), (5500, 1.2), (8500, 0.5), (14000, -1.5)],
        "treble": 0.10,
        "warmth": 0.15,
        "chain": {"exciter": 0.05, "parallel": 0.14, "presence": 0.8, "ratio": 2.5, "prox": 1.5,
                  "deess_hz": 6200.0, "deess": 0.85, "hpf_f0": 0.50},
    },
    # Theatrical: commanding cinematic presence — deep warm chest resonance, pristine clarity
    "theatrical": {
        "label": "Theatrical",
        "blurb": "Commanding cinematic presence · deep warm chest resonance · pristine clarity",
        "curve": [(50, -3.0), (130, 3.5), (250, 2.0), (700, 0.8), (1800, 1.5), (3000, 2.2), (5200, 1.8), (8000, 1.0), (13000, -1.5)],
        "treble": 0.15,
        "warmth": 0.20,
        "chain": {"exciter": 0.08, "parallel": 0.18, "presence": 1.0, "ratio": 2.8, "prox": 2.2,
                  "deess_hz": 6300.0, "deess": 0.88, "hpf_f0": 0.50},
    },
    # Dolby Cinema: signature Dolby immersive voice — deep controlled sub-bass, clean mud scoop, forward dialogue presence, and ultra-silky crystalline air
    "dolby": {
        "label": "Dolby Cinema",
        "blurb": "Immersive cinema spatial field · dialogue leveling · rich sub-bass & crystal 3D air",
        "curve": [(50, -3.0), (130, 3.2), (250, 1.8), (600, -0.6), (1800, 1.2), (3000, 2.2), (5500, 1.8), (8500, 1.6), (13000, 1.8), (17000, 0.5)],
        "treble": 0.20,
        "warmth": 0.22,
        "theatre": True,
        "space": "dolby",
        "chain": {"exciter": 0.16, "parallel": 0.20, "presence": 1.4, "ratio": 2.8, "prox": 2.2,
                  "deess_hz": 6400.0, "deess": 0.88, "hpf_f0": 0.50},
    },
    # Crisp Air & Detail: modern HD creator sound — balanced warm low-end, silky smooth presence
    "bass_treble": {
        "label": "Crisp Air & Detail",
        "blurb": "Modern HD creator sound · balanced warm low-end · silky smooth presence",
        "curve": [(50, -3.5), (140, 2.2), (280, 1.2), (800, 0.5), (2000, 1.2), (3600, 2.0), (7000, 1.5), (11000, 1.0), (15000, -1.5)],
        "treble": 0.15,
        "warmth": 0.10,
        "chain": {"exciter": 0.08, "parallel": 0.12, "presence": 0.8, "ratio": 2.4, "prox": 1.2,
                  "deess_hz": 6500.0, "deess": 0.88, "hpf_f0": 0.52},
    },
    # Warm Intimate: late-night radio — rich velvety low-mids, analog tube warmth
    "ultra_bass": {
        "label": "Warm Intimate",
        "blurb": "Late-night radio · rich velvety low-mids · analog tube warmth",
        "curve": [(50, -2.5), (120, 4.5), (240, 3.0), (500, 1.8), (1000, 0.8), (2200, 0.5), (4500, -0.5), (8000, -1.5), (13000, -3.5)],
        "treble": 0.0,
        "warmth": 0.35,
        "chain": {"exciter": 0.0, "parallel": 0.22, "presence": 0.4, "ratio": 2.8, "prox": 2.5,
                  "deess_hz": 5800.0, "deess": 0.88, "hpf_f0": 0.48},
    },
    # Crystal Presence: maximum intelligibility — forward projection, warm core, clear diction
    "crystal_treble": {
        "label": "Crystal Presence",
        "blurb": "Intelligible and focused · warm voice core · crystal clear diction",
        "curve": [(50, -4.0), (140, 2.0), (280, 1.0), (800, 0.5), (1800, 1.5), (3200, 2.5), (5500, 1.8), (8500, 1.0), (14000, -1.5)],
        "treble": 0.16,
        "warmth": 0.10,
        "chain": {"exciter": 0.08, "parallel": 0.16, "presence": 1.2, "ratio": 2.8, "prox": 1.0,
                  "deess_hz": 6400.0, "deess": 0.90, "hpf_f0": 0.55},
    },
    # Studio Booth: acoustically treated dead vocal booth — clean warm voice isolation, zero room echo
    "studio_booth": {
        "label": "Studio Booth",
        "blurb": "Acoustically treated booth · clean warm voice isolation · zero room echo",
        "curve": [(50, -3.5), (130, 2.5), (260, 1.2), (600, 0.0), (1500, 1.2), (3000, 2.0), (5500, 1.5), (8500, 0.8), (14000, -1.5)],
        "treble": 0.12,
        "warmth": 0.15,
        "chain": {"exciter": 0.06, "parallel": 0.15, "presence": 1.0, "ratio": 2.6, "prox": 1.5,
                  "deess_hz": 6300.0, "deess": 0.88, "hpf_f0": 0.52},
    },
}


def podcast_tone_cfg(tone: str) -> Dict[str, object]:
    return PODCAST_TONES.get(tone, PODCAST_TONES["general_bass"])


def podcast_chain_cfg(tone: str, level: str = "enhanced") -> Dict[str, float]:
    """Full dynamics/colour chain for a Podcast filter.
    Each filter has its own tuned defaults. When level is natural or max,
    dynamics and exciter air adapt accordingly.
    """
    base = {k: float(v) for k, v in LEVELS.get(level, LEVELS["enhanced"]).items() if isinstance(v, (int, float))}
    base.update({"deess_hz": 6500.0, "deess": 0.75, "hpf_f0": 0.0})
    base.update({k: float(v) for k, v in dict(podcast_tone_cfg(tone).get("chain", {})).items()})  # type: ignore[arg-type]
    if level == "natural":
        base["exciter"] = 0.0
        base["parallel"] = 0.0
        base["presence"] = max(0.0, base.get("presence", 0.0) - 1.0)
    elif level == "max":
        base["exciter"] = min(1.0, base.get("exciter", 0.3) * 1.5 + 0.15)
        base["parallel"] = min(0.4, base.get("parallel", 0.15) * 1.5 + 0.05)
        base["presence"] = base.get("presence", 1.5) + 1.0
    return base

# Enhance level: how far the voice is taken beyond "cleaned".
#   exciter  – generated high-frequency detail (air / clarity a phone mic loses)
#   parallel – blended heavy compression for density and presence
#   presence – extra 2–6 kHz lift in dB
#   ratio    – main compressor ratio
LEVELS: Dict[str, Dict[str, object]] = {
    "natural": {"label": "Natural", "blurb": "Clean, light touch", "exciter": 0.0, "parallel": 0.0, "presence": 0.0, "ratio": 2.0, "prox": 0.0},
    "enhanced": {"label": "Enhanced", "blurb": "Clear, present, polished", "exciter": 0.35, "parallel": 0.15, "presence": 1.5, "ratio": 2.4, "prox": 1.2},
    "max": {"label": "Studio Max", "blurb": "Full studio-condenser sound", "exciter": 0.55, "parallel": 0.22, "presence": 2.5, "ratio": 2.8, "prox": 2.0},
}


def podcast_tone_curve(tone: str) -> Curve:
    return list(PODCAST_TONES.get(tone, PODCAST_TONES["general_bass"])["curve"])  # type: ignore[arg-type]


def level_cfg(level: str) -> Dict[str, object]:
    return LEVELS.get(level, LEVELS["enhanced"])
