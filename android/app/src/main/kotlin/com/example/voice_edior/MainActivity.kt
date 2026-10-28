package com.example.voice_edior

import com.example.voice_edior.rt.MixChannel
import com.example.voice_edior.rt.RealtimeChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var rt: RealtimeChannel? = null
    private var mix: MixChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        rt = RealtimeChannel(applicationContext).also { it.register(messenger) }
        mix = MixChannel(applicationContext).also { it.register(messenger) }
    }

    override fun onDestroy() {
        if (isFinishing) {
            rt?.dispose()
            mix?.dispose()
        }
        super.onDestroy()
    }
}
