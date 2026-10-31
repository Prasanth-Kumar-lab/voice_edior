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
        val beta = 1.0 + 1.5 * a
        val floorGain = dbToLin(-(6.0 + 24.0 * a))

        for (k in 0 until BINS) {
            val p = re[k] * re[k] + im[k] * im[k] + 1e-8
            if (!primed) { ps[k] = p; cur[k] = p } else ps[k] = 0.7 * ps[k] + 0.3 * p
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
        // so a sustained note cannot be learned as "noise".
        for (k in 0 until BINS) {
            val startBin = (k - 7).coerceIn(0, BINS - 15)
            for (j in 0 until 15) med[j] = mMin[startBin + j]
            for (x in 1 until 15) { val v = med[x]; var b = x - 1; while (b >= 0 && med[b] > v) { med[b + 1] = med[b]; b-- }; med[b + 1] = v }
            noise[k] = BIAS * min(mMin[k], med[7])
        }
        for (k in 0 until BINS) {
            val p = re[k] * re[k] + im[k] * im[k] + 1e-8
            val gam = p / noise[k]
            val xi = ALPHA * gPrev[k] * gPrev[k] * gamPrev[k] + (1 - ALPHA) * max(gam - 1.0, 0.0)
            gain[k] = max(xi / (xi + beta), floorGain)
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
