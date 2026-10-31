"""Pick-and-go presets for Vocals: Tone (equalizer) and Space (surround). No sliders for the user to fiddle with."""
from __future__ import annotations

from typing import Dict, List, Tuple

Curve = List[Tuple[float, float]]

# Tone presets are *added* to the pitch-adaptive base EQ, so every one still follows the singer's voice.
TONES: Dict[str, Dict[str, object]] = {
    "natural": {"label": "Natural", "blurb": "Your voice, cleaned and balanced", "curve": []},
    "smooth": {
        "label": "Smooth", "blurb": "Silky, softens harshness",
        "curve": [(120, 0.0), (220, 1.0), (400, 0.5), (2500, -1.0), (3500, -2.5), (4800, -2.0), (7000, -2.0), (12000, -0.5)],
    },
    "warm": {
        "label": "Warm", "blurb": "Fuller, rounder, intimate",
        "curve": [(80, 0.0), (170, 2.5), (320, 1.5), (1000, 0.0), (3000, -0.5), (5500, -1.5), (10000, -2.5)],
    },
    "bright": {
        "label": "Bright", "blurb": "Airy, forward, sparkly",
        "curve": [(120, 0.0), (250, -1.0), (1000, 0.0), (3500, 2.0), (8000, 3.0), (13000, 4.0), (18000, 3.0)],
    },
    "deep": {
        "label": "Deep", "blurb": "Weight and body in the low end",
        "curve": [(60, 1.5), (120, 3.0), (250, 1.5), (600, 0.0), (3000, 0.5), (9000, -1.0)],
    },
    "radio": {
        "label": "Radio", "blurb": "Punchy mid-range, broadcast feel",
        "curve": [(100, -3.0), (200, -1.0), (800, 1.5), (2000, 3.0), (4000, 2.0), (8000, -1.0), (14000, -3.0)],
    },
}

# Space presets: reverb time (s), pre-delay (ms), wet level re voice (dB), damping (0 bright .. 1 dark), stereo width (0..1)
SPACES: Dict[str, Dict[str, object]] = {
    "dry": {"label": "Dry", "blurb": "Clean, no space", "t60": 0.0},
    "room": {"label": "Studio Room", "blurb": "Close and natural", "t60": 0.45, "pre": 12.0, "mix": -23.0, "damp": 0.35, "width": 0.5},
    "plate": {"label": "Plate", "blurb": "Classic vocal shine", "t60": 1.1, "pre": 22.0, "mix": -21.0, "damp": 0.3, "width": 0.7},
    "hall": {"label": "Hall", "blurb": "Big and cinematic", "t60": 2.0, "pre": 35.0, "mix": -20.0, "damp": 0.55, "width": 0.9},
    "wide": {"label": "Surround", "blurb": "Wide immersive stereo field", "t60": 1.0, "pre": 18.0, "mix": -19.0, "damp": 0.3, "width": 1.0},
}


def tone_curve(tone: str) -> Curve:
    return list(TONES.get(tone, TONES["natural"])["curve"])  # type: ignore[arg-type]


def space_cfg(space: str) -> Dict[str, object]:
    return SPACES.get(space, SPACES["dry"])


# ───────────────────────────── Podcast ─────────────────────────────

PODCAST_TONES: Dict[str, Dict[str, object]] = {
    # Every Podcast filter is a complete, self-contained chain (EQ + dynamics + colour + de-ess), so there is no
    # separate Enhance level to pick. ONLY Theatrical adds bass; every other filter is strictly bass-free:
    # nothing below 250 Hz is ever boosted, and the low cut follows the speaker's own pitch for a clean voice.
    #
    #   chain keys: exciter (generated air), parallel (density), presence (extra 2-6 kHz dB), ratio (compressor),
    #               prox (close-mic low-mid body, Theatrical only), deess_hz / deess (sibilance control),
    #               hpf_f0 (low cut = hpf_f0 x the speaker's lowest pitch).

    # Studio Clarity: neutral, pristine broadcast microphone — honest, articulate, nothing hyped
    "general_bass": {
        "label": "Studio Clarity",
        "blurb": "Neutral broadcast-mic clarity · zero bass, zero mud · every word articulate",
        "curve": [(50, -8.0), (110, -3.0), (300, -3.0), (800, 0.5), (2500, 2.5), (3500, 3.0), (6000, 0.5), (10000, -1.5), (15000, -4.0)],
        "treble": 0.12,
        "warmth": 0.05,
        "chain": {"exciter": 0.08, "parallel": 0.12, "presence": 1.2, "ratio": 2.6, "prox": 0.0,
                  "deess_hz": 6200.0, "deess": 0.85, "hpf_f0": 0.70},
    },
    # Theatrical: clean cinematic narrator voice — zero bass mud, commanding mid-high focus & clarity
    "theatrical": {
        "label": "Theatrical",
        "blurb": "Clean cinematic presence · zero bass mud · commanding, crystal-clear voice",
        "curve": [(50, -8.5), (120, -3.5), (300, -4.0), (800, 1.0), (1500, 2.2), (3000, 4.0), (5000, 3.5), (8000, 2.0), (12000, 1.5), (16000, -3.5)],
        "treble": 0.22,
        "warmth": 0.05,
        "chain": {"exciter": 0.14, "parallel": 0.18, "presence": 1.6, "ratio": 3.0, "prox": 0.0,
                  "deess_hz": 6300.0, "deess": 0.88, "hpf_f0": 0.78},
    },
    # Crisp Air & Detail: modern HD creator sound — open, articulate top, silky (never harsh) consonants
    "bass_treble": {
        "label": "Crisp Air & Detail",
        "blurb": "Modern HD creator sound · open sparkling air · silky consonants",
        "curve": [(50, -9.0), (140, -3.5), (350, -3.0), (900, 0.0), (2200, 2.0), (4000, 3.2), (7500, 2.0), (11000, 1.5), (16000, -3.0)],
        "treble": 0.25,
        "warmth": 0.0,
        "chain": {"exciter": 0.14, "parallel": 0.10, "presence": 1.0, "ratio": 2.4, "prox": 0.0,
                  "deess_hz": 6500.0, "deess": 0.90, "hpf_f0": 0.75},
    },
    # Warm Intimate: late-night radio — analog tube colour in the low-mids, smooth rounded top, dense and close
    "ultra_bass": {
        "label": "Warm Intimate",
        "blurb": "Late-night radio · analog tube colour · smooth, close and velvety",
        "curve": [(50, -7.0), (140, -1.5), (250, 0.0), (500, 1.2), (900, 0.8), (2200, 1.0), (4500, -1.0), (8000, -3.5), (13000, -6.0)],
        "treble": 0.0,
        "warmth": 0.35,
        "chain": {"exciter": 0.0, "parallel": 0.22, "presence": 0.6, "ratio": 3.0, "prox": 0.0,
                  "deess_hz": 5800.0, "deess": 0.88, "hpf_f0": 0.65},
    },
    # Crystal Presence: maximum intelligibility — forward, projected, cuts through any playback device
    "crystal_treble": {
        "label": "Crystal Presence",
        "blurb": "Maximum intelligibility · forward projection · cuts through phone speakers",
        "curve": [(70, -9.0), (150, -4.5), (300, -4.5), (600, -1.5), (1400, 2.0), (2800, 4.5), (4200, 4.0), (7000, 1.5), (11000, 1.0), (16000, -3.5)],
        "treble": 0.28,
        "warmth": 0.0,
        "chain": {"exciter": 0.15, "parallel": 0.20, "presence": 1.8, "ratio": 3.2, "prox": 0.0,
                  "deess_hz": 6400.0, "deess": 0.92, "hpf_f0": 0.85},
    },
    # Studio Booth: acoustically treated dead vocal booth — ultra-clean isolation, zero room echo/boxiness
    "studio_booth": {
        "label": "Studio Booth",
        "blurb": "Acoustically treated booth · ultra-clean voice isolation · zero room echo",
        "curve": [(50, -9.0), (130, -3.5), (280, -4.5), (420, -3.0), (1200, 1.8), (3000, 3.5), (5500, 3.0), (8500, 2.0), (12000, 1.5), (16000, -3.5)],
        "treble": 0.20,
        "warmth": 0.04,
        "chain": {"exciter": 0.12, "parallel": 0.16, "presence": 1.5, "ratio": 2.8, "prox": 0.0,
                  "deess_hz": 6300.0, "deess": 0.88, "hpf_f0": 0.82},
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
    if not podcast_tone_cfg(tone).get("theatre"):
        base["prox"] = 0.0                                   # bass-free guarantee for every non-Theatrical filter
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
