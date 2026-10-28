package com.example.voice_edior.rt

import com.example.voice_edior.dsp.VoiceInfo
import com.example.voice_edior.dsp.VocalFx

/** The two product modes as native chains. Vocals is steered by the detected pitch, then a Tone and a Space are picked. */
object ModeFx {
    /** Podcast voice filters, added band by band to the speech base EQ (60, 150, 400, 1k, 2.4k, 5k, 8k, 12k Hz). */
    private val podcastTones = mapOf(
        // Studio Clarity: zero mud, crystal presence, pitch-adaptive body, zero high hiss
        "general_bass" to floatArrayOf(-3.0f, 0.0f, -2.5f, 0.8f, 2.8f, 1.8f, -1.5f, -3.5f),
        // Theatrical + Bass: movie-trailer bass + sub-octave + cinema-hall depth (Super & Next Level)
        "theatrical" to floatArrayOf(4.5f, 5.0f, -3.0f, 0.5f, 2.8f, 1.2f, -2.5f, -4.5f),
        // Crisp Air & Detail: HD articulation with silky consonant detail, zero low-end mud, zero hiss
        "bass_treble" to floatArrayOf(-4.0f, -1.0f, -3.0f, 0.5f, 3.2f, 3.0f, 1.0f, -1.5f),
        // Warm Intimate: velvet tube warmth and smooth presence, close-mic proximity without boom
        "ultra_bass" to floatArrayOf(-2.0f, 0.5f, 0.8f, 0.5f, 1.5f, -0.5f, -3.0f, -5.0f),
        // Crystal Presence: razor-sharp articulation, forward intelligibility for soft voices
        "crystal_treble" to floatArrayOf(-4.5f, -2.5f, -2.5f, 1.8f, 4.2f, 3.5f, 0.5f, -2.0f),
        // Studio Booth: acoustically treated studio room with wide stereo depth
        "studio_booth" to floatArrayOf(-3.0f, 0.0f, -2.0f, 1.0f, 2.5f, 1.8f, -1.0f, -3.0f),
    )

    /** Enhance level: exciter amount, compressor ratio, extra presence (dB at 2.4k / 5k / 8k). */
    private class Level(val exciter: Float, val ratio: Float, val presence: Float, val air: Float, val body: Float)

    private val levels = mapOf(
        "natural" to Level(0f, 2.0f, 0f, -1.5f, 0f),
        "enhanced" to Level(0.42f, 2.5f, 1.5f, 1.4f, 1.0f),
        "max" to Level(0.75f, 2.9f, 2.4f, 2.8f, 1.8f),
    )

    /** Broadcast speech: aggressive clean-up, intelligibility EQ, tight dynamics, then the chosen voice filter + level. */
    fun podcast(
        tone: String = "general_bass",
        level: String = "enhanced",
        info: VoiceInfo? = null,
    ): VocalFx {
        val base = floatArrayOf(-5f, -1.5f, -2.5f, 0.5f, 2.5f, 1.0f, -2.5f, -3.0f)
        val off = podcastTones[tone] ?: podcastTones.getValue("general_bass")
        val lv = levels[level] ?: levels.getValue("enhanced")
        val gains = FloatArray(8) { base[it] + off[it] }

        // Pitch-adaptive vocal body & clean clarity
        val f0 = if (info != null && info.f0Median > 0f) info.f0Median else 150f
        if (tone == "theatrical") {
            // Keep Theatrical + Bass massive cinematic sub-bass & chest resonance
            gains[0] += 3.5f
            gains[1] += lv.body + 2.0f
        } else {
            // All other filters: automatically apply clean, pitch-tracked voice body without subwoofer rumble
            if (f0 < 130f) {
                // Baritone / deep voice: track 100-130 Hz fundamental cleanly
                gains[0] -= 1.0f // cut rumble
                gains[1] += 1.2f + lv.body * 0.4f // tight body
                gains[2] -= 1.0f // clean 250-400 Hz boxiness
            } else if (f0 > 185f) {
                // Higher / female voice: fundamental is around 200 Hz
                gains[0] -= 2.5f // remove low rumble
                gains[1] += 0.5f
                gains[2] += 1.0f + lv.body * 0.4f // body around 250-400 Hz
            } else {
                // Mid voice (~150 Hz)
                gains[1] += 1.0f + lv.body * 0.4f
            }
        }

        gains[4] += lv.presence; gains[5] += lv.presence * 0.85f; gains[6] += lv.air
        val revMix = when (tone) {
            "theatrical" -> 0.10f
            "studio_booth" -> 0.08f
            else -> 0f
        }
        val revSize = if (tone == "theatrical") 0.65f else 0.30f
        val warmAmt = when (tone) {
            "ultra_bass" -> 0.35f
            "studio_booth" -> 0.15f
            "theatrical" -> 0.20f
            "general_bass" -> 0.08f
            else -> 0.05f
        }
        val exAmt = when (tone) {
            "crystal_treble" -> (lv.exciter + 0.15f).coerceAtMost(0.85f)
            "bass_treble" -> (lv.exciter + 0.10f).coerceAtMost(0.80f)
            "ultra_bass" -> 0.0f
            else -> lv.exciter.coerceAtMost(0.75f)
        }
        val hpf = if (tone == "theatrical") 55f else (0.65f * (info?.f0P10 ?: (f0 * 0.8f))).coerceIn(75f, 125f)
        return VocalFx(
            hpfHz = hpf, denoise = 1.0f, gateOn = true, gateThresholdDb = -48f,
            deEssOn = true, deEss = 0.88f, deEssHz = 6200f,
            eqOn = true, eqGains = gains,
            compOn = true, compThresholdDb = -24f, compRatio = lv.ratio, compAttackMs = 10f, compReleaseMs = 170f, compMakeupDb = 0f,
            warmth = warmAmt, exciter = exAmt, reverbMix = revMix, reverbSize = revSize, reverbDamp = 0.75f, limiterCeilingDb = -1f,
        )
    }

    /** Tone presets are added, band by band, to the pitch-adaptive base EQ (60, 150, 400, 1k, 2.4k, 5k, 8k, 12k Hz). */
    private val tones = mapOf(
        "natural" to floatArrayOf(0f, 0f, 0f, 0f, 0f, 0f, -1.5f, -3.0f),
        "smooth" to floatArrayOf(0f, 0.5f, 0.5f, 0f, -1.0f, -2.0f, -3.0f, -4.5f),
        "warm" to floatArrayOf(0f, 2.0f, 1.5f, 0f, -0.5f, -1.5f, -3.0f, -5.0f),
        "bright" to floatArrayOf(0f, -0.5f, -1f, 0.8f, 2.2f, 2.5f, 0.5f, -1.5f),
        "deep" to floatArrayOf(1.5f, 2.5f, 1.5f, 0f, 0.5f, 0f, -2.0f, -4.0f),
        "radio" to floatArrayOf(-3f, -1.5f, 0f, 1.8f, 3.2f, 1.2f, -2.5f, -5.0f),
    )

    /** Space presets: reverb mix, size, damping, pre-delay. (The phone engine is mono; "wide" is stereo only via the service.) */
    private class Space(val mix: Float, val size: Float, val damp: Float, val pre: Float)

    private val spaces = mapOf(
        "dry" to Space(0f, 0.5f, 0.65f, 20f),
        "room" to Space(0.08f, 0.3f, 0.65f, 12f),
        "plate" to Space(0.12f, 0.5f, 0.65f, 22f),
        "hall" to Space(0.15f, 0.75f, 0.75f, 35f),
        "wide" to Space(0.12f, 0.55f, 0.65f, 18f),
    )

    fun reverbTailSeconds(space: String): Double = when (space) { "dry" -> 0.0; "room" -> 0.8; "hall" -> 2.4; else -> 1.6 }

    fun vocals(v: VoiceInfo, tone: String = "natural", space: String = "dry"): VocalFx {
        val f0 = if (v.f0Median > 0f) v.f0Median else 180f
        val p10 = if (v.f0P10 > 0f) v.f0P10 else f0 * 0.8f
        val hpf = (0.65f * p10).coerceIn(75f, 140f)
        val mudCut = if (f0 < 150f) -3.0f else -2.2f           // low voices carry more 250–400 Hz build-up
        val presence = if (f0 < 200f) 2.8f else 2.2f
        val base = floatArrayOf(-6f, -1.0f, mudCut, 0.5f, presence, 0.8f, -2.5f, -3.5f)
        val off = tones[tone] ?: tones.getValue("natural")
        val sp = spaces[space] ?: spaces.getValue("dry")
        return VocalFx(
            hpfHz = hpf, denoise = 1.0f, gateOn = true, gateThresholdDb = -48f,
            deEssOn = true, deEss = 0.88f, deEssHz = (5200f + 6f * f0).coerceIn(5500f, 7800f),
            eqOn = true, eqGains = FloatArray(8) { base[it] + off[it] },
            compOn = true, compThresholdDb = -22f, compRatio = 3.0f, compAttackMs = 10f, compReleaseMs = 150f, compMakeupDb = 0f,
            warmth = if (f0 > 200f) 0.14f else 0.22f,
            reverbMix = sp.mix, reverbSize = sp.size, reverbDamp = sp.damp, reverbPreMs = sp.pre, limiterCeilingDb = -1f,
        )
    }
}
