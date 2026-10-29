package com.example.voice_edior.dsp

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/** RBJ biquad, transposed direct form II. */
class Biquad {
    private var b0 = 1.0
    private var b1 = 0.0
    private var b2 = 0.0
    private var a1 = 0.0
    private var a2 = 0.0
    private var z1 = 0.0
    private var z2 = 0.0

    fun process(x: Double): Double {
        val y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }

    fun reset() {
        z1 = 0.0
        z2 = 0.0
    }

    private fun set(nb0: Double, nb1: Double, nb2: Double, a0: Double, na1: Double, na2: Double) {
        b0 = nb0 / a0
        b1 = nb1 / a0
        b2 = nb2 / a0
        a1 = na1 / a0
        a2 = na2 / a0
    }

    fun passthrough() = set(1.0, 0.0, 0.0, 1.0, 0.0, 0.0)

    fun lowpass(sr: Int, f: Double, q: Double = 0.7071) {
        val w = 2 * PI * f / sr
        val c = cos(w)
        val alpha = sin(w) / (2 * q)
        set((1 - c) / 2, 1 - c, (1 - c) / 2, 1 + alpha, -2 * c, 1 - alpha)
    }

    fun highpass(sr: Int, f: Double, q: Double = 0.7071) {
        val w = 2 * PI * f / sr
        val c = cos(w)
        val alpha = sin(w) / (2 * q)
        set((1 + c) / 2, -(1 + c), (1 + c) / 2, 1 + alpha, -2 * c, 1 - alpha)
    }

    fun peaking(sr: Int, f: Double, gainDb: Double, q: Double) {
        val a = 10.0.pow(gainDb / 40)
        val w = 2 * PI * f / sr
        val c = cos(w)
        val alpha = sin(w) / (2 * q)
        set(1 + alpha * a, -2 * c, 1 - alpha * a, 1 + alpha / a, -2 * c, 1 - alpha / a)
    }

    fun lowShelf(sr: Int, f: Double, gainDb: Double) {
        val a = 10.0.pow(gainDb / 40)
        val w = 2 * PI * f / sr
        val c = cos(w)
        val alpha = sin(w) / 2 * sqrt(2.0)
        val beta = 2 * sqrt(a) * alpha
        set(
            a * ((a + 1) - (a - 1) * c + beta),
            2 * a * ((a - 1) - (a + 1) * c),
            a * ((a + 1) - (a - 1) * c - beta),
            (a + 1) + (a - 1) * c + beta,
            -2 * ((a - 1) + (a + 1) * c),
            (a + 1) + (a - 1) * c - beta,
        )
    }

    fun highShelf(sr: Int, f: Double, gainDb: Double) {
        val a = 10.0.pow(gainDb / 40)
        val w = 2 * PI * f / sr
        val c = cos(w)
        val alpha = sin(w) / 2 * sqrt(2.0)
        val beta = 2 * sqrt(a) * alpha
        set(
            a * ((a + 1) + (a - 1) * c + beta),
            -2 * a * ((a - 1) + (a + 1) * c),
            a * ((a + 1) + (a - 1) * c - beta),
            (a + 1) - (a - 1) * c + beta,
            2 * ((a - 1) - (a + 1) * c),
            (a + 1) - (a - 1) * c - beta,
        )
    }
}

fun dbToLin(db: Double): Double = 10.0.pow(db / 20.0)
fun linToDb(lin: Double): Double = 20.0 * kotlin.math.log10(max(lin, 1e-9))

/** One-pole smoothing coefficient for a time constant in ms. */
fun timeCoef(ms: Double, sr: Int): Double = kotlin.math.exp(-1.0 / (max(ms, 0.01) * 0.001 * sr))

/** Radix-2 complex FFT, in place. */
class Fft(private val n: Int) {
    private val cosT = DoubleArray(n / 2) { cos(2 * PI * it / n) }
    private val sinT = DoubleArray(n / 2) { -sin(2 * PI * it / n) }
    private val rev = IntArray(n)

    init {
        val bits = Integer.numberOfTrailingZeros(n)
        for (i in 0 until n) rev[i] = Integer.reverse(i) ushr (32 - bits)
    }

    fun transform(re: DoubleArray, im: DoubleArray) {
        for (i in 0 until n) {
            val j = rev[i]
            if (j > i) {
                var t = re[i]; re[i] = re[j]; re[j] = t
                t = im[i]; im[i] = im[j]; im[j] = t
            }
        }
        var size = 2
        while (size <= n) {
            val half = size / 2
            val step = n / size
            var start = 0
            while (start < n) {
                var k = 0
                for (j in start until start + half) {
                    val wr = cosT[k]
                    val wi = sinT[k]
                    val xr = re[j + half] * wr - im[j + half] * wi
                    val xi = re[j + half] * wi + im[j + half] * wr
                    re[j + half] = re[j] - xr
                    im[j + half] = im[j] - xi
                    re[j] += xr
                    im[j] += xi
                    k += step
                }
                start += size
            }
            size *= 2
        }
    }

    /** Inverse via conjugation; output is scaled by 1/n. */
    fun inverse(re: DoubleArray, im: DoubleArray) {
        for (i in 0 until n) im[i] = -im[i]
        transform(re, im)
        val s = 1.0 / n
        for (i in 0 until n) {
            re[i] *= s
            im[i] = -im[i] * s
        }
    }
}

/**
 * Streaming STFT noise reducer tuned for voice (sqrt-Hann, 75% overlap, N = 512).
 *
 *  - Noise floor: minimum statistics over ~3 s of smoothed power per bin, so held vowels and
 *    sustained notes are NOT mistaken for noise, while hiss, fans, hum and room tone are learned.
 *  - Gain: decision-directed a-priori SNR Wiener filter (Ephraim–Malah). This keeps speech onsets
 *    intact and avoids the "musical noise" warble of plain spectral subtraction.
 *  - Constant latency of [N] samples; `amount` = 0 is bit-transparent.
 */
class SpectralDenoiser(private val sr: Int) {
    companion object {
        const val N = 512
        const val HOP = 128
        const val BINS = N / 2 + 1
        private const val SUB_FRAMES = 75   // ~0.2 s per sub-window at 48 kHz
        private const val SUBS = 15         // ~3 s memory
        private const val BIAS = 3.0        // min-statistics under-estimates the mean power
        private const val ALPHA = 0.97      // decision-directed smoothing
    }

    private val fft = Fft(N)
    private val win = DoubleArray(N) { sqrt(0.5 - 0.5 * cos(2 * PI * it / N)) }
    private val inRing = DoubleArray(N)
    private val outRing = DoubleArray(N)
    private val re = DoubleArray(N)
    private val im = DoubleArray(N)

    private val ps = DoubleArray(BINS)
    private val cur = DoubleArray(BINS)
    private val mMin = DoubleArray(BINS)
    private val med = DoubleArray(15)
    private var warm = 0
    private val subs = Array(SUBS) { DoubleArray(BINS) { Double.MAX_VALUE } }
    private var subIdx = 0
    private var subCount = 0
    private val noise = DoubleArray(BINS)
    private val gPrev = DoubleArray(BINS) { 1.0 }
    private val gamPrev = DoubleArray(BINS) { 1.0 }
    private val gain = DoubleArray(BINS)
    private val smooth = DoubleArray(BINS)

    private var inPos = 0
    private var outPos = 0
    private var count = 0
    private var primed = false

    @Volatile var amount = 0.5

    fun process(x: Double): Double {
        inRing[inPos] = x
        inPos = (inPos + 1) % N
        val y = outRing[outPos]
        outRing[outPos] = 0.0
        outPos = (outPos + 1) % N
        if (++count == HOP) {
            count = 0
            frame()
        }
        return y
    }

    private fun frame() {
        val a = amount.coerceIn(0.0, 1.0)
        // The first N/HOP frames still contain the zero-filled start-up buffer; learning from them
        // would pin the noise floor near zero for the whole 3 s memory. Pass them through untouched.
        if (warm < N / HOP) {
            warm++
        } else if (a > 1e-4) {
            for (i in 0 until N) {
                re[i] = inRing[(inPos + i) % N] * win[i]
                im[i] = 0.0
            }
            fft.transform(re, im)
            filter(a)
            fft.inverse(re, im)
            val scale = 0.5 // sqrt-Hann in/out at 75% overlap sums to 2
            for (i in 0 until N) outRing[(outPos + i) % N] += re[i] * win[i] * scale
            return
        }
        val scale = 0.5
        for (i in 0 until N) {
            val w = win[i]
            outRing[(outPos + i) % N] += inRing[(inPos + i) % N] * (w * w * scale)
        }
    }

    /** Learns the noise floor from the spectrum in [re]/[im] and attenuates it in place. */
    private fun filter(a: Double) {
        val strength = min(1.0, a * 8.0)              // smooth hand-off to exact bypass at 0
        val beta = 2.2 + 2.8 * a
        val floorGain = dbToLin(-(14.0 + 36.0 * a))
        val hiCutBin = (4200.0 * N / sr).toInt().coerceIn(1, BINS - 1)
        val ultraCutBin = (11500.0 * N / sr).toInt().coerceIn(1, BINS - 1)

        for (k in 0 until BINS) {
            val p = re[k] * re[k] + im[k] * im[k] + 1e-8
            if (!primed) { ps[k] = p; cur[k] = p } else ps[k] = 0.65 * ps[k] + 0.35 * p
            if (ps[k] < cur[k]) cur[k] = ps[k]
        }
        primed = true
        if (++subCount >= SUB_FRAMES) {
            val slot = subs[subIdx]
            for (k in 0 until BINS) { slot[k] = cur[k]; cur[k] = ps[k] }
            subIdx = (subIdx + 1) % SUBS
            subCount = 0
        }
        for (k in 0 until BINS) {
            var m = cur[k]
            for (s in 0 until SUBS) if (subs[s][k] < m) m = subs[s][k]
            mMin[k] = m
        }
        // Noise is smooth across frequency, held notes are peaky: cap each bin at the local median
        // over 15 distinct neighboring bins so a multi-harmonic sustained note is never learned as "noise".
        for (k in 0 until BINS) {
            val startBin = (k - 7).coerceIn(0, BINS - 15)
            for (j in 0 until 15) med[j] = mMin[startBin + j]
            for (x in 1 until 15) { val v = med[x]; var b = x - 1; while (b >= 0 && med[b] > v) { med[b + 1] = med[b]; b-- }; med[b + 1] = v }
            val freqBoost = if (k >= hiCutBin) 1.5 else 1.0
            noise[k] = BIAS * 1.25 * freqBoost * min(mMin[k], med[7])
        }
        for (k in 0 until BINS) {
            val p = re[k] * re[k] + im[k] * im[k] + 1e-8
            val gam = p / noise[k]
            val xi = ALPHA * gPrev[k] * gPrev[k] * gamPrev[k] + (1 - ALPHA) * max(gam - 1.0, 0.0)
            val localBeta = if (k >= hiCutBin) beta * 1.6 else beta
            var g = max(xi / (xi + localBeta), floorGain)
            if (k >= ultraCutBin) {
                val roll = ((BINS - 1 - k).toDouble() / max(1, BINS - 1 - ultraCutBin)).coerceIn(0.0, 1.0)
                g *= roll * roll
            }
            gain[k] = g
            gamPrev[k] = gam
        }
        for (k in 0 until BINS) {
            val lo = gain[max(k - 1, 0)]
            val hi = gain[min(k + 1, BINS - 1)]
            smooth[k] = 0.25 * lo + 0.5 * gain[k] + 0.25 * hi
            gPrev[k] = smooth[k]
        }
        for (k in 0 until BINS) {
            val g = 1.0 + (smooth[k] - 1.0) * strength
            re[k] *= g
            im[k] *= g
            if (k in 1 until N / 2) {
                re[N - k] = re[k]
                im[N - k] = -im[k]
            }
        }
    }
}

/**
 * Pro-Level Offline Harmonic + Inter-Harmonic Valley + Formant-Gated Vocal Isolator.
 *
 * Specifically engineered to solve:
 *  1. Non-stationary passing vehicle/bike/traffic/horn noise in the background (via Formant HNR +
 *     Sub-Rumble Voice-vs-Bike discrimination and direct non-vocal noise tracking).
 *  2. Simultaneous & close-to-vocal noise during or immediately adjacent to speech (via 2048-bin
 *     inter-harmonic valley noise estimation, dynamic sub-fundamental rumble cut below 0.82*f0,
 *     per-bin spectral envelope gating, and 32 ms tight syllable hangover).
 *  3. High-frequency 'sshhh' vocal hiss (via spectral flatness + consonant SNR gating).
 */
object VocalIsolator {
    private const val N = 2048
    private const val HOP = 512
    private const val BINS = N / 2 + 1

    fun isolate(xIn: FloatArray, sr: Int, f0Hint: Float = 150f, vocalsMode: Boolean = false): FloatArray {
        if (xIn.size < N * 2) return xIn.copyOf()

        // 1. Remove sharp pin/click/ignition transients (5-point median spike suppressor)
        val x = FloatArray(xIn.size)
        val m5 = FloatArray(5)
        var diffAbsSum = 0.0
        for (i in xIn.indices) {
            for (d in -2..2) m5[d + 2] = xIn[(i + d).coerceIn(0, xIn.size - 1)]
            m5.sort()
            val med = m5[2]
            x[i] = med
            diffAbsSum += kotlin.math.abs(xIn[i] - med)
        }
        val mad = (diffAbsSum / xIn.size) * 1.4826 + 1e-7
        for (i in xIn.indices) {
            val med = x[i]
            x[i] = if (kotlin.math.abs(xIn[i] - med) > 3.6 * mad) med else xIn[i]
        }

        // 2. High-resolution STFT analysis (N = 2048, HOP = 512, 23.4 Hz bin spacing at 48 kHz)
        val nFrames = (x.size - N) / HOP + 1
        if (nFrames < 4) return x
        val fft = Fft(N)
        val win = DoubleArray(N) { sqrt(0.5 - 0.5 * cos(2 * PI * it / N)) }
        val specRe = Array(nFrames) { DoubleArray(BINS) }
        val specIm = Array(nFrames) { DoubleArray(BINS) }
        val power = Array(nFrames) { DoubleArray(BINS) }

        val re = DoubleArray(N)
        val im = DoubleArray(N)
        val binHz = sr.toDouble() / N
        val subLoBin = (20.0 / binHz).toInt().coerceIn(1, BINS - 1)
        val subHiBin = (95.0 / binHz).toInt().coerceIn(subLoBin + 1, BINS - 1)
        val vLoBin = (95.0 / binHz).toInt().coerceIn(1, BINS - 1)
        val vHiBin = (3600.0 / binHz).toInt().coerceIn(vLoBin + 1, BINS - 1)
        val formLoBin = (280.0 / binHz).toInt().coerceIn(vLoBin, BINS - 1)
        val formHiBin = (2800.0 / binHz).toInt().coerceIn(formLoBin + 1, BINS - 1)
        val sibLoBin = (3800.0 / binHz).toInt().coerceIn(1, BINS - 1)
        val sibHiBin = (11000.0 / binHz).toInt().coerceIn(sibLoBin + 1, BINS - 1)
        val maxVocalBin = ((if (vocalsMode) 13000.0 else 11500.0) / binHz).toInt().coerceIn(sibLoBin + 1, BINS - 1)

        val vocalBandDb = DoubleArray(nFrames)
        val harmonicity = DoubleArray(nFrames)
        val instF0Bin = DoubleArray(nFrames)
        val highFlatness = DoubleArray(nFrames)
        val consonantRatio = DoubleArray(nFrames)

        val defaultF0Bin = ((if (f0Hint > 65f) f0Hint.toDouble() else 150.0) / binHz).coerceIn(3.0, 20.0)
        val minF0Bin = (75.0 / binHz).coerceAtLeast(3.0)
        val maxF0Bin = (460.0 / binHz).coerceAtMost(24.0)

        for (t in 0 until nFrames) {
            val off = t * HOP
            for (i in 0 until N) {
                re[i] = x[off + i] * win[i]
                im[i] = 0.0
            }
            fft.transform(re, im)
            var subEnergy = 1e-12
            var vEnergy = 1e-12
            var formEnergy = 1e-12
            var consEnergy = 1e-12
            for (k in 0 until BINS) {
                specRe[t][k] = re[k]
                specIm[t][k] = im[k]
                val p = re[k] * re[k] + im[k] * im[k] + 1e-12
                power[t][k] = p
                if (k in subLoBin..subHiBin) subEnergy += p
                if (k in vLoBin..vHiBin) vEnergy += p
                if (k in formLoBin..formHiBin) formEnergy += p
                if (k in (2400.0 / binHz).toInt()..sibHiBin) consEnergy += p
            }
            val meanSub = subEnergy / (subHiBin - subLoBin + 1)
            val meanVocal = vEnergy / (vHiBin - vLoBin + 1)
            val meanForm = formEnergy / (formHiBin - formLoBin + 1)
            val meanCons = consEnergy / max(1, sibHiBin - (2400.0 / binHz).toInt() + 1)
            vocalBandDb[t] = 10.0 * kotlin.math.log10(meanVocal)
            consonantRatio[t] = meanCons / (meanSub + meanVocal * 0.25 + 1e-12)

            // High-band spectral flatness (detects 'sshhh' white-noise hiss vs crisp consonants)
            var logSum = 0.0
            var arithSum = 1e-12
            val nHi = (sibHiBin - sibLoBin + 1).toDouble()
            for (k in sibLoBin..sibHiBin) {
                val p = power[t][k]
                logSum += kotlin.math.ln(p)
                arithSum += p
            }
            highFlatness[t] = (kotlin.math.exp(logSum / nHi) / (arithSum / nHi)).coerceIn(0.0, 1.0)

            // High-precision Harmonic Comb + Formant HNR detector (distinguishes human voice from passing bikes)
            var bestScore = 0.0
            var bestFormantScore = 0.0
            var bestF0 = defaultF0Bin
            var step = minF0Bin
            while (step <= maxF0Bin) {
                var hSum = 0.0
                var vSum = 0.0
                var fhSum = 0.0
                var fvSum = 0.0
                val maxH = min(10, (vHiBin / step).toInt())
                for (h in 1..maxH) {
                    val hk = kotlin.math.round(h * step).toInt()
                    val vk = kotlin.math.round((h + 0.5) * step).toInt()
                    if (hk in 1 until (BINS - 1) && vk in 1 until (BINS - 1)) {
                        val w = 1.0 / sqrt(h.toDouble())
                        // Symmetric 3-bin mainlobe integration eliminates max/min random white-noise bias
                        val hPeak = 0.25 * power[t][hk - 1] + 0.50 * power[t][hk] + 0.25 * power[t][hk + 1]
                        val vMin = 0.25 * power[t][vk - 1] + 0.50 * power[t][vk] + 0.25 * power[t][vk + 1]
                        val hAmp = sqrt(hPeak) * w
                        val vAmp = sqrt(vMin) * w
                        hSum += hAmp
                        vSum += vAmp
                        if (hk in formLoBin..formHiBin) {
                            fhSum += hAmp
                            fvSum += vAmp
                        }
                    }
                }
                val score = hSum / (vSum + 1e-6)
                val fScore = if (fhSum > 0.0) fhSum / (fvSum + 1e-6) else 1.0
                val combined = score * 0.50 + fScore * 0.50
                if (combined > bestScore) {
                    bestScore = combined
                    bestFormantScore = fScore
                    bestF0 = step
                }
                step += 0.20
            }
            instF0Bin[t] = bestF0

            // Passing bikes / motorcycles have heavy sub-rumble (<95 Hz) and broadband exhaust roar (low formant comb)
            val rumbleRatio = meanSub / (meanForm + 1e-12)
            val bikePenalty = when {
                bestFormantScore < 1.48 -> 0.15
                rumbleRatio > 2.5 && bestFormantScore < 1.85 -> 0.20
                rumbleRatio > 1.5 && bestFormantScore < 1.65 -> 0.40
                else -> 1.0
            }
            val rawHarm = ((bestScore - 1.30) / 1.35).coerceIn(0.0, 1.0)
            harmonicity[t] = (rawHarm * bikePenalty).coerceIn(0.0, 1.0)
        }

        // 3. Smooth pitch trajectory & harmonicity to reject transient engine knocks / clicks
        val smoothF0Bin = DoubleArray(nFrames)
        val smoothHarm = DoubleArray(nFrames)
        val p3 = DoubleArray(3)
        for (t in 0 until nFrames) {
            for (d in -1..1) p3[d + 1] = instF0Bin[(t + d).coerceIn(0, nFrames - 1)]
            p3.sort()
            smoothF0Bin[t] = p3[1]

            // Check 3-frame pitch stability: human vocal cords maintain coherent pitch across syllables
            val fPrev = instF0Bin[max(0, t - 1)]
            val fNext = instF0Bin[min(nFrames - 1, t + 1)]
            val pitchCoherent = kotlin.math.abs(instF0Bin[t] - fPrev) < 0.18 * instF0Bin[t] ||
                kotlin.math.abs(instF0Bin[t] - fNext) < 0.18 * instF0Bin[t]
            val cohFactor = if (pitchCoherent) 1.12 else 0.72
            val hAvg = 0.25 * harmonicity[max(0, t - 1)] + 0.50 * harmonicity[t] + 0.25 * harmonicity[min(nFrames - 1, t + 1)]
            smoothHarm[t] = (hAvg * cohFactor).coerceIn(0.0, 1.0)
        }

        // 4. Strict Voice vs. Background/Bike Frame Classification (never opens on loudness alone!)
        val sortedV = vocalBandDb.copyOf().also { it.sort() }
        val p15 = sortedV[(nFrames * 0.15).toInt()]
        val p85 = sortedV[(nFrames * 0.85).toInt()]
        val dynRange = max(8.0, p85 - p15)
        val speechThrDb = max(p15 + 4.5, p85 - min(22.0, dynRange * 0.68))

        val isVoicedVowel = BooleanArray(nFrames) { t ->
            vocalBandDb[t] > speechThrDb && smoothHarm[t] > 0.23
        }
        // Remove isolated 1-frame false-positive blips
        val cleanVoiced = BooleanArray(nFrames) { t ->
            if (!isVoicedVowel[t]) false
            else (t > 0 && isVoicedVowel[t - 1]) || (t + 1 < nFrames && isVoicedVowel[t + 1])
        }
        // Attach brief unvoiced consonants ('s', 't', 'k') ONLY if within 3 frames (~32 ms) of a confirmed voiced vowel
        val isVocalFrame = BooleanArray(nFrames) { t ->
            if (cleanVoiced[t]) {
                true
            } else if (vocalBandDb[t] > speechThrDb - 3.5 && consonantRatio[t] > 0.45 && highFlatness[t] < 0.78) {
                var nearVowel = false
                for (d in -3..3) {
                    val idx = t + d
                    if (idx in 0 until nFrames && cleanVoiced[idx]) {
                        nearVowel = true
                        break
                    }
                }
                nearVowel
            } else {
                false
            }
        }

        // 5. Learn Global Floor + Dynamic Non-Vocal Noise Envelope (tracks passing bikes & close noise!)
        val globalFloor = DoubleArray(BINS)
        val binScratch = DoubleArray(nFrames)
        for (k in 0 until BINS) {
            var countNonVocal = 0
            for (t in 0 until nFrames) {
                if (!isVocalFrame[t]) {
                    binScratch[countNonVocal++] = power[t][k]
                }
            }
            if (countNonVocal >= 3) {
                java.util.Arrays.sort(binScratch, 0, countNonVocal)
                globalFloor[k] = binScratch[(countNonVocal * 0.65).toInt().coerceIn(0, countNonVocal - 1)]
            } else {
                for (t in 0 until nFrames) binScratch[t] = power[t][k]
                binScratch.sort()
                globalFloor[k] = binScratch[(nFrames * 0.20).toInt().coerceIn(0, nFrames - 1)]
            }
        }

        // Precompute prev/next non-vocal frame indices so noise close to or during speech is interpolated
        val prevNonVocal = IntArray(nFrames) { -1 }
        val nextNonVocal = IntArray(nFrames) { -1 }
        var lastNv = -1
        for (t in 0 until nFrames) {
            if (!isVocalFrame[t]) lastNv = t
            prevNonVocal[t] = lastNv
        }
        var nextNv = -1
        for (t in nFrames - 1 downTo 0) {
            if (!isVocalFrame[t]) nextNv = t
            nextNonVocal[t] = nextNv
        }

        // Tight syllable gate: 1-frame look-ahead (10 ms) + 3-frame hold (32 ms) so zero noise trails after words
        val holdFrames = max(2, (0.032 * sr / HOP).toInt())
        val lookFrames = max(1, (0.010 * sr / HOP).toInt())
        val rawGate = DoubleArray(nFrames)
        var hold = 0
        for (t in 0 until nFrames) {
            if (isVocalFrame[t]) hold = holdFrames
            rawGate[t] = if (hold > 0) 1.0 else 0.0
            if (hold > 0) hold--
        }
        val frameGate = DoubleArray(nFrames)
        var gCur = 0.0
        for (t in 0 until nFrames) {
            val target = rawGate[min(nFrames - 1, t + lookFrames)]
            val coef = if (target > gCur) 0.25 else 0.62
            gCur = coef * gCur + (1.0 - coef) * target
            frameGate[t] = gCur
        }

        // 6. Simultaneous Inter-Harmonic Valley Noise + Harmonic Comb + Per-Bin Envelope Suppression
        val gPrev = DoubleArray(BINS) { 1.0 }
        val gamPrev = DoubleArray(BINS) { 1.0 }
        val gainMatrix = Array(nFrames) { DoubleArray(BINS) }
        val pauseFloorLin = dbToLin(-68.0)
        val activeFloorLin = dbToLin(if (vocalsMode) -44.0 else -50.0)
        val valleyNoise = DoubleArray(BINS)

        for (t in 0 until nFrames) {
            val f0b = smoothF0Bin[t]
            val harmStr = smoothHarm[t]
            val flatHi = highFlatness[t]
            val vGate = frameGate[t]
            val pNv = prevNonVocal[t]
            val nNv = nextNonVocal[t]

            // Estimate simultaneous background/bike noise sitting in inter-harmonic valleys (m + 0.5)*f0 during speech
            for (k in 0 until BINS) {
                if (f0b >= 2.5 && k in vLoBin..vHiBin) {
                    val mLow = kotlin.math.floor(k / f0b - 0.5)
                    val vBin1 = kotlin.math.round((max(0.0, mLow) + 0.5) * f0b).toInt().coerceIn(1, BINS - 2)
                    val vBin2 = kotlin.math.round((max(0.0, mLow + 1.0) + 0.5) * f0b).toInt().coerceIn(1, BINS - 2)
                    val vp1 = minOf(power[t][vBin1 - 1], power[t][vBin1], power[t][vBin1 + 1])
                    val vp2 = minOf(power[t][vBin2 - 1], power[t][vBin2], power[t][vBin2 + 1])
                    valleyNoise[k] = 0.5 * (vp1 + vp2)
                } else {
                    valleyNoise[k] = globalFloor[k]
                }
            }

            // Pitch-adaptive sub-fundamental cutoff: everything below 0.82 * f0 is bike/traffic/mic rumble
            val subVoiceCutBin = (f0b * 0.82).toInt().coerceIn(subLoBin, vLoBin + 8)

            for (k in 0 until BINS) {
                val p = power[t][k]

                // Interpolate non-vocal noise across words (or directly match power[t][k] in non-vocal frames!)
                val nvEst = when {
                    !isVocalFrame[t] -> p
                    pNv >= 0 && nNv >= 0 -> {
                        val w = (t - pNv).toDouble() / max(1, nNv - pNv)
                        (1.0 - w) * power[pNv][k] + w * power[nNv][k]
                    }
                    pNv >= 0 -> power[pNv][k]
                    nNv >= 0 -> power[nNv][k]
                    else -> globalFloor[k]
                }

                // Check if bin k sits on a vocal harmonic peak (m * f0)
                val distToHarm = if (k in subVoiceCutBin..vHiBin && f0b >= 2.5) {
                    val nearestHarm = kotlin.math.round(k / f0b) * f0b
                    kotlin.math.abs(k - nearestHarm) / f0b
                } else {
                    0.5
                }
                val onHarmPeak = isVocalFrame[t] && k in subVoiceCutBin..vHiBin && distToHarm <= 0.24

                // Combine global floor, adjacent non-vocal noise, and simultaneous inter-harmonic valley noise
                val baseNoise = if (onHarmPeak) {
                    max(globalFloor[k], nvEst * 0.65)
                } else {
                    maxOf(globalFloor[k], nvEst * 0.85, valleyNoise[k] * 1.25)
                }
                val overSub = when {
                    k < subVoiceCutBin -> 8.0
                    k >= sibLoBin -> 4.5 + 4.5 * flatHi
                    onHarmPeak -> if (vocalsMode) 1.25 else 1.45
                    else -> if (vocalsMode) 2.8 else 3.5
                }
                val nEst = baseNoise * overSub + 1e-12
                val gam = p / nEst
                val xi = 0.92 * gPrev[k] * gPrev[k] * gamPrev[k] + 0.08 * max(gam - 1.0, 0.0)
                val beta = when {
                    k >= sibLoBin -> 4.0
                    onHarmPeak -> 1.0
                    else -> 2.5
                }
                var g = max(xi / (xi + beta), activeFloorLin)

                // Dynamic sub-fundamental rumble elimination (removes bike/engine rumble under the vocal)
                if (k < subVoiceCutBin) {
                    val roll = (k.toDouble() / max(1, subVoiceCutBin)).coerceIn(0.0, 1.0)
                    g *= roll * roll * 0.04
                }

                // Sharp Harmonic Comb Mask: strip simultaneous background bike/music/noise between vocal harmonics
                if (k in subVoiceCutBin..vHiBin && f0b >= 2.5 && distToHarm > 0.20) {
                    val combStrength = max(0.35, harmStr)
                    val normDist = ((distToHarm - 0.20) / 0.30).coerceIn(0.0, 1.0)
                    val valleyAtten = 1.0 - (0.86 * combStrength * normDist)
                    g *= valleyAtten
                }

                // Per-Bin Spectral Envelope Gate: close unused frequency bands even WHILE speaking (kills close-to-vocal noise halo)
                val xiGateThr = if (onHarmPeak) 0.45 else 1.6
                if (xi < xiGateThr) {
                    val binOpen = (xi / xiGateThr).coerceIn(0.05, 1.0)
                    g *= binOpen * binOpen
                }

                // Anti-'sshhh' High-Frequency Gate (>3.8 kHz)
                if (k >= sibLoBin) {
                    val hissPenalty = (1.0 - 0.85 * flatHi).coerceIn(0.06, 1.0)
                    val snrHi = gam / (1.2 + gam)
                    g *= hissPenalty * snrHi
                }

                // Ultrasonic / high-hiss low-pass roll-off above 11.5 kHz (Podcast) / 13 kHz (Vocals)
                if (k >= maxVocalBin) {
                    val roll = ((BINS - 1 - k).toDouble() / max(1, BINS - 1 - maxVocalBin)).coerceIn(0.0, 1.0)
                    g *= roll * roll * 0.12
                }

                val finalG = pauseFloorLin + (g - pauseFloorLin) * vGate
                gainMatrix[t][k] = finalG.coerceIn(pauseFloorLin, 1.0)
                gPrev[k] = gainMatrix[t][k]
                gamPrev[k] = gam
            }
        }

        // 7. Spectro-Temporal Persistence Polish (removes isolated musical-noise islands close to vocal) + Overlap-Add
        val smoothG = DoubleArray(BINS)
        val out = FloatArray(x.size)
        for (t in 0 until nFrames) {
            val gCurRow = gainMatrix[t]
            val gPrevRow = gainMatrix[max(0, t - 1)]
            val gNextRow = gainMatrix[min(nFrames - 1, t + 1)]

            for (k in 0 until BINS) {
                val lo = gCurRow[max(0, k - 1)]
                val hi = gCurRow[min(BINS - 1, k + 1)]
                val avgFreq = 0.25 * lo + 0.50 * gCurRow[k] + 0.25 * hi
                // Preserve sharp vocal harmonic peaks across adjacent attenuated valleys while smoothing non-harmonic bins
                var gFreq = if (gPrevRow[k] > 0.30 || gNextRow[k] > 0.30) {
                    max(gCurRow[k] * 0.95, avgFreq)
                } else {
                    avgFreq
                }
                // If neither the previous nor next frame had energy in this bin, suppress isolated 1-frame noise blip
                if (gPrevRow[k] < 0.08 && gNextRow[k] < 0.08 && gFreq < 0.35) {
                    gFreq *= 0.20
                }
                smoothG[k] = gFreq
            }

            for (k in 0 until BINS) {
                val g = smoothG[k]
                re[k] = specRe[t][k] * g
                im[k] = specIm[t][k] * g
                if (k in 1 until N / 2) {
                    re[N - k] = re[k]
                    im[N - k] = -im[k]
                }
            }
            fft.inverse(re, im)
            val off = t * HOP
            val scale = 0.5 // sqrt-Hann at 75% overlap (N=2048, HOP=512) sums to 2.0
            for (i in 0 until N) {
                out[off + i] += (re[i] * win[i] * scale).toFloat()
            }
        }

        // 8. Final 4th-order Butterworth sub-vocal rumble high-pass & anti-hiss low-pass
        val hp1 = Biquad().also { it.highpass(sr, if (vocalsMode) 78.0 else 85.0) }
        val hp2 = Biquad().also { it.highpass(sr, if (vocalsMode) 78.0 else 85.0) }
        val lp1 = Biquad().also { it.lowpass(sr, if (vocalsMode) 13200.0 else 11800.0) }
        val lp2 = Biquad().also { it.lowpass(sr, if (vocalsMode) 13200.0 else 11800.0) }
        for (i in out.indices) {
            val v = lp2.process(lp1.process(hp2.process(hp1.process(out[i].toDouble()))))
            out[i] = v.toFloat()
        }
        return out
    }
}
