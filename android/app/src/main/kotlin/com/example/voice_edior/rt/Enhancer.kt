package com.example.voice_edior.rt

import com.example.voice_edior.dsp.Biquad
import com.example.voice_edior.dsp.Mastering
import com.example.voice_edior.dsp.PitchAnalyzer
import com.example.voice_edior.dsp.VocalChain
import com.example.voice_edior.dsp.VocalFx
import com.example.voice_edior.dsp.VocalIsolator
import com.example.voice_edior.dsp.VoiceInfo
import java.io.File

class EnhanceResult(
    val path: String, val durationMs: Int, val lufsIn: Double, val lufsOut: Double,
    val floorInDb: Double, val floorOutDb: Double, val f0: Float, val voiceType: String,
    val stereo: Boolean = false,
)

/**
 * On-device premium pass: pitch analysis → harmonic vocal isolation → two-stage noise removal
 * → mode chain (EQ + dynamics + de-ess) → final zero-noise gate → space → loudness.
 *
 * Includes an in-memory [CleanedVocalCache] so switching filters/tones/spaces/intensity on the
 * Result screen skips file decoding, pitch analysis, STFT vocal isolation, and FFT denoising,
 * applying new filters in ~30–60 ms.
 */
object Enhancer {
    private val flat = VocalFx(
        hpfHz = 20f, denoise = 0f, gateOn = false, deEssOn = false, eqOn = false, compOn = false,
        compMakeupDb = 0f, limiterCeilingDb = 0f,
    )

    private class CleanedVocalCache(
        val key: String,
        val sr: Int,
        val lufsIn: Double,
        val floorIn: Double,
        val info: VoiceInfo,
        val pass1: FloatArray,
        val cleanMatched: FloatArray,
    )

    @Volatile
    private var cachedClean: CleanedVocalCache? = null

    fun run(
        inPath: String, outPath: String, mode: String, tone: String = "natural", space: String = "dry",
        level: String = "enhanced", strength: Float = 1.0f,
        progress: (String, Float) -> Unit = { _, _ -> },
    ): EnhanceResult {
        val vocals = mode == "vocals"
        val targetLufs = if (vocals) -14.0 else -16.0
        val inFile = File(inPath)
        val cacheKey = "$inPath|${inFile.length()}|${inFile.lastModified()}|$vocals"

        var cache = cachedClean
        if (cache == null || cache.key != cacheKey) {
            progress("Reading recording", 0.05f)
            val clip = WavFile.read(inPath)
            val sr = clip.sampleRate
            val x = clip.samples
            val lufsIn = Mastering.integratedLufs(x, sr)
            val floorIn = Mastering.noiseFloorDb(x, sr)

            progress("Analyzing voice & pitch", 0.14f)
            val info = PitchAnalyzer.analyze(x, sr)
            val f0 = if (info.f0Median > 0f) info.f0Median else 160f
            val p10 = if (info.f0P10 > 0f) info.f0P10 else f0 * 0.8f
            val baseHpf = (0.65f * p10).coerceIn(70f, 125f)

            // Stage 1: Offline Harmonic + Multi-Band Spectral Vocal Isolator (run ONCE per recording)
            progress("Isolating vocal & removing background noise", 0.28f)
            val isolated = VocalIsolator.isolate(x, sr, info.f0Median, vocalsMode = vocals)
            val step1 = process(isolated, sr, flat.copy(hpfHz = baseHpf, denoise = 1.0f))
            val pass1 = process(step1, sr, flat.copy(hpfHz = baseHpf, denoise = 0.85f))

            val cleanMatched = pass1.copyOf()
            Mastering.normalize(cleanMatched, targetLufs, -1.0, sr)

            cache = CleanedVocalCache(
                key = cacheKey,
                sr = sr,
                lufsIn = lufsIn,
                floorIn = floorIn,
                info = info,
                pass1 = pass1,
                cleanMatched = cleanMatched,
            )
            cachedClean = cache
        }

        val sr = cache.sr
        val info = cache.info
        val pass1 = cache.pass1
        val fx = if (vocals) ModeFx.vocals(info, tone, space) else ModeFx.podcast(if (tone == "natural") "general_bass" else tone, level, info)

        // Stage 2: Instant zero-FFT voice shaping, dynamics, exciter + active de-esser
        progress("Applying studio filter", 0.55f)
        val chain = fx.copy(
            denoise = 0f,
            hpfHz = fx.hpfHz,
            gateOn = false,
            reverbMix = 0f,
            deEssOn = true,
            deEss = 0.90f,
        )
        val shaped = process(pass1, sr, chain)
        if (!vocals && tone == "theatrical") {
            applyTheatricalBass(shaped, sr, info.f0Median)
        }

        // Stage 3: Final clean gate after leveling/compression so pauses drop to studio black
        progress("Final clean", 0.75f)
        val gateDb = gateThresholdDb(shaped, sr, if (vocals) 8.5 else 9.5)
        var y = process(
            shaped,
            sr,
            flat.copy(
                gateOn = true,
                gateThresholdDb = gateDb,
                gateDepthDb = 58f,
                gateReleaseMs = if (vocals) 75f else 55f,
            ),
        )

        // Stage 4: Space comes after the gate (band-limited 240 Hz - 3.2 kHz inside VocalChain so no 'sshhh' tail)
        if (fx.reverbMix > 0.001f) {
            progress("Adding studio space", 0.84f)
            val tail = (ModeFx.reverbTailSeconds(space) * sr).toInt()
            y = process(
                y, sr,
                flat.copy(
                    reverbMix = fx.reverbMix, reverbSize = fx.reverbSize,
                    reverbDamp = fx.reverbDamp, reverbPreMs = fx.reverbPreMs,
                ),
                tail,
            )
        }

        // Smooth anti-hiss low-pass ceiling so output is 100% free of high-frequency 'sshhh' fizz
        val lpFinal = Biquad().also { it.lowpass(sr, if (vocals) 12800.0 else 11500.0) }
        for (i in y.indices) {
            y[i] = lpFinal.process(y[i].toDouble()).toFloat()
        }

        progress("Mastering loudness", 0.92f)
        Mastering.normalize(y, targetLufs, -1.0, sr)

        val blend = strength.coerceIn(0f, 1f)
        if (blend < 0.999f) {
            val cleanMatched = cache.cleanMatched
            val n = minOf(y.size, cleanMatched.size)
            for (i in 0 until n) {
                y[i] = (1f - blend) * cleanMatched[i] + blend * y[i]
            }
        }

        val isStereo = (space == "wide" || tone == "theatrical" || tone == "studio_booth" || tone == "studio_echo")
        if (isStereo) {
            val haasSamples = (0.014 * sr).toInt().coerceAtLeast(1)
            val sideHp = Biquad().also { it.highpass(sr, 200.0) }
            val sideLp = Biquad().also { it.lowpass(sr, 2400.0) }
            val left = FloatArray(y.size)
            val right = FloatArray(y.size)
            for (i in y.indices) {
                val delayed = if (i >= haasSamples) y[i - haasSamples] else 0f
                // Band-limit stereo width to warm mids (200 - 2400 Hz) so highs never comb-filter into 'sshhh'
                val side = sideLp.process(sideHp.process(delayed.toDouble())).toFloat() * 0.18f
                left[i] = (y[i] + side).coerceIn(-0.891f, 0.891f)
                right[i] = (y[i] - side).coerceIn(-0.891f, 0.891f)
            }
            WavFile.writeStereo(outPath, left, right, sr)
        } else {
            WavFile.write(outPath, PcmClip(y, sr))
        }
        progress("Done", 1f)
        return EnhanceResult(
            outPath, (y.size * 1000L / sr).toInt(), cache.lufsIn, Mastering.integratedLufs(y, sr),
            cache.floorIn, Mastering.noiseFloorDb(y, sr), info.f0Median, info.type, isStereo,
        )
    }

    /**
     * Gate threshold from the same peak-following envelope the gate itself uses: tracks the non-speech
     * floor and closes firmly between words even when background noise or music was loud.
     */
    fun gateThresholdDb(x: FloatArray, sr: Int, marginDb: Double): Float {
        val coef = kotlin.math.exp(-1.0 / (0.012 * sr))
        var env = 0.0
        val levels = ArrayList<Double>(x.size / 480 + 1)
        for (i in x.indices) {
            val a = kotlin.math.abs(x[i]).toDouble()
            env = if (a > env) a else env * coef + a * (1 - coef)
            if (i % 480 == 0) levels.add(20 * kotlin.math.log10(env + 1e-9))
        }
        if (levels.size < 10) return -55f
        levels.sort()
        val p20 = levels[(levels.size * 0.20).toInt()]
        val p90 = levels[minOf(levels.size - 1, (levels.size * 0.90).toInt())]
        return minOf(p20 + marginDb, p90 - 15.0).coerceIn(-68.0, -24.0).toFloat()
    }

    /** Runs a chain over the whole clip, removes its latency, and optionally keeps [tail] extra samples (reverb). */
    fun process(x: FloatArray, sr: Int, fx: VocalFx, tail: Int = 0): FloatArray {
        val chain = VocalChain(sr).also { it.setFx(fx) }
        val lat = chain.latencySamples
        val total = x.size + lat + tail
        val out = FloatArray(x.size + tail)
        val buf = FloatArray(4096)
        var fed = 0
        while (fed < total) {
            val n = minOf(buf.size, total - fed)
            for (i in 0 until n) { val idx = fed + i; buf[i] = if (idx < x.size) x[idx] else 0f }
            chain.process(buf, 0, n)
            for (i in 0 until n) { val o = fed + i - lat; if (o in out.indices) out[o] = buf[i] }
            fed += n
        }
        return out
    }

    /** Speech-following sub-octave + chest resonance for Theatrical + Bass (only active while speaking). */
    private fun applyTheatricalBass(x: FloatArray, sr: Int, f0Hint: Float) {
        val f0 = (if (f0Hint > 65f) f0Hint.toDouble() else 135.0).coerceIn(75.0, 260.0)
        val fundHp = Biquad().also { it.highpass(sr, (f0 * 0.72).coerceAtLeast(52.0)) }
        val fundLp = Biquad().also { it.lowpass(sr, (f0 * 1.95).coerceAtMost(420.0)) }
        val subLp = Biquad().also { it.lowpass(sr, (f0 * 0.80).coerceAtMost(145.0)) }
        val subHp = Biquad().also { it.highpass(sr, 38.0) }
        val envLp = Biquad().also { it.lowpass(sr, 18.0) }

        val env = FloatArray(x.size)
        var maxEnv = 1e-6f
        for (i in x.indices) {
            val e = envLp.process(kotlin.math.abs(x[i]).toDouble()).toFloat().coerceAtLeast(0f)
            env[i] = e
            if (e > maxEnv) maxEnv = e
        }

        var sign = 1.0
        var prevFund = 0.0
        for (i in x.indices) {
            val v = x[i].toDouble()
            val fund = fundLp.process(fundHp.process(v))
            if (prevFund <= 0.0 && fund > 0.0) sign = -sign
            prevFund = fund
            val drive = ((env[i] / maxEnv) - 0.08f).coerceIn(0f, 1.2f).toDouble()
            val subRaw = sign * env[i].toDouble() * drive
            val sub = subHp.process(subLp.process(subRaw))
            val chest = fund * 0.48 * drive
            x[i] = (v + chest + sub * 0.32).toFloat()
        }
    }
}
