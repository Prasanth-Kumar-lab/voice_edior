package com.example.voice_edior.dsp

import kotlin.math.max

/** Mono Freeverb-style plate: 8 damped combs + 4 all-passes, with pre-delay. Returns the wet signal only. */
class Reverb(private val sr: Int) {
    private val combLens = intArrayOf(1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617).map { max(8, it * sr / 44100) }
    private val apLens = intArrayOf(556, 441, 341, 225).map { max(8, it * sr / 44100) }
    private val combBuf = combLens.map { DoubleArray(it) }
    private val combPos = IntArray(8)
    private val combLp = DoubleArray(8)
    private val apBuf = apLens.map { DoubleArray(it) }
    private val apPos = IntArray(4)
    private val pre = DoubleArray(sr / 4)
    private var prePos = 0

    var size = 0.5
    var damp = 0.5
    var preMs = 20.0

    fun process(x: Double): Double {
        val delay = (preMs * 0.001 * sr).toInt().coerceIn(0, pre.size - 1)
        pre[prePos] = x
        val inp = pre[(prePos - delay + pre.size) % pre.size] * 0.015
        prePos = (prePos + 1) % pre.size

        val fb = 0.7 + 0.28 * size
        val d = 0.15 + 0.7 * damp
        var acc = 0.0
        for (i in 0 until 8) {
            val buf = combBuf[i]
            val p = combPos[i]
            val o = buf[p]
            combLp[i] = o * (1 - d) + combLp[i] * d
            buf[p] = inp + combLp[i] * fb
            combPos[i] = (p + 1) % buf.size
            acc += o
        }
        for (i in 0 until 4) {
            val buf = apBuf[i]
            val p = apPos[i]
            val b = buf[p]
            val out = -acc + b
            buf[p] = acc + b * 0.5
            apPos[i] = (p + 1) % buf.size
            acc = out
        }
        return acc * 3.0
    }

    fun reset() {
        combBuf.forEach { it.fill(0.0) }; apBuf.forEach { it.fill(0.0) }; pre.fill(0.0)
        combLp.fill(0.0)
    }
}
