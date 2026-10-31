package com.example.voice_edior.rt

import com.example.voice_edior.dsp.VoiceInfo
import com.example.voice_edior.dsp.VocalFx

/** The two product modes as native chains. Vocals is steered by the detected pitch, then a Tone and a Space are picked. */
object ModeFx {
    /** Podcast voice filters, added band by band to the speech base EQ (60, 150, 400, 1k, 2.4k, 5k, 8k, 12k Hz). */
    private val podcastTones = mapOf(
        // Studio Clarity: neutral, articulate broadcast microphone (zero bass boom, crisp presence)
        "general_bass" to floatArrayOf(-3.0f, 1.5f, -1.5f, 1.0f, 2.5f, 2.5f, 2.0f, 1.5f),
        // Theatrical: clean cinematic narrator voice — zero bass mud, commanding mid-high focus & clarity
        "theatrical" to floatArrayOf(-4.5f, -2.0f, -3.5f, 2.5f, 4.5f, 4.0f, 3.0f, 2.5f),
        // Crisp Air & Detail: modern HD creator sound — open, sparkling high-definition top end
        "bass_treble" to floatArrayOf(-4.0f, 0.5f, -2.0f, 0.5f, 3.5f, 5.0f, 5.5f, 5.5f),
        // Warm Intimate: late-night radio — warm low-mid body, analog tube colour, smooth velvety top
        "ultra_bass" to floatArrayOf(-1.0f, 3.5f, 3.5f, 1.5f, 0.0f, -3.5f, -5.0f, -6.5f),
        // Crystal Presence: maximum forward projection — tight low cut, cuts through any phone speaker
        "crystal_treble" to floatArrayOf(-5.0f, -2.5f, -2.5f, 2.5f, 5.0f, 5.0f, 4.0f, 3.5f),
        // Studio Booth: acoustically treated dead vocal booth — ultra-clean isolation, zero room boxiness
        "studio_booth" to floatArrayOf(-5.0f, -2.5f, -4.5f, 2.0f, 3.8f, 3.5f, 2.5f, 2.5f),
        "studio" to floatArrayOf(-3.0f, 1.5f, -1.5f, 1.0f, 2.5f, 2.5f, 2.0f, 1.5f),
    )

    /** Enhance level: exciter amount, compressor ratio, extra presence (dB at 2.4k / 5k). */
    private class Level(val exciter: Float, val ratio: Float, val presence: Float, val body: Float)

    private val levels = mapOf(
        "natural" to Level(0f, 2.0f, 0f, 0f),
        "enhanced" to Level(0.4f, 2.4f, 1.5f, 1.0f),
        "max" to Level(0.6f, 2.8f, 2.5f, 2.0f),
    )

    /** Broadcast speech: deep noise removal, intelligibility EQ, tight dynamics, then the chosen voice filter + level. */
    fun podcast(
        tone: String = "general_bass",
        level: String = "enhanced",
        info: VoiceInfo? = null,
    ): VocalFx {
        val base = floatArrayOf(-5f, -1.5f, -2.5f, 0.5f, 3.0f, 1.5f, -1.5f, 1.5f)
        val off = podcastTones[tone] ?: podcastTones.getValue("general_bass")
        val lv = levels[level] ?: levels.getValue("enhanced")
        val gains = FloatArray(8) { base[it] + off[it] }
        gains[2] += lv.body * 0.3f
        gains[4] += lv.presence
        gains[5] += lv.presence * 0.8f
        gains[6] += lv.presence * 0.3f
        val warmAmt = when (tone) {
            "ultra_bass" -> 0.28f
            "theatrical" -> 0.06f
            "studio_booth" -> 0.05f
            else -> 0.10f
        }
        val exAmt = when (tone) {
            "crystal_treble" -> (lv.exciter + 0.35f).coerceAtMost(0.90f)
            "bass_treble" -> (lv.exciter + 0.30f).coerceAtMost(0.85f)
            "theatrical" -> (lv.exciter + 0.22f).coerceAtMost(0.80f)
            "studio_booth" -> (lv.exciter + 0.18f).coerceAtMost(0.75f)
            "ultra_bass" -> 0f
            else -> lv.exciter
        }
        val compRatio = when (tone) {
            "crystal_treble", "theatrical" -> (lv.ratio + 0.6f).coerceAtMost(3.6f)
            "studio_booth", "ultra_bass" -> (lv.ratio + 0.4f).coerceAtMost(3.4f)
            else -> lv.ratio
        }
        val hpf = when (tone) {
            "crystal_treble" -> 105f
            "studio_booth" -> 95f
            "theatrical", "bass_treble" -> 90f
            else -> 75f
        }
        val deEssAmt = if (tone == "studio_booth" || tone == "theatrical") 0.82f else 0.75f
        return VocalFx(
            hpfHz = hpf, denoise = 1.0f, gateOn = true, gateThresholdDb = -52f,
            deEssOn = true, deEss = deEssAmt, deEssHz = 6400f,
            eqOn = true, eqGains = gains,
            compOn = true, compThresholdDb = -24f, compRatio = compRatio, compAttackMs = 10f, compReleaseMs = 170f, compMakeupDb = 0f,
            warmth = warmAmt, exciter = exAmt, reverbMix = 0f, reverbSize = 0.35f, reverbDamp = 0.5f, reverbPreMs = 14f, limiterCeilingDb = -1f,
        )
    }

    /** Tone presets are added, band by band, to the pitch-adaptive base EQ (60, 150, 400, 1k, 2.4k, 5k, 8k, 12k Hz). */
    private val tones = mapOf(
        "natural" to floatArrayOf(0f, 0f, 0f, 0f, 0f, 0f, 0f, 0f),
        "smooth" to floatArrayOf(0f, 1.5f, 1.5f, 0.5f, -2.5f, -3.5f, -3.0f, -2.0f),
        "warm" to floatArrayOf(1.5f, 4.0f, 3.0f, 1.0f, -1.0f, -2.5f, -3.5f, -4.0f),
        "bright" to floatArrayOf(-2.0f, -1.5f, -2.0f, 0.5f, 3.0f, 4.5f, 5.0f, 5.5f),
        "deep" to floatArrayOf(4.5f, 5.5f, 2.5f, 0.0f, 0.5f, -1.0f, -2.0f, -2.5f),
        "radio" to floatArrayOf(-5.0f, -3.0f, -1.0f, 3.0f, 5.0f, 3.0f, -2.0f, -4.5f),
    )

    /** Space presets: reverb mix, size, damping, pre-delay. */
    private class Space(val mix: Float, val size: Float, val damp: Float, val pre: Float)

    private val spaces = mapOf(
        "dry" to Space(0f, 0.5f, 0.5f, 20f),
        "room" to Space(0.16f, 0.35f, 0.40f, 14f),
        "plate" to Space(0.24f, 0.60f, 0.30f, 22f),
        "hall" to Space(0.30f, 0.88f, 0.50f, 35f),
        "wide" to Space(0.26f, 0.65f, 0.30f, 18f),
    )

    fun reverbTailSeconds(space: String): Double = when (space) { "dry" -> 0.0; "room" -> 0.8; "hall" -> 2.4; else -> 1.6 }

    fun vocals(v: VoiceInfo, tone: String = "natural", space: String = "dry"): VocalFx {
        val f0 = if (v.f0Median > 0f) v.f0Median else 180f
        val p10 = if (v.f0P10 > 0f) v.f0P10 else f0 * 0.8f
        val hpf = if (tone == "deep") 55f else (0.55f * p10).coerceIn(60f, 140f)
        val mudCut = if (f0 < 150f) -3.0f else -2.2f           // low voices carry more 250–400 Hz build-up
        val presence = if (f0 < 200f) 3.0f else 2.2f
        val air = if (f0 < 200f) 1.5f else 2.2f
        val base = floatArrayOf(-6f, -1.0f, mudCut, 0.0f, presence, 0.8f, -1.5f, air)
        val off = tones[tone] ?: tones.getValue("natural")
        val sp = spaces[space] ?: spaces.getValue("dry")
        val warmAmt = when (tone) {
            "warm", "deep" -> 0.26f
            "smooth" -> 0.20f
            else -> if (f0 > 200f) 0.12f else 0.18f
        }
        val exAmt = when (tone) {
            "bright" -> 0.45f
            "radio" -> 0.25f
            else -> 0.12f
        }
        return VocalFx(
            hpfHz = hpf, denoise = 1.0f, gateOn = true, gateThresholdDb = -55f,
            deEssOn = true, deEss = 0.75f, deEssHz = (5200f + 7f * f0).coerceIn(5500f, 8500f),
            eqOn = true, eqGains = FloatArray(8) { base[it] + off[it] },
            compOn = true, compThresholdDb = -22f, compRatio = 3.0f, compAttackMs = 10f, compReleaseMs = 150f, compMakeupDb = 0f,
            warmth = warmAmt, exciter = exAmt,
            reverbMix = sp.mix, reverbSize = sp.size, reverbDamp = sp.damp, reverbPreMs = sp.pre, limiterCeilingDb = -1f,
        )
    }
}
