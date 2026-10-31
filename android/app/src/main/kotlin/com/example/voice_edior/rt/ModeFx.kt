package com.example.voice_edior.rt

import com.example.voice_edior.dsp.VoiceInfo
import com.example.voice_edior.dsp.VocalFx

/** The two product modes as native chains. Vocals is steered by the detected pitch, then a Tone and a Space are picked. */
object ModeFx {
    /** Podcast voice filters, added band by band to the speech base EQ (60, 150, 400, 1k, 2.4k, 5k, 8k, 12k Hz). */
    private val podcastTones = mapOf(
        // Studio Clarity: pure, clean broadcast voice without bass boom or harshness (flat 150 Hz fundamental)
        "general_bass" to floatArrayOf(0.0f, 1.5f, -1.0f, 0.5f, 2.0f, 1.5f, 1.0f, 0.5f),
        // Theatrical + Bass: warm, deep natural studio bass + clear voice (only filter with bass boost)
        "theatrical" to floatArrayOf(5.0f, 5.5f, -2.0f, 0.0f, 2.0f, 1.2f, -0.5f, -1.0f),
        // Crisp Air & Detail: clean high-definition consonant detail without bass boost
        "bass_treble" to floatArrayOf(-1.0f, 1.5f, -1.5f, 0.5f, 2.5f, 3.0f, 2.5f, 2.0f),
        // Warm Intimate: smooth, warm close-mic midrange presence without sub-bass boom
        "ultra_bass" to floatArrayOf(0.0f, 2.0f, 1.5f, 0.5f, 0.5f, -1.0f, -2.0f, -2.5f),
        // Crystal Presence: forward vocal articulation and studio condenser clarity
        "crystal_treble" to floatArrayOf(-2.0f, 0.5f, -1.5f, 1.5f, 3.5f, 3.5f, 3.0f, 2.5f),
        // Studio Booth: balanced, treated studio booth clarity
        "studio_booth" to floatArrayOf(-0.5f, 1.5f, -1.0f, 1.0f, 2.2f, 2.0f, 1.5f, 1.0f),
        "studio" to floatArrayOf(0.0f, 1.5f, -1.0f, 0.5f, 2.0f, 1.5f, 1.0f, 0.5f),
    )

    /** Enhance level: exciter amount, compressor ratio, extra presence (dB at 2.4k / 5k). */
    private class Level(val exciter: Float, val ratio: Float, val presence: Float, val body: Float)

    private val levels = mapOf(
        "natural" to Level(0f, 2.0f, 0f, 0f),
        "enhanced" to Level(0.35f, 2.4f, 1.5f, 0.8f),
        "max" to Level(0.55f, 2.8f, 2.5f, 1.5f),
    )

    /** Broadcast speech: clean noise removal, natural studio EQ, smooth dynamics, zero artificial editor effects. */
    fun podcast(
        tone: String = "general_bass",
        level: String = "enhanced",
        info: VoiceInfo? = null,
    ): VocalFx {
        val base = floatArrayOf(-5f, -1.5f, -2.5f, 0.5f, 2.5f, 1.2f, -1.0f, 0.5f)
        val off = podcastTones[tone] ?: podcastTones.getValue("general_bass")
        val lv = levels[level] ?: levels.getValue("enhanced")
        val gains = FloatArray(8) { base[it] + off[it] }
        if (tone == "theatrical") {
            gains[1] += lv.body
            gains[2] += lv.body * 0.4f
        } else {
            gains[2] += lv.body * 0.3f
        }
        gains[4] += lv.presence; gains[5] += lv.presence * 0.8f; gains[6] += lv.presence * 0.3f
        val warmAmt = when (tone) {
            "ultra_bass" -> 0.18f
            "theatrical" -> 0.15f
            "studio_booth" -> 0.12f
            else -> 0.08f
        }
        val exAmt = when (tone) {
            "crystal_treble" -> (lv.exciter + 0.15f).coerceAtMost(0.65f)
            "bass_treble" -> (lv.exciter + 0.10f).coerceAtMost(0.60f)
            "ultra_bass" -> 0f
            else -> lv.exciter
        }
        val hpf = if (tone == "theatrical") 60f else 75f
        return VocalFx(
            hpfHz = hpf, denoise = 1.0f, gateOn = true, gateThresholdDb = -52f,
            deEssOn = true, deEss = 0.7f, deEssHz = 6500f,
            eqOn = true, eqGains = gains,
            compOn = true, compThresholdDb = -24f, compRatio = lv.ratio, compAttackMs = 10f, compReleaseMs = 170f, compMakeupDb = 0f,
            warmth = warmAmt, exciter = exAmt, reverbMix = 0f, reverbSize = 0.35f, limiterCeilingDb = -1f,
        )
    }

    /** Tone presets are added, band by band, to the pitch-adaptive base EQ (60, 150, 400, 1k, 2.4k, 5k, 8k, 12k Hz). */
    private val tones = mapOf(
        "natural" to floatArrayOf(0f, 0f, 0f, 0f, 0f, 0f, 0f, 0f),
        "smooth" to floatArrayOf(0f, 0.5f, 0.5f, 0f, -1.5f, -2f, -1.5f, -0.5f),
        "warm" to floatArrayOf(0f, 2.0f, 1.5f, 0f, -0.5f, -1.5f, -2f, -2.5f),
        "bright" to floatArrayOf(0f, -0.5f, -1f, 0f, 1.5f, 2.2f, 2.0f, 2.0f),
        "deep" to floatArrayOf(1.5f, 2.5f, 1.5f, 0f, 0.3f, 0f, -0.5f, -1f),
        "radio" to floatArrayOf(-3f, -1.5f, 0f, 1.5f, 2.8f, 1f, -1.5f, -3f),
    )

    /** Space presets: reverb mix, size, damping, pre-delay. */
    private class Space(val mix: Float, val size: Float, val damp: Float, val pre: Float)

    private val spaces = mapOf(
        "dry" to Space(0f, 0.5f, 0.5f, 20f),
        "room" to Space(0.10f, 0.3f, 0.45f, 12f),
        "plate" to Space(0.14f, 0.5f, 0.4f, 22f),
        "hall" to Space(0.18f, 0.75f, 0.55f, 35f),
        "wide" to Space(0.15f, 0.55f, 0.4f, 18f),
    )

    fun reverbTailSeconds(space: String): Double = when (space) { "dry" -> 0.0; "room" -> 0.8; "hall" -> 2.4; else -> 1.6 }

    fun vocals(v: VoiceInfo, tone: String = "natural", space: String = "dry"): VocalFx {
        val f0 = if (v.f0Median > 0f) v.f0Median else 180f
        val p10 = if (v.f0P10 > 0f) v.f0P10 else f0 * 0.8f
        val hpf = (0.55f * p10).coerceIn(60f, 140f)
        val mudCut = if (f0 < 150f) -3.0f else -2.2f           // low voices carry more 250–400 Hz build-up
        val presence = if (f0 < 200f) 2.8f else 2.0f
        val air = if (f0 < 200f) 1.2f else 1.8f
        val base = floatArrayOf(-6f, -1.0f, mudCut, 0.0f, presence, 0.8f, -1.5f, air)
        val off = tones[tone] ?: tones.getValue("natural")
        val sp = spaces[space] ?: spaces.getValue("dry")
        return VocalFx(
            hpfHz = hpf, denoise = 0.9f, gateOn = true, gateThresholdDb = -58f,
            deEssOn = true, deEss = 0.7f, deEssHz = (5200f + 7f * f0).coerceIn(5500f, 8500f),
            eqOn = true, eqGains = FloatArray(8) { base[it] + off[it] },
            compOn = true, compThresholdDb = -22f, compRatio = 3.0f, compAttackMs = 10f, compReleaseMs = 150f, compMakeupDb = 0f,
            warmth = if (f0 > 200f) 0.10f else 0.16f,
            reverbMix = sp.mix, reverbSize = sp.size, reverbDamp = sp.damp, reverbPreMs = sp.pre, limiterCeilingDb = -1f,
        )
    }
}
