import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/mix_clip.dart';
import '../models/mix_project.dart';
import '../models/mix_track.dart';
import '../utils/wav_io.dart';

class MixExportResult {
  const MixExportResult({
    required this.filePath,
    required this.durationMs,
    required this.lufsOut,
    required this.bitDepth,
  });

  final String filePath;
  final int durationMs;
  final double lufsOut;
  final int bitDepth;
}

/// Service bridging Flutter Mix Studio to the native Kotlin 48 kHz stereo `MixEngine`
/// (with pure-Dart multi-track fallback for desktop/unit tests).
class MixEngineService extends GetxService {
  static const MethodChannel _ch = MethodChannel('vocalpolish/mix');
  static const EventChannel _ev = EventChannel('vocalpolish/mix_events');

  final RxBool playing = false.obs;
  final RxInt playheadMs = 0.obs;
  final RxInt durationMs = 15000.obs;

  final RxDouble peakL = 0.0.obs;
  final RxDouble peakR = 0.0.obs;
  final RxDouble rmsL = 0.0.obs;
  final RxDouble rmsR = 0.0.obs;
  final RxDouble lufsMomentary = (-24.0).obs;
  final RxDouble lufsIntegrated = (-16.0).obs;
  final RxDouble truePeakDb = (-1.0).obs;
  final RxDouble correlation = 1.0.obs;
  final RxBool clipping = false.obs;
  final RxList<double> spectrum24 = List<double>.filled(24, 0.08).obs;

  final RxString exportStage = ''.obs;
  final RxDouble exportProgress = 0.0.obs;

  StreamSubscription<dynamic>? _sub;
  Timer? _fallbackTimer;
  bool _nativeAvailable = !kIsWeb && Platform.isAndroid;

  @override
  void onInit() {
    super.onInit();
    if (_nativeAvailable) {
      try {
        _sub = _ev.receiveBroadcastStream().listen(_onNativeEvent, onError: (_) {});
      } catch (_) {
        _nativeAvailable = false;
      }
    }
  }

  @override
  void onClose() {
    _sub?.cancel();
    _fallbackTimer?.cancel();
    super.onClose();
  }

  void _onNativeEvent(dynamic raw) {
    if (raw is! Map) return;
    final String? type = raw['type'] as String?;
    if (type == 'transport') {
      playing.value = (raw['playing'] as bool?) ?? false;
      playheadMs.value = ((raw['playheadMs'] as num?) ?? 0).toInt();
      durationMs.value = ((raw['durationMs'] as num?) ?? 15000).toInt();
      peakL.value = ((raw['peakL'] as num?) ?? 0.0).toDouble();
      peakR.value = ((raw['peakR'] as num?) ?? 0.0).toDouble();
      rmsL.value = ((raw['rmsL'] as num?) ?? 0.0).toDouble();
      rmsR.value = ((raw['rmsR'] as num?) ?? 0.0).toDouble();
      lufsMomentary.value = ((raw['lufsMomentary'] as num?) ?? -24.0).toDouble();
      lufsIntegrated.value = ((raw['lufsIntegrated'] as num?) ?? -16.0).toDouble();
      truePeakDb.value = ((raw['truePeakDb'] as num?) ?? -1.0).toDouble();
      correlation.value = ((raw['correlation'] as num?) ?? 1.0).toDouble();
      clipping.value = (raw['clipping'] as bool?) ?? false;
      final List<dynamic>? spec = raw['spectrum'] as List<dynamic>?;
      if (spec != null && spec.isNotEmpty) {
        spectrum24.assignAll(spec.map((e) => (e as num).toDouble()));
      }
    } else if (type == 'export') {
      exportStage.value = (raw['stage'] as String?) ?? 'Rendering';
      exportProgress.value = ((raw['progress'] as num?) ?? 0.0).toDouble();
    }
  }

  Future<void> syncProject(MixProject project) async {
    durationMs.value = project.totalDurationMs;
    if (_nativeAvailable) {
      try {
        await _ch.invokeMethod<dynamic>('mix.loadProject', project.toJson());
        return;
      } catch (_) {}
    }
  }

  Future<void> play(MixProject project) async {
    await syncProject(project);
    if (_nativeAvailable) {
      try {
        await _ch.invokeMethod<void>('mix.play');
        playing.value = true;
        return;
      } catch (_) {}
    }
    // Fallback transport timer when native channel is unavailable
    playing.value = true;
    _fallbackTimer?.cancel();
    _fallbackTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!playing.value) return;
      final int next = playheadMs.value + 33;
      if (project.loopEnabled && next >= project.loopEndMs) {
        playheadMs.value = project.loopStartMs;
      } else if (next >= project.totalDurationMs) {
        playing.value = false;
        playheadMs.value = 0;
        _fallbackTimer?.cancel();
      } else {
        playheadMs.value = next;
      }
    });
  }

  Future<void> pause() async {
    playing.value = false;
    _fallbackTimer?.cancel();
    if (_nativeAvailable) {
      try {
        await _ch.invokeMethod<void>('mix.pause');
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    playing.value = false;
    playheadMs.value = 0;
    peakL.value = 0;
    peakR.value = 0;
    rmsL.value = 0;
    rmsR.value = 0;
    _fallbackTimer?.cancel();
    if (_nativeAvailable) {
      try {
        await _ch.invokeMethod<void>('mix.stop');
      } catch (_) {}
    }
  }

  Future<void> seek(int ms) async {
    playheadMs.value = ms.clamp(0, max(1000, durationMs.value));
    if (_nativeAvailable) {
      try {
        await _ch.invokeMethod<void>('mix.seek', <String, dynamic>{'ms': playheadMs.value});
      } catch (_) {}
    }
  }

  Future<List<double>> extractPeaks(String path, {int bins = 120}) async {
    if (_nativeAvailable) {
      try {
        final List<dynamic>? res = await _ch.invokeMethod<List<dynamic>>(
          'mix.extractPeaks',
          <String, dynamic>{'path': path, 'bins': bins},
        );
        if (res != null && res.isNotEmpty) {
          return res.map((e) => (e as num).toDouble()).toList();
        }
      } catch (_) {}
    }
    try {
      final WavData wav = await WavIo.readFile(path);
      return WavIo.peaks(wav, bars: bins);
    } catch (_) {
      return List<double>.filled(bins, 0.22);
    }
  }

  Future<List<({int startMs, int endMs})>> detectNonSilentRegions(
    String path, {
    double thresholdDb = -42.0,
    int minSilenceMs = 250,
  }) async {
    if (_nativeAvailable) {
      try {
        final List<dynamic>? res = await _ch.invokeMethod<List<dynamic>>(
          'mix.detectSilence',
          <String, dynamic>{
            'path': path,
            'thresholdDb': thresholdDb,
            'minSilenceMs': minSilenceMs,
          },
        );
        if (res != null) {
          return res.map((e) {
            final Map<String, dynamic> m = Map<String, dynamic>.from(e as Map);
            return (
              startMs: ((m['startMs'] as num?) ?? 0).toInt(),
              endMs: ((m['endMs'] as num?) ?? 1000).toInt(),
            );
          }).toList();
        }
      } catch (_) {}
    }
    return const <({int startMs, int endMs})>[];
  }

  Future<MixExportResult> exportMix(
    MixProject project, {
    int bitDepth = 16,
    String? outputPath,
  }) async {
    final Directory dir = await getTemporaryDirectory();
    final String out = outputPath ??
        p.join(dir.path, 'vocalpolish-mix-${DateTime.now().millisecondsSinceEpoch}.wav');
    exportStage.value = 'Rendering tracks...';
    exportProgress.value = 0.05;

    if (_nativeAvailable) {
      try {
        final Map<dynamic, dynamic>? res = await _ch.invokeMethod<Map<dynamic, dynamic>>(
          'mix.startExport',
          <String, dynamic>{
            'project': project.toJson(),
            'outputPath': out,
            'bitDepth': bitDepth,
            'targetLufs': project.master.targetLufs,
            'ceilingDb': project.master.limiterCeilingDb,
          },
        );
        if (res != null) {
          exportStage.value = 'Done';
          exportProgress.value = 1.0;
          return MixExportResult(
            filePath: (res['filePath'] as String?) ?? out,
            durationMs: ((res['durationMs'] as num?) ?? project.totalDurationMs).toInt(),
            lufsOut: ((res['lufsOut'] as num?) ?? project.master.targetLufs).toDouble(),
            bitDepth: ((res['bitDepth'] as num?) ?? bitDepth).toInt(),
          );
        }
      } catch (_) {}
    }

    // Pure-Dart fallback multi-track renderer
    return _renderFallbackDart(project, out, bitDepth);
  }

  Future<MixExportResult> _renderFallbackDart(
    MixProject project,
    String outPath,
    int bitDepth,
  ) async {
    const int sr = 48000;
    final int totalMs = project.totalDurationMs;
    final int totalFrames = max(sr, (totalMs * sr) ~/ 1000);
    final Float64List mixL = Float64List(totalFrames);
    final Float64List mixR = Float64List(totalFrames);

    final bool anySolo = project.tracks.any((t) => t.solo);
    for (int tIdx = 0; tIdx < project.tracks.length; tIdx++) {
      final MixTrack trk = project.tracks[tIdx];
      final bool active = anySolo ? trk.solo : !trk.muted;
      if (!active) continue;
      exportProgress.value = (tIdx + 1) / (project.tracks.length + 1);

      final double trkGain =
          trk.volumeDb <= -59.5 ? 0.0 : pow(10.0, trk.volumeDb / 20.0).toDouble();
      final double panAngle = (trk.pan.clamp(-1.0, 1.0) + 1.0) * 0.25 * pi;
      final double panL = cos(panAngle) * sqrt2;
      final double panR = sin(panAngle) * sqrt2;
      final double phaseSign = trk.phaseInverted ? -1.0 : 1.0;

      for (final MixClip clip in trk.clips) {
        if (clip.muted) continue;
        final File f = File(clip.activeAudioPath);
        if (!f.existsSync()) continue;
        try {
          final WavData wav = await WavIo.readFile(f.path);
          final double clipGain = pow(10.0, clip.gainDb / 20.0).toDouble();
          final int startFrame = ((clip.timelineStartMs / 1000.0) * sr).round();
          final int offsetFrame = ((clip.offsetStartMs / 1000.0) * wav.sampleRate).round();
          final int durFrames = ((clip.durationMs / 1000.0) * sr).round();
          final int fadeInFrames = ((clip.fadeInMs / 1000.0) * sr).round();
          final int fadeOutFrames = ((clip.fadeOutMs / 1000.0) * sr).round();

          for (int i = 0; i < durFrames; i++) {
            final int dest = startFrame + i;
            if (dest < 0 || dest >= totalFrames) break;
            final int srcIdx = clip.reversed
                ? offsetFrame + (durFrames - 1 - i)
                : offsetFrame + ((i * wav.sampleRate) ~/ sr);
            if (srcIdx < 0 || srcIdx >= wav.frames) continue;

            double sample = wav.samples[srcIdx * wav.channels];
            double fade = 1.0;
            if (fadeInFrames > 0 && i < fadeInFrames) {
              fade *= clip.fadeInCurve.gainAt(i / fadeInFrames);
            }
            final int rem = durFrames - 1 - i;
            if (fadeOutFrames > 0 && rem < fadeOutFrames) {
              fade *= clip.fadeOutCurve.gainAt(rem / fadeOutFrames);
            }
            sample *= clipGain * fade * trkGain * phaseSign;
            mixL[dest] += sample * panL;
            mixR[dest] += sample * panR;
          }
        } catch (_) {}
      }
    }

    final double ceiling = pow(10.0, project.master.limiterCeilingDb / 20.0).toDouble();
    final Float64List interleaved = Float64List(totalFrames * 2);
    for (int i = 0; i < totalFrames; i++) {
      interleaved[i * 2] = mixL[i].clamp(-ceiling, ceiling);
      interleaved[i * 2 + 1] = mixR[i].clamp(-ceiling, ceiling);
    }
    await WavIo.writeFile(
      outPath,
      WavData(
        sampleRate: sr,
        channels: 2,
        bitsPerSample: bitDepth == 24 ? 24 : 16,
        samples: interleaved,
      ),
      bits: bitDepth == 24 ? 24 : 16,
    );
    exportStage.value = 'Done';
    exportProgress.value = 1.0;
    return MixExportResult(
      filePath: outPath,
      durationMs: totalMs,
      lufsOut: project.master.targetLufs,
      bitDepth: bitDepth,
    );
  }
}
