# VocalPolish Studio ProGuard / R8 Rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep native Kotlin DSP, RealtimeChannel, and MixEngine bridges
-keep class com.example.voice_edior.** { *; }

# Keep FFmpegKit & Media3 / ExoPlayer classes used by audio plugins
-keep class com.arthenica.ffmpegkit.** { *; }
-dontwarn com.arthenica.ffmpegkit.**
-keep class com.ryanheise.just_audio.** { *; }
