package com.example.voice_edior.dsp

/** Immutable snapshot of every knob in the vocal chain. Swapped atomically from the UI thread. */
data class VocalFx(
    val bypass: Boolean = false,
    val inputGainDb: Float = 0f,
    // Clean-up
    val hpfHz: Float = 90f,
    val denoise: Float = 0.55f,       // 0..1 spectral noise reduction amount
    val gateThresholdDb: Float = -58f,
    val gateOn: Boolean = true,
    val gateDepthDb: Float = 26f,     // how far a closed gate attenuates
    val gateReleaseMs: Float = 140f,
    // De-esser
    val deEss: Float = 0.4f,          // 0..1
    val deEssHz: Float = 6500f,
    val deEssOn: Boolean = true,
    // EQ
    val eqOn: Boolean = true,
    val eqGains: FloatArray = floatArrayOf(-2.2f, -1.6f, -2.4f, 0.6f, 3.5f, 1.9f, -3.4f, 2.2f),
    // Compressor
    val compOn: Boolean = true,
    val compThresholdDb: Float = -20f,
    val compRatio: Float = 3f,
    val compAttackMs: Float = 8f,
    val compReleaseMs: Float = 120f,
    val compMakeupDb: Float = 3f,
    // Colour & space
    val warmth: Float = 0f,           // 0..1 analog-style saturation
    val exciter: Float = 0f,          // 0..1 harmonic exciter (generated high-frequency detail)
    val reverbMix: Float = 0f,        // 0..1
    val reverbSize: Float = 0.5f,
    val reverbDamp: Float = 0.5f,
    val reverbPreMs: Float = 20f,
    // Output
    val limiterCeilingDb: Float = -1f,
    val outputGainDb: Float = 0f,
) {
    companion object {
        val EQ_HZ = floatArrayOf(60f, 150f, 400f, 1000f, 2400f, 5000f, 8000f, 12000f)

        @Suppress("UNCHECKED_CAST")
        fun fromMap(m: Map<String, Any?>): VocalFx {
            fun f(k: String, d: Float) = (m[k] as? Number)?.toFloat() ?: d
            fun b(k: String, d: Boolean) = (m[k] as? Boolean) ?: d
            val gains = (m["eqGains"] as? List<Any?>)?.map { (it as Number).toFloat() }
            val base = VocalFx()
            return VocalFx(
                bypass = b("bypass", base.bypass),
                inputGainDb = f("inputGainDb", base.inputGainDb),
                hpfHz = f("hpfHz", base.hpfHz),
                denoise = f("denoise", base.denoise),
                gateThresholdDb = f("gateThresholdDb", base.gateThresholdDb),
                gateOn = b("gateOn", base.gateOn),
                gateDepthDb = f("gateDepthDb", base.gateDepthDb),
                gateReleaseMs = f("gateReleaseMs", base.gateReleaseMs),
                deEss = f("deEss", base.deEss),
                deEssHz = f("deEssHz", base.deEssHz),
                deEssOn = b("deEssOn", base.deEssOn),
                eqOn = b("eqOn", base.eqOn),
                eqGains = if (gains != null && gains.size == 8) gains.toFloatArray() else base.eqGains,
                compOn = b("compOn", base.compOn),
                compThresholdDb = f("compThresholdDb", base.compThresholdDb),
                compRatio = f("compRatio", base.compRatio),
                compAttackMs = f("compAttackMs", base.compAttackMs),
                compReleaseMs = f("compReleaseMs", base.compReleaseMs),
                compMakeupDb = f("compMakeupDb", base.compMakeupDb),
                warmth = f("warmth", base.warmth),
                exciter = f("exciter", base.exciter),
                reverbMix = f("reverbMix", base.reverbMix),
                reverbSize = f("reverbSize", base.reverbSize),
                reverbDamp = f("reverbDamp", base.reverbDamp),
                reverbPreMs = f("reverbPreMs", base.reverbPreMs),
                limiterCeilingDb = f("limiterCeilingDb", base.limiterCeilingDb),
                outputGainDb = f("outputGainDb", base.outputGainDb),
            )
        }
    }
}

/** Meter values produced by one processed block. */
class Meters {
    @Volatile var inPeak = 0f
    @Volatile var inRms = 0f
    @Volatile var outPeak = 0f
    @Volatile var outRms = 0f
    @Volatile var compGrDb = 0f
    @Volatile var deEssGrDb = 0f
    @Volatile var gateOpen = 1f
    @Volatile var clipped = false
}
