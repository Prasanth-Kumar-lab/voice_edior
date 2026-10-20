package com.example.voice_edior.dsp

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class VocalChainTest {
    private val sr = 48000

    private fun run(fx: VocalFx, x: FloatArray): FloatArray {
        val chain = VocalChain(sr)
        chain.setFx(fx)
        val y = x.copyOf()
        var i = 0
        while (i < y.size) {
            val n = minOf(240, y.size - i)
            chain.process(y, i, n)
            i += n
        }
        return y
    }

    private fun rmsDb(x: FloatArray, from: Int = 0, to: Int = x.size): Double {
        var s = 0.0
        for (i in from until to) s += x[i] * x[i]
        return 20 * log10(sqrt(s / (to - from)).coerceAtLeast(1e-9))
    }

    private fun tone(hz: Double, amp: Double, secs: Double) =
        FloatArray((secs * sr).toInt()) { (amp * sin(2 * PI * hz * it / sr)).toFloat() }

    private fun noise(db: Double, secs: Double, seed: Int = 1): FloatArray {
        val r = Random(seed)
        val a = Math.pow(10.0, db / 20) * sqrt(3.0)
        return FloatArray((secs * sr).toInt()) { ((r.nextDouble() * 2 - 1) * a).toFloat() }
    }

    private fun plus(a: FloatArray, b: FloatArray) = FloatArray(a.size) { a[it] + b[it] }

    /** Everything off except the stage under test. */
    private val flat = VocalFx(
        denoise = 0f, gateOn = false, deEssOn = false, eqOn = false, compOn = false,
        hpfHz = 20f, compMakeupDb = 0f, limiterCeilingDb = 0f,
    )

    /** Speech-like: syllables of harmonic tone (with vibrato) separated by silent gaps. Returns signal + on-mask. */
    private fun voice(secs: Double): Pair<FloatArray, BooleanArray> {
        val n = (secs * sr).toInt()
        val y = FloatArray(n)
        val on = BooleanArray(n)
        var t = 0.3
        var k = 0
        while (t < secs - 0.8) {
            val dur = 0.45 + 0.1 * (k % 3)
            val f0 = 150.0 + 25 * (k % 4)
            val i0 = (t * sr).toInt(); val i1 = ((t + dur) * sr).toInt()
            for (i in i0 until i1) {
                val tt = (i - i0).toDouble() / sr
                val env = minOf(1.0, minOf(tt / 0.03, (dur - tt) / 0.06))
                var v = 0.0
                for (h in 1..12) v += (1.0 / h) * sin(2 * PI * h * (f0 * tt + 3 * sin(2 * PI * 5.5 * tt) / (2 * PI * 5.5)))
                y[i] = (0.12 * env * v).toFloat()
                on[i] = true
            }
            t += dur + 0.25
            k++
        }
        return Pair(y, on)
    }

    private fun maskedRmsDb(x: FloatArray, m: BooleanArray, shift: Int, want: Boolean, margin: Int = 0): Double {
        var s = 0.0; var c = 0
        for (i in margin until x.size - margin) {
            val j = i - shift
            if (j < 0 || j >= m.size) continue
            var ok = m[j] == want
            if (!want) for (d in intArrayOf(-2880, 2880)) { val q = j + d; if (q in m.indices && m[q]) ok = false }
            if (ok) { s += x[i] * x[i]; c++ }
        }
        return 10 * log10((s / c.coerceAtLeast(1)).coerceAtLeast(1e-18))
    }

    @Test fun flatChainIsTransparent() {
        val x = plus(tone(1000.0, 0.2, 1.0), tone(2500.0, 0.1, 1.0))
        val y = run(flat, x)
        val lat = VocalChain(sr).latencySamples
        var err = 0.0; var ref = 0.0
        for (i in 24000 until x.size - 100) { err += (y[i] - x[i - lat]).let { it * it }; ref += x[i - lat] * x[i - lat] }
        println("flat chain error %.1f dB".format(10 * log10(err / ref)))
        assertTrue("flat chain should be transparent", err / ref < 0.01)
    }

    @Test fun bypassIsLatencyAlignedWithProcessed() {
        val x = tone(300.0, 0.2, 1.0)
        val y = run(flat.copyWith(bypass = true), x)
        val lat = VocalChain(sr).latencySamples
        for (i in 24000 until 40000) assertEquals(x[i - lat].toDouble(), y[i].toDouble(), 1e-4)
    }

    @Test fun denoiseCutsSteadyNoise() {
        val x = noise(-45.0, 4.0)
        val y = run(flat.copyWith(denoise = 1f), x)
        val drop = rmsDb(x, 96000, 190000) - rmsDb(y, 96000, 190000)
        println("denoise noise reduction (white -45 dBFS): %.1f dB".format(drop))
        assertTrue("expected >12 dB reduction, got $drop", drop > 12)
    }

    @Test fun denoiseRemovesRoomNoiseButKeepsTheVoice() {
        val (v, on) = voice(8.0)
        val x = plus(v, noise(-48.0, 8.0))
        val y = run(flat.copyWith(denoise = 0.55f), x)
        val lat = VocalChain(sr).latencySamples
        val m = 2 * sr
        val voiceChange = maskedRmsDb(y, on, lat, true, m) - maskedRmsDb(v.let { arr -> FloatArray(arr.size) { arr[it] } }, on, 0, true, m - lat).let { it }
        val gapDrop = maskedRmsDb(x, on, 0, false, m) - maskedRmsDb(y, on, lat, false, m)
        println("denoise 0.55 on voice+room noise: voice %+.2f dB, gaps -%.1f dB".format(voiceChange, gapDrop))
        assertTrue("voice should stay within 1.5 dB, got $voiceChange", voiceChange > -1.5)
        assertTrue("room noise in gaps should drop >8 dB, got $gapDrop", gapDrop > 8)
    }

    @Test fun heldNoteIsNotMistakenForNoise() {
        val note = plus(tone(220.0, 0.12, 2.5), tone(440.0, 0.06, 2.5))
        val x = plus(note, noise(-50.0, 2.5))
        val y = run(flat.copyWith(denoise = 0.8f), x)
        val lat = VocalChain(sr).latencySamples
        val keep = rmsDb(y, 70000, 115000) - rmsDb(note, 70000 - lat, 115000 - lat)
        println("held 2.5 s note level change: %+.2f dB".format(keep))
        assertTrue("held note must survive, got $keep", keep > -4.0)
    }

    @Test fun deEsserTamesSibilanceNotBody() {
        val sib = tone(8000.0, 0.25, 1.5)
        val body = tone(300.0, 0.25, 1.5)
        val ySib = run(flat.copyWith(deEssOn = true, deEss = 1f), sib)
        val yBody = run(flat.copyWith(deEssOn = true, deEss = 1f), body)
        val sibDrop = rmsDb(sib, 30000, 60000) - rmsDb(ySib, 30000, 60000)
        val bodyDrop = rmsDb(body, 30000, 60000) - rmsDb(yBody, 30000, 60000)
        println("de-ess: sibilance -%.1f dB, body -%.2f dB".format(sibDrop, bodyDrop))
        assertTrue("sibilance should drop >3 dB, got $sibDrop", sibDrop > 3)
        assertTrue("body should be untouched, dropped $bodyDrop", bodyDrop < 0.5)
    }

    @Test fun compressorReducesDynamicRange() {
        val loud = tone(300.0, 0.5, 1.0)
        val quiet = tone(300.0, 0.05, 1.0)
        val fx = flat.copyWith(compOn = true, compThresholdDb = -24f, compRatio = 4f, compMakeupDb = 0f)
        val both = loud + quiet
        val y = run(fx, both)
        val inRange = rmsDb(both, 20000, 40000) - rmsDb(both, 68000, 90000)
        val outRange = rmsDb(y, 20000, 40000) - rmsDb(y, 68000, 90000)
        println("dynamic range %.1f dB -> %.1f dB".format(inRange, outRange))
        assertTrue("range should shrink", outRange < inRange - 6)
    }

    @Test fun limiterNeverExceedsCeiling() {
        val x = tone(220.0, 0.9, 1.5)
        val fx = flat.copyWith(outputGainDb = 12f, limiterCeilingDb = -3f)
        val y = run(fx, x)
        val ceil = Math.pow(10.0, -3.0 / 20)
        val peak = y.maxOf { abs(it) }
        println("limiter peak %.4f (ceiling %.4f)".format(peak, ceil))
        assertTrue("peak $peak above ceiling $ceil", peak <= ceil + 1e-6)
    }

    @Test fun reverbAddsATailAndMixZeroAddsNone() {
        val burst = FloatArray(sr) { if (it < 2400) (0.3 * sin(2 * PI * 300.0 * it / sr)).toFloat() else 0f }
        val wet = run(flat.copy(reverbMix = 0.4f), burst)
        val dry = run(flat, burst)
        val lat = VocalChain(sr).latencySamples
        val from = lat + 14400; val to = lat + 40000   // 0.3 s .. 0.8 s after the burst
        val tail = rmsDb(wet, from, to); val none = rmsDb(dry, from, to)
        println("reverb tail %.1f dB vs dry %.1f dB".format(tail, none))
        assertTrue("reverb should ring on", tail > -70 && tail > none + 30)
    }

    @Test fun warmthIsTransparentForQuietSignalsAndSoftensPeaks() {
        val quiet = tone(300.0, 0.02, 1.0)
        val yq = run(flat.copy(warmth = 1f), quiet)
        assertEquals(0.0, rmsDb(quiet, 24000, 40000) - rmsDb(yq, 24000, 40000), 0.3)
        val loud = tone(300.0, 0.8, 1.0)
        val yl = run(flat.copy(warmth = 1f), loud)
        assertTrue("peaks should be softened", yl.maxOf { abs(it) } < 0.8f)
    }

    @Test fun fullChainStaysFiniteOnAbusiveInput() {
        val r = Random(3)
        val x = FloatArray(sr * 2) { (if (it % 7000 < 40) 2.0 else r.nextDouble() * 2 - 1).toFloat() }
        val y = run(VocalFx(denoise = 1f, deEss = 1f), x)
        assertTrue("no NaN/Inf", y.all { it.isFinite() })
        assertTrue("within ceiling", y.maxOf { abs(it) } <= 1.0f)
    }
}

private fun VocalFx.copyWith(
    bypass: Boolean = this.bypass, denoise: Float = this.denoise, deEssOn: Boolean = this.deEssOn,
    deEss: Float = this.deEss, compOn: Boolean = this.compOn, compThresholdDb: Float = this.compThresholdDb,
    compRatio: Float = this.compRatio, compMakeupDb: Float = this.compMakeupDb,
    outputGainDb: Float = this.outputGainDb, limiterCeilingDb: Float = this.limiterCeilingDb,
) = copy(
    bypass = bypass, denoise = denoise, deEssOn = deEssOn, deEss = deEss, compOn = compOn,
    compThresholdDb = compThresholdDb, compRatio = compRatio, compMakeupDb = compMakeupDb,
    outputGainDb = outputGainDb, limiterCeilingDb = limiterCeilingDb,
)
