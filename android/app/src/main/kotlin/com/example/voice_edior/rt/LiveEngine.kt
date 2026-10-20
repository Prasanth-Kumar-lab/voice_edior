package com.example.voice_edior.rt

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.os.Process
import com.example.voice_edior.dsp.VocalChain
import com.example.voice_edior.dsp.VocalFx
import java.io.File

/**
 * Live vocal engine: mic → [VocalChain] → (optional) low-latency monitor out, while writing both the
 * untouched take (master) and the processed take to disk. Runs on a dedicated audio-priority thread.
 */
class LiveEngine(private val ctx: Context, private val dir: File) {
    companion object { const val SR = 48000; const val BLOCK = 240 }

    class Result(val rawPath: String, val processedPath: String, val durationMs: Int)

    private val chain = VocalChain(SR)
    val meters get() = chain.meters
    @Volatile var recording = false; private set
    @Volatile var paused = false
    @Volatile var monitoring = false
    @Volatile var monitorWanted = false
    @Volatile var elapsedMs = 0L; private set
    val active: Boolean get() = run
    @Volatile var error: String? = null; private set
    val latencyMs: Float get() = chain.latencySamples * 1000f / SR

    private var thread: Thread? = null
    @Volatile private var run = false
    @Volatile private var capture = false
    private var raw: WavFile.Writer? = null
    private var proc: WavFile.Writer? = null

    /** Latest peak bars (processed), drained by the UI timer. */
    private val barLock = Any()
    private var barPeak = 0f

    fun setFx(fx: VocalFx) = chain.setFx(fx)

    fun drainBar(): Float = synchronized(barLock) { val v = barPeak; barPeak = 0f; v }

    /** Opens the mic and starts metering/monitoring (not yet writing a take). */
    @SuppressLint("MissingPermission")
    fun arm(): Boolean {
        if (run) return true
        error = null
        run = true
        thread = Thread({ loop() }, "vp-live").also { it.start() }
        return true
    }

    fun startTake() {
        if (!run) arm()
        val stamp = System.currentTimeMillis()
        raw = WavFile.Writer(File(dir, "live-$stamp-raw.wav").path, SR)
        proc = WavFile.Writer(File(dir, "live-$stamp-fx.wav").path, SR)
        elapsedMs = 0
        paused = false
        capture = true
        recording = true
    }

    fun stopTake(): Result? {
        capture = false
        recording = false
        val r = raw; val p = proc
        raw = null; proc = null
        if (r == null || p == null) return null
        val ms = (r.frames * 1000 / SR).toInt()
        r.close(); p.close()
        return Result(r.path, p.path, ms)
    }

    fun disarm() {
        if (recording) stopTake()
        run = false
        thread?.join(800)
        thread = null
    }

    fun headphonesConnected(): Boolean {
        val am = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        return am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any {
            when (it.type) {
                android.media.AudioDeviceInfo.TYPE_WIRED_HEADSET,
                android.media.AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                android.media.AudioDeviceInfo.TYPE_USB_HEADSET,
                android.media.AudioDeviceInfo.TYPE_USB_DEVICE,
                android.media.AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                android.media.AudioDeviceInfo.TYPE_BLE_HEADSET,
                android.media.AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> true
                else -> false
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun loop() {
        Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
        val minIn = AudioRecord.getMinBufferSize(SR, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        var rec: AudioRecord? = null
        for (src in intArrayOf(MediaRecorder.AudioSource.UNPROCESSED, MediaRecorder.AudioSource.MIC)) {
            try {
                val r = AudioRecord(src, SR, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, maxOf(minIn, BLOCK * 8))
                if (r.state == AudioRecord.STATE_INITIALIZED) { rec = r; break } else r.release()
            } catch (_: Throwable) {}
        }
        if (rec == null) { error = "Could not open the microphone"; run = false; return }

        var track: AudioTrack? = null
        val pcm = ShortArray(BLOCK)
        val f = FloatArray(BLOCK)
        val raws = FloatArray(BLOCK)
        val outS = ShortArray(BLOCK)
        try {
            rec.startRecording()
            while (run) {
                val n = rec.read(pcm, 0, BLOCK)
                if (n <= 0) continue
                for (i in 0 until n) { f[i] = pcm[i] / 32768f; raws[i] = f[i] }
                chain.process(f, 0, n)

                var pk = 0f
                for (i in 0 until n) pk = maxOf(pk, kotlin.math.abs(f[i]))
                synchronized(barLock) { if (pk > barPeak) barPeak = pk }

                if (capture && !paused) {
                    raw?.write(raws, 0, n)
                    proc?.write(f, 0, n)
                    elapsedMs = (raw?.frames ?: 0) * 1000 / SR
                }

                val wantMon = monitorWanted && headphonesConnected()
                if (wantMon && track == null) track = openTrack()
                if (!wantMon && track != null) { track.pause(); track.flush(); track.release(); track = null }
                monitoring = track != null
                track?.let {
                    for (i in 0 until n) outS[i] = (f[i].coerceIn(-1f, 1f) * 32767f).toInt().toShort()
                    it.write(outS, 0, n)
                }
            }
        } catch (t: Throwable) {
            error = t.message ?: "Audio engine error"
        } finally {
            try { rec.stop() } catch (_: Throwable) {}
            rec.release()
            track?.release()
            monitoring = false
            chain.reset()
        }
    }

    private fun openTrack(): AudioTrack? = try {
        val min = AudioTrack.getMinBufferSize(SR, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
        AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
            .setAudioFormat(AudioFormat.Builder().setSampleRate(SR).setEncoding(AudioFormat.ENCODING_PCM_16BIT).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
            .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .setBufferSizeInBytes(maxOf(min, BLOCK * 2 * 2))
            .build().also { it.play() }
    } catch (_: Throwable) { null }
}
