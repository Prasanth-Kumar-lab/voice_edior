package com.example.voice_edior.rt

import com.example.voice_edior.dsp.Mastering
import com.example.voice_edior.dsp.PitchAnalyzer
import com.example.voice_edior.dsp.VocalChain
import com.example.voice_edior.dsp.VocalFx
import com.example.voice_edior.dsp.VoiceInfo
import java.io.File

class EnhanceResult(
    val path: String, val durationMs: Int, val lufsIn: Double, val lufsOut: Double,
    val floorInDb: Double, val floorOutDb: Double, val f0: Float, val voiceType: String,
    val stereo: Boolean = false,
)

/**
 * On-device premium pass: pitch analysis → two-stage noise removal → mode chain → final clean → space → loudness.
 *
 * The final clean runs *after* the dynamics: leveling and compression lift whatever remains in the pauses,
 * so the gate has to be the last thing that touches the background.
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

            progress("Analyzing pitch", 0.15f)
            val info = PitchAnalyzer.analyze(x, sr)
            val initFx = if (vocals) ModeFx.vocals(info, tone, space) else ModeFx.podcast(if (tone == "natural") "general_bass" else tone, level, info)

            // Stage 1: dedicated noise removal at full strength; stage 2 learns the cleaner floor and finishes the job.
            progress("Removing background noise", 0.3f)
            val pass1 = process(x, sr, flat.copy(hpfHz = initFx.hpfHz, denoise = 1.0f))

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

        progress("Polishing the voice", 0.5f)
        val chain = fx.copy(
            denoise = if (vocals) 0.55f else 0.7f,
            hpfHz = 20f,
            gateOn = false,
            reverbMix = 0f,
            exciter = 0f,
        )
        val shaped = process(pass1, sr, chain)

        // Final clean: gate relative to the measured floor, applied after leveling/compression.
        progress("Final clean", 0.72f)
        val gateDb = gateThresholdDb(shaped, sr, if (vocals) 8.0 else 10.0)
        var y = process(
            shaped,
            sr,
            flat.copy(
                gateOn = true,
                gateThresholdDb = gateDb,
                gateDepthDb = if (vocals) 34f else 42f,
                gateReleaseMs = if (vocals) 80f else 60f,
            ),
        )

        // Colour comes after the gate: the exciter and the reverb then never touch the silenced background.
        if (fx.reverbMix > 0.001f || fx.exciter > 0.001f) {
            progress(if (fx.exciter > 0.001f) "Enhancing the voice" else "Adding space", 0.82f)
            val tail = if (fx.reverbMix > 0.001f) (ModeFx.reverbTailSeconds(space) * sr).toInt() else 0
            y = process(
                y, sr,
                flat.copy(
                    exciter = fx.exciter, reverbMix = fx.reverbMix, reverbSize = fx.reverbSize,
                    reverbDamp = fx.reverbDamp, reverbPreMs = fx.reverbPreMs,
                ),
                tail,
            )
        }

        progress("Mastering loudness", 0.9f)
        Mastering.normalize(y, targetLufs, -1.0, sr)

        val blend = strength.coerceIn(0f, 1f)
        if (blend < 0.999f) {
            val cleanMatched = cache.cleanMatched
            val n = minOf(y.size, cleanMatched.size)
            for (i in 0 until n) {
                y[i] = (1f - blend) * cleanMatched[i] + blend * y[i]
            }
        }

        WavFile.write(outPath, PcmClip(y, sr))
        progress("Done", 1f)
        return EnhanceResult(
            outPath, (y.size * 1000L / sr).toInt(), cache.lufsIn, Mastering.integratedLufs(y, sr),
            cache.floorIn, Mastering.noiseFloorDb(y, sr), info.f0Median, info.type, false,
        )
    }

    /**
     * Gate threshold from the same peak-following envelope the gate itself uses: a little above the
     * quiet end of the recording, but never so high that it could clip soft speech (capped 28 dB under loud speech).
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
        if (levels.size < 10) return -60f
        levels.sort()
        val p15 = levels[(levels.size * 0.15).toInt()]
        val p90 = levels[minOf(levels.size - 1, (levels.size * 0.90).toInt())]
        return minOf(p15 + marginDb, p90 - 15.0).coerceIn(-72.0, -32.0).toFloat()
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
}
