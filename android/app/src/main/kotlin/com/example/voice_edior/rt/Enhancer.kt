package com.example.voice_edior.rt

import com.example.voice_edior.dsp.Biquad
import com.example.voice_edior.dsp.Fft
import com.example.voice_edior.dsp.Mastering
import com.example.voice_edior.dsp.PitchAnalyzer
import com.example.voice_edior.dsp.VoiceInfo
import com.example.voice_edior.dsp.VocalChain
import com.example.voice_edior.dsp.VocalFx
import com.example.voice_edior.dsp.dbToLin
import java.io.File
import java.util.Arrays
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sqrt

class EnhanceResult(
    val path: String, val durationMs: Int,
    val lufsIn: Double, val lufsOut: Double,
    val floorInDb: Double, val floorOutDb: Double,
    val f0: Float, val voiceType: String,
    val stereo: Boolean = false,
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

/**
 * Multi-stage offline studio vocal enhancer:
 *  - Stage 1 (Cached): Pitch analysis + Recording-Wide Learned Noise-Profile Wiener Denoiser +
 *    Streaming Minimum-Statistics Denoiser + Multiband STFT Spectral Expander.
 *  - Stage 2 (Instant on Filter Tap): Warm vocal bass enhancement, filter-specific studio EQ,
 *    De-Esser, Soft-Knee Compressor, and Analog Warmth.
 *  - Stage 3: Natural Smooth-Release Speech Expander (Artifact-free, zero gate-chatter / bomb sounds).
 *  - Stage 4: Acoustic Reverb + Harmonic Air + True-Peak LUFS Mastering with boundary de-clicking.
 */
object Enhancer {
    private val flat = VocalFx(
        hpfHz = 45f, denoise = 0f, gateOn = false, deEssOn = false, eqOn = false, compOn = false,
        compMakeupDb = 0f, limiterCeilingDb = 0f,
    )

    @Volatile
    private var cachedClean: CleanedVocalCache? = null

    fun run(
        inPath: String, outPath: String, mode: String, tone: String = "natural", space: String = "dry",
        level: String = "enhanced",
        strength: Float = 1.0f,
        customFx: VocalFx? = null,
        progress: (String, Float) -> Unit = { _, _ -> },
    ): EnhanceResult {
        val vocals = mode == "vocals"
        val effTone = if (!vocals && tone == "natural") "general_bass" else tone
        val targetLufs = if (customFx != null && customFx.outputGainDb < -5.0f) customFx.outputGainDb.toDouble() else (if (vocals) -14.0 else -16.0)
        val fileLen = try { File(inPath).length() } catch (_: Throwable) { 0L }
        val fileMod = try { File(inPath).lastModified() } catch (_: Throwable) { 0L }
        val cacheKey = "$inPath|$fileLen|$fileMod|$vocals"

        var cache = cachedClean
        if (cache == null || cache.key != cacheKey) {
            progress("Reading recording", 0.05f)
            val clip = WavFile.read(inPath)
            val sr = clip.sampleRate
            val x = clip.samples
            val lufsIn = Mastering.integratedLufs(x, sr)
            val floorIn = Mastering.noiseFloorDb(x, sr)

            progress("Analyzing voice & noise profile", 0.14f)
            val info = PitchAnalyzer.analyze(x, sr)

            // 1A. Recording-wide learned noise-profile spectral subtraction
            progress("Removing background noise", 0.28f)
            val preCleaned = profileSpectralDenoise(x, sr, if (vocals) 0.85 else 0.95)

            // 1B. Streaming minimum-statistics Wiener denoiser pass
            val baseHpf = if (vocals) (0.45f * (if (info.f0P10 > 0f) info.f0P10 else 120f)).coerceIn(50f, 85f) else 55f
            val denoised = process(preCleaned, sr, flat.copy(hpfHz = baseHpf, denoise = 0.85f))

            // 1C. Multiband STFT spectral expander to strip band-specific hiss & hum smoothly
            progress("Deep spectral clean", 0.42f)
            val pass1 = multibandSpectralGate(
                denoised,
                sr,
                depthDb = if (vocals) 16.0 else 20.0,
                marginDb = 5.0,
                holdMs = if (vocals) 140.0 else 120.0,
                releaseMs = if (vocals) 200.0 else 180.0,
            )

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
        val fx = customFx ?: (if (vocals) ModeFx.vocals(info, effTone, space) else ModeFx.podcast(effTone, level, info))

        progress("Applying vocal filter & EQ", 0.56f)
        val chain = fx.copy(
            denoise = if (customFx != null) fx.denoise.coerceIn(0f, 1f) else (if (vocals) 0.25f else 0.30f),
            hpfHz = fx.hpfHz,
            gateOn = false,
            reverbMix = 0f,
            exciter = 0f,
        )
        var shaped = process(pass1, sr, chain)

        // Add rich, warm chest resonance & vocal bass fundamental (90-260 Hz) so voices feel full and natural
        val warmBodyAmt = if (customFx != null) {
            0.15f
        } else if (vocals) {
            when (effTone) {
                "deep", "warm" -> 0.45f
                "smooth" -> 0.38f
                else -> 0.30f
            }
        } else {
            when (effTone) {
                "ultra_bass" -> 0.50f
                "theatrical" -> 0.40f
                "bass_treble" -> 0.38f
                "general_bass" -> 0.32f
                "studio_booth" -> 0.28f
                else -> 0.30f
            }
        }
        shaped = applyVocalWarmthBody(shaped, sr, warmBodyAmt)

        // Musical vocal clean pass with gentle depth so background is silenced without cutting vocal tails
        progress("Polishing vocal tone", 0.66f)
        val cleanDepth = if (customFx != null) 12.0 else (if (vocals) 10.0 else 14.0)
        shaped = multibandSpectralGate(shaped, sr, cleanDepth, marginDb = 5.0, holdMs = 120.0, releaseMs = 180.0)

        // Delicate speech-following air (never over-hyped or harsh)
        val airAmount = if (customFx != null) {
            (fx.exciter * 0.4f).coerceIn(0f, 0.4f)
        } else if (vocals) {
            when (effTone) {
                "bright" -> 0.22f
                "radio" -> 0.16f
                else -> 0.10f
            }
        } else {
            when (effTone) {
                "crystal_treble" -> 0.24f
                "bass_treble" -> 0.20f
                "theatrical" -> 0.14f
                "studio_booth" -> 0.12f
                "ultra_bass" -> 0.05f
                else -> 0.12f
            }
        }
        shaped = applyCrispTreble(shaped, sr, airAmount)

        // Natural smooth-release speech expander: eliminates noise in pauses without sudden clicks or gate pops
        progress("Final background silence", 0.74f)
        val pauseFloor = when {
            customFx != null -> (fx.gateThresholdDb.toDouble() - 10.0).coerceIn(-35.0, -18.0)
            vocals -> -22.0
            effTone == "studio_booth" -> -26.0
            effTone == "theatrical" -> -24.0
            else -> -24.0
        }
        var y = applySpeechGate(
            shaped,
            sr,
            pauseFloorDb = pauseFloor,
            holdMs = 160.0,
            lookMs = 20.0,
        )

        // Post-gate colour & acoustic space: exciter and reverb
        if (fx.reverbMix > 0.001f || fx.exciter > 0.001f) {
            progress(if (fx.reverbMix > 0.001f) "Adding studio acoustic space" else "Enhancing vocal air", 0.84f)
            val tailSec = if (customFx != null) {
                if (fx.reverbMix > 0.001f) (fx.reverbSize * 1.4).toDouble() else 0.0
            } else if (vocals && fx.reverbMix > 0.001f) {
                ModeFx.reverbTailSeconds(space)
            } else 0.0
            val tail = (tailSec * sr).toInt()
            y = process(
                y, sr,
                flat.copy(
                    exciter = fx.exciter, reverbMix = fx.reverbMix, reverbSize = fx.reverbSize,
                    reverbDamp = fx.reverbDamp, reverbPreMs = fx.reverbPreMs,
                ),
                tail,
            )
        }

        progress("Mastering loudness", 0.92f)
        Mastering.normalize(y, targetLufs, -1.0, sr)

        // Smooth cosine fade-in (15ms) and fade-out (20ms) to guarantee zero onset/offset DC pops or thumps
        val inFade = (0.015 * sr).toInt().coerceIn(16, y.size / 4)
        for (i in 0 until inFade) {
            val w = (0.5 - 0.5 * cos(PI * i / inFade)).toFloat()
            y[i] *= w
        }
        val outFade = (0.020 * sr).toInt().coerceIn(16, y.size / 4)
        for (i in 0 until outFade) {
            val w = (0.5 - 0.5 * cos(PI * i / outFade)).toFloat()
            y[y.size - 1 - i] *= w
        }

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
     * Speech-following vocal warmth and chest resonance enhancer (90–260 Hz).
     * Gives voices natural fullness and satisfying bass depth without boomy room boxiness.
     */
    private fun applyVocalWarmthBody(x: FloatArray, sr: Int, amount: Float): FloatArray {
        if (amount <= 0.01f || x.size < sr / 10) return x
        val out = x.copyOf()
        val bassHp = Biquad().apply { highpass(sr, 95.0, 0.707) }
        val bassLp = Biquad().apply { lowpass(sr, 250.0, 0.707) }

        val env = FloatArray(x.size)
        val envRel = exp(-1.0 / (0.050 * sr))
        var cur = 0.0
        for (i in x.indices) {
            val av = abs(x[i]).toDouble()
            cur = if (av > cur) av else envRel * cur + (1.0 - envRel) * av
            env[i] = cur.toFloat()
        }
        val sorted = env.copyOf()
        Arrays.sort(sorted)
        val ref = max(1e-6f, sorted[(sorted.size * 0.90).toInt().coerceIn(0, sorted.size - 1)])

        for (i in x.indices) {
            val v = x[i].toDouble()
            val body = bassLp.process(bassHp.process(v)).toFloat()
            val gate = ((env[i] - 0.08f * ref) / (0.35f * ref)).coerceIn(0f, 1.0f)
            out[i] = (x[i] + body * 0.75f * amount * gate).coerceIn(-0.98f, 0.98f)
        }
        return out
    }

    /**
     * Recording-wide noise-profile spectral denoiser (1024-bin STFT, 75% overlap).
     * Learns the noise spectrum from the quietest 20% of frames across the entire recording
     * and applies a smooth Decision-Directed Wiener filter.
     */
    private fun profileSpectralDenoise(x: FloatArray, sr: Int, amount: Double): FloatArray {
        val N = 1024
        val hop = 256
        val B = N / 2 + 1
        if (x.size < N * 2) return x.copyOf()

        val nFrames = (x.size - N) / hop + 1
        val win = DoubleArray(N) { sqrt(0.5 - 0.5 * cos(2.0 * PI * it / N)) }
        val fft = Fft(N)

        // 1. Measure frame RMS to identify noise-only frames
        val frameRms = DoubleArray(nFrames)
        for (f in 0 until nFrames) {
            val off = f * hop
            var s = 0.0
            for (i in 0 until N) {
                val v = x[off + i].toDouble()
                s += v * v
            }
            frameRms[f] = sqrt(s / N)
        }
        val sortedRms = frameRms.copyOf()
        Arrays.sort(sortedRms)
        val p20Rms = sortedRms[(nFrames * 0.20).toInt().coerceIn(0, nFrames - 1)]
        val noiseFrameIndices = ArrayList<Int>()
        for (f in 0 until nFrames) {
            if (frameRms[f] <= max(p20Rms * 1.15, 1e-7)) {
                noiseFrameIndices.add(f)
            }
        }
        if (noiseFrameIndices.isEmpty()) {
            for (f in 0 until min(8, nFrames)) noiseFrameIndices.add(f)
        }

        // 2. Build per-bin noise power profile from the 75th percentile of noise frames
        val re = DoubleArray(N)
        val im = DoubleArray(N)
        val nNoise = noiseFrameIndices.size
        val noiseSpecs = Array(B) { DoubleArray(nNoise) }
        for (idx in 0 until nNoise) {
            val off = noiseFrameIndices[idx] * hop
            for (i in 0 until N) {
                re[i] = x[off + i] * win[i]
                im[i] = 0.0
            }
            fft.transform(re, im)
            for (k in 0 until B) {
                noiseSpecs[k][idx] = re[k] * re[k] + im[k] * im[k] + 1e-12
            }
        }
        val rawNoiseProf = DoubleArray(B)
        for (k in 0 until B) {
            Arrays.sort(noiseSpecs[k])
            rawNoiseProf[k] = noiseSpecs[k][(nNoise * 0.75).toInt().coerceIn(0, nNoise - 1)]
        }
        // Smooth noise profile across frequency bins
        val noiseProf = DoubleArray(B)
        for (k in 0 until B) {
            var sum = 0.0
            var cnt = 0
            for (d in -2..2) {
                val j = (k + d).coerceIn(0, B - 1)
                sum += rawNoiseProf[j]
                cnt++
            }
            noiseProf[k] = (sum / cnt) * (1.6 + 1.0 * amount)
        }

        // 3. Apply Decision-Directed Wiener filtering across the recording
        val out = FloatArray(x.size)
        val norm = FloatArray(x.size)
        val gPrev = DoubleArray(B) { 1.0 }
        val gamPrev = DoubleArray(B) { 1.0 }
        val gain = DoubleArray(B)
        val smoothGain = DoubleArray(B)
        val beta = 1.2 + 1.4 * amount
        val floorGain = dbToLin(-(12.0 + 18.0 * amount))
        val alpha = 0.96

        for (f in 0 until nFrames) {
            val off = f * hop
            for (i in 0 until N) {
                re[i] = x[off + i] * win[i]
                im[i] = 0.0
            }
            fft.transform(re, im)
            for (k in 0 until B) {
                val p = re[k] * re[k] + im[k] * im[k] + 1e-12
                val gam = p / max(noiseProf[k], 1e-12)
                val xi = alpha * gPrev[k] * gPrev[k] * gamPrev[k] + (1.0 - alpha) * max(gam - 1.0, 0.0)
                gain[k] = max(xi / (xi + beta), floorGain)
                gamPrev[k] = gam
            }
            for (k in 0 until B) {
                val lo = gain[max(k - 1, 0)]
                val hi = gain[min(k + 1, B - 1)]
                smoothGain[k] = 0.25 * lo + 0.50 * gain[k] + 0.25 * hi
                gPrev[k] = smoothGain[k]
            }
            for (k in 0 until B) {
                val g = smoothGain[k]
                re[k] *= g
                im[k] *= g
                if (k in 1 until N / 2) {
                    re[N - k] = re[k]
                    im[N - k] = -im[k]
                }
            }
            fft.inverse(re, im)
            for (i in 0 until N) {
                val w = win[i]
                out[off + i] += (re[i] * w).toFloat()
                norm[off + i] += (w * w).toFloat()
            }
        }
        for (i in x.indices) {
            out[i] = if (norm[i] > 1e-4f) out[i] / norm[i] else x[i]
        }
        return out
    }

    /**
     * 10-band STFT spectral expander: smoothly reduces noise in unoccupied frequency bands.
     */
    private fun multibandSpectralGate(
        x: FloatArray,
        sr: Int,
        depthDb: Double,
        marginDb: Double,
        holdMs: Double,
        releaseMs: Double,
    ): FloatArray {
        val N = 1024
        val hop = 256
        val B = N / 2 + 1
        if (x.size < N * 2) return x.copyOf()

        val edges = doubleArrayOf(0.0, 120.0, 250.0, 500.0, 1000.0, 2000.0, 3200.0, 5000.0, 8000.0, 12000.0, 24001.0)
        val nb = edges.size - 1
        val binBand = IntArray(B) { k ->
            val hz = k.toDouble() * sr / N
            var b = 0
            while (b < nb - 1 && hz >= edges[b + 1]) b++
            b
        }
        val centersLog = DoubleArray(nb) { b -> ln(max(20.0, 0.5 * (edges[b] + edges[b + 1]))) }
        val binLog = DoubleArray(B) { k -> ln(max(20.0, k.toDouble() * sr / N)) }

        val nFrames = (x.size - N) / hop + 1
        val win = DoubleArray(N) { sqrt(0.5 - 0.5 * cos(2.0 * PI * it / N)) }
        val fft = Fft(N)
        val re = DoubleArray(N)
        val im = DoubleArray(N)

        // Pass 1: measure band energy E[b][f] in dB
        val E = Array(nb) { DoubleArray(nFrames) }
        for (f in 0 until nFrames) {
            val off = f * hop
            for (i in 0 until N) {
                re[i] = x[off + i] * win[i]
                im[i] = 0.0
            }
            fft.transform(re, im)
            val bandSum = DoubleArray(nb)
            for (k in 0 until B) {
                bandSum[binBand[k]] += re[k] * re[k] + im[k] * im[k]
            }
            for (b in 0 until nb) {
                E[b][f] = 10.0 * log10(bandSum[b] + 1e-12)
            }
        }

        // Compute per-band open amount with hold & asymmetric smoothing
        val holdFrames = max(1, (holdMs * 1e-3 * sr / hop).toInt())
        val aOpen = exp(-1.0 / max(1.0, 0.012 * sr / hop))
        val aClose = exp(-1.0 / max(1.0, releaseMs * 1e-3 * sr / hop))
        val gBand = Array(nb) { DoubleArray(nFrames) }

        for (b in 0 until nb) {
            val sorted = E[b].copyOf()
            Arrays.sort(sorted)
            val floor = sorted[(nFrames * 0.12).toInt().coerceIn(0, nFrames - 1)]
            val peak = sorted[(nFrames * 0.88).toInt().coerceIn(0, nFrames - 1)]
            val thr = max(floor + marginDb, peak - 24.0).coerceAtMost(peak - 6.0)
            val rawOpen = DoubleArray(nFrames) { f -> ((E[b][f] - thr) / 6.0).coerceIn(0.0, 1.0) }

            var cur = 0.0
            for (f in 0 until nFrames) {
                var maxHeld = 0.0
                val j0 = max(0, f - holdFrames)
                val j1 = min(nFrames - 1, f + 2) // 2-frame lookahead
                for (j in j0..j1) {
                    if (rawOpen[j] > maxHeld) maxHeld = rawOpen[j]
                }
                val c = if (maxHeld > cur) aOpen else aClose
                cur = c * cur + (1.0 - c) * maxHeld
                gBand[b][f] = cur
            }
        }

        // Pass 2: apply interpolated band gains in STFT domain
        val out = FloatArray(x.size)
        val norm = FloatArray(x.size)
        val gs = DoubleArray(nb)
        val gainDb = DoubleArray(nb)

        for (f in 0 until nFrames) {
            for (b in 0 until nb) {
                gs[b] = when (b) {
                    0, nb - 1 -> gBand[b][f]
                    else -> 0.25 * gBand[b - 1][f] + 0.50 * gBand[b][f] + 0.25 * gBand[b + 1][f]
                }
                gainDb[b] = -(1.0 - gs[b]) * depthDb
            }
            val off = f * hop
            for (i in 0 until N) {
                re[i] = x[off + i] * win[i]
                im[i] = 0.0
            }
            fft.transform(re, im)
            for (k in 0 until B) {
                val lk = binLog[k]
                val gdb = when {
                    lk <= centersLog[0] -> gainDb[0]
                    lk >= centersLog[nb - 1] -> gainDb[nb - 1]
                    else -> {
                        var b = 0
                        while (b < nb - 2 && lk > centersLog[b + 1]) b++
                        val t = (lk - centersLog[b]) / max(1e-9, centersLog[b + 1] - centersLog[b])
                        gainDb[b] + t * (gainDb[b + 1] - gainDb[b])
                    }
                }
                val g = 10.0.pow(gdb / 20.0)
                re[k] *= g
                im[k] *= g
                if (k in 1 until N / 2) {
                    re[N - k] = re[k]
                    im[N - k] = -im[k]
                }
            }
            fft.inverse(re, im)
            for (i in 0 until N) {
                val w = win[i]
                out[off + i] += (re[i] * w).toFloat()
                norm[off + i] += (w * w).toFloat()
            }
        }
        for (i in x.indices) {
            out[i] = if (norm[i] > 1e-4f) out[i] / norm[i] else x[i]
        }
        return out
    }

    /**
     * Natural smooth-release speech expander: eliminates noise in pauses without sudden clicks,
     * gate-drops, or bomb-like transients.
     */
    private fun applySpeechGate(
        x: FloatArray,
        sr: Int,
        pauseFloorDb: Double,
        holdMs: Double,
        lookMs: Double,
    ): FloatArray {
        val hop = max(1, (0.003 * sr).toInt())
        val win = max(hop * 2, (0.025 * sr).toInt())
        if (x.size < win * 2) return x.copyOf()

        val nFrames = (x.size - win) / hop + 1
        val frameDb = DoubleArray(nFrames)
        for (f in 0 until nFrames) {
            val off = f * hop
            var s = 0.0
            for (i in 0 until win) {
                val v = x[off + i].toDouble()
                s += v * v
            }
            frameDb[f] = 20.0 * log10(sqrt(s / win) + 1e-9)
        }
        val sorted = frameDb.copyOf()
        Arrays.sort(sorted)
        val p15 = sorted[(nFrames * 0.15).toInt().coerceIn(0, nFrames - 1)]
        val p88 = sorted[(nFrames * 0.88).toInt().coerceIn(0, nFrames - 1)]
        val dyn = max(6.0, p88 - p15)
        val speechThr = max(p15 + max(3.0, 0.20 * dyn), p88 - 22.0).coerceAtMost(p88 - 6.0)

        val holdCount = max(1, (holdMs * 1e-3 * sr / hop).toInt())
        val lookCount = max(1, (lookMs * 1e-3 * sr / hop).toInt())
        val env = DoubleArray(nFrames)
        var h = 0
        for (i in 0 until nFrames) {
            if (frameDb[i] > speechThr) h = holdCount
            env[i] = if (h > 0) 1.0 else 0.0
            if (h > 0) h--
        }
        val looked = DoubleArray(nFrames) { i ->
            env[min(nFrames - 1, i + lookCount)]
        }
        // Smooth 16ms attack and 160ms decay prevents transient thumps and envelope clicks
        val aIn = exp(-1.0 / max(1.0, 0.016 * sr / hop))
        val aOut = exp(-1.0 / max(1.0, 0.160 * sr / hop))
        val smoothEnv = DoubleArray(nFrames)
        var cur = 0.0
        for (i in 0 until nFrames) {
            val c = if (looked[i] > cur) aIn else aOut
            cur = c * cur + (1.0 - c) * looked[i]
            smoothEnv[i] = cur
        }

        val pauseFloor = 10.0.pow(pauseFloorDb / 20.0)
        val out = FloatArray(x.size)
        val halfWin = win / 2
        for (i in x.indices) {
            val fPos = (i - halfWin).toDouble() / hop
            val f0 = fPos.toInt().coerceIn(0, nFrames - 1)
            val f1 = (f0 + 1).coerceIn(0, nFrames - 1)
            val frac = (fPos - f0).coerceIn(0.0, 1.0)
            val g = smoothEnv[f0] + frac * (smoothEnv[f1] - smoothEnv[f0])
            val mult = pauseFloor + (1.0 - pauseFloor) * g
            out[i] = (x[i] * mult).toFloat()
        }
        return out
    }

    /**
     * Speech-following high-definition articulation & air enhancer for top-end polish.
     */
    private fun applyCrispTreble(x: FloatArray, sr: Int, amount: Float): FloatArray {
        if (amount <= 0.01f || x.size < sr / 10) return x
        val out = x.copyOf()
        val presHp = Biquad().apply { highpass(sr, 3000.0, 0.707) }
        val presLp = Biquad().apply { lowpass(sr, 6000.0, 0.707) }
        val airHp = Biquad().apply { highpass(sr, 6500.0, 0.707) }
        val airLp = Biquad().apply { lowpass(sr, 11500.0, 0.707) }

        val env = FloatArray(x.size)
        val envRel = exp(-1.0 / (0.045 * sr))
        var cur = 0.0
        for (i in x.indices) {
            val av = abs(x[i]).toDouble()
            cur = if (av > cur) av else envRel * cur + (1.0 - envRel) * av
            env[i] = cur.toFloat()
        }
        val sorted = env.copyOf()
        Arrays.sort(sorted)
        val ref = max(1e-6f, sorted[(sorted.size * 0.92).toInt().coerceIn(0, sorted.size - 1)])

        for (i in x.indices) {
            val v = x[i].toDouble()
            val pres = presLp.process(presHp.process(v)).toFloat()
            val air = airLp.process(airHp.process(v)).toFloat()
            val gate = ((env[i] - 0.10f * ref) / (0.40f * ref)).coerceIn(0f, 1.0f)
            out[i] = (x[i] + (pres * 0.35f * amount + air * 0.50f * amount) * gate).coerceIn(-0.98f, 0.98f)
        }
        return out
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
