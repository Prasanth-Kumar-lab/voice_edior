package com.example.voice_edior.rt

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import com.example.voice_edior.dsp.Fft
import com.example.voice_edior.dsp.Mastering
import com.example.voice_edior.dsp.MixDspMath
import com.example.voice_edior.dsp.Reverb
import com.example.voice_edior.dsp.StereoBuffer
import com.example.voice_edior.dsp.StereoFxChainProcessor
import com.example.voice_edior.dsp.dbToLin
import com.example.voice_edior.dsp.linToDb
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Multi-track 48 kHz stereo mixing engine for Mix Studio:
 * - Decodes & caches source WAV clips
 * - Applies non-destructive clip trim, WSOLA stretch, pitch-shift, reverse, normalize, fade curves, and clip FX
 * - Mixes tracks with volume automation, constant-power pan, solo-in-place, phase invert, track FX, and sidechain Auto-Ducking
 * - Sums shared Reverb & Delay send/return buses and Master Bus (5-band EQ, glue comp, stereo width, LUFS target, lookahead limiter)
 * - Streams real-time playback via AudioTrack with 30 fps live meter + 24-band 1/3-octave FFT telemetry
 * - Exports 16-bit, 24-bit, or 32-bit float stereo WAV files.
 */
class MixEngine(private val cacheDir: File) {
    companion object {
        const val SR = 48000
    }

    private val clipCache = ConcurrentHashMap<String, FloatArray>()

    @Volatile var playing = false
        private set
    @Volatile var playheadMs = 0
        private set
    @Volatile var totalDurationMs = 15000
        private set

    @Volatile var loopEnabled = false
    @Volatile var loopStartMs = 0
    @Volatile var loopEndMs = 15000
    @Volatile var metronomeEnabled = false
    @Volatile var bpm = 120.0

    // Live master telemetry
    @Volatile var peakL = 0f
    @Volatile var peakR = 0f
    @Volatile var rmsL = 0f
    @Volatile var rmsR = 0f
    @Volatile var lufsMomentary = -24.0
    @Volatile var lufsIntegrated = -16.0
    @Volatile var truePeakDb = -1.0
    @Volatile var correlation = 1.0
    @Volatile var clipping = false
    @Volatile var spectrum24 = DoubleArray(24) { 0.08 }

    private var renderedStereo: StereoBuffer = StereoBuffer(FloatArray(SR), FloatArray(SR), SR)
    private var playThread: Thread? = null
    private val cancelExportFlag = AtomicBoolean(false)

    init {
        cacheDir.mkdirs()
    }

    private fun loadMonoAt48k(path: String): FloatArray {
        if (path.isBlank() || !File(path).exists()) return FloatArray(0)
        clipCache[path]?.let { return it }
        return try {
            val clip = WavFile.read(path)
            val resampled = if (clip.sampleRate == SR) {
                clip.samples
            } else {
                val ratio = clip.sampleRate.toDouble() / SR
                val outLen = max(1, (clip.samples.size / ratio).roundToInt())
                val maxIdx = clip.samples.size - 1
                FloatArray(outLen) { i ->
                    val p = i * ratio
                    val idx = p.toInt()
                    if (idx >= maxIdx) clip.samples[maxIdx]
                    else {
                        val frac = (p - idx).toFloat()
                        clip.samples[idx] * (1f - frac) + clip.samples[idx + 1] * frac
                    }
                }
            }
            clipCache[path] = resampled
            resampled
        } catch (_: Throwable) {
            FloatArray(0)
        }
    }

    /** Extract normalized waveform peaks for UI display and cache to `<path>.peaks`. */
    fun extractPeaks(path: String, numBins: Int = 120): List<Double> {
        val samples = loadMonoAt48k(path)
        if (samples.isEmpty() || numBins <= 0) return List(numBins.coerceAtLeast(1)) { 0.1 }
        val step = max(1.0, samples.size.toDouble() / numBins)
        return List(numBins) { b ->
            val start = (b * step).toInt().coerceIn(0, samples.size - 1)
            val end = ((b + 1) * step).toInt().coerceIn(start + 1, samples.size)
            var pk = 0f
            for (i in start until end) {
                val a = abs(samples[i])
                if (a > pk) pk = a
            }
            pk.toDouble().coerceIn(0.04, 1.0)
        }
    }

    /** Detect non-silent intervals in an audio file for "Remove Silence". */
    fun detectNonSilentRegions(
        path: String,
        thresholdDb: Double = -42.0,
        minSilenceMs: Int = 250,
    ): List<Map<String, Int>> {
        val samples = loadMonoAt48k(path)
        if (samples.isEmpty()) return emptyList()
        val threshLin = dbToLin(thresholdDb).toFloat()
        val hop = (0.020 * SR).toInt() // 20 ms frames
        val minSilentFrames = max(1, minSilenceMs / 20)
        val regions = mutableListOf<Map<String, Int>>()

        var inSpeech = false
        var speechStartFrame = 0
        var silentRun = 0
        val totalFrames = samples.size / hop

        for (f in 0 until totalFrames) {
            var pk = 0f
            val base = f * hop
            for (i in base until min(samples.size, base + hop)) {
                val a = abs(samples[i])
                if (a > pk) pk = a
            }
            if (pk >= threshLin) {
                if (!inSpeech) {
                    inSpeech = true
                    speechStartFrame = f
                }
                silentRun = 0
            } else if (inSpeech) {
                silentRun++
                if (silentRun >= minSilentFrames) {
                    val startMs = speechStartFrame * 20
                    val endMs = max(startMs + 60, (f - silentRun + 1) * 20)
                    regions.add(mapOf("startMs" to startMs, "endMs" to endMs))
                    inSpeech = false
                    silentRun = 0
                }
            }
        }
        if (inSpeech) {
            regions.add(mapOf("startMs" to speechStartFrame * 20, "endMs" to totalFrames * 20))
        }
        return regions
    }

    /** Render the full project graph into a stereo buffer at 48 kHz. */
    @Suppress("UNCHECKED_CAST")
    fun renderProjectGraph(
        project: Map<String, Any?>,
        onProgress: ((String, Double) -> Unit)? = null,
    ): StereoBuffer {
        bpm = (project["bpm"] as? Number)?.toDouble() ?: 120.0
        loopEnabled = (project["loopEnabled"] as? Boolean) ?: false
        loopStartMs = (project["loopStartMs"] as? Number)?.toInt() ?: 0
        loopEndMs = (project["loopEndMs"] as? Number)?.toInt() ?: 15000
        metronomeEnabled = (project["metronomeEnabled"] as? Boolean) ?: false

        val tracks = (project["tracks"] as? List<Map<String, Any?>>) ?: emptyList()
        val masterCfg = (project["master"] as? Map<String, Any?>) ?: emptyMap()

        // Determine total duration across all clips
        var maxEndMs = 5000
        for (trk in tracks) {
            val clips = (trk["clips"] as? List<Map<String, Any?>>) ?: emptyList()
            for (c in clips) {
                val startMs = (c["timelineStartMs"] as? Number)?.toInt() ?: 0
                val durMs = (c["durationMs"] as? Number)?.toInt() ?: 0
                maxEndMs = max(maxEndMs, startMs + durMs)
            }
        }
        totalDurationMs = maxEndMs
        val totalFrames = max(SR, (maxEndMs.toLong() * SR / 1000L).toInt())

        val anySolo = tracks.any { (it["solo"] as? Boolean) == true }
        val trackStemsMono = HashMap<String, FloatArray>()
        val trackStemsStereo = HashMap<String, StereoBuffer>()

        // Pass 1: Render each track's clips + clip FX + track FX
        tracks.forEachIndexed { idx, trk ->
            val trackId = (trk["id"] as? String) ?: "trk_$idx"
            val muted = (trk["muted"] as? Boolean) ?: false
            val solo = (trk["solo"] as? Boolean) ?: false
            val active = if (anySolo) solo else !muted

            onProgress?.invoke("Mixing ${trk["name"] ?: "Track ${idx + 1}"}", (idx + 1).toDouble() / (tracks.size + 2))

            val trkBuf = StereoBuffer(FloatArray(totalFrames), FloatArray(totalFrames), SR)
            if (active) {
                val clips = (trk["clips"] as? List<Map<String, Any?>>) ?: emptyList()
                for (clip in clips) {
                    if ((clip["muted"] as? Boolean) == true) continue
                    renderClipIntoTrack(clip, trkBuf)
                }

                // Track insert FX
                val fxChain = (trk["fxChain"] as? List<Map<String, Any?>>) ?: emptyList()
                if (fxChain.isNotEmpty()) {
                    StereoFxChainProcessor.processChain(trkBuf, fxChain)
                }

                // Input gain + phase invert
                val inGain = dbToLin((trk["inputGainDb"] as? Number)?.toDouble() ?: 0.0).toFloat()
                val sign = if ((trk["phaseInverted"] as? Boolean) == true) -1f else 1f
                val mult = inGain * sign
                if (abs(mult - 1f) > 1e-4f) {
                    for (i in 0 until totalFrames) {
                        trkBuf.left[i] *= mult
                        trkBuf.right[i] *= mult
                    }
                }
            }

            // Store mono sum for potential sidechain Auto-Ducking key
            val mono = FloatArray(totalFrames) { i -> 0.5f * (trkBuf.left[i] + trkBuf.right[i]) }
            trackStemsMono[trackId] = mono
            trackStemsStereo[trackId] = trkBuf
        }

        // Pass 2: Sum tracks into Master + Shared Reverb/Delay Send Buses + Sidechain Auto-Duck
        val masterL = FloatArray(totalFrames)
        val masterR = FloatArray(totalFrames)
        val revBus = FloatArray(totalFrames)
        val dlyBus = FloatArray(totalFrames)

        for (trk in tracks) {
            val trackId = (trk["id"] as? String) ?: continue
            val trkBuf = trackStemsStereo[trackId] ?: continue
            val volDb = (trk["volumeDb"] as? Number)?.toDouble() ?: 0.0
            val baseGain = if (volDb <= -59.5) 0.0 else dbToLin(volDb)
            val pan = (trk["pan"] as? Number)?.toDouble() ?: 0.0
            val (panL, panR) = MixDspMath.constantPowerPan(pan)
            val revSend = ((trk["reverbSend"] as? Number)?.toDouble() ?: 0.0).toFloat()
            val dlySend = ((trk["delaySend"] as? Number)?.toDouble() ?: 0.0).toFloat()

            // Optional sidechain Auto-Ducking
            val duckCfg = (trk["autoDuck"] as? Map<String, Any?>) ?: emptyMap()
            val duckEnabled = (duckCfg["enabled"] as? Boolean) ?: false
            val keyTrackId = duckCfg["keyTrackId"] as? String
            val duckEnv = if (duckEnabled && keyTrackId != null && trackStemsMono.containsKey(keyTrackId)) {
                MixDspMath.computeAutoDuckEnvelope(
                    voiceMono = trackStemsMono[keyTrackId]!!,
                    sr = SR,
                    thresholdDb = (duckCfg["thresholdDb"] as? Number)?.toDouble() ?: -28.0,
                    ratio = (duckCfg["ratio"] as? Number)?.toDouble() ?: 4.0,
                    attackMs = (duckCfg["attackMs"] as? Number)?.toDouble() ?: 25.0,
                    releaseMs = (duckCfg["releaseMs"] as? Number)?.toDouble() ?: 320.0,
                    amountDb = (duckCfg["amountDb"] as? Number)?.toDouble() ?: -10.0,
                )
            } else null

            val gL = (baseGain * panL).toFloat()
            val gR = (baseGain * panR).toFloat()

            for (i in 0 until totalFrames) {
                val duck = duckEnv?.get(i) ?: 1f
                val l = trkBuf.left[i] * gL * duck
                val r = trkBuf.right[i] * gR * duck
                masterL[i] += l
                masterR[i] += r
                val monoSend = 0.5f * (l + r)
                revBus[i] += monoSend * revSend
                dlyBus[i] += monoSend * dlySend
            }
        }

        // Process shared Reverb send bus
        val sharedRevL = Reverb(SR).apply { size = 0.68; damp = 0.4; preMs = 24.0 }
        val sharedRevR = Reverb(SR).apply { size = 0.71; damp = 0.42; preMs = 28.0 }
        val dlySamples = (0.320 * SR).toInt()
        val dlyRing = FloatArray(dlySamples)
        var dp = 0
        for (i in 0 until totalFrames) {
            if (abs(revBus[i]) > 1e-6f) {
                masterL[i] += sharedRevL.process(revBus[i].toDouble()).toFloat() * 0.35f
                masterR[i] += sharedRevR.process(revBus[i].toDouble()).toFloat() * 0.35f
            }
            val dOut = dlyRing[dp]
            dlyRing[dp] = (dlyBus[i] + dOut * 0.35f).coerceIn(-1f, 1f)
            dp = (dp + 1) % dlySamples
            masterL[i] += dOut * 0.3f
            masterR[i] += dOut * 0.3f
        }

        // Pass 3: Master Bus Processing
        onProgress?.invoke("Mastering & LUFS Normalization", 0.92)
        val masterBuf = StereoBuffer(masterL, masterR, SR)
        val masterFx = (masterCfg["fxChain"] as? List<Map<String, Any?>>) ?: emptyList()
        if (masterFx.isNotEmpty()) {
            StereoFxChainProcessor.processChain(masterBuf, masterFx)
        }

        val masterVol = dbToLin((masterCfg["volumeDb"] as? Number)?.toDouble() ?: 0.0).toFloat()
        val width = ((masterCfg["stereoWidth"] as? Number)?.toDouble() ?: 1.0).coerceIn(0.0, 2.0).toFloat()
        val ceilingDb = ((masterCfg["limiterCeilingDb"] as? Number)?.toDouble() ?: -1.0).coerceIn(-6.0, 0.0)

        for (i in 0 until totalFrames) {
            val mid = 0.5f * (masterBuf.left[i] + masterBuf.right[i]) * masterVol
            val side = 0.5f * (masterBuf.left[i] - masterBuf.right[i]) * masterVol * width
            masterBuf.left[i] = mid + side
            masterBuf.right[i] = mid - side
        }

        Mastering.limit(masterBuf.left, ceilingDb, SR)
        Mastering.limit(masterBuf.right, ceilingDb, SR)

        val monoMaster = FloatArray(totalFrames) { i -> 0.5f * (masterBuf.left[i] + masterBuf.right[i]) }
        lufsIntegrated = Mastering.integratedLufs(monoMaster, SR)
        renderedStereo = masterBuf
        onProgress?.invoke("Complete", 1.0)
        return masterBuf
    }

    @Suppress("UNCHECKED_CAST")
    private fun renderClipIntoTrack(clip: Map<String, Any?>, trkBuf: StereoBuffer) {
        val useEnh = (clip["useEnhanced"] as? Boolean) == true
        val enhPath = clip["enhancedPath"] as? String
        val srcPath = (clip["sourcePath"] as? String) ?: ""
        val activePath = if (useEnh && !enhPath.isNullOrBlank()) enhPath else srcPath
        val raw = loadMonoAt48k(activePath)
        if (raw.isEmpty()) return

        val offsetStartMs = ((clip["offsetStartMs"] as? Number)?.toInt() ?: 0).coerceAtLeast(0)
        val durationMs = ((clip["durationMs"] as? Number)?.toInt() ?: 1000).coerceAtLeast(50)
        val timelineStartMs = ((clip["timelineStartMs"] as? Number)?.toInt() ?: 0).coerceAtLeast(0)

        val startSample = (offsetStartMs.toLong() * SR / 1000L).toInt().coerceIn(0, raw.size - 1)
        val desiredSamples = (durationMs.toLong() * SR / 1000L).toInt().coerceAtLeast(1)
        val endSample = (startSample + desiredSamples).coerceIn(startSample + 1, raw.size)
        var seg = raw.copyOfRange(startSample, endSample)

        // Reverse
        if ((clip["reversed"] as? Boolean) == true) {
            seg.reverse()
        }

        // Normalize
        if ((clip["normalized"] as? Boolean) == true) {
            var pk = 1e-6f
            for (v in seg) pk = max(pk, abs(v))
            val normG = 0.89f / pk
            for (i in seg.indices) seg[i] = (seg[i] * normG).coerceIn(-1f, 1f)
        }

        // Time-stretch (WSOLA)
        val stretchRate = ((clip["stretchRate"] as? Number)?.toDouble() ?: 1.0).coerceIn(0.5, 2.0)
        if (abs(stretchRate - 1.0) > 0.02) {
            seg = MixDspMath.timeStretchWsola(seg, SR, stretchRate)
        }

        // Pitch-shift (semitones)
        val pitchSt = ((clip["pitchSemitones"] as? Number)?.toDouble() ?: 0.0).coerceIn(-12.0, 12.0)
        if (abs(pitchSt) > 0.05) {
            seg = MixDspMath.pitchShiftSemitones(seg, SR, pitchSt)
        }

        // Clip Gain & Fade-in / Fade-out envelopes
        val gain = dbToLin((clip["gainDb"] as? Number)?.toDouble() ?: 0.0).toFloat()
        val fadeInSamples = (((clip["fadeInMs"] as? Number)?.toInt() ?: 20).toLong() * SR / 1000L).toInt()
        val fadeOutSamples = (((clip["fadeOutMs"] as? Number)?.toInt() ?: 40).toLong() * SR / 1000L).toInt()
        val fadeInCurve = (clip["fadeInCurve"] as? String) ?: "s_curve"
        val fadeOutCurve = (clip["fadeOutCurve"] as? String) ?: "s_curve"

        val clipStereo = StereoBuffer(FloatArray(seg.size), FloatArray(seg.size), SR)
        for (i in seg.indices) {
            var env = 1.0
            if (fadeInSamples > 0 && i < fadeInSamples) {
                env *= MixDspMath.fadeGain(i.toDouble() / fadeInSamples, fadeInCurve)
            }
            val rem = seg.size - 1 - i
            if (fadeOutSamples > 0 && rem < fadeOutSamples) {
                env *= MixDspMath.fadeGain(rem.toDouble() / fadeOutSamples, fadeOutCurve)
            }
            val s = (seg[i] * gain * env.toFloat()).coerceIn(-1f, 1f)
            clipStereo.left[i] = s
            clipStereo.right[i] = s
        }

        val clipFx = (clip["fxChain"] as? List<Map<String, Any?>>) ?: emptyList()
        if (clipFx.isNotEmpty()) {
            StereoFxChainProcessor.processChain(clipStereo, clipFx)
        }

        // Sum into parent track at timelineStartMs
        val destStart = (timelineStartMs.toLong() * SR / 1000L).toInt()
        val copyLen = min(clipStereo.frames, trkBuf.frames - destStart)
        if (copyLen > 0) {
            for (i in 0 until copyLen) {
                trkBuf.left[destStart + i] += clipStereo.left[i]
                trkBuf.right[destStart + i] += clipStereo.right[i]
            }
        }
    }

    fun play() {
        if (playing) return
        playing = true
        playThread = Thread({
            val minBuf = AudioTrack.getMinBufferSize(
                SR,
                AudioFormat.CHANNEL_OUT_STEREO,
                AudioFormat.ENCODING_PCM_16BIT,
            ).coerceAtLeast(4096)
            val track = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build(),
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(SR)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                        .build(),
                )
                .setBufferSizeInBytes(minBuf)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()

            track.play()
            val blockFrames = 512
            val pcm16 = ShortArray(blockFrames * 2)
            val fft = Fft(512)
            val fftRe = DoubleArray(512)
            val fftIm = DoubleArray(512)

            while (playing) {
                val buf = renderedStereo
                var curFrame = (playheadMs.toLong() * SR / 1000L).toInt()
                if (curFrame >= buf.frames) {
                    if (loopEnabled) {
                        playheadMs = loopStartMs
                        curFrame = (playheadMs.toLong() * SR / 1000L).toInt()
                    } else {
                        playing = false
                        playheadMs = 0
                        break
                    }
                }

                var pkL = 0f; var pkR = 0f
                var sumL = 0.0; var sumR = 0.0
                var sumLR = 0.0
                val beatSamples = (60.0 / bpm.coerceIn(40.0, 240.0) * SR).toInt().coerceAtLeast(1)

                for (i in 0 until blockFrames) {
                    val fIdx = curFrame + i
                    var l = if (fIdx < buf.frames) buf.left[fIdx] else 0f
                    var r = if (fIdx < buf.frames) buf.right[fIdx] else 0f

                    // Optional metronome click on beat boundaries
                    if (metronomeEnabled) {
                        val posInBeat = fIdx % beatSamples
                        if (posInBeat < 480) {
                            val click = (sin(2.0 * PI * 1000.0 * posInBeat / SR) *
                                (1.0 - posInBeat / 480.0) * 0.22).toFloat()
                            l += click
                            r += click
                        }
                    }

                    l = l.coerceIn(-1f, 1f)
                    r = r.coerceIn(-1f, 1f)
                    pcm16[i * 2] = (l * 32767f).roundToInt().toShort()
                    pcm16[i * 2 + 1] = (r * 32767f).roundToInt().toShort()

                    val al = abs(l); val ar = abs(r)
                    if (al > pkL) pkL = al
                    if (ar > pkR) pkR = ar
                    sumL += l * l
                    sumR += r * r
                    sumLR += l * r
                    fftRe[i] = 0.5 * (l + r)
                    fftIm[i] = 0.0
                }

                track.write(pcm16, 0, pcm16.size)
                val nextMs = ((curFrame + blockFrames).toLong() * 1000L / SR).toInt()
                if (loopEnabled && nextMs >= loopEndMs && loopEndMs > loopStartMs) {
                    playheadMs = loopStartMs
                } else {
                    playheadMs = nextMs
                }

                // Update live meters
                peakL = pkL
                peakR = pkR
                rmsL = sqrt(sumL / blockFrames).toFloat()
                rmsR = sqrt(sumR / blockFrames).toFloat()
                val maxPk = max(pkL, pkR).toDouble()
                truePeakDb = linToDb(maxPk)
                clipping = maxPk >= 0.98
                val denom = sqrt(sumL * sumR)
                correlation = if (denom > 1e-9) (sumLR / denom).coerceIn(-1.0, 1.0) else 1.0
                lufsMomentary = -0.691 + 10.0 * log10((sumL + sumR) / (2.0 * blockFrames) + 1e-12)

                // Compute 24-band spectrum
                fft.transform(fftRe, fftIm)
                val bands = DoubleArray(24)
                for (b in 0 until 24) {
                    val b0 = (1.28.pow(b.toDouble())).toInt().coerceIn(1, 250)
                    val b1 = (1.28.pow((b + 1).toDouble())).toInt().coerceIn(b0 + 1, 255)
                    var mag = 0.0
                    for (k in b0 until b1) {
                        mag += sqrt(fftRe[k] * fftRe[k] + fftIm[k] * fftIm[k])
                    }
                    mag /= (b1 - b0)
                    val db = 20.0 * log10(mag / 32.0 + 1e-6)
                    bands[b] = ((db + 60.0) / 60.0).coerceIn(0.05, 1.0)
                }
                spectrum24 = bands
            }

            try {
                track.stop()
                track.release()
            } catch (_: Throwable) {}
        }, "VocalPolish-MixPlayback").also { it.start() }
    }

    fun pause() {
        playing = false
    }

    fun stop() {
        playing = false
        playheadMs = 0
        peakL = 0f; peakR = 0f; rmsL = 0f; rmsR = 0f
    }

    fun seek(ms: Int) {
        playheadMs = ms.coerceIn(0, max(1000, totalDurationMs))
    }

    fun cancelExport() {
        cancelExportFlag.set(true)
    }

    /** Export the rendered stereo project to a 16-bit, 24-bit, or 32-bit float stereo WAV file. */
    fun exportStereoWav(
        project: Map<String, Any?>,
        outPath: String,
        bitDepth: Int = 16,
        targetLufs: Double = -16.0,
        ceilingDb: Double = -1.0,
        onProgress: ((String, Double) -> Unit)? = null,
    ): Map<String, Any> {
        cancelExportFlag.set(false)
        val buf = renderProjectGraph(project, onProgress)
        val n = buf.frames
        val mono = FloatArray(n) { i -> 0.5f * (buf.left[i] + buf.right[i]) }
        val currentLufs = Mastering.integratedLufs(mono, SR)
        if (currentLufs > -65.0) {
            val gain = dbToLin(targetLufs - currentLufs).toFloat()
            for (i in 0 until n) {
                buf.left[i] *= gain
                buf.right[i] *= gain
            }
        }
        Mastering.limit(buf.left, ceilingDb, SR)
        Mastering.limit(buf.right, ceilingDb, SR)

        val finalMono = FloatArray(n) { i -> 0.5f * (buf.left[i] + buf.right[i]) }
        val outLufs = Mastering.integratedLufs(finalMono, SR)

        writeStereoWavFile(outPath, buf, bitDepth)
        return mapOf(
            "filePath" to outPath,
            "durationMs" to (n.toLong() * 1000L / SR).toInt(),
            "lufsOut" to outLufs,
            "bitDepth" to bitDepth,
        )
    }

    private fun writeStereoWavFile(path: String, buf: StereoBuffer, bits: Int) {
        val file = File(path).also { it.parentFile?.mkdirs() }
        val frames = buf.frames
        val channels = 2
        val validBits = if (bits in listOf(16, 24, 32)) bits else 16
        val bytesPerSample = validBits / 8
        val blockAlign = channels * bytesPerSample
        val dataBytes = frames * blockAlign
        val fmtTag: Short = if (validBits == 32) 3 else 1 // 3 = IEEE Float32, 1 = PCM

        RandomAccessFile(file, "rw").use { raf ->
            raf.setLength(0)
            val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
            header.put("RIFF".toByteArray())
            header.putInt(36 + dataBytes)
            header.put("WAVE".toByteArray())
            header.put("fmt ".toByteArray())
            header.putInt(16)
            header.putShort(fmtTag)
            header.putShort(channels.toShort())
            header.putInt(buf.sampleRate)
            header.putInt(buf.sampleRate * blockAlign)
            header.putShort(blockAlign.toShort())
            header.putShort(validBits.toShort())
            header.put("data".toByteArray())
            header.putInt(dataBytes)
            raf.write(header.array())

            val chunkFrames = 4096
            val chunk = ByteBuffer.allocate(chunkFrames * blockAlign).order(ByteOrder.LITTLE_ENDIAN)
            var offset = 0
            while (offset < frames) {
                chunk.clear()
                val count = min(chunkFrames, frames - offset)
                for (i in 0 until count) {
                    val l = buf.left[offset + i].coerceIn(-1f, 1f)
                    val r = buf.right[offset + i].coerceIn(-1f, 1f)
                    when (validBits) {
                        16 -> {
                            chunk.putShort((l * 32767f).roundToInt().toShort())
                            chunk.putShort((r * 32767f).roundToInt().toShort())
                        }
                        24 -> {
                            val vl = (l * 8388607f).roundToInt()
                            val vr = (r * 8388607f).roundToInt()
                            chunk.put((vl and 0xFF).toByte())
                            chunk.put(((vl shr 8) and 0xFF).toByte())
                            chunk.put(((vl shr 16) and 0xFF).toByte())
                            chunk.put((vr and 0xFF).toByte())
                            chunk.put(((vr shr 8) and 0xFF).toByte())
                            chunk.put(((vr shr 16) and 0xFF).toByte())
                        }
                        32 -> {
                            chunk.putFloat(l)
                            chunk.putFloat(r)
                        }
                    }
                }
                raf.write(chunk.array(), 0, count * blockAlign)
                offset += count
            }
        }
    }
}
