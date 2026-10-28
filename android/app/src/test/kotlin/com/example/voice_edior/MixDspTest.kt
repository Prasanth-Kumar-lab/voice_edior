package com.example.voice_edior

import com.example.voice_edior.dsp.MixDspMath
import com.example.voice_edior.dsp.StereoBuffer
import com.example.voice_edior.dsp.StereoFxChainProcessor
import com.example.voice_edior.dsp.VocalIsolator
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Random
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin
import kotlin.math.sqrt

class MixDspTest {

    @Test
    fun constantPowerPanPreservesEnergyAndExtremes() {
        val (centerL, centerR) = MixDspMath.constantPowerPan(0.0)
        assertEquals(1.0, centerL, 1e-4)
        assertEquals(1.0, centerR, 1e-4)

        val (hardL, hardR) = MixDspMath.constantPowerPan(-1.0)
        assertTrue(hardL > 1.4)
        assertEquals(0.0, hardR, 1e-4)

        val (rightL, rightR) = MixDspMath.constantPowerPan(1.0)
        assertEquals(0.0, rightL, 1e-4)
        assertTrue(rightR > 1.4)
    }

    @Test
    fun fadeCurvesHonorEndpointsAndShape() {
        for (curve in listOf("linear", "exponential", "s_curve")) {
            assertEquals(0.0, MixDspMath.fadeGain(0.0, curve), 1e-6)
            assertEquals(1.0, MixDspMath.fadeGain(1.0, curve), 1e-6)
        }
        val linHalf = MixDspMath.fadeGain(0.5, "linear")
        val expHalf = MixDspMath.fadeGain(0.5, "exponential")
        val sHalf = MixDspMath.fadeGain(0.5, "s_curve")
        assertEquals(0.5, linHalf, 1e-4)
        assertEquals(0.25, expHalf, 1e-4)
        assertEquals(0.7071, sHalf, 1e-3)
    }

    @Test
    fun wsolaTimeStretchChangesDurationProportionally() {
        val sr = 48000
        val sine = FloatArray(sr) { i -> (0.5 * sin(2.0 * PI * 220.0 * i / sr)).toFloat() }

        val halfSpeed = MixDspMath.timeStretchWsola(sine, sr, 0.5)
        assertEquals((sr * 2).toDouble(), halfSpeed.size.toDouble(), sr * 0.05)

        val doubleSpeed = MixDspMath.timeStretchWsola(sine, sr, 2.0)
        assertEquals((sr / 2).toDouble(), doubleSpeed.size.toDouble(), sr * 0.05)
    }

    @Test
    fun pitchShiftPreservesClipLength() {
        val sr = 48000
        val sine = FloatArray(sr / 2) { i -> (0.4 * sin(2.0 * PI * 300.0 * i / sr)).toFloat() }
        val shifted = MixDspMath.pitchShiftSemitones(sine, sr, 5.0)
        assertEquals(sine.size, shifted.size)
    }

    @Test
    fun autoDuckReducesGainDuringVoiceActivity() {
        val sr = 48000
        val voice = FloatArray(sr) { i ->
            if (i in (sr / 4)..(sr * 3 / 4)) 0.5f else 0.0f
        }
        val env = MixDspMath.computeAutoDuckEnvelope(
            voiceMono = voice,
            sr = sr,
            thresholdDb = -28.0,
            ratio = 4.0,
            attackMs = 15.0,
            releaseMs = 120.0,
            amountDb = -12.0,
        )
        assertTrue("Silence at start should stay near unity", env[100] > 0.95f)
        assertTrue("Active voice region should duck below 0.5", env[sr / 2] < 0.5f)
    }

    @Test
    fun stereoFxChainApplies5CoreMvpEffectsCleanly() {
        val sr = 48000
        val n = sr / 2
        val left = FloatArray(n) { i -> (0.4 * sin(2.0 * PI * 440.0 * i / sr)).toFloat() }
        val right = left.copyOf()
        val buf = StereoBuffer(left, right, sr)

        val chain = listOf(
            mapOf("type" to "eq8", "enabled" to true, "wetDry" to 1.0, "params" to mapOf("airGainDb" to 3.0)),
            mapOf("type" to "compressor", "enabled" to true, "wetDry" to 1.0, "params" to mapOf("thresholdDb" to -16.0, "ratio" to 3.0)),
            mapOf("type" to "reverb", "enabled" to true, "wetDry" to 0.25, "params" to mapOf("size" to 0.5)),
            mapOf("type" to "delay", "enabled" to true, "wetDry" to 0.2, "params" to mapOf("timeMs" to 120.0, "feedback" to 0.3)),
            mapOf("type" to "limiter", "enabled" to true, "wetDry" to 1.0, "params" to mapOf("ceilingDb" to -1.0)),
        )
        StereoFxChainProcessor.processChain(buf, chain)

        var maxPeak = 0f
        for (i in 0 until n) {
            maxPeak = maxOf(maxPeak, abs(buf.left[i]), abs(buf.right[i]))
        }
        assertTrue("Limiter must keep peak <= -1 dBTP (~0.892)", maxPeak <= 0.90f)
        assertTrue("Signal must remain audible", maxPeak > 0.1f)
    }

    @Test
    fun vocalIsolatorRemovesBackgroundNoiseAndHissWhilePreservingVocal() {
        val sr = 48000
        val n = sr // 1.0 second
        val rng = Random(42L)
        val f0 = 160.0 // Spoken vocal fundamental

        // 0.0..0.3s: background music chord + white hiss only
        // 0.3..0.8s: vocal harmonics + background music + hiss
        // 0.8..1.0s: background music + white hiss only
        val input = FloatArray(n) { i ->
            val t = i.toDouble() / sr
            val bgMusic = 0.06 * sin(2.0 * PI * 261.63 * t) + 0.05 * sin(2.0 * PI * 329.63 * t)
            val hiss = 0.05 * (rng.nextDouble() * 2.0 - 1.0)
            val vocal = if (i in (sr * 3 / 10)..(sr * 8 / 10)) {
                0.35 * sin(2.0 * PI * f0 * t) +
                    0.22 * sin(2.0 * PI * (2 * f0) * t) +
                    0.14 * sin(2.0 * PI * (3 * f0) * t) +
                    0.09 * sin(2.0 * PI * (4 * f0) * t)
            } else {
                0.0
            }
            (vocal + bgMusic + hiss).toFloat()
        }

        val cleanedPodcast = VocalIsolator.isolate(input, sr, f0.toFloat(), vocalsMode = false)
        val cleanedVocals = VocalIsolator.isolate(input, sr, f0.toFloat(), vocalsMode = true)

        fun rmsRange(x: FloatArray, start: Int, end: Int): Double {
            var s = 0.0
            for (i in start until end) s += x[i].toDouble() * x[i].toDouble()
            return sqrt(s / (end - start).coerceAtLeast(1))
        }

        val inNoiseRms = rmsRange(input, sr / 20, sr * 25 / 100)
        val outPodcastNoiseRms = rmsRange(cleanedPodcast, sr / 20, sr * 25 / 100)
        val outVocalsNoiseRms = rmsRange(cleanedVocals, sr / 20, sr * 25 / 100)
        val outPodcastVoiceRms = rmsRange(cleanedPodcast, sr * 4 / 10, sr * 7 / 10)
        val outVocalsVoiceRms = rmsRange(cleanedVocals, sr * 4 / 10, sr * 7 / 10)

        assertTrue("Podcast isolator must heavily attenuate background noise/music", outPodcastNoiseRms < inNoiseRms * 0.20)
        assertTrue("Vocals isolator must heavily attenuate background noise/music", outVocalsNoiseRms < inNoiseRms * 0.25)
        assertTrue("Podcast vocal must remain strong and clean", outPodcastVoiceRms > 0.10)
        assertTrue("Vocals vocal must remain strong and clean", outVocalsVoiceRms > 0.10)
    }
}
