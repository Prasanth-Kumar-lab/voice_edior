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
    # General + Bass: all-round clean podcast voice with rich speaking-driven bass & balanced clarity
    "general_bass": {
        "label": "General + Bass",
        "blurb": "Clean studio voice with warm, speaking-driven bass",
        "curve": [(50, 2.0), (95, 5.5), (150, 4.5), (300, -3.5), (700, 0.0), (2800, 3.0), (5000, 2.5), (10000, 2.0), (15000, 1.5)],
        "bass": 0.55,
        "treble": 0.25,
        "warmth": 0.12,
    },
    # Theatrical: movie-trailer bass + sub-octave + stereo cinema-hall depth
    "theatrical": {
        "label": "Theatrical",
        "blurb": "Movie-trailer bass that follows your voice, cinema-hall depth",
        "curve": [(40, 2.5), (80, 6.0), (140, 5.0), (300, -4.5), (600, -1.5), (1500, 0.0), (3000, 3.5), (5000, 2.0), (9000, -1.5), (14000, -3.0)],
        "bass": 0.85,
        "treble": 0.20,
        "warmth": 0.18,
        "theatre": True,
        "space": "theatre",
    },
    # Bass + Treble: modern Hi-Fi V-shape — deep dynamic sub-bass + sparkling HD treble air
    "bass_treble": {
        "label": "Bass + Treble",
        "blurb": "Punchy dynamic bass paired with crisp high-definition treble",
        "curve": [(45, 3.5), (90, 7.0), (150, 5.0), (340, -6.5), (650, -3.0), (1600, 0.5), (3500, 5.5), (6500, 6.5), (11000, 7.5), (16000, 6.5)],
        "bass": 0.70,
        "treble": 0.85,
        "warmth": 0.15,
    },
    # Ultra Bass: maximum sub-harmonic chest thunder and dark velvety top-end
    "ultra_bass": {
        "label": "Ultra Bass",
        "blurb": "Deepest sub-octave chest resonance, dark and heavy",
        "curve": [(40, 5.0), (75, 9.5), (125, 8.0), (210, 4.5), (420, -5.0), (1000, -1.0), (2800, 1.5), (5500, -4.5), (9500, -8.0), (14000, -10.0)],
        "bass": 1.15,
        "treble": 0.0,
        "warmth": 0.28,
    },
    # Crystal Treble: razor-sharp articulation, tight low end, shimmering condenser air
    "crystal_treble": {
        "label": "Crystal Treble",
        "blurb": "Ultra-crisp treble, articulation and studio condenser air",
        "curve": [(70, -6.0), (140, -4.0), (280, -5.5), (500, -3.0), (1200, 1.5), (2800, 6.5), (4800, 8.0), (8000, 7.5), (12500, 9.0), (16500, 8.0)],
        "bass": 0.0,
        "treble": 1.0,
        "warmth": 0.0,
    },
    # Studio Booth: wide stereo broadcast booth, warm analog tube body + bass & treble
    "studio_booth": {
        "label": "Studio Booth",
        "blurb": "Wide stereo acoustic booth with warm bass and silky treble",
        "curve": [(55, 2.5), (110, 5.5), (180, 4.0), (350, -4.0), (1000, 1.0), (3200, 4.5), (5800, 4.0), (10500, 5.0), (15000, 4.0)],
        "bass": 0.50,
        "treble": 0.55,
        "warmth": 0.25,
        "space": "booth",
    },
}


def podcast_tone_cfg(tone: str) -> Dict[str, object]:
    return PODCAST_TONES.get(tone, PODCAST_TONES["general_bass"])

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
