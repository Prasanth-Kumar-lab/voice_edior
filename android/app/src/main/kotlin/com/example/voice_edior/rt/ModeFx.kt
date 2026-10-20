package com.example.voice_edior.rt

import com.example.voice_edior.dsp.VoiceInfo
import com.example.voice_edior.dsp.VocalFx

/** The two product modes as native chains. Vocals is steered by the detected pitch, then a Tone and a Space are picked. */
object ModeFx {
    /** Podcast voice filters, added band by band to the speech base EQ (60, 150, 400, 1k, 2.4k, 5k, 8k, 12k Hz). */
    private val podcastTones = mapOf(
        "general_bass" to floatArrayOf(3.0f, 3.5f, -1.5f, 0.5f, 2.0f, 2.0f, 1.5f, 1.5f),
        "theatrical" to floatArrayOf(4.0f, 4.5f, -2.5f, 0.0f, 2.5f, 1.5f, -1.5f, -2.5f),
        "bass_treble" to floatArrayOf(4.0f, 4.0f, -3.5f, -1.0f, 3.5f, 4.5f, 4.5f, 5.0f),
        "ultra_bass" to floatArrayOf(5.5f, 5.5f, -2.0f, -1.0f, 1.0f, -2.5f, -4.5f, -6.0f),
        "crystal_treble" to floatArrayOf(-3.0f, -2.5f, -2.5f, 1.0f, 4.0f, 5.0f, 5.0f, 5.5f),
        "studio_booth" to floatArrayOf(3.0f, 3.5f, -2.0f, 1.0f, 2.5f, 3.0f, 2.5f, 3.0f),
    )

    /** Enhance level: exciter amount, compressor ratio, extra presence (dB at 2.4k / 5k). */
    private class Level(val exciter: Float, val ratio: Float, val presence: Float, val body: Float)

    private val levels = mapOf(
        "natural" to Level(0f, 2.0f, 0f, 0f),
        "enhanced" to Level(0.4f, 2.4f, 1.5f, 1.0f),
        "max" to Level(0.6f, 2.8f, 2.5f, 2.0f),
    )

    /** Broadcast speech: aggressive clean-up, intelligibility EQ, tight dynamics, then the chosen voice filter + level. */
    fun podcast(tone: String = "general_bass", level: String = "enhanced"): VocalFx {
        val base = floatArrayOf(-5f, -1.5f, -2.5f, 0.5f, 3.0f, 1.5f, -1.5f, 1.5f)
        val off = podcastTones[tone] ?: podcastTones.getValue("general_bass")
        val lv = levels[level] ?: levels.getValue("enhanced")
        val gains = FloatArray(8) { base[it] + off[it] }
        gains[1] += lv.body; gains[2] += lv.body * 0.5f
        gains[4] += lv.presence; gains[5] += lv.presence * 0.8f; gains[6] += lv.presence * 0.3f
        val revMix = when (tone) {
            "theatrical" -> 0.18f
            "studio_booth" -> 0.12f
            else -> 0f
        }
        val revSize = if (tone == "theatrical") 0.8f else 0.35f
        val warmAmt = when (tone) {
            "ultra_bass" -> 0.28f
            "studio_booth" -> 0.25f
            "theatrical" -> 0.18f
            else -> 0.12f
        }
        val exAmt = when (tone) {
            "crystal_treble" -> (lv.exciter + 0.35f).coerceAtMost(0.95f)
            "bass_treble" -> (lv.exciter + 0.25f).coerceAtMost(0.9f)
            "ultra_bass" -> 0f
            else -> lv.exciter
        }
        return VocalFx(
            hpfHz = 70f, denoise = 1.0f, gateOn = true, gateThresholdDb = -52f,
            deEssOn = true, deEss = 0.7f, deEssHz = 6500f,
            eqOn = true, eqGains = gains,
            compOn = true, compThresholdDb = -24f, compRatio = lv.ratio, compAttackMs = 10f, compReleaseMs = 170f, compMakeupDb = 0f,
            warmth = warmAmt, exciter = exAmt, reverbMix = revMix, reverbSize = revSize, limiterCeilingDb = -1f,
        )
    }

    /** Tone presets are added, band by band, to the pitch-adaptive base EQ (60, 150, 400, 1k, 2.4k, 5k, 8k, 12k Hz). */
    private val tones = mapOf(
        "natural" to floatArrayOf(0f, 0f, 0f, 0f, 0f, 0f, 0f, 0f),
        "smooth" to floatArrayOf(0f, 0.5f, 0.5f, 0f, -1.5f, -2f, -1.5f, -0.5f),
        "warm" to floatArrayOf(0f, 2.0f, 1.5f, 0f, -0.5f, -1.5f, -2f, -2.5f),
        "bright" to floatArrayOf(0f, -0.5f, -1f, 0f, 1.5f, 2.5f, 3f, 4f),
        "deep" to floatArrayOf(2f, 3f, 1.5f, 0f, 0.3f, 0f, -0.5f, -1f),
        "radio" to floatArrayOf(-3f, -1.5f, 0f, 1.5f, 3f, 1f, -1.5f, -3f),
    )

    /** Space presets: reverb mix, size, damping, pre-delay. (The phone engine is mono; "wide" is stereo only via the service.) */
    private class Space(val mix: Float, val size: Float, val damp: Float, val pre: Float)

    private val spaces = mapOf(
        "dry" to Space(0f, 0.5f, 0.5f, 20f),
        "room" to Space(0.12f, 0.3f, 0.4f, 12f),
        "plate" to Space(0.18f, 0.55f, 0.3f, 22f),
        "hall" to Space(0.22f, 0.85f, 0.55f, 35f),
        "wide" to Space(0.20f, 0.6f, 0.3f, 18f),
    )

    fun reverbTailSeconds(space: String): Double = when (space) { "dry" -> 0.0; "room" -> 0.8; "hall" -> 2.4; else -> 1.6 }

    fun vocals(v: VoiceInfo, tone: String = "natural", space: String = "dry"): VocalFx {
        val f0 = if (v.f0Median > 0f) v.f0Median else 180f
        val p10 = if (v.f0P10 > 0f) v.f0P10 else f0 * 0.8f
        val hpf = (0.55f * p10).coerceIn(60f, 140f)
        val mudCut = if (f0 < 150f) -3.0f else -2.2f           // low voices carry more 250–400 Hz build-up
        val presence = if (f0 < 200f) 3.0f else 2.2f
        val air = if (f0 < 200f) 1.5f else 2.2f
        val base = floatArrayOf(-6f, -1.0f, mudCut, 0.0f, presence, 0.8f, -1.5f, air)
        val off = tones[tone] ?: tones.getValue("natural")
        val sp = spaces[space] ?: spaces.getValue("dry")
        return VocalFx(
            hpfHz = hpf, denoise = 0.9f, gateOn = true, gateThresholdDb = -58f,
            deEssOn = true, deEss = 0.7f, deEssHz = (5200f + 7f * f0).coerceIn(5500f, 8500f),
            eqOn = true, eqGains = FloatArray(8) { base[it] + off[it] },
            compOn = true, compThresholdDb = -22f, compRatio = 3.0f, compAttackMs = 10f, compReleaseMs = 150f, compMakeupDb = 0f,
            warmth = if (f0 > 200f) 0.12f else 0.2f,
            reverbMix = sp.mix, reverbSize = sp.size, reverbDamp = sp.damp, reverbPreMs = sp.pre, limiterCeilingDb = -1f,
        )
    }
}
