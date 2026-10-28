package com.example.voice_edior.rt

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * MethodChannel (`vocalpolish/mix`) and EventChannel (`vocalpolish/mix_events`) bridge
 * for the Mix Studio multi-track audio workstation.
 */
class MixChannel(ctx: Context) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val mixDir = File(ctx.filesDir, "vocalpolish/mix").also { it.mkdirs() }
    private val engine = MixEngine(mixDir)
    private var sink: EventChannel.EventSink? = null
    private var ticking = false

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "vocalpolish/mix").setMethodCallHandler(this)
        EventChannel(messenger, "vocalpolish/mix_events").setStreamHandler(this)
    }

    fun dispose() {
        engine.stop()
        worker.shutdownNow()
    }

    @Suppress("UNCHECKED_CAST")
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "mix.loadProject" -> {
                    val project = (call.arguments as? Map<String, Any?>) ?: emptyMap()
                    worker.execute {
                        try {
                            engine.renderProjectGraph(project)
                            main.post {
                                startTick()
                                result.success(mapOf("durationMs" to engine.totalDurationMs))
                            }
                        } catch (t: Throwable) {
                            main.post { result.error("mix_load_failed", t.message, null) }
                        }
                    }
                }
                "mix.play" -> {
                    engine.play()
                    startTick()
                    result.success(null)
                }
                "mix.pause" -> {
                    engine.pause()
                    result.success(null)
                }
                "mix.stop" -> {
                    engine.stop()
                    result.success(null)
                }
                "mix.seek" -> {
                    val ms = call.argument<Int>("ms") ?: 0
                    engine.seek(ms)
                    result.success(null)
                }
                "mix.extractPeaks" -> {
                    val path = call.argument<String>("path") ?: ""
                    val bins = call.argument<Int>("bins") ?: 120
                    worker.execute {
                        val peaks = engine.extractPeaks(path, bins)
                        main.post { result.success(peaks) }
                    }
                }
                "mix.detectSilence" -> {
                    val path = call.argument<String>("path") ?: ""
                    val thresholdDb = call.argument<Double>("thresholdDb") ?: -42.0
                    val minSilenceMs = call.argument<Int>("minSilenceMs") ?: 250
                    worker.execute {
                        val regions = engine.detectNonSilentRegions(path, thresholdDb, minSilenceMs)
                        main.post { result.success(regions) }
                    }
                }
                "mix.startExport" -> {
                    val project = call.argument<Map<String, Any?>>("project") ?: emptyMap()
                    val outPath = call.argument<String>("outputPath")
                        ?: File(mixDir, "mix-master-${System.currentTimeMillis()}.wav").path
                    val bitDepth = call.argument<Int>("bitDepth") ?: 16
                    val targetLufs = call.argument<Double>("targetLufs") ?: -16.0
                    val ceilingDb = call.argument<Double>("ceilingDb") ?: -1.0
                    worker.execute {
                        try {
                            val res = engine.exportStereoWav(
                                project = project,
                                outPath = outPath,
                                bitDepth = bitDepth,
                                targetLufs = targetLufs,
                                ceilingDb = ceilingDb,
                            ) { stage, progress ->
                                main.post {
                                    sink?.success(
                                        mapOf(
                                            "type" to "export",
                                            "stage" to stage,
                                            "progress" to progress,
                                        ),
                                    )
                                }
                            }
                            main.post { result.success(res) }
                        } catch (t: Throwable) {
                            main.post { result.error("mix_export_failed", t.message, null) }
                        }
                    }
                }
                "mix.cancelExport" -> {
                    engine.cancelExport()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (t: Throwable) {
            result.error("mix_error", t.message, null)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        startTick()
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    private fun startTick() {
        if (ticking) return
        ticking = true
        main.post(tickRunnable)
    }

    private val tickRunnable = object : Runnable {
        override fun run() {
            val s = sink
            if (s != null) {
                s.success(
                    mapOf(
                        "type" to "transport",
                        "playing" to engine.playing,
                        "playheadMs" to engine.playheadMs,
                        "durationMs" to engine.totalDurationMs,
                        "peakL" to engine.peakL,
                        "peakR" to engine.peakR,
                        "rmsL" to engine.rmsL,
                        "rmsR" to engine.rmsR,
                        "lufsMomentary" to engine.lufsMomentary,
                        "lufsIntegrated" to engine.lufsIntegrated,
                        "truePeakDb" to engine.truePeakDb,
                        "correlation" to engine.correlation,
                        "clipping" to engine.clipping,
                        "spectrum" to engine.spectrum24.toList(),
                    ),
                )
            }
            if (s != null && engine.playing) {
                main.postDelayed(this, 33)
            } else {
                ticking = false
            }
        }
    }
}
