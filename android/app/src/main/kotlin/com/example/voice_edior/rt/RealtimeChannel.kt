package com.example.voice_edior.rt

import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.provider.MediaStore
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.example.voice_edior.dsp.Meters
import com.example.voice_edior.dsp.VocalFx
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** Bridge for `com.vocalpolish/rt` (methods) and `com.vocalpolish/rt_events` (meters, transport, routing). */
class RealtimeChannel(private val ctx: Context) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private val dir = File(ctx.filesDir, "vocalpolish/live").also { it.mkdirs() }
    private val live = LiveEngine(ctx, dir)
    private val player = FilePlayer()
    private var sink: EventChannel.EventSink? = null
    private var ticking = false
    private var lastFx = VocalFx()
    private val am = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private val routeCb = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>?) = routeChanged()
        override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>?) = routeChanged()
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "com.vocalpolish/rt").setMethodCallHandler(this)
        EventChannel(messenger, "com.vocalpolish/rt_events").setStreamHandler(this)
        am.registerAudioDeviceCallback(routeCb, main)
    }

    fun dispose() {
        am.unregisterAudioDeviceCallback(routeCb)
        live.disarm()
        player.release()
        RecordingService.stop(ctx)
    }

    private fun routeChanged() {
        sink?.success(mapOf("type" to "route", "headphones" to live.headphonesConnected()))
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "caps" -> {
                    val pm = ctx.packageManager
                    result.success(mapOf(
                        "sampleRate" to LiveEngine.SR,
                        "lowLatency" to pm.hasSystemFeature(PackageManager.FEATURE_AUDIO_LOW_LATENCY),
                        "proAudio" to pm.hasSystemFeature(PackageManager.FEATURE_AUDIO_PRO),
                        "headphones" to live.headphonesConnected(),
                        "engineLatencyMs" to live.latencyMs,
                        "outputFramesPerBuffer" to am.getProperty(AudioManager.PROPERTY_OUTPUT_FRAMES_PER_BUFFER),
                    ))
                }
                "setFx" -> {
                    @Suppress("UNCHECKED_CAST")
                    lastFx = VocalFx.fromMap(call.arguments as Map<String, Any?>)
                    live.setFx(lastFx); player.setFx(lastFx)
                    result.success(null)
                }
                "live.arm" -> {
                    live.setFx(lastFx)
                    RecordingService.start(ctx)
                    live.arm()
                    startTick()
                    result.success(mapOf("headphones" to live.headphonesConnected()))
                }
                "live.disarm" -> {
                    live.disarm(); RecordingService.stop(ctx); result.success(null)
                }
                "live.setMonitor" -> {
                    val on = call.argument<Boolean>("on") == true
                    live.monitorWanted = on
                    result.success(mapOf("blocked" to (on && !live.headphonesConnected())))
                }
                "live.start" -> { live.startTake(); result.success(null) }
                "live.pause" -> { live.paused = true; result.success(null) }
                "live.resume" -> { live.paused = false; result.success(null) }
                "live.stop" -> {
                    val r = live.stopTake()
                    if (r == null) result.error("no_take", "No active take", null)
                    else result.success(mapOf("rawPath" to r.rawPath, "fxPath" to r.processedPath, "durationMs" to r.durationMs))
                }
                "player.load" -> io.execute {
                    try {
                        val d = player.load(call.argument<String>("path")!!)
                        player.setFx(lastFx)
                        main.post { startTick(); result.success(mapOf("durationMs" to d, "sampleRate" to player.sampleRate)) }
                    } catch (t: Throwable) { main.post { result.error("load_failed", t.message, null) } }
                }
                "player.play" -> { player.setFx(lastFx); player.play(); startTick(); result.success(null) }
                "player.pause" -> { player.pause(); result.success(null) }
                "player.seek" -> { player.seekMs(call.argument<Int>("ms") ?: 0); result.success(null) }
                "player.loop" -> {
                    player.loopStart = call.argument<Int>("startMs")?.let { if (it < 0) -1 else (it.toLong() * player.sampleRate / 1000).toInt() } ?: -1
                    player.loopEnd = call.argument<Int>("endMs")?.let { if (it < 0) -1 else (it.toLong() * player.sampleRate / 1000).toInt() } ?: -1
                    result.success(null)
                }
                "player.release" -> { player.release(); result.success(null) }
                "render" -> io.execute {
                    try {
                        @Suppress("UNCHECKED_CAST")
                        val fx = VocalFx.fromMap(call.argument<Map<String, Any?>>("fx") ?: emptyMap())
                        val out = call.argument<String>("output") ?: File(dir, "render-${System.currentTimeMillis()}.wav").path
                        val ms = FilePlayer.render(call.argument<String>("input")!!, out, fx, call.argument<Int>("startMs") ?: 0, call.argument<Int>("endMs") ?: 0)
                        main.post { result.success(mapOf("filePath" to out, "durationMs" to ms)) }
                    } catch (t: Throwable) { main.post { result.error("render_failed", t.message, null) } }
                }
                "enhance" -> io.execute {
                    try {
                        val inPath = call.argument<String>("input")!!
                        val out = call.argument<String>("output") ?: File(dir, "enhanced-${System.currentTimeMillis()}.wav").path
                        val mode = call.argument<String>("mode") ?: "podcast"
                        val tone = call.argument<String>("tone") ?: "natural"
                        val space = call.argument<String>("space") ?: "dry"
                        val level = call.argument<String>("level") ?: "enhanced"
                        val r = Enhancer.run(inPath, out, mode, tone, space, level) { stage, p ->
                            main.post { sink?.success(mapOf("type" to "enhance", "stage" to stage, "progress" to p)) }
                        }
                        main.post {
                            result.success(mapOf(
                                "filePath" to r.path, "durationMs" to r.durationMs,
                                "lufsIn" to r.lufsIn, "lufsOut" to r.lufsOut,
                                "floorInDb" to r.floorInDb, "floorOutDb" to r.floorOutDb,
                                "f0" to r.f0, "voiceType" to r.voiceType,
                            ))
                        }
                    } catch (t: Throwable) { main.post { result.error("enhance_failed", t.message, null) } }
                }
                "saveToDownloads" -> io.execute {
                    try {
                        val src = File(call.argument<String>("path")!!)
                        val name = call.argument<String>("name") ?: src.name
                        if (Build.VERSION.SDK_INT < 29) throw IllegalStateException("Use the share sheet on this Android version")
                        val values = ContentValues().apply {
                            put(MediaStore.Downloads.DISPLAY_NAME, name)
                            put(MediaStore.Downloads.MIME_TYPE, "audio/wav")
                            put(MediaStore.Downloads.RELATIVE_PATH, "Download/VocalPolish")
                            put(MediaStore.Downloads.IS_PENDING, 1)
                        }
                        val resolver = ctx.contentResolver
                        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                            ?: throw IllegalStateException("Could not create the file")
                        resolver.openOutputStream(uri)!!.use { o -> src.inputStream().use { it.copyTo(o) } }
                        values.clear(); values.put(MediaStore.Downloads.IS_PENDING, 0)
                        resolver.update(uri, values, null, null)
                        main.post { result.success("Download/VocalPolish/$name") }
                    } catch (t: Throwable) { main.post { result.error("save_failed", t.message, null) } }
                }
                else -> result.notImplemented()
            }
        } catch (t: Throwable) {
            result.error("rt_error", t.message, null)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events; startTick() }
    override fun onCancel(arguments: Any?) { sink = null }

    private fun startTick() {
        if (ticking) return
        ticking = true
        main.post(tick)
    }

    private val tick = object : Runnable {
        override fun run() {
            val s = sink
            if (s != null) {
                if (live.active) emitLive(s)
                if (player.durationMs > 0) emitPlayer(s)
            }
            if (s != null && (live.active || player.durationMs > 0)) main.postDelayed(this, 33) else ticking = false
        }
    }

    private fun emitLive(s: EventChannel.EventSink) {
        val m = live.meters
        s.success(mapOf(
            "type" to "live",
            "inPeak" to m.inPeak, "inRms" to m.inRms, "outPeak" to m.outPeak, "outRms" to m.outRms,
            "comp" to m.compGrDb, "deEss" to m.deEssGrDb, "gate" to m.gateOpen, "clip" to m.clipped,
            "bar" to live.drainBar(), "elapsedMs" to live.elapsedMs,
            "recording" to live.recording, "paused" to live.paused, "monitoring" to live.monitoring,
            "error" to live.error,
        ))
        m.clipped = false
    }

    private fun emitPlayer(s: EventChannel.EventSink) {
        val m: Meters? = player.meters
        s.success(mapOf(
            "type" to "player",
            "positionMs" to player.positionMs, "durationMs" to player.durationMs,
            "playing" to player.playing, "ended" to player.ended,
            "inPeak" to (m?.inPeak ?: 0f), "outPeak" to (m?.outPeak ?: 0f), "outRms" to (m?.outRms ?: 0f),
            "inRms" to (m?.inRms ?: 0f), "comp" to (m?.compGrDb ?: 0f), "deEss" to (m?.deEssGrDb ?: 0f),
            "gate" to (m?.gateOpen ?: 1f), "clip" to (m?.clipped ?: false),
        ))
        m?.clipped = false
    }
}
