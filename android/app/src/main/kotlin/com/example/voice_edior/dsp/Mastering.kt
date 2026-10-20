package com.example.voice_edior.dsp

import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sqrt

/** ITU-R BS.1770 loudness (48 kHz) and a look-ahead peak limiter for final mastering. */
object Mastering {
    private val B1 = doubleArrayOf(1.53512485958697, -2.69169618940638, 1.19839281085285)
    private val A1 = doubleArrayOf(1.0, -1.69065929318241, 0.73248077421585)
    private val B2 = doubleArrayOf(1.0, -2.0, 1.0)
    private val A2 = doubleArrayOf(1.0, -1.99004745483398, 0.99007225036621)

    private fun filt(x: DoubleArray, b: DoubleArray, a: DoubleArray): DoubleArray {
        val y = DoubleArray(x.size)
        var x1 = 0.0; var x2 = 0.0; var y1 = 0.0; var y2 = 0.0
        for (i in x.indices) {
            val v = b[0] * x[i] + b[1] * x1 + b[2] * x2 - a[1] * y1 - a[2] * y2
            x2 = x1; x1 = x[i]; y2 = y1; y1 = v
            y[i] = v
        }
        return y
    }

    fun integratedLufs(x: FloatArray, sr: Int = 48000): Double {
        val block = (0.4 * sr).toInt(); val hop = (0.1 * sr).toInt()
        if (x.size < block) return -70.0
        val k = filt(filt(DoubleArray(x.size) { x[it].toDouble() }, B1, A1), B2, A2)
        val c = DoubleArray(k.size + 1)
        for (i in k.indices) c[i + 1] = c[i] + k[i] * k[i]
        val ms = ArrayList<Double>()
        var s = 0
        while (s + block <= k.size) { ms.add((c[s + block] - c[s]) / block); s += hop }
        val lk = ms.map { -0.691 + 10 * log10(it + 1e-12) }
        val abs = ms.filterIndexed { i, _ -> lk[i] > -70 }
        if (abs.isEmpty()) return -70.0
        val rel = -0.691 + 10 * log10(abs.average() + 1e-12) - 10
        val kept = ms.filterIndexed { i, _ -> lk[i] > rel }
        if (kept.isEmpty()) return -70.0
        return -0.691 + 10 * log10(kept.average() + 1e-12)
    }

    /** Level spread between 90th and 10th percentile 50 ms frames — a robust SNR-like figure. */
    fun noiseFloorDb(x: FloatArray, sr: Int = 48000): Double {
        val w = (0.05 * sr).toInt()
        val n = x.size / w
        if (n < 4) return -90.0
        val r = DoubleArray(n) { i ->
            var s = 0.0
            for (j in i * w until (i + 1) * w) s += x[j].toDouble() * x[j]
            10 * log10(s / w + 1e-12)
        }
        r.sort()
        return r[(n * 0.1).toInt()]
    }

    fun limit(x: FloatArray, ceilingDb: Double, sr: Int = 48000, lookaheadMs: Double = 12.0) {
        val ceil = 10.0.pow(ceilingDb / 20)
        val l = max(2, (lookaheadMs * 1e-3 * sr).toInt())
        val n = x.size
        val g = DoubleArray(n) { i -> val a = abs(x[i]).toDouble(); if (a > ceil) ceil / a else 1.0 }
        // sliding minimum (monotonic deque), then moving average with the same window
        val win = 2 * l + 1
        val mn = DoubleArray(n)
        val dq = IntArray(n); var head = 0; var tail = 0
        for (i in 0 until n + l) {
            if (i < n) { while (tail > head && g[dq[tail - 1]] >= g[i]) tail--; dq[tail++] = i }
            val c = i - l
            if (c >= 0) { while (dq[head] < c - l) head++; mn[c] = g[dq[head]] }
        }
        val pre = DoubleArray(n + 1)
        for (i in 0 until n) pre[i + 1] = pre[i] + mn[i]
        for (i in 0 until n) {
            val a = max(0, i - l); val b = min(n, i + l + 1)
            val gain = (pre[b] - pre[a]) / (b - a)
            x[i] = (x[i] * gain).toFloat().coerceIn(-ceil.toFloat(), ceil.toFloat())
        }
    }

    /** Gain to the target loudness, then limit; one corrective pass if limiting pulled it down. */
    fun normalize(x: FloatArray, targetLufs: Double, ceilingDb: Double, sr: Int = 48000) {
        val cur = integratedLufs(x, sr)
        if (cur <= -69) return
        val gain = 10.0.pow((targetLufs - cur) / 20).toFloat()
        val src = x.copyOf()
        for (i in x.indices) x[i] = src[i] * gain
        limit(x, ceilingDb, sr)
        val after = integratedLufs(x, sr)
        if (abs(after - targetLufs) > 0.4) {
            val g2 = (gain * 10.0.pow((targetLufs - after) / 20)).toFloat()
            for (i in x.indices) x[i] = src[i] * g2
            limit(x, ceilingDb, sr)
        }
    }
}
