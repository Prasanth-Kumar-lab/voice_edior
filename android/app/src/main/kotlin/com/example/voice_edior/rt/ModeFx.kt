package com.example.voice_edior.rt

import com.example.voice_edior.dsp.VoiceInfo
import com.example.voice_edior.dsp.VocalFx

/** The two product modes as native chains. Vocals is steered by the detected pitch, then a Tone and a Space are picked. */
object ModeFx {
    /** Podcast voice filters, added band by band to the speech base EQ (60, 150, 400, 1k, 2.4k, 5k, 8k, 12k Hz). */
    private val podcastTones = mapOf(
        // Studio Clarity: neutral broadcast microphone with warm chest resonance & articulate presence
        "general_bass" to floatArrayOf(-0.5f, 2.0f, 0.5f, 0.5f, 1.2f, 1.0f, 0.5f, 0.5f),
        // Theatrical: deep cinematic narrator authority — rich warm voice, zero boom mud, commanding clarity
        "theatrical" to floatArrayOf(-1.0f, 2.5f, 0.0f, 0.8f, 1.5f, 1.2f, 0.8f, 0.5f),
        // Dolby Cinema: signature Dolby immersive voice — deep controlled sub-bass, clean mud scoop, forward dialogue presence, and ultra-silky crystalline air
        "dolby" to floatArrayOf(-0.5f, 3.2f, -0.6f, 0.6f, 2.2f, 1.8f, 1.6f, 1.8f),
        // Crisp Air & Detail: modern HD creator sound — warm solid bottom with open, silky top end
        "bass_treble" to floatArrayOf(-0.5f, 2.5f, 0.5f, 0.0f, 1.2f, 2.0f, 1.8f, 1.8f),
        // Warm Intimate: late-night radio — rich velvety analog tube vocal bass, smooth rounded top
        "ultra_bass" to floatArrayOf(0.0f, 4.0f, 1.8f, 0.5f, 0.0f, -0.5f, -1.0f, -1.0f),
        // Crystal Presence: clear forward articulation supported by solid vocal chest warmth
        "crystal_treble" to floatArrayOf(-1.5f, 1.8f, -0.5f, 0.8f, 2.2f, 1.8f, 1.2f, 1.0f),
        // Studio Booth: acoustically treated dead vocal booth — warm close-mic body with high isolation
        "studio_booth" to floatArrayOf(-1.0f, 2.0f, -0.5f, 0.5f, 1.2f, 1.0f, 0.5f, 0.5f),
        "studio" to floatArrayOf(-0.5f, 2.0f, 0.5f, 0.5f, 1.2f, 1.0f, 0.5f, 0.5f),
    )

    /** Enhance level: exciter amount, compressor ratio, extra presence (dB at 2.4k / 5k). */
    private class Level(val exciter: Float, val ratio: Float, val presence: Float, val body: Float)

    private val levels = mapOf(
        "natural" to Level(0.05f, 2.0f, 0.0f, 0.5f),
        "enhanced" to Level(0.20f, 2.4f, 0.8f, 1.2f),
        "max" to Level(0.35f, 2.8f, 1.5f, 1.8f),
    )

    /** Broadcast speech: deep noise removal, warm intelligibility EQ, tight dynamics, voice filter + level. */
    fun podcast(
        tone: String = "general_bass",
        level: String = "enhanced",
        info: VoiceInfo? = null,
    ): VocalFx {
        // Base EQ: Clean rumble cut at 60Hz, +2.0dB chest resonance at 150Hz (warm vocal bass), balanced mids and highs
        val base = floatArrayOf(-2.0f, 2.0f, 0.0f, 0.5f, 1.5f, 1.0f, 0.5f, 0.5f)
        val off = podcastTones[tone] ?: podcastTones.getValue("general_bass")
        val lv = levels[level] ?: levels.getValue("enhanced")
        val gains = FloatArray(8) { base[it] + off[it] }
        gains[1] += lv.body * 0.5f // add vocal bass warmth per level
        gains[2] += lv.body * 0.3f
        gains[4] += lv.presence * 0.7f
        gains[5] += lv.presence * 0.5f
        val warmAmt = when (tone) {
            "ultra_bass" -> 0.32f
            "dolby" -> 0.22f
            "theatrical" -> 0.18f
            "general_bass" -> 0.15f
            "studio_booth" -> 0.12f
            else -> 0.14f
        }
        val exAmt = when (tone) {
            "dolby" -> (lv.exciter + 0.18f).coerceAtMost(0.48f)
            "crystal_treble" -> (lv.exciter + 0.15f).coerceAtMost(0.45f)
            "bass_treble" -> (lv.exciter + 0.12f).coerceAtMost(0.40f)
            "theatrical" -> (lv.exciter + 0.08f).coerceAtMost(0.35f)
            "studio_booth" -> (lv.exciter + 0.06f).coerceAtMost(0.30f)
            "ultra_bass" -> 0.0f
            else -> lv.exciter
        }
        val compRatio = when (tone) {
            "dolby" -> (lv.ratio + 0.35f).coerceAtMost(3.2f)
            "crystal_treble", "theatrical" -> (lv.ratio + 0.3f).coerceAtMost(3.2f)
            "studio_booth", "ultra_bass" -> (lv.ratio + 0.2f).coerceAtMost(3.0f)
            else -> lv.ratio
        }
        // Musical high-pass cutoff (60-70 Hz) that preserves male and female vocal pitch fundamentals
        val hpf = when (tone) {
            "crystal_treble" -> 72f
            "studio_booth" -> 68f
            "dolby", "theatrical", "bass_treble" -> 65f
            else -> 60f
        }
        val deEssAmt = if (tone == "studio_booth" || tone == "theatrical" || tone == "dolby") 0.70f else 0.65f
        return VocalFx(
            hpfHz = hpf, denoise = 1.0f, gateOn = true, gateThresholdDb = -52f,
            deEssOn = true, deEss = deEssAmt, deEssHz = 6400f,
            eqOn = true, eqGains = gains,
            compOn = true, compThresholdDb = -22f, compRatio = compRatio, compAttackMs = 12f, compReleaseMs = 180f, compMakeupDb = 0f,
            warmth = warmAmt, exciter = exAmt,
            reverbMix = if (tone == "dolby") 0.15f else 0f,
            reverbSize = if (tone == "dolby") 0.52f else 0.30f,
            reverbDamp = if (tone == "dolby") 0.42f else 0.5f,
            reverbPreMs = if (tone == "dolby") 18f else 14f,
            limiterCeilingDb = -1f,
        )
    }

    /** Tone presets are added, band by band, to the pitch-adaptive base EQ (60, 150, 400, 1k, 2.4k, 5k, 8k, 12k Hz). */
    private val tones = mapOf(
        "natural" to floatArrayOf(0f, 1.0f, 0.0f, 0f, 0f, 0f, 0f, 0f),
        "smooth" to floatArrayOf(0f, 2.0f, 1.0f, 0f, -0.5f, -1.0f, -1.0f, -0.5f),
        "warm" to floatArrayOf(0.5f, 3.5f, 2.0f, 0.5f, 0.0f, -0.5f, -1.0f, -1.0f),
        "bright" to floatArrayOf(-0.5f, 1.5f, -0.5f, 0.5f, 1.5f, 2.0f, 2.0f, 2.0f),
        "deep" to floatArrayOf(1.0f, 4.5f, 2.5f, 0f, 0.5f, 0f, -0.5f, -0.5f),
        "radio" to floatArrayOf(-1.5f, 2.0f, 0.5f, 1.5f, 2.0f, 1.0f, 0f, -0.5f),
        // Dolby Spatial: immersive 3D spatial field, harmonic air sheen, clear vocal presence & full-bodied resonance
        "dolby" to floatArrayOf(0.0f, 3.0f, -0.6f, 0.5f, 2.0f, 1.8f, 2.2f, 2.4f),
    )

    /** Space presets: reverb mix, size, damping, pre-delay. */
    private class Space(val mix: Float, val size: Float, val damp: Float, val pre: Float)

    private val spaces = mapOf(
        "dry" to Space(0f, 0.4f, 0.5f, 20f),
        "room" to Space(0.12f, 0.30f, 0.45f, 14f),
        "plate" to Space(0.18f, 0.50f, 0.35f, 20f),
        "hall" to Space(0.22f, 0.70f, 0.55f, 30f),
        "wide" to Space(0.20f, 0.55f, 0.35f, 18f),
        "dolby" to Space(0.24f, 0.60f, 0.38f, 16f),
    )

    fun reverbTailSeconds(space: String): Double = when (space) { "dry" -> 0.0; "room" -> 0.6; "hall" -> 1.8; "dolby" -> 1.4; else -> 1.2 }

    fun vocals(v: VoiceInfo, tone: String = "natural", space: String = "dry"): VocalFx {
        val f0 = if (v.f0Median > 0f) v.f0Median else 180f
        val p10 = if (v.f0P10 > 0f) v.f0P10 else f0 * 0.8f
        val hpf = (0.45f * p10).coerceIn(50f, 85f)
        val mudCut = if (f0 < 150f) -1.2f else -0.5f // keep vocal weight without boxiness
        val presence = if (f0 < 200f) 1.8f else 1.5f
        val air = if (f0 < 200f) 1.0f else 1.4f
        // Base EQ for singing: Solid warm chest resonance at 150Hz (+2.5dB), gentle highs
        val base = floatArrayOf(-1.5f, 2.5f, mudCut, 0.5f, presence, 1.0f, 0.5f, air)
        val off = tones[tone] ?: tones.getValue("natural")
        val sp = spaces[space] ?: spaces.getValue("dry")
        val warmAmt = when (tone) {
            "warm", "deep" -> 0.30f
            "dolby" -> 0.24f
            "smooth" -> 0.22f
            else -> 0.16f
        }
        val exAmt = when (tone) {
            "dolby" -> 0.32f
            "bright" -> 0.30f
            "radio" -> 0.20f
            "natural" -> 0.15f
            "deep" -> 0.10f
            "smooth", "warm" -> 0.08f
            else -> 0.12f
        }
        return VocalFx(
            hpfHz = hpf, denoise = 1.0f, gateOn = true, gateThresholdDb = -55f,
            deEssOn = true, deEss = 0.65f, deEssHz = (5200f + 6f * f0).coerceIn(5500f, 8200f),
            eqOn = true, eqGains = FloatArray(8) { base[it] + off[it] },
            compOn = true, compThresholdDb = -22f, compRatio = 2.6f, compAttackMs = 12f, compReleaseMs = 160f, compMakeupDb = 0f,
            warmth = warmAmt, exciter = exAmt,
            reverbMix = sp.mix, reverbSize = sp.size, reverbDamp = sp.damp, reverbPreMs = sp.pre, limiterCeilingDb = -1f,
        )
    }
}
