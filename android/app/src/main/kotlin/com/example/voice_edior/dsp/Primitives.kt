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
 * Offline Two-Pass Harmonic + Multi-Band Spectral Vocal Isolator.
 *
 * Strips out stationary noise, non-stationary street/café chatter, background music accompaniment,
 * and high-frequency 'sshhh' vocal hiss while preserving crystal-clear human voice in both
 * Podcast and Vocals/Sing modes.
 */
object VocalIsolator {
    private const val N = 1024
    private const val HOP = 256
    private const val BINS = N / 2 + 1

    fun isolate(xIn: FloatArray, sr: Int, f0Hint: Float = 150f, vocalsMode: Boolean = false): FloatArray {
        if (xIn.size < N * 2) return xIn.copyOf()

        // 1. Remove sharp pin/click transients (5-point median spike suppressor)
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
            x[i] = if (kotlin.math.abs(xIn[i] - med) > 4.0 * mad) med else xIn[i]
        }

        // 2. STFT analysis (N = 1024, HOP = 256, sqrt-Hann window)
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
        val vLoBin = (120.0 / binHz).toInt().coerceIn(1, BINS - 1)
        val vHiBin = (3600.0 / binHz).toInt().coerceIn(vLoBin + 1, BINS - 1)
        val sibLoBin = (3800.0 / binHz).toInt().coerceIn(1, BINS - 1)
        val sibHiBin = (11000.0 / binHz).toInt().coerceIn(sibLoBin + 1, BINS - 1)
        val maxVocalBin = ((if (vocalsMode) 13000.0 else 11500.0) / binHz).toInt().coerceIn(sibLoBin + 1, BINS - 1)

        val vocalBandDb = DoubleArray(nFrames)
        val harmonicity = DoubleArray(nFrames)
        val instF0Bin = DoubleArray(nFrames)
        val highFlatness = DoubleArray(nFrames)

        for (t in 0 until nFrames) {
            val off = t * HOP
            for (i in 0 until N) {
                re[i] = x[off + i] * win[i]
                im[i] = 0.0
            }
            fft.transform(re, im)
            var vEnergy = 1e-12
            var vMax = 1e-12
            for (k in 0 until BINS) {
                specRe[t][k] = re[k]
                specIm[t][k] = im[k]
                val p = re[k] * re[k] + im[k] * im[k] + 1e-12
                power[t][k] = p
                if (k in vLoBin..vHiBin) {
                    vEnergy += p
                    if (p > vMax) vMax = p
                }
            }
            vocalBandDb[t] = 10.0 * kotlin.math.log10(vEnergy / (vHiBin - vLoBin + 1))

            // High-band spectral flatness (detects 'sshhh' white-noise hiss vs crisp consonants)
            var logSum = 0.0
            var arithSum = 1e-12
            val nHi = (sibHiBin - sibLoBin + 1).toDouble()
            for (k in sibLoBin..sibHiBin) {
                val p = power[t][k]
                logSum += kotlin.math.ln(p)
                arithSum += p
            }
            val geomMean = kotlin.math.exp(logSum / nHi)
            val arithMean = arithSum / nHi
            highFlatness[t] = (geomMean / arithMean).coerceIn(0.0, 1.0)

            // Instantaneous harmonic pitch detection via Harmonic Product / Comb Correlation
            val minF0Bin = (75.0 / binHz).coerceAtLeast(1.5)
            val maxF0Bin = (460.0 / binHz).coerceAtMost(60.0)
            var bestScore = 0.0
            var bestF0 = (if (f0Hint > 65f) f0Hint.toDouble() else 150.0) / binHz
            var step = minF0Bin
            while (step <= maxF0Bin) {
                var hSum = 0.0
                var vSum = 0.0
                for (h in 1..6) {
                    val hk = (h * step).toInt()
                    val vk = ((h + 0.5) * step).toInt()
                    if (hk < vHiBin) hSum += sqrt(power[t][hk])
                    if (vk < vHiBin) vSum += sqrt(power[t][vk])
                }
                val score = hSum / (vSum + 1e-6)
                if (score > bestScore) {
                    bestScore = score
                    bestF0 = step
                }
                step += 0.35
            }
            instF0Bin[t] = bestF0
            harmonicity[t] = ((bestScore - 1.15) / 1.5).coerceIn(0.0, 1.0)
        }

        // 3. Identify vocal vs non-vocal (background noise / music-only) frames
        val sortedV = vocalBandDb.copyOf().also { it.sort() }
        val p15 = sortedV[(nFrames * 0.15).toInt()]
        val p85 = sortedV[(nFrames * 0.85).toInt()]
        val dynRange = max(8.0, p85 - p15)
        val speechThrDb = max(p15 + 4.5, p85 - min(22.0, dynRange * 0.68))

        val isVocalFrame = BooleanArray(nFrames) { t ->
            vocalBandDb[t] > speechThrDb && (harmonicity[t] > 0.18 || vocalBandDb[t] > speechThrDb + 5.0)
        }

        // 4. Learn global + local sliding noise/music power floor per bin
        val globalFloor = DoubleArray(BINS)
        val binScratch = DoubleArray(nFrames)
        for (k in 0 until BINS) {
            var countNonVocal = 0
            for (t in 0 until nFrames) {
                if (!isVocalFrame[t]) {
                    binScratch[countNonVocal++] = power[t][k]
                }
            }
            if (countNonVocal >= 4) {
                java.util.Arrays.sort(binScratch, 0, countNonVocal)
                globalFloor[k] = binScratch[(countNonVocal * 0.60).toInt().coerceIn(0, countNonVocal - 1)]
            } else {
                for (t in 0 until nFrames) binScratch[t] = power[t][k]
                binScratch.sort()
                globalFloor[k] = binScratch[(nFrames * 0.22).toInt().coerceIn(0, nFrames - 1)]
            }
        }

        // Smooth global vocal activity envelope with look-ahead (15 ms) and hold (95 ms)
        val holdFrames = max(2, (0.095 * sr / HOP).toInt())
        val lookFrames = max(1, (0.015 * sr / HOP).toInt())
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
            val coef = if (target > gCur) 0.35 else 0.84
            gCur = coef * gCur + (1.0 - coef) * target
            frameGate[t] = gCur
        }

        // 5. Two-pass Wiener + Harmonic Comb + High-Band Anti-'sshhh' suppression
        val gPrev = DoubleArray(BINS) { 1.0 }
        val gamPrev = DoubleArray(BINS) { 1.0 }
        val gain = DoubleArray(BINS)
        val smoothG = DoubleArray(BINS)
        val pauseFloorLin = dbToLin(-65.0)
        val activeFloorLin = dbToLin(if (vocalsMode) -40.0 else -46.0)
        val out = FloatArray(x.size)

        val winRadius = max(6, (0.45 * sr / HOP).toInt())
        val localMin = DoubleArray(BINS)

        for (t in 0 until nFrames) {
            val t0 = max(0, t - winRadius)
            val t1 = min(nFrames - 1, t + winRadius)
            for (k in 0 until BINS) {
                var m = Double.MAX_VALUE
                var stepT = t0
                while (stepT <= t1) {
                    if (power[stepT][k] < m) m = power[stepT][k]
                    stepT += 2
                }
                localMin[k] = max(globalFloor[k], m * 2.8)
            }

            val f0b = instF0Bin[t]
            val harmStr = harmonicity[t]
            val flatHi = highFlatness[t]
            val vGate = frameGate[t]

            for (k in 0 until BINS) {
                val p = power[t][k]
                // Over-subtraction: stronger in sub (<100 Hz) and high hiss (>3.8 kHz) bands
                val overSub = when {
                    k < vLoBin -> 4.5
                    k >= sibLoBin -> 4.2 + 4.0 * flatHi
                    else -> if (vocalsMode) 2.6 else 3.2
                }
                val nEst = localMin[k] * overSub + 1e-12
                val gam = p / nEst
                val xi = 0.94 * gPrev[k] * gPrev[k] * gamPrev[k] + 0.06 * max(gam - 1.0, 0.0)
                val beta = if (k >= sibLoBin) 3.8 else 2.2
                var g = max(xi / (xi + beta), activeFloorLin)

                // Harmonic Comb Mask: suppress background music & noise between vocal harmonics (85 Hz - 3800 Hz)
                if (k in vLoBin..vHiBin && harmStr > 0.22 && f0b >= 1.5) {
                    val nearestHarm = kotlin.math.round(k / f0b) * f0b
                    val dist = kotlin.math.abs(k - nearestHarm) / f0b // 0.0 on harmonic, 0.5 mid-valley
                    if (dist > 0.22) {
                        val valleyAtten = 1.0 - (0.65 * harmStr * ((dist - 0.22) / 0.28).coerceIn(0.0, 1.0))
                        g *= valleyAtten
                    }
                }

                // Anti-'sshhh' High-Frequency Gate:
                // During vowels or when high band is flat white-noise hiss, suppress >3.8 kHz
                if (k >= sibLoBin) {
                    val hissPenalty = (1.0 - 0.82 * flatHi).coerceIn(0.08, 1.0)
                    // Also require high-band energy to be a genuine consonant peak, not continuous hiss
                    val snrHi = gam / (1.0 + gam)
                    g *= hissPenalty * snrHi
                }

                // Smooth ultrasonic / high-hiss low-pass roll-off above 11.5 kHz (Podcast) / 13 kHz (Vocals)
                if (k >= maxVocalBin) {
                    val roll = ((BINS - 1 - k).toDouble() / max(1, BINS - 1 - maxVocalBin)).coerceIn(0.0, 1.0)
                    g *= roll * roll * 0.15
                }

                // Apply pause gate so non-vocal gaps drop to -65 dB studio black
                val finalG = pauseFloorLin + (g - pauseFloorLin) * vGate
                gain[k] = finalG.coerceIn(pauseFloorLin, 1.0)
                gamPrev[k] = gam
            }

            // Smooth across adjacent bins to prevent musical noise artifacts
            for (k in 0 until BINS) {
                val lo = gain[max(0, k - 1)]
                val hi = gain[min(BINS - 1, k + 1)]
                smoothG[k] = 0.25 * lo + 0.50 * gain[k] + 0.25 * hi
                gPrev[k] = smoothG[k]
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
            val scale = 0.5 // sqrt-Hann at 75% overlap (N=1024, HOP=256) sums to 2.0
            for (i in 0 until N) {
                out[off + i] += (re[i] * win[i] * scale).toFloat()
            }
        }

        // 6. Final clean Butterworth high-pass (80 Hz) & anti-hiss low-pass (11.8 kHz / 13.2 kHz)
        val hp1 = Biquad().also { it.highpass(sr, if (vocalsMode) 75.0 else 82.0) }
        val hp2 = Biquad().also { it.highpass(sr, if (vocalsMode) 75.0 else 82.0) }
        val lp1 = Biquad().also { it.lowpass(sr, if (vocalsMode) 13200.0 else 11800.0) }
        val lp2 = Biquad().also { it.lowpass(sr, if (vocalsMode) 13200.0 else 11800.0) }
        for (i in out.indices) {
            val v = lp2.process(lp1.process(hp2.process(hp1.process(out[i].toDouble()))))
            out[i] = v.toFloat()
        }
        return out
    }
}
