package com.example.voice_edior.rt

import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.roundToInt

class PcmClip(val samples: FloatArray, val sampleRate: Int)

object WavFile {
    /** Reads PCM16/24/32 or float32 WAV and returns a mono float clip (channels averaged). */
    fun read(path: String): PcmClip {
        RandomAccessFile(path, "r").use { f ->
            val head = ByteArray(12)
            f.readFully(head)
            require(String(head, 0, 4) == "RIFF" && String(head, 8, 4) == "WAVE") { "Not a WAV file" }
            var fmtTag = 1; var ch = 1; var sr = 48000; var bits = 16
            var dataPos = -1L; var dataLen = 0L
            while (f.filePointer + 8 <= f.length()) {
                val ch4 = ByteArray(4); f.readFully(ch4)
                val len = Integer.reverseBytes(f.readInt()).toLong() and 0xFFFFFFFFL
                val id = String(ch4)
                if (id == "fmt ") {
                    val b = ByteArray(len.toInt()); f.readFully(b)
                    val bb = ByteBuffer.wrap(b).order(ByteOrder.LITTLE_ENDIAN)
                    fmtTag = bb.getShort(0).toInt() and 0xFFFF
                    ch = bb.getShort(2).toInt()
                    sr = bb.getInt(4)
                    bits = bb.getShort(14).toInt()
                    if (fmtTag == 0xFFFE && b.size >= 26) fmtTag = bb.getShort(24).toInt() and 0xFFFF
                } else if (id == "data") {
                    dataPos = f.filePointer
                    dataLen = if (len == 0xFFFFFFFFL || dataPos + len > f.length()) f.length() - dataPos else len
                    break
                } else {
                    f.seek(f.filePointer + len + (len and 1L))
                }
            }
            require(dataPos >= 0) { "WAV has no data chunk" }
            val bytesPer = bits / 8
            val frames = (dataLen / (bytesPer * ch)).toInt()
            val out = FloatArray(frames)
            f.seek(dataPos)
            val chunkFrames = 16384
            val buf = ByteArray(chunkFrames * ch * bytesPer)
            var done = 0
            while (done < frames) {
                val n = minOf(chunkFrames, frames - done)
                f.readFully(buf, 0, n * ch * bytesPer)
                val bb = ByteBuffer.wrap(buf).order(ByteOrder.LITTLE_ENDIAN)
                for (i in 0 until n) {
                    var acc = 0f
                    for (c in 0 until ch) {
                        val p = (i * ch + c) * bytesPer
                        acc += when {
                            fmtTag == 3 && bits == 32 -> bb.getFloat(p)
                            bits == 16 -> bb.getShort(p) / 32768f
                            bits == 24 -> ((buf[p].toInt() and 0xFF) or ((buf[p + 1].toInt() and 0xFF) shl 8) or (buf[p + 2].toInt() shl 16)) / 8388608f
                            bits == 32 -> bb.getInt(p) / 2147483648f
                            else -> throw IllegalArgumentException("Unsupported WAV bit depth $bits")
                        }
                    }
                    out[done + i] = acc / ch
                }
                done += n
            }
            return PcmClip(out, sr)
        }
    }

    fun write(path: String, clip: PcmClip) {
        Writer(path, clip.sampleRate).use { it.write(clip.samples, 0, clip.samples.size) }
    }

    /** Streaming mono PCM16 writer with TPDF dither; header is patched on close. */
    class Writer(val path: String, private val sampleRate: Int) : AutoCloseable {
        private val raf = RandomAccessFile(File(path).also { it.parentFile?.mkdirs() }, "rw")
        private var bytes = 0L
        private val rnd = java.util.Random(7)
        @Volatile var frames = 0L
            private set

        init {
            raf.setLength(0)
            raf.write(ByteArray(44))
        }

        fun write(s: FloatArray, off: Int, n: Int) {
            val b = ByteArray(n * 2)
            for (i in 0 until n) {
                val d = (rnd.nextFloat() - rnd.nextFloat()) / 32768f
                val v = ((s[off + i] + d).coerceIn(-1f, 1f) * 32767f).roundToInt()
                b[i * 2] = v.toByte()
                b[i * 2 + 1] = (v shr 8).toByte()
            }
            raf.write(b)
            bytes += b.size
            frames += n
        }

        override fun close() {
            val h = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
            h.put("RIFF".toByteArray()).putInt((36 + bytes).toInt()).put("WAVE".toByteArray())
            h.put("fmt ".toByteArray()).putInt(16).putShort(1).putShort(1)
            h.putInt(sampleRate).putInt(sampleRate * 2).putShort(2).putShort(16)
            h.put("data".toByteArray()).putInt(bytes.toInt())
            raf.seek(0)
            raf.write(h.array())
            raf.close()
        }
    }
}
