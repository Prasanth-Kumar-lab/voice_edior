package com.example.voice_edior.dsp

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tanh

/**
 * Stereo DSP building blocks for the Mix Studio multi-track engine:
 * - Constant-power pan law & fade curves (linear, exponential, S-curve equal-power)
 * - WSOLA pitch-preserving time-stretch (0.5x..2.0x) and pitch-shift (±12 semitones)
 * - Sidechain Auto-Ducker envelope follower
 * - Stereo Ping-Pong Delay, Stereo Freeverb, Chorus/Flanger/Phaser, Saturator, Bitcrusher,
 *   Haas Vocal Doubler, Mid/Side Stereo Widener, Resonant Filter, 8-band EQ, and Compressor.
 */
object MixDspMath {

    /** Constant-power stereo pan law for pan in [-1.0 (L) .. 0.0 (C) .. +1.0 (R)]. */
    fun constantPowerPan(pan: Double): Pair<Double, Double> {
        val p = pan.coerceIn(-1.0, 1.0)
        val angle = (p + 1.0) * 0.25 * PI // 0 .. pi/2
        // Normalize so center pan (0.0) gives 1.0 (0 dB) or equal power sqrt(2)/2
        val norm = sqrt(2.0)
        return Pair(cos(angle) * norm, sin(angle) * norm)
    }

    /** Fade envelope multiplier in [0.0..1.0] for progress t in [0.0..1.0]. */
    fun fadeGain(t: Double, curve: String): Double {
        val x = t.coerceIn(0.0, 1.0)
        return when (curve) {
            "linear" -> x
            "exponential" -> x * x
            else -> sin(x * PI * 0.5) // S-curve equal-power
        }
    }

    /**
     * WSOLA (Waveform Similarity Overlap-Add) pitch-preserving time-stretcher.
     * `rate` > 1.0 speeds up (shorter output); `rate` < 1.0 slows down (longer output).
     */
    fun timeStretchWsola(input: FloatArray, sr: Int, rate: Double): FloatArray {
        val r = rate.coerceIn(0.5, 2.0)
        if (abs(r - 1.0) < 0.01 || input.size < 2048) return input.copyOf()

        val winSize = (0.040 * sr).toInt().coerceAtLeast(512) // 40 ms Hann window
        val synHop = winSize / 2
        val anaHop = (synHop * r).roundToInt().coerceAtLeast(1)
        val searchRange = (0.012 * sr).toInt().coerceAtLeast(64)

        val outLen = max(winSize, (input.size / r).roundToInt())
        val out = FloatArray(outLen + winSize)
        val norm = FloatArray(outLen + winSize)
        val hann = FloatArray(winSize) { i ->
            (0.5 * (1.0 - cos(2.0 * PI * i / (winSize - 1)))).toFloat()
        }

        var synPos = 0
        var expectedAnaPos = 0.0

        while (synPos + winSize < out.size && expectedAnaPos.toInt() + winSize < input.size) {
            val centerAna = expectedAnaPos.toInt()
            var bestOffset = 0
            if (synPos > 0) {
                var bestCorr = -1e30f
                val minOff = max(-searchRange, -centerAna)
                val maxOff = min(searchRange, input.size - winSize - centerAna - 1)
                val step = 4 // decimated correlation for mobile speed
                var off = minOff
                while (off <= maxOff) {
                    var corr = 0f
                    var i = 0
                    while (i < synHop) {
                        corr += out[synPos + i] * input[centerAna + off + i]
                        i += step
                    }
                    if (corr > bestCorr) {
                        bestCorr = corr
                        bestOffset = off
                    }
                    off += 2
                }
            }

            val actualAna = (centerAna + bestOffset).coerceIn(0, input.size - winSize)
            for (i in 0 until winSize) {
                val w = hann[i]
                out[synPos + i] += input[actualAna + i] * w
                norm[synPos + i] += w
            }
            synPos += synHop
            expectedAnaPos = actualAna + anaHop.toDouble()
        }

        val result = FloatArray(outLen)
        for (i in 0 until outLen) {
            result[i] = if (norm[i] > 1e-4f) (out[i] / norm[i]).coerceIn(-1f, 1f) else 0f
        }
        return result
    }

    /**
     * Pitch-shift by `semitones` (-12..+12) while keeping original duration constant
     * (WSOLA time-stretch by 2^(semitones/12) followed by linear cubic-ish resampling).
     */
    fun pitchShiftSemitones(input: FloatArray, sr: Int, semitones: Double): FloatArray {
        val st = semitones.coerceIn(-12.0, 12.0)
        if (abs(st) < 0.05 || input.size < 1024) return input.copyOf()
        val factor = 2.0.pow(st / 12.0)
        // Stretch by 1/factor so resampling by factor restores original length
        val stretched = timeStretchWsola(input, sr, 1.0 / factor)
        val out = FloatArray(input.size)
        val maxIdx = stretched.size - 1
        for (i in out.indices) {
            val pos = i * factor
            val idx = pos.toInt()
            if (idx >= maxIdx) {
                out[i] = stretched[maxIdx]
            } else {
                val frac = (pos - idx).toFloat()
                out[i] = stretched[idx] * (1f - frac) + stretched[idx + 1] * frac
            }
        }
        return out
    }

    /** Compute sidechain Auto-Ducking gain array for a music track keyed by a voice track. */
    fun computeAutoDuckEnvelope(
        voiceMono: FloatArray,
        sr: Int,
        thresholdDb: Double,
        ratio: Double,
        attackMs: Double,
        releaseMs: Double,
        amountDb: Double,
    ): FloatArray {
        val n = voiceMono.size
        val env = FloatArray(n)
        val threshLin = dbToLin(thresholdDb)
        val maxDuckLin = dbToLin(-abs(amountDb))
        val atk = timeCoef(max(2.0, attackMs), sr)
        val rel = timeCoef(max(15.0, releaseMs), sr)
        val slope = 1.0 - 1.0 / max(1.1, ratio)

        var det = 0.0
        var gain = 1.0
        for (i in 0 until n) {
            val a = abs(voiceMono[i].toDouble())
            det = if (a > det) atk * det + (1.0 - atk) * a else rel * det + (1.0 - rel) * a
            val targetGain = if (det > threshLin) {
                val overDb = linToDb(det / threshLin)
                val grDb = -overDb * slope
                max(maxDuckLin, dbToLin(grDb))
            } else {
                1.0
            }
            gain = if (targetGain < gain) {
                atk * gain + (1.0 - atk) * targetGain
            } else {
                rel * gain + (1.0 - rel) * targetGain
            }
            env[i] = gain.toFloat()
        }
        return env
    }
}

/** Stereo buffer container (left and right channels at 48 kHz). */
class StereoBuffer(val left: FloatArray, val right: FloatArray, val sampleRate: Int = 48000) {
    val frames: Int get() = min(left.size, right.size)

    fun copy(): StereoBuffer = StereoBuffer(left.copyOf(), right.copyOf(), sampleRate)
}

/** Applies a list of serialized FX slots (`Map<String, Any?>`) to a `StereoBuffer` in-place. */
object StereoFxChainProcessor {

    fun processChain(buf: StereoBuffer, fxList: List<Map<String, Any?>>) {
        for (slot in fxList) {
            val enabled = slot["enabled"] as? Boolean ?: true
            if (!enabled) continue
            val type = (slot["type"] as? String) ?: continue
            val wet = ((slot["wetDry"] as? Number)?.toDouble() ?: 1.0).coerceIn(0.0, 1.0)
            @Suppress("UNCHECKED_CAST")
            val params = (slot["params"] as? Map<String, Any?>) ?: emptyMap()
            applySingleFx(buf, type, wet, params)
        }
    }

    private fun param(params: Map<String, Any?>, key: String, default: Double): Double =
        (params[key] as? Number)?.toDouble() ?: default

    private fun applySingleFx(
        buf: StereoBuffer,
        type: String,
        wet: Double,
        params: Map<String, Any?>,
    ) {
        val sr = buf.sampleRate
        val n = buf.frames
        if (n == 0 || wet <= 0.001) return

        val dryL = if (wet < 0.999) buf.left.copyOf() else null
        val dryR = if (wet < 0.999) buf.right.copyOf() else null

        when (type) {
            "eq8" -> {
                val lowCut = param(params, "lowCutHz", 80.0).coerceIn(20.0, 600.0)
                val lowShelf = param(params, "lowShelfGainDb", 1.5).coerceIn(-15.0, 15.0)
                val lowMidHz = param(params, "lowMidHz", 250.0).coerceIn(100.0, 800.0)
                val lowMidGain = param(params, "lowMidGainDb", -1.5).coerceIn(-15.0, 15.0)
                val midHz = param(params, "midHz", 1200.0).coerceIn(400.0, 4000.0)
                val midGain = param(params, "midGainDb", 1.0).coerceIn(-15.0, 15.0)
                val hiMidHz = param(params, "highMidHz", 4200.0).coerceIn(1500.0, 9000.0)
                val hiMidGain = param(params, "highMidGainDb", 2.0).coerceIn(-15.0, 15.0)
                val airGain = param(params, "airGainDb", 2.5).coerceIn(-15.0, 15.0)

                for (ch in listOf(buf.left, buf.right)) {
                    val hp = Biquad().apply { highpass(sr, lowCut, 0.707) }
                    val ls = Biquad().apply { lowShelf(sr, 110.0, lowShelf) }
                    val pk1 = Biquad().apply { peaking(sr, lowMidHz, lowMidGain, 1.1) }
                    val pk2 = Biquad().apply { peaking(sr, midHz, midGain, 1.0) }
                    val pk3 = Biquad().apply { peaking(sr, hiMidHz, hiMidGain, 1.1) }
                    val hs = Biquad().apply { highShelf(sr, 10000.0, airGain) }
                    for (i in 0 until n) {
                        var v = ch[i].toDouble()
                        v = hp.process(v)
                        v = ls.process(v)
                        v = pk1.process(v)
                        v = pk2.process(v)
                        v = pk3.process(v)
                        v = hs.process(v)
                        ch[i] = v.toFloat()
                    }
                }
            }

            "compressor" -> {
                val threshDb = param(params, "thresholdDb", -18.0)
                val ratio = param(params, "ratio", 3.2).coerceAtLeast(1.0)
                val atk = timeCoef(param(params, "attackMs", 8.0), sr)
                val rel = timeCoef(param(params, "releaseMs", 110.0), sr)
                val makeup = dbToLin(param(params, "makeupDb", 2.5))
                val slope = 1.0 - 1.0 / ratio
                var env = 0.0
                for (i in 0 until n) {
                    val pk = max(abs(buf.left[i]), abs(buf.right[i])).toDouble()
                    env = if (pk > env) atk * env + (1.0 - atk) * pk else rel * env + (1.0 - rel) * pk
                    val envDb = linToDb(env)
                    val grDb = if (envDb > threshDb) -(envDb - threshDb) * slope else 0.0
                    val g = (dbToLin(grDb) * makeup).toFloat()
                    buf.left[i] *= g
                    buf.right[i] *= g
                }
            }

            "gate" -> {
                val threshLin = dbToLin(param(params, "thresholdDb", -45.0))
                val floorLin = dbToLin(param(params, "floorDb", -60.0))
                val atk = timeCoef(param(params, "attackMs", 3.0), sr)
                val rel = timeCoef(param(params, "releaseMs", 140.0), sr)
                var g = 1.0
                for (i in 0 until n) {
                    val pk = max(abs(buf.left[i]), abs(buf.right[i])).toDouble()
                    val target = if (pk >= threshLin) 1.0 else floorLin
                    g = if (target > g) atk * g + (1.0 - atk) * target else rel * g + (1.0 - rel) * target
                    buf.left[i] = (buf.left[i] * g).toFloat()
                    buf.right[i] = (buf.right[i] * g).toFloat()
                }
            }

            "de_esser" -> {
                val freq = param(params, "freqHz", 6800.0).coerceIn(3500.0, 11000.0)
                val threshDb = param(params, "thresholdDb", -24.0)
                val maxCutDb = param(params, "amountDb", 7.0).coerceIn(0.0, 18.0)
                val scL = Biquad().apply { highpass(sr, freq, 0.9) }
                val scR = Biquad().apply { highpass(sr, freq, 0.9) }
                val rel = timeCoef(35.0, sr)
                var env = 0.0
                for (i in 0 until n) {
                    val s = max(abs(scL.process(buf.left[i].toDouble())), abs(scR.process(buf.right[i].toDouble())))
                    env = max(s, rel * env + (1.0 - rel) * s)
                    val overDb = linToDb(env) - threshDb
                    if (overDb > 0.0) {
                        val cut = dbToLin(-min(maxCutDb, overDb * 0.65)).toFloat()
                        buf.left[i] *= cut
                        buf.right[i] *= cut
                    }
                }
            }

            "reverb" -> {
                val revL = Reverb(sr).apply {
                    size = param(params, "size", 0.55).coerceIn(0.1, 0.98)
                    damp = param(params, "damping", 0.45).coerceIn(0.05, 0.95)
                    preMs = param(params, "preDelayMs", 22.0).coerceIn(0.0, 120.0)
                }
                val revR = Reverb(sr).apply {
                    size = (revL.size + 0.02).coerceAtMost(0.99)
                    damp = revL.damp
                    preMs = revL.preMs + 3.5
                }
                for (i in 0 until n) {
                    val m = 0.5 * (buf.left[i] + buf.right[i])
                    buf.left[i] = revL.process(m + buf.left[i] * 0.2).toFloat()
                    buf.right[i] = revR.process(m + buf.right[i] * 0.2).toFloat()
                }
            }

            "delay" -> {
                val timeMs = param(params, "timeMs", 320.0).coerceIn(20.0, 1500.0)
                val fb = param(params, "feedback", 0.32).coerceIn(0.0, 0.88)
                val pingPong = param(params, "pingPong", 1.0) >= 0.5
                val dSamples = max(16, (timeMs * 0.001 * sr).toInt())
                val dLineL = FloatArray(dSamples)
                val dLineR = FloatArray(dSamples)
                var p = 0
                for (i in 0 until n) {
                    val dl = dLineL[p]
                    val dr = dLineR[p]
                    val inL = buf.left[i]
                    val inR = buf.right[i]
                    if (pingPong) {
                        dLineL[p] = (inL + dr * fb.toFloat()).coerceIn(-1f, 1f)
                        dLineR[p] = (inR * 0.4f + dl * fb.toFloat()).coerceIn(-1f, 1f)
                    } else {
                        dLineL[p] = (inL + dl * fb.toFloat()).coerceIn(-1f, 1f)
                        dLineR[p] = (inR + dr * fb.toFloat()).coerceIn(-1f, 1f)
                    }
                    buf.left[i] = dl
                    buf.right[i] = dr
                    p = (p + 1) % dSamples
                }
            }

            "chorus", "flanger", "vocal_doubler" -> {
                val rate = param(params, "rateHz", if (type == "flanger") 0.35 else 0.85)
                val baseMs = when (type) {
                    "flanger" -> 2.5
                    "vocal_doubler" -> param(params, "haasDelayMs", 18.0)
                    else -> 14.0
                }
                val depthMs = param(params, "depthMs", if (type == "flanger") 2.2 else 5.5)
                val maxDelay = ((baseMs + depthMs + 5.0) * 0.001 * sr).toInt().coerceAtLeast(64)
                val ringL = FloatArray(maxDelay)
                val ringR = FloatArray(maxDelay)
                var wp = 0
                for (i in 0 until n) {
                    ringL[wp] = buf.left[i]
                    ringR[wp] = buf.right[i]
                    val lfoL = sin(2.0 * PI * rate * i / sr)
                    val lfoR = cos(2.0 * PI * rate * i / sr)
                    val dL = ((baseMs + depthMs * lfoL) * 0.001 * sr).toInt().coerceIn(1, maxDelay - 1)
                    val dR = ((baseMs + depthMs * lfoR) * 0.001 * sr).toInt().coerceIn(1, maxDelay - 1)
                    buf.left[i] = 0.6f * buf.left[i] + 0.4f * ringL[(wp - dL + maxDelay) % maxDelay]
                    buf.right[i] = 0.6f * buf.right[i] + 0.4f * ringR[(wp - dR + maxDelay) % maxDelay]
                    wp = (wp + 1) % maxDelay
                }
            }

            "phaser" -> {
                val rate = param(params, "rateHz", 0.5)
                val depth = param(params, "depth", 0.75)
                val bpL = Biquad()
                val bpR = Biquad()
                for (i in 0 until n) {
                    if (i % 64 == 0) {
                        val lfo = 0.5 + 0.5 * sin(2.0 * PI * rate * i / sr)
                        val f = 350.0 + depth * 2200.0 * lfo
                        bpL.peaking(sr, f, -9.0, 1.8)
                        bpR.peaking(sr, f * 1.12, -9.0, 1.8)
                    }
                    buf.left[i] = bpL.process(buf.left[i].toDouble()).toFloat()
                    buf.right[i] = bpR.process(buf.right[i].toDouble()).toFloat()
                }
            }

            "saturator" -> {
                val drive = dbToLin(param(params, "driveDb", 6.0).coerceIn(0.0, 24.0))
                val norm = 1.0 / tanh(drive.coerceAtLeast(1.0))
                for (i in 0 until n) {
                    buf.left[i] = (tanh(buf.left[i] * drive) * norm).toFloat()
                    buf.right[i] = (tanh(buf.right[i] * drive) * norm).toFloat()
                }
            }

            "bitcrusher" -> {
                val bits = param(params, "bitDepth", 10.0).coerceIn(4.0, 16.0)
                val step = max(1, param(params, "downsample", 4.0).roundToInt())
                val levels = (1 shl bits.roundToInt()).toFloat()
                var holdL = 0f
                var holdR = 0f
                for (i in 0 until n) {
                    if (i % step == 0) {
                        holdL = (buf.left[i] * levels).roundToInt() / levels
                        holdR = (buf.right[i] * levels).roundToInt() / levels
                    }
                    buf.left[i] = holdL
                    buf.right[i] = holdR
                }
            }

            "stereo_widener" -> {
                val width = param(params, "width", 1.35).coerceIn(0.0, 2.0).toFloat()
                for (i in 0 until n) {
                    val mid = 0.5f * (buf.left[i] + buf.right[i])
                    val side = 0.5f * (buf.left[i] - buf.right[i]) * width
                    buf.left[i] = (mid + side).coerceIn(-1f, 1f)
                    buf.right[i] = (mid - side).coerceIn(-1f, 1f)
                }
            }

            "filter" -> {
                val mode = param(params, "mode", 0.0).roundToInt()
                val cutoff = param(params, "cutoffHz", 2400.0).coerceIn(40.0, 18000.0)
                val q = param(params, "resonanceQ", 1.4).coerceIn(0.5, 8.0)
                for (ch in listOf(buf.left, buf.right)) {
                    val bq = Biquad().apply {
                        when (mode) {
                            1 -> highpass(sr, cutoff, q)
                            2 -> peaking(sr, cutoff, 8.0, q)
                            else -> lowpass(sr, cutoff, q)
                        }
                    }
                    for (i in 0 until n) ch[i] = bq.process(ch[i].toDouble()).toFloat()
                }
            }

            "limiter" -> {
                val ceilDb = param(params, "ceilingDb", -1.0).coerceIn(-12.0, 0.0)
                Mastering.limit(buf.left, ceilDb, sr)
                Mastering.limit(buf.right, ceilDb, sr)
            }
        }

        if (dryL != null && dryR != null) {
            val w = wet.toFloat()
            val d = 1f - w
            for (i in 0 until n) {
                buf.left[i] = dryL[i] * d + buf.left[i] * w
                buf.right[i] = dryR[i] * d + buf.right[i] * w
            }
        }
    }
}
