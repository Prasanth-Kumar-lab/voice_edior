package com.example.voice_edior.dsp

import com.example.voice_edior.rt.Enhancer
import com.example.voice_edior.rt.PcmClip
import com.example.voice_edior.rt.WavFile
import java.io.File
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class EnhancerTest {
    private val sr = 48000

    /** Sung/spoken-like phrases: harmonic tone with vibrato, separated by gaps. Returns signal + voiced mask. */
    private fun voice(f0: Double, secs: Double): Pair<FloatArray, BooleanArray> {
        val n = (secs * sr).toInt(); val y = FloatArray(n); val on = BooleanArray(n)
        var t = 0.6; var k = 0
        while (t < secs - 0.8) {
            val dur = 0.5 + 0.1 * (k % 3); val i0 = (t * sr).toInt(); val i1 = ((t + dur) * sr).toInt()
            for (i in i0 until minOf(i1, n)) {
                val tt = (i - i0).toDouble() / sr
                val env = minOf(1.0, minOf(tt / 0.03, (dur - tt) / 0.06))
                var v = 0.0
                for (h in 1..14) v += (1.0 / h) * sin(2 * PI * h * (f0 * tt + 1.5 * sin(2 * PI * 5.5 * tt) / (2 * PI * 5.5)))
                y[i] = (0.16 * env * v).toFloat(); on[i] = true
            }
            t += dur + 0.4; k++
        }
        return Pair(y, on)
    }

    private fun noise(db: Double, n: Int): FloatArray {
        val r = Random(5); val a = Math.pow(10.0, db / 20) * sqrt(3.0)
        // hiss + low rumble + mains hum
        return FloatArray(n) { i -> ((r.nextDouble() * 2 - 1) * a + 0.4 * a * sin(2 * PI * 50 * i / sr) + 0.3 * a * sin(2 * PI * 100 * i / sr)).toFloat() }
    }

    private fun rmsDb(x: FloatArray, m: BooleanArray, want: Boolean, from: Int = 0): Double {
        var s = 0.0; var c = 0
        for (i in from until x.size) {
            var ok = m[i] == want
            if (!want) for (d in intArrayOf(-4800, 4800)) { val q = i + d; if (q in m.indices && m[q]) ok = false }
            if (ok) { s += x[i] * x[i]; c++ }
        }
        return 10 * log10((s / c.coerceAtLeast(1)).coerceAtLeast(1e-18))
    }

    private fun run(mode: String, f0: Double): Triple<Double, Double, com.example.voice_edior.rt.EnhanceResult> {
        val (v, on) = voice(f0, 12.0)
        val nz = noise(-44.0, v.size)
        val noisy = FloatArray(v.size) { v[it] + nz[it] }
        val dir = createTempDir("vpenh"); val inF = File(dir, "in.wav"); val outF = File(dir, "out.wav")
        WavFile.write(inF.path, PcmClip(noisy, sr))
        val r = Enhancer.run(inF.path, outF.path, mode)
        val out = WavFile.read(outF.path).samples
        val gapDrop = (rmsDb(noisy, on, false, 96000) - rmsDb(out, on, false, 96000)) -
            (rmsDb(noisy, on, true, 96000) - rmsDb(out, on, true, 96000)) // relative to the voice level change
        val peak = out.maxOf { abs(it) }.toDouble()
        println("[$mode f0=$f0] type=${r.voiceType} f0=${"%.1f".format(r.f0)} LUFS ${"%.1f".format(r.lufsIn)} -> ${"%.1f".format(r.lufsOut)}, " +
            "background -${"%.1f".format(gapDrop)} dB relative to voice, peak ${"%.2f".format(20 * log10(peak))} dBFS")
        return Triple(gapDrop, 20 * log10(peak), r)
    }

    @Test fun podcastRemovesBackgroundAndHitsBroadcastLoudness() {
        val (drop, peakDb, r) = run("podcast", 125.0)
        assertTrue("background should fall >20 dB relative to the voice, got $drop", drop > 20)
        assertTrue("loudness should be -16 LUFS +-0.7, got ${r.lufsOut}", abs(r.lufsOut + 16.0) < 0.7)
        assertTrue("true-peak safe, got $peakDb", peakDb <= -0.7)
    }

    @Test fun vocalsDetectsPitchAndMastersForStreaming() {
        val (drop, peakDb, r) = run("vocals", 220.0)
        assertTrue("pitch should be found near 220 Hz, got ${r.f0}", abs(r.f0 - 220f) < 8f)
        assertTrue("220 Hz is an alto, got ${r.voiceType}", r.voiceType == "alto")
        assertTrue("background should fall >18 dB relative to the voice, got $drop", drop > 18)
        assertTrue("loudness should be -14 LUFS +-1.2 (ceiling-limited), got ${r.lufsOut}", abs(r.lufsOut + 14.0) < 1.2)
        assertTrue("peak safe, got $peakDb", peakDb <= -0.7)
    }

    @Test fun lowVoiceIsClassifiedAsBass() {
        val (_, _, r) = run("vocals", 95.0)
        assertTrue("95 Hz should be bass, got ${r.voiceType} ${r.f0}", r.voiceType == "bass" && abs(r.f0 - 95f) < 6f)
    }

    /** Wide-band voice (60 harmonics, brighter than the other synthetic voices) so the exciter has material to work on. */
    private fun hfEnergyDb(level: String): Double {
        val n = sr * 6
        val x = FloatArray(n) { i ->
            val tt = i.toDouble() / sr
            val env = if ((tt % 1.0) < 0.7) 1.0 else 0.0
            var v = 0.0
            for (h in 1..60) v += (1.0 / Math.pow(h.toDouble(), 1.1)) * sin(2 * PI * h * 125.0 * tt)
            (0.1 * env * v).toFloat()
        }
        val dir = createTempDir("vppod"); val inF = File(dir, "in.wav"); val outF = File(dir, "out.wav")
        WavFile.write(inF.path, PcmClip(x, sr))
        Enhancer.run(inF.path, outF.path, "podcast", "natural", "dry", level)
        val y = WavFile.read(outF.path).samples
        // energy above 6 kHz relative to the whole signal, via a first-difference high-pass (~+6 dB/oct)
        var hi = 0.0; var all = 0.0
        for (i in 2 until y.size) { val d = y[i] - 2 * y[i - 1] + y[i - 2]; hi += d * d; all += y[i].toDouble() * y[i] }
        return 10 * log10(hi / all.coerceAtLeast(1e-12))
    }

    @Test fun podcastEnhanceLevelsAddAirProgressively() {
        val natural = hfEnergyDb("natural"); val enhanced = hfEnergyDb("enhanced"); val max = hfEnergyDb("max")
        println("[podcast levels] high-frequency energy: natural %.1f, enhanced %.1f, max %.1f dB".format(natural, enhanced, max))
        assertTrue("Enhanced should add air over Natural ($natural -> $enhanced)", enhanced > natural + 1.0)
        assertTrue("Studio Max should be brighter than Enhanced ($enhanced -> $max)", max > enhanced)
    }

    @Test fun limiterAndLoudnessAreConsistent() {
        val x = FloatArray(sr * 5) { (0.9 * sin(2 * PI * 300 * it / sr) * (if ((it / 24000) % 2 == 0) 1.0 else 0.1)).toFloat() }
        Mastering.normalize(x, -16.0, -1.0)
        val lufs = Mastering.integratedLufs(x)
        val peak = 20 * log10(x.maxOf { abs(it) }.toDouble())
        println("mastering: ${"%.2f".format(lufs)} LUFS, peak ${"%.2f".format(peak)} dBFS")
        assertTrue("peak <= -1 dBFS, got $peak", peak <= -0.99)
        assertTrue("loudness within 1 LU of target, got $lufs", abs(lufs + 16.0) < 1.0)
    }

    @Test fun cachedFilterRestyleIsSignificantlyFasterThanInitialClean() {
        val (v, _) = voice(135.0, 8.0)
        val nz = noise(-44.0, v.size)
        val noisy = FloatArray(v.size) { v[it] + nz[it] }
        val dir = createTempDir("vpfast")
        val inF = File(dir, "in.wav")
        val out1 = File(dir, "out1.wav")
        val out2 = File(dir, "out2.wav")
        WavFile.write(inF.path, PcmClip(noisy, sr))

        val t0 = System.nanoTime()
        val r1 = Enhancer.run(inF.path, out1.path, "podcast", "general_bass", "dry", "enhanced")
        val firstMs = (System.nanoTime() - t0) / 1_000_000.0

        val t1 = System.nanoTime()
        val r2 = Enhancer.run(inF.path, out2.path, "podcast", "theatrical", "dry", "enhanced")
        val secondMs = (System.nanoTime() - t1) / 1_000_000.0

        println("Initial clean+enhance: %.1f ms, cached filter switch (theatrical): %.1f ms".format(firstMs, secondMs))
        assertTrue("Cached restyle should be faster than initial clean ($secondMs ms vs $firstMs ms)", secondMs < firstMs)
        assertTrue("Cached theatrical restyle hits target loudness", abs(r2.lufsOut + 16.0) < 1.0)
        assertEquals(r1.f0, r2.f0)
    }
}
