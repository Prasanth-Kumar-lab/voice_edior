package com.example.voice_edior

import com.example.voice_edior.rt.RealtimeChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var rt: RealtimeChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        rt = RealtimeChannel(applicationContext).also { it.register(flutterEngine.dartExecutor.binaryMessenger) }
    }

    override fun onDestroy() {
        if (isFinishing) rt?.dispose()
        super.onDestroy()
    }
}
