package com.example.voice_edior.rt

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Process
import com.example.voice_edior.dsp.VocalChain
import com.example.voice_edior.dsp.VocalFx
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/** Plays a take through the live [VocalChain] so every knob is audible instantly, with seamless A/B. */
class FilePlayer {
    private var clip: PcmClip? = null
    private var chain: VocalChain? = null
    @Volatile private var fx = VocalFx()
    @Volatile var playing = false; private set
    @Volatile var positionFrames = 0; private set
    @Volatile var loopStart = -1
    @Volatile var loopEnd = -1
    @Volatile var ended = false
    private var thread: Thread? = null
    @Volatile private var alive = false
    private val lock = ReentrantLock()
    private val wake = lock.newCondition()

    val meters get() = chain?.meters
    val sampleRate get() = clip?.sampleRate ?: 0
    val durationMs get() = clip?.let { (it.samples.size * 1000L / it.sampleRate).toInt() } ?: 0
    val positionMs get() = clip?.let { (positionFrames * 1000L / it.sampleRate).toInt() } ?: 0

    fun load(path: String): Int {
        release()
        val c = WavFile.read(path)
        clip = c
        chain = VocalChain(c.sampleRate).also { it.setFx(fx) }
        positionFrames = 0
        ended = false
        alive = true
        thread = Thread({ loop() }, "vp-player").also { it.start() }
        return durationMs
    }

    fun setFx(next: VocalFx) { fx = next; chain?.setFx(next) }

    fun play() {
        val c = clip ?: return
        lock.withLock {
            if (positionFrames >= c.samples.size - 1) positionFrames = 0
            ended = false
            playing = true
            wake.signalAll()
        }
    }

    fun pause() {
        lock.withLock { playing = false }
    }

    fun seekMs(ms: Int) {
        val c = clip ?: return
        positionFrames = (ms.toLong() * c.sampleRate / 1000).toInt().coerceIn(0, c.samples.size)
    }

    fun release() {
        alive = false
        lock.withLock { playing = false; wake.signalAll() }
        thread?.join(600)
        thread = null
        clip = null
        chain = null
    }

    private fun loop() {
        Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
        val c = clip ?: return
        val ch = chain ?: return
        val sr = c.sampleRate
        val block = 480
        val min = AudioTrack.getMinBufferSize(sr, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val track = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
            .setAudioFormat(AudioFormat.Builder().setSampleRate(sr).setEncoding(AudioFormat.ENCODING_PCM_16BIT).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
            .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .setBufferSizeInBytes(maxOf(min, block * 4))
            .build()
        val f = FloatArray(block)
        val s = ShortArray(block)
        var started = false
        var tail = 0
        try {
            while (alive) {
                lock.withLock { while (alive && !playing) { if (started) { track.pause(); started = false }; wake.await() } }
                if (!alive) break
                if (!started) { track.play(); started = true }

                var pos = positionFrames
                val total = c.samples.size
                val ls = loopStart; val le = loopEnd
                val end = if (ls >= 0 && le > ls) minOf(le, total) else total
                var n = minOf(block, end - pos)
                if (n <= 0) {
                    if (ls >= 0 && le > ls) { positionFrames = ls; continue }
                    // flush the chain tail, then stop
                    if (tail < ch.latencySamples) {
                        java.util.Arrays.fill(f, 0f)
                        ch.process(f, 0, block)
                        tail += block
                        for (i in 0 until block) s[i] = (f[i].coerceIn(-1f, 1f) * 32767f).toInt().toShort()
                        track.write(s, 0, block)
                        continue
                    }
                    tail = 0
                    playing = false; ended = true; positionFrames = 0
                    track.pause(); track.flush(); started = false
                    continue
                }
                tail = 0
                System.arraycopy(c.samples, pos, f, 0, n)
                ch.process(f, 0, n)
                for (i in 0 until n) s[i] = (f[i].coerceIn(-1f, 1f) * 32767f).toInt().toShort()
                track.write(s, 0, n)
                // seek may have happened during the blocking write; only advance if we weren't moved.
                if (positionFrames == pos) positionFrames = pos + n
            }
        } finally {
            try { track.stop() } catch (_: Throwable) {}
            track.release()
        }
    }

    companion object {
        /** Offline render with the exact same DSP — what you hear is what you export. */
        fun render(inPath: String, outPath: String, fx: VocalFx, startMs: Int, endMs: Int): Int {
            val c = WavFile.read(inPath)
            val sr = c.sampleRate
            val a = (startMs.toLong() * sr / 1000).toInt().coerceIn(0, c.samples.size)
            val b = (if (endMs <= 0) c.samples.size else (endMs.toLong() * sr / 1000).toInt()).coerceIn(a, c.samples.size)
            val chain = VocalChain(sr).also { it.setFx(fx) }
            val lat = chain.latencySamples
            val buf = FloatArray(4096)
            var skip = lat
            var fed = 0
            val tail = if (fx.reverbMix > 0.01f) (sr * 1.8).toInt() else 0 // let the reverb ring out
            val total = (b - a) + lat + tail
            WavFile.Writer(outPath, sr).use { w ->
                while (fed < total) {
                    val n = minOf(buf.size, total - fed)
                    for (i in 0 until n) { val idx = a + fed + i; buf[i] = if (idx < b) c.samples[idx] else 0f }
                    chain.process(buf, 0, n)
                    val from = minOf(skip, n)
                    skip -= from
                    if (n - from > 0) w.write(buf, from, n - from)
                    fed += n
                }
                return (w.frames * 1000 / sr).toInt()
            }
        }
    }
}
