package com.example.voice_edior.dsp

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

class VoiceInfo(
    val f0Median: Float,
    val f0P10: Float,
    val f0P90: Float,
    val voicedRatio: Float,
    val type: String,
)

/** YIN fundamental-frequency tracker on 16 kHz audio (20 ms hop). Steers the vocal chain per voice. */
object PitchAnalyzer {
    private const val SR = 16000
    private const val W = 512
    private const val HOP = 320

    fun unknown() = VoiceInfo(0f, 0f, 0f, 0f, "unknown")

    fun analyze(samples: FloatArray, sr: Int, maxSeconds: Int = 75): VoiceInfo {
        val x = decimateTo16k(samples, sr, maxSeconds)
        val frames = (x.size - 2 * W) / HOP + 1
        if (frames < 5) return unknown()
        val fft = Fft(2 * W)
        val tauMin = SR / 900
        val tauMax = min(SR / 65, W - 1)
        val ar = DoubleArray(2 * W); val ai = DoubleArray(2 * W)
        val br = DoubleArray(2 * W); val bi = DoubleArray(2 * W)
        val cs = DoubleArray(2 * W + 1)
        val dn = DoubleArray(tauMax + 2)
        val f0s = ArrayList<Float>()
        var voicedCount = 0
        for (f in 0 until frames) {
            val off = f * HOP
            var rmsAcc = 0.0
            for (i in 0 until 2 * W) {
                val v = x[off + i].toDouble()
                br[i] = v; bi[i] = 0.0
                ar[i] = if (i < W) v else 0.0; ai[i] = 0.0
                cs[i + 1] = cs[i] + v * v
                if (i < W) rmsAcc += v * v
            }
            if (kotlin.math.sqrt(rmsAcc / W) < 0.004) continue
            fft.transform(ar, ai); fft.transform(br, bi)
            for (k in 0 until 2 * W) { // conj(A) * B
                val re = ar[k] * br[k] + ai[k] * bi[k]
                val im = ar[k] * bi[k] - ai[k] * br[k]
                ar[k] = re; ai[k] = im
            }
            fft.inverse(ar, ai)
            val e0 = cs[W]
            var running = 0.0
            dn[0] = 1.0
            for (tau in 1..tauMax + 1) {
                val d = e0 + (cs[W + tau] - cs[tau]) - 2 * ar[tau]
                running += d
                dn[tau] = if (running > 1e-12) d * tau / running else 1.0
            }
            var tau = -1
            for (t in tauMin..tauMax) if (dn[t] < 0.15) { tau = t; break }
            if (tau > 0) { while (tau + 1 <= tauMax && dn[tau + 1] < dn[tau]) tau++ }
            else {
                var best = tauMin
                for (t in tauMin..tauMax) if (dn[t] < dn[best]) best = t
                if (dn[best] < 0.28) tau = best
            }
            if (tau in 1 until tauMax) {
                val a = dn[tau - 1]; val b = dn[tau]; val c = dn[tau + 1]
                val den = a - 2 * b + c
                val shift = if (abs(den) > 1e-12) (0.5 * (a - c) / den).coerceIn(-1.0, 1.0) else 0.0
                f0s.add((SR / (tau + shift)).toFloat())
                voicedCount++
            }
        }
        if (f0s.size < 12) return unknown()
        val sorted = f0s.sorted()
        val med = sorted[sorted.size / 2]
        val p10 = sorted[(sorted.size * 0.1).toInt()]
        val p90 = sorted[min(sorted.size - 1, (sorted.size * 0.9).toInt())]
        val type = when {
            med < 105 -> "bass"
            med < 145 -> "baritone"
            med < 190 -> "tenor"
            med < 240 -> "alto"
            med < 330 -> "mezzo"
            else -> "soprano"
        }
        return VoiceInfo(med, p10, p90, voicedCount.toFloat() / frames, type)
    }

    /** 31-tap windowed-sinc low-pass at 7 kHz then decimate to 16 kHz (linear interpolation for non-integer ratios). */
    private fun decimateTo16k(src: FloatArray, sr: Int, maxSeconds: Int): FloatArray {
        val n = min(src.size, sr * maxSeconds)
        val ratio = sr.toDouble() / SR
        val taps = 31
        val fc = 7000.0 / sr
        val h = DoubleArray(taps) { i ->
            val m = i - taps / 2
            val s = if (m == 0) 2 * fc else sin(2 * PI * fc * m) / (PI * m)
            s * (0.54 - 0.46 * cos(2 * PI * i / (taps - 1)))
        }
        val sum = h.sum(); for (i in h.indices) h[i] /= sum
        val outLen = (n / ratio).toInt()
        val out = FloatArray(outLen)
        for (o in 0 until outLen) {
            val c = o * ratio
            val i0 = c.toInt()
            var acc = 0.0
            for (k in 0 until taps) {
                val idx = i0 + k - taps / 2
                if (idx in 0 until n) acc += src[idx] * h[k]
            }
            out[o] = acc.toFloat()
        }
        return out
    }
}
