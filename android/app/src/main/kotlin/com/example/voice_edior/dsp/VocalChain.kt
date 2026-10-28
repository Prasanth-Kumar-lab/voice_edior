package com.example.voice_edior.dsp

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Mono real-time vocal chain:
 * input trim → HPF → spectral denoise → gate → de-esser → 8-band EQ → compressor → limiter → output.
 *
 * [setFx] may be called from any thread; [process] runs on the audio thread and picks the new
 * settings up at the start of the next block. A/B bypass is latency-matched and cross-faded.
 */
class VocalChain(private val sr: Int) {
    val meters = Meters()

    @Volatile private var fx = VocalFx()
    private var applied: VocalFx? = null

    private val hpf1 = Biquad()
    private val hpf2 = Biquad()
    private val denoiser = SpectralDenoiser(sr)
    private val eq = Array(8) { Biquad() }
    private val eqActive = BooleanArray(8)
    // De-esser: Linkwitz-Riley (LR4) crossover so low + high bands recombine flat when not reducing.
    private val sibHp1 = Biquad()
    private val sibHp2 = Biquad()
    private val sibLp1 = Biquad()
    private val sibLp2 = Biquad()
    private val sibDetect = Biquad()
    private var bodyEnv = 0.0

    // gate
    private var gateEnv = 0.0
    private var gateGain = 1.0
    private var gateHold = 0

    // de-esser
    private var sibEnv = 0.0
    private var sibGain = 1.0

    // compressor
    private var compEnv = 0.0
    private var compGrDb = 0.0

    // limiter
    private val look = 48
    private val limDelay = DoubleArray(look)
    private var limPos = 0
    private var limGain = 1.0

    private val reverb = Reverb(sr)
    private val revHp = Biquad().also { it.highpass(sr, 240.0) }
    private val revLp = Biquad().also { it.lowpass(sr, 3200.0) }

    // Harmonic exciter: new highs generated from the 3.2 kHz+ presence band, only the new harmonics are mixed back
    private val exHp1 = Biquad().also { it.highpass(sr, 3200.0) }
    private val exHp2 = Biquad().also { it.highpass(sr, 3200.0) }
    private val exOut1 = Biquad().also { it.highpass(sr, 5200.0) }
    private val exOut2 = Biquad().also { it.lowpass(sr, 10500.0) }
    private var exRef = 0.015

    // latency-matched dry path for bypass
    private val latency = SpectralDenoiser.N + look
    private val dryDelay = DoubleArray(latency)
    private var dryPos = 0
    private var wet = 1.0

    val latencySamples: Int get() = latency

    fun setFx(next: VocalFx) {
        fx = next
    }

    fun reset() {
        hpf1.reset(); hpf2.reset(); eq.forEach { it.reset() }; sibHp1.reset(); sibHp2.reset(); sibLp1.reset(); sibLp2.reset(); sibDetect.reset(); bodyEnv = 0.0
        reverb.reset(); revHp.reset(); revLp.reset(); exHp1.reset(); exHp2.reset(); exOut1.reset(); exOut2.reset(); exRef = 0.015; gateEnv = 0.0; gateGain = 1.0; sibEnv = 0.0; sibGain = 1.0; compEnv = 0.0; compGrDb = 0.0
        limGain = 1.0
    }

    private fun refresh(f: VocalFx) {
        val prev = applied
        if (prev == null || prev.hpfHz != f.hpfHz) {
            hpf1.highpass(sr, f.hpfHz.toDouble().coerceIn(20.0, 400.0))
            hpf2.highpass(sr, f.hpfHz.toDouble().coerceIn(20.0, 400.0))
        }
        if (prev == null || !prev.eqGains.contentEquals(f.eqGains) || prev.eqOn != f.eqOn) {
            for (i in 0 until 8) {
                val g = if (f.eqOn) f.eqGains[i].toDouble().coerceIn(-15.0, 15.0) else 0.0
                eqActive[i] = abs(g) > 0.05
                val hz = VocalFx.EQ_HZ[i].toDouble()
                when (i) {
                    0 -> eq[i].lowShelf(sr, hz, g)
                    7 -> eq[i].highShelf(sr, hz, g)
                    else -> eq[i].peaking(sr, hz, g, 1.1)
                }
            }
        }
        if (prev == null || prev.deEssHz != f.deEssHz) {
            val fc = f.deEssHz.toDouble().coerceIn(3000.0, 10000.0) * 0.85
            sibHp1.highpass(sr, fc); sibHp2.highpass(sr, fc)
            sibLp1.lowpass(sr, fc); sibLp2.lowpass(sr, fc)
            sibDetect.highpass(sr, fc, 1.0)
        }
        denoiser.amount = f.denoise.toDouble().coerceIn(0.0, 1.0)
        reverb.size = f.reverbSize.toDouble().coerceIn(0.0, 1.0)
        reverb.damp = f.reverbDamp.toDouble().coerceIn(0.0, 1.0)
        reverb.preMs = f.reverbPreMs.toDouble().coerceIn(0.0, 150.0)
        applied = f
    }

    fun process(buf: FloatArray, off: Int, n: Int) {
        val f = fx
        if (f !== applied) refresh(f)

        val inGain = dbToLin(f.inputGainDb.toDouble())
        val outGain = dbToLin(f.outputGainDb.toDouble())
        val ceil = dbToLin(f.limiterCeilingDb.toDouble().coerceIn(-12.0, 0.0))
        val gateThr = dbToLin(f.gateThresholdDb.toDouble())
        val gateAtk = timeCoef(2.0, sr)
        val gateRel = timeCoef(f.gateReleaseMs.toDouble().coerceIn(20.0, 600.0), sr)
        val envCoef = timeCoef(12.0, sr)
        val gateHoldN = (0.08 * sr).toInt()
        val gateFloor = dbToLin(-f.gateDepthDb.toDouble().coerceIn(6.0, 60.0))

        val sibAmt = f.deEss.toDouble().coerceIn(0.0, 1.0)
        val sibAtk = timeCoef(0.5, sr)
        val sibRel = timeCoef(45.0, sr)
        val sibRatioThr = 0.54 - 0.26 * sibAmt
        val sibMinGain = dbToLin(-(8.0 + 14.0 * sibAmt))
        val bodyRel = timeCoef(30.0, sr)

        val compAtk = timeCoef(f.compAttackMs.toDouble(), sr)
        val compRel = timeCoef(f.compReleaseMs.toDouble(), sr)
        val thr = f.compThresholdDb.toDouble()
        val ratio = max(1.0, f.compRatio.toDouble())
        val knee = 6.0
        val makeup = dbToLin(f.compMakeupDb.toDouble())
        val warm = f.warmth.toDouble().coerceIn(0.0, 1.0)
        val exAmt = f.exciter.toDouble().coerceIn(0.0, 1.0)
        val exDrive = 1.8 + 2.4 * exAmt
        val exRel = timeCoef(180.0, sr)
        val satDrive = 1.0 + 4.0 * warm
        val rvMix = f.reverbMix.toDouble().coerceIn(0.0, 1.0)
        val limRel = timeCoef(90.0, sr)
        val limAtk = 0.2
        val wetTarget = if (f.bypass) 0.0 else 1.0
        val wetStep = 1.0 / (0.008 * sr)

        var inPk = 0.0; var inSq = 0.0; var outPk = 0.0; var outSq = 0.0
        var grMax = 0.0; var sibMax = 0.0; var gateOpenAcc = 0.0
        var clipped = false

        for (i in off until off + n) {
            val dry = buf[i].toDouble() * inGain
            val a0 = abs(dry)
            if (a0 > inPk) inPk = a0
            inSq += dry * dry

            var x = hpf2.process(hpf1.process(dry))
            x = denoiser.process(x)

            if (f.gateOn) {
                val a = abs(x)
                gateEnv = if (a > gateEnv) a else gateEnv * envCoef + a * (1 - envCoef)
                if (gateEnv > gateThr) {
                    gateHold = gateHoldN
                }
                val target = if (gateHold > 0) 1.0 else gateFloor
                if (gateHold > 0) gateHold--
                val c = if (target > gateGain) gateAtk else gateRel
                gateGain = c * gateGain + (1 - c) * target
                x *= gateGain
            } else gateGain = 1.0
            gateOpenAcc += if (gateGain > 0.5) 1.0 else 0.0

            for (b in 0 until 8) if (eqActive[b]) x = eq[b].process(x)

            if (f.compOn) {
                val lvl = linToDb(abs(x))
                val over = lvl - thr
                val outDb = when {
                    over <= -knee / 2 -> lvl
                    over >= knee / 2 -> thr + over / ratio
                    else -> lvl + (1 / ratio - 1) * (over + knee / 2) * (over + knee / 2) / (2 * knee)
                }
                val targetGr = max(0.0, lvl - outDb)
                val c = if (targetGr > compGrDb) compAtk else compRel
                compGrDb = c * compGrDb + (1 - c) * targetGr
                x *= dbToLin(-compGrDb) * makeup
                if (compGrDb > grMax) grMax = compGrDb
            } else compGrDb = 0.0

            val axBody = abs(x)
            bodyEnv = if (axBody > bodyEnv) bodyEnv * 0.99 + axBody * 0.01 else bodyEnv * bodyRel + axBody * (1 - bodyRel)

            // De-esser tames sibilance ('sshhh' / 'sss') and provides sibGain to suppress exciter on sibilants
            if (f.deEssOn && sibAmt > 0.01) {
                val hi = sibHp2.process(sibHp1.process(x))
                val lo = sibLp2.process(sibLp1.process(x))
                val det = abs(sibDetect.process(x))
                sibEnv = if (det > sibEnv) sibAtk * sibEnv + (1 - sibAtk) * det else sibRel * sibEnv + (1 - sibRel) * det
                var target = 1.0
                if (bodyEnv > 1e-4) {
                    val ratioSib = sibEnv / bodyEnv
                    if (ratioSib > sibRatioThr) target = (sibRatioThr / ratioSib).coerceIn(sibMinGain, 1.0)
                }
                val c = if (target < sibGain) sibAtk else sibRel
                sibGain = c * sibGain + (1 - c) * target
                x = lo + hi * sibGain
                val grDb = -linToDb(sibGain)
                if (grDb > sibMax) sibMax = grDb
            } else sibGain = 1.0

            // Speech-gated, de-ess-ducked harmonic presence (band-limited 5.2 - 10.5 kHz, never boosts noise or sibilance)
            if (exAmt > 0.01 && bodyEnv > 0.012) {
                val band = exHp2.process(exHp1.process(x))
                val ab = abs(band)
                exRef = if (ab > exRef) exRef * 0.9 + ab * 0.1 else exRef * exRel + ab * (1 - exRel)
                val ref = max(exRef, bodyEnv * 0.14).coerceAtLeast(0.008)
                val harm = exOut2.process(exOut1.process(Math.tanh(band / ref * exDrive) * ref))
                x += harm * exAmt * 0.65 * (sibGain * sibGain)
            }

            // Analog-style warmth: gentle tanh saturation (unity gain for small signals).
            if (warm > 0.001) x = Math.tanh(x * satDrive) / satDrive

            // Band-limited (240 Hz - 3.2 kHz) plate reverb send so sibilants never ring as 'sshhh' in the tail
            if (rvMix > 0.001) {
                val revSend = revLp.process(revHp.process(x))
                x += reverb.process(revSend) * rvMix * 0.5
            } else {
                reverb.process(0.0)
            }

            x *= outGain

            // Lookahead limiter
            val ax = abs(x)
            val want = if (ax > ceil) ceil / ax else 1.0
            limGain = if (want < limGain) limGain + (want - limGain) * limAtk else limRel * limGain + (1 - limRel)
            val delayed = limDelay[limPos]
            limDelay[limPos] = x
            limPos = (limPos + 1) % look
            var y = delayed * limGain
            if (abs(y) > ceil) y = if (y > 0) ceil else -ceil
            if (limGain < 0.9 || a0 >= 0.995) clipped = true

            // latency-matched dry for A/B
            val d = dryDelay[dryPos]
            dryDelay[dryPos] = dry
            dryPos = (dryPos + 1) % latency
            wet += (wetTarget - wet).coerceIn(-wetStep, wetStep)
            val out = if (wet >= 0.9999) y else d * (1 - wet) + y * wet

            val ao = abs(out)
            if (ao > outPk) outPk = ao
            outSq += out * out
            buf[i] = out.toFloat()
        }

        val nn = max(1, n).toDouble()
        meters.inPeak = inPk.toFloat()
        meters.inRms = sqrt(inSq / nn).toFloat()
        meters.outPeak = outPk.toFloat()
        meters.outRms = sqrt(outSq / nn).toFloat()
        meters.compGrDb = grMax.toFloat()
        meters.deEssGrDb = sibMax.toFloat()
        meters.gateOpen = (gateOpenAcc / nn).toFloat()
        if (clipped) meters.clipped = true
    }
}
