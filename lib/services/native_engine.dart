import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../models/enhance_mode.dart';
import '../models/vocal_fx.dart';

class Levels {
  const Levels({this.inRms = 0, this.inPeak = 0, this.outRms = 0, this.outPeak = 0, this.clip = false});
  final double inRms, inPeak, outRms, outPeak; // 0..1 meter position (-60..0 dBFS)
  final bool clip;
}

class NativeEnhance {
  const NativeEnhance({
    required this.path,
    required this.durationMs,
    required this.lufsIn,
    required this.lufsOut,
    required this.floorIn,
    required this.floorOut,
    required this.f0,
    required this.voiceType,
    this.stereo = false,
  });
  final String path;
  final int durationMs;
  final double lufsIn, lufsOut, floorIn, floorOut, f0;
  final String voiceType;
  final bool stereo;
}

/// Recording + on-device enhancement. Android uses the native Kotlin engine (48 kHz, live meters,
/// optional clean headphone monitor, on-device premium fallback). Other platforms record with `record`.
class NativeEngine extends GetxService {
  static const MethodChannel _m = MethodChannel('com.vocalpolish/rt');
  static const EventChannel _e = EventChannel('com.vocalpolish/rt_events');
  static const int _bars = 64;

  bool get native => Platform.isAndroid;

  final levels = const Levels().obs;
  final bars = <double>[].obs;
  final elapsedMs = 0.obs;
  final headphones = false.obs;
  final monitor = false.obs;
  final enhanceStage = ''.obs;
  final enhanceProgress = 0.0.obs;

  StreamSubscription<dynamic>? _sub;
  AudioRecorder? _rec;
  StreamSubscription<Amplitude>? _amp;
  String? _recPath;
  DateTime? _started;

  @override
  void onInit() {
    super.onInit();
    bars.assignAll(List<double>.filled(_bars, 0.03));
    if (native) _sub = _e.receiveBroadcastStream().listen(_onEvent, onError: (_) {});
  }

  static double _norm(num v) {
    final double db = 20 * math.log(math.max(v.toDouble(), 1e-6)) / math.ln10;
    return ((db + 60) / 60).clamp(0.0, 1.0);
  }

  void _onEvent(dynamic raw) {
    if (raw is! Map) return;
    switch (raw['type']) {
      case 'live':
        levels.value = Levels(
          inRms: _norm(raw['inRms'] as num? ?? 0),
          inPeak: _norm(raw['inPeak'] as num? ?? 0),
          outRms: _norm(raw['outRms'] as num? ?? 0),
          outPeak: _norm(raw['outPeak'] as num? ?? 0),
          clip: raw['clip'] == true,
        );
        elapsedMs.value = (raw['elapsedMs'] as num?)?.toInt() ?? 0;
        if (raw['recording'] == true && raw['paused'] != true) {
          final List<double> next = List<double>.from(bars)..removeAt(0);
          bars.assignAll(next..add(math.max(_norm(raw['bar'] as num? ?? 0), 0.03)));
        }
        break;
      case 'route':
        headphones.value = raw['headphones'] == true;
        if (!headphones.value) monitor.value = false;
        break;
      case 'enhance':
        enhanceStage.value = (raw['stage'] as String?) ?? '';
        enhanceProgress.value = (raw['progress'] as num?)?.toDouble() ?? 0;
        break;
    }
  }

  // ── recording ───────────────────────────────────────────────────────────────

  Future<void> startRecording(EnhanceMode mode) async {
    bars.assignAll(List<double>.filled(_bars, 0.03));
    elapsedMs.value = 0;
    if (native) {
      await _m.invokeMethod('setFx', (mode == EnhanceMode.podcast ? VocalFx.podcastLive : VocalFx.vocalsLive).toMap());
      final Map<dynamic, dynamic>? r = await _m.invokeMapMethod('live.arm');
      headphones.value = r?['headphones'] == true;
      await _m.invokeMethod('live.start');
      return;
    }
    final Directory dir = await getTemporaryDirectory();
    _recPath = p.join(dir.path, 'take-${DateTime.now().millisecondsSinceEpoch}.wav');
    _rec ??= AudioRecorder();
    if (!await _rec!.hasPermission()) throw StateError('Microphone permission denied');
    await _rec!.start(const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 48000, numChannels: 1), path: _recPath!);
    _started = DateTime.now();
    _amp = _rec!.onAmplitudeChanged(const Duration(milliseconds: 60)).listen((Amplitude a) {
      final double n = ((a.current + 60) / 60).clamp(0.0, 1.0);
      levels.value = Levels(inRms: n, inPeak: n, outRms: n, outPeak: n);
      elapsedMs.value = DateTime.now().difference(_started!).inMilliseconds;
      final List<double> next = List<double>.from(bars)..removeAt(0);
      bars.assignAll(next..add(math.max(n, 0.03)));
    });
  }

  /// Stops and returns the untouched master recording.
  Future<String> stopRecording() async {
    if (native) {
      final Map<dynamic, dynamic>? r = await _m.invokeMapMethod('live.stop');
      monitor.value = false;
      await _m.invokeMethod('live.disarm');
      levels.value = const Levels();
      return r!['rawPath'] as String;
    }
    await _amp?.cancel();
    final String? path = await _rec?.stop();
    levels.value = const Levels();
    return path ?? _recPath ?? '';
  }

  Future<void> cancelRecording() async {
    try {
      if (native) {
        await _m.invokeMethod('live.disarm');
      } else {
        await _amp?.cancel();
        await _rec?.stop();
      }
    } catch (_) {}
    levels.value = const Levels();
    monitor.value = false;
  }

  Future<bool> setMonitor(bool on) async {
    if (!native) return false;
    final Map<dynamic, dynamic>? r = await _m.invokeMapMethod('live.setMonitor', {'on': on});
    final bool ok = !(r?['blocked'] == true) && on;
    monitor.value = ok;
    return !(r?['blocked'] == true);
  }

  // ── on-device premium pass ──────────────────────────────────────────────────

  Future<NativeEnhance> enhance(
    String input,
    EnhanceMode mode, {
    String tone = 'natural',
    String space = 'dry',
    String level = 'enhanced',
    double strength = 1.0,
  }) async {
    enhanceStage.value = 'Starting';
    enhanceProgress.value = 0;
    final Map<dynamic, dynamic>? r = await _m.invokeMapMethod('enhance', {
      'input': input,
      'mode': mode.id,
      'tone': tone,
      'space': space,
      'level': level,
      'strength': strength,
    });
    return NativeEnhance(
      path: r!['filePath'] as String,
      durationMs: (r['durationMs'] as num).toInt(),
      lufsIn: (r['lufsIn'] as num).toDouble(),
      lufsOut: (r['lufsOut'] as num).toDouble(),
      floorIn: (r['floorInDb'] as num).toDouble(),
      floorOut: (r['floorOutDb'] as num).toDouble(),
      f0: (r['f0'] as num).toDouble(),
      voiceType: r['voiceType'] as String,
      stereo: (r['stereo'] as bool?) ?? false,
    );
  }

  /// Saves into Downloads/VocalPolish (Android 10+). Returns the visible location, or null if unsupported.
  Future<String?> saveToDownloads(String path, String name) async {
    if (!native) return null;
    try {
      return await _m.invokeMethod<String>('saveToDownloads', {'path': path, 'name': name});
    } catch (_) {
      return null;
    }
  }

  @override
  void onClose() {
    _sub?.cancel();
    _amp?.cancel();
    _rec?.dispose();
    super.onClose();
  }
}
