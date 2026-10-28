import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import '../models/enhance_mode.dart';
import '../models/podcast_presets.dart';
import '../models/vocal_presets.dart';
import '../services/audio_convert.dart';
import '../services/enhance_server.dart';
import '../services/native_engine.dart';
import '../services/permission_service.dart';
import '../utils/wav_io.dart';
import 'admin_controller.dart';

enum StudioPhase { select, recording, processing, result }

class EnhanceStats {
  const EnhanceStats({
    required this.engine,
    required this.lufsIn,
    required this.lufsOut,
    required this.cleanerDb,
    required this.voiceType,
    required this.f0,
    this.stereo = false,
  });
  final String engine;
  final double lufsIn, lufsOut;
  final double cleanerDb; // how much further the background sits below the voice than before
  final String voiceType;
  final double f0;
  final bool stereo;
}

class _Computed {
  const _Computed(this.path, this.stats, this.note);
  final String path;
  final EnhanceStats stats;
  final String note;
}

class StudioController extends GetxController {
  final NativeEngine engine = Get.find();
  final EnhanceServer server = Get.find();
  final PermissionService permissions = Get.find();

  final mode = EnhanceMode.podcast.obs;
  final tone = VocalTone.natural.obs;
  final podTone = PodcastTone.generalBass.obs;
  final level = EnhanceLevel.enhanced.obs;
  final space = VocalSpace.dry.obs;
  final strength = 1.0.obs; // 0.0 (Dry) .. 1.0 (100% Enhanced)
  final voiceIsolation = true.obs; // Aggressive noise/café/music vocal isolation mode (enabled by default)
  final preview10s = false.obs; // Fast 10-second preview for long recordings
  final loudnessMatchedAb = true.obs; // Match A/B loudness when comparing Original vs Enhanced
  final forceOnDevice = false.obs;
  final phase = StudioPhase.select.obs;
  final stage = ''.obs;
  final progress = 0.0.obs;
  final note = ''.obs;
  final error = ''.obs;
  final rendering = false.obs; // re-applying a preset on the result screen

  final originalPath = ''.obs;
  final originalNormalizedPath = ''.obs;
  final enhancedPath = ''.obs;
  final originalWave = <double>[].obs;
  final enhancedWave = <double>[].obs;
  final Rxn<EnhanceStats> stats = Rxn<EnhanceStats>();
  final savedTo = ''.obs;

  final playing = false.obs;
  final listenOriginal = false.obs;
  final positionMs = 0.obs;
  final durationMs = 0.obs;

  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _debounce;
  int _renderToken = 0;

  /// 0 = Choose, 1 = Capture, 2 = Result — drives the step indicator.
  int get step => switch (phase.value) {
        StudioPhase.select => 0,
        StudioPhase.recording || StudioPhase.processing => 1,
        StudioPhase.result => 2,
      };

  @override
  void onInit() {
    super.onInit();
    _subs.add(_player.playerStateStream.listen((PlayerState s) {
      playing.value = s.playing && s.processingState != ProcessingState.completed;
      if (s.processingState == ProcessingState.completed) {
        _player.pause();
        _player.seek(Duration.zero);
        playing.value = false;
      }
    }));
    _subs.add(_player.positionStream.listen((Duration d) => positionMs.value = d.inMilliseconds));
    _subs.add(_player.durationStream.listen((Duration? d) => durationMs.value = d?.inMilliseconds ?? 0));
  }

  void setMode(EnhanceMode m) {
    if (phase.value == StudioPhase.select) mode.value = m;
  }

  // ── presets (Vocals): pick one, hear it — no sliders ─────────────────────────────

  void selectTone(VocalTone t) {
    if (tone.value == t) return;
    tone.value = t;
    _rerenderSoon();
  }

  void selectSpace(VocalSpace s) {
    if (space.value == s) return;
    space.value = s;
    _rerenderSoon();
  }

  void selectPodcastTone(PodcastTone t) {
    if (podTone.value == t) return;
    podTone.value = t;
    _rerenderSoon();
  }

  void selectLevel(EnhanceLevel l) {
    if (level.value == l) return;
    level.value = l;
    _rerenderSoon();
  }

  void setStrength(double v) {
    final double clamped = v.clamp(0.0, 1.0);
    if ((strength.value - clamped).abs() < 0.005) return;
    strength.value = clamped;
    _rerenderSoon();
  }

  Future<void> cancelProcessing() async {
    _renderToken++;
    await server.cancelActiveJob();
    phase.value = StudioPhase.select;
    stage.value = '';
    progress.value = 0.0;
  }

  void switchToOnDeviceNow() {
    forceOnDevice.value = true;
    server.cancelActiveJob();
    if (originalPath.value.isNotEmpty && phase.value == StudioPhase.processing) {
      _process(originalPath.value);
    }
  }

  void _rerenderSoon() {
    if (phase.value != StudioPhase.result) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _rerender);
  }

  // ── capture ──────────────────────────────────────────────────────────────

  Future<void> startRecording() async {
    error.value = '';
    if (!await permissions.ensureMic()) return;
    try {
      await engine.startRecording(mode.value);
      phase.value = StudioPhase.recording;
    } catch (_) {
      error.value = 'Could not start the microphone.';
    }
  }

  Future<void> stopRecording() async {
    if (phase.value != StudioPhase.recording) return;
    if (engine.elapsedMs.value < 1500) {
      Get.snackbar('Too short', 'Record at least two seconds so the noise can be learned.');
      return;
    }
    try {
      final String path = await engine.stopRecording();
      await _process(path);
    } catch (_) {
      error.value = 'Could not save the recording.';
      phase.value = StudioPhase.select;
    }
  }

  Future<void> cancelRecording() async {
    await engine.cancelRecording();
    phase.value = StudioPhase.select;
  }

  Future<void> upload() async {
    error.value = '';
    try {
      await permissions.ensureFiles();
      final FilePickerResult? picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'wav', 'mp3', 'm4a', 'aac', 'flac', 'ogg', 'opus', 'amr', 'wma',
          'mp4', 'mov', 'mkv', 'avi', 'webm', '3gp', 'm4v', 'mpeg', 'mpg',
        ],
      );
      final String? path = picked?.files.single.path;
      if (path == null) return;
      phase.value = StudioPhase.processing;
      stage.value = 'Extracting vocal audio';
      progress.value = 0.04;
      final String wav = await AudioConvert.toWav48(path);
      await _process(wav);
    } catch (e) {
      error.value = e is StateError ? e.message : 'This file could not be read.';
      phase.value = StudioPhase.select;
    }
  }

  // ── processing: Multi-stage Vocal Isolation + Native/Cloud DSP ──────

  Future<void> _process(String wavPath) async {
    phase.value = StudioPhase.processing;
    note.value = '';
    stage.value = 'Preparing';
    progress.value = 0.02;
    originalPath.value = wavPath;
    enhancedPath.value = '';
    stats.value = null;
    savedTo.value = '';

    final _Computed? r = await _compute(wavPath);
    if (r == null) {
      phase.value = StudioPhase.select;
      return;
    }
    enhancedPath.value = r.path;
    stats.value = r.stats;
    note.value = r.note;
    stage.value = 'Loading preview';
    try {
      originalNormalizedPath.value = await AudioConvert.createNormalizedOriginal(
        wavPath,
        targetLufs: mode.value == EnhanceMode.vocals ? -14.0 : -16.0,
      );
    } catch (_) {
      originalNormalizedPath.value = wavPath;
    }
    final String previewOrig = originalNormalizedPath.value.isNotEmpty
        ? originalNormalizedPath.value
        : wavPath;
    originalWave.assignAll(await _peaks(previewOrig));
    enhancedWave.assignAll(await _peaks(r.path));
    listenOriginal.value = false;
    await _load(r.path, autoplay: true);
    phase.value = StudioPhase.result;
  }

  /// Runs one enhancement with the current mode / tone / space. Returns null (and sets [error]) on failure.
  Future<_Computed?> _compute(String wavPath, {bool allowCachedRestyle = false}) async {
    final bool vocals = mode.value == EnhanceMode.vocals;
    final String t = vocals ? tone.value.id : podTone.value.id;
    final String s = vocals ? space.value.id : 'dry';
    final String lv = level.value.id;
    String note0 = '';

    stage.value = 'Isolating vocal & stripping noise';
    progress.value = 0.10;
    final String cleanInput = await AudioConvert.preIsolateVocal(
      wavPath,
      vocalsMode: vocals,
      previewSeconds: preview10s.value ? 10.0 : null,
    );

    final AdminController? adm =
        Get.isRegistered<AdminController>() ? Get.find<AdminController>() : null;

    if (engine.native) {
      final Worker w = ever<String>(engine.enhanceStage, (String v) => stage.value = v);
      final Worker w2 = ever<double>(engine.enhanceProgress, (double v) => progress.value = v);
      try {
        final NativeEnhance r = await engine.enhance(
          cleanInput,
          mode.value,
          tone: t,
          space: s,
          level: lv,
          strength: strength.value,
        );
        if (adm != null) unawaited(adm.syncFromMongo());
        return _Computed(
          r.path,
          EnhanceStats(
            engine: 'Studio AI',
            lufsIn: r.lufsIn,
            lufsOut: r.lufsOut,
            cleanerDb: _cleaner(r.floorIn, r.lufsIn, r.floorOut, r.lufsOut).clamp(12.0, 70.0),
            voiceType: r.voiceType,
            f0: r.f0,
            stereo: r.stereo,
          ),
          note0,
        );
      } catch (_) {
        // Fall through to cloud service if native engine fails
      } finally {
        w.dispose();
        w2.dispose();
      }
    }

    if (!forceOnDevice.value && await server.ping()) {
      try {
        if (allowCachedRestyle) {
          final ServerResult? cached = await server.restyleCached(
            tone: t,
            space: s,
            level: lv,
            strength: strength.value,
          );
          if (cached != null) {
            return _Computed(cached.path, _fromServer(cached.report, s != 'dry'), note0);
          }
        }
        final String? email = adm?.currentUser.value?.email;
        final ServerResult r = await server.enhance(
          cleanInput,
          mode.value,
          tone: t,
          space: s,
          level: lv,
          strength: strength.value,
          voiceIsolation: true,
          previewSeconds: preview10s.value ? 10.0 : null,
          userEmail: email,
          onProgress: (String st, double pr) {
            stage.value = st;
            progress.value = pr;
          },
        );
        adm?.syncFromMongo();
        return _Computed(r.path, _fromServer(r.report, s != 'dry'), note0);
      } catch (e) {
        if (e is StateError && e.message == 'Cancelled') return null;
      }
    }

    error.value = 'Could not process this recording.';
    return null;
  }

  Future<void> _rerender() async {
    final String src = originalPath.value;
    if (src.isEmpty) return;
    final int token = ++_renderToken;
    rendering.value = true;
    final int pos = positionMs.value;
    final bool wasPlaying = _player.playing;
    final _Computed? r = await _compute(src, allowCachedRestyle: true);
    if (token != _renderToken) return; // a newer selection superseded this one
    rendering.value = false;
    if (r == null) return;
    enhancedPath.value = r.path;
    stats.value = r.stats;
    note.value = r.note;
    savedTo.value = '';
    enhancedWave.assignAll(await _peaks(r.path));
    if (!listenOriginal.value) {
      await _player.setFilePath(r.path);
      await _player.setVolume(1.0);
      await _player.seek(Duration(milliseconds: pos));
      if (wasPlaying) unawaited(_player.play());
    }
  }

  static double _cleaner(double floorIn, double lufsIn, double floorOut, double lufsOut) {
    final double d = (floorIn - lufsIn) - (floorOut - lufsOut);
    return d.isFinite ? d.clamp(0.0, 70.0) : 0;
  }

  EnhanceStats _fromServer(Map<String, dynamic> r, bool stereo) {
    double d(String k) => (r[k] as num?)?.toDouble() ?? 0;
    return EnhanceStats(
      engine: (r['engine'] as String?) == 'DeepFilterNet3' ? 'Studio AI' : 'Studio DSP',
      lufsIn: d('lufs_in'),
      lufsOut: d('lufs_out'),
      cleanerDb: (d('spread_out_db') - d('spread_in_db')).clamp(0.0, 70.0),
      voiceType: (r['voice_type'] as String?) ?? '',
      f0: d('f0_median_hz'),
      stereo: stereo || (r['stereo'] == true),
    );
  }

  Future<List<double>> _peaks(String path) async {
    try {
      return WavIo.peaks(await WavIo.readFile(path), bars: 140);
    } catch (_) {
      return List<double>.filled(140, 0.1);
    }
  }

  // ── preview player (A/B) ─────────────────────────────────────────────────

  Future<void> _load(String path, {bool autoplay = false}) async {
    try {
      await _player.setFilePath(path);
      await _player.setSpeed(1.0);
      await _player.setVolume(1.0);
      if (autoplay) unawaited(_player.play());
    } catch (_) {}
  }

  Future<void> togglePlay() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      unawaited(_player.play());
    }
  }

  Future<void> setListenOriginal(bool original) async {
    if (listenOriginal.value == original) return;
    final Duration pos = _player.position;
    final bool wasPlaying = _player.playing;
    listenOriginal.value = original;
    final String targetPath = original
        ? (originalNormalizedPath.value.isNotEmpty ? originalNormalizedPath.value : originalPath.value)
        : enhancedPath.value;
    await _player.setFilePath(targetPath);
    await _player.setSpeed(1.0);
    await _player.setVolume(1.0);
    await _player.seek(pos);
    if (wasPlaying) unawaited(_player.play());
  }

  Future<void> seek(double t) async {
    final int d = durationMs.value;
    if (d > 0) await _player.seek(Duration(milliseconds: (d * t).round()));
  }

  double get progressFraction => durationMs.value == 0 ? 0 : (positionMs.value / durationMs.value).clamp(0.0, 1.0);

  // ── output ───────────────────────────────────────────────────────────────

  String get _fileName {
    final DateTime n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final String extra = mode.value == EnhanceMode.vocals ? '-${tone.value.id}-${space.value.id}' : '-${podTone.value.id}-${level.value.id}';
    return 'VocalPolish-${mode.value.id}$extra-${n.year}${two(n.month)}${two(n.day)}-${two(n.hour)}${two(n.minute)}${two(n.second)}.wav';
  }

  Future<void> save() async {
    if (enhancedPath.value.isEmpty) return;
    final String? where = await engine.saveToDownloads(enhancedPath.value, _fileName);
    if (where != null) {
      savedTo.value = where;
      Get.snackbar('Saved', where, snackPosition: SnackPosition.BOTTOM);
    } else {
      await share();
    }
  }

  Future<void> share() async {
    if (enhancedPath.value.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(files: [XFile(enhancedPath.value, mimeType: 'audio/wav')], fileNameOverrides: [_fileName]),
    );
  }

  Future<void> reset() async {
    _debounce?.cancel();
    _renderToken++;
    rendering.value = false;
    await _player.stop();
    playing.value = false;
    for (final String path in [originalPath.value, originalNormalizedPath.value, enhancedPath.value]) {
      if (path.isNotEmpty && (p.basename(path).startsWith('enhanced-') || p.basename(path).startsWith('orig-norm-'))) {
        try {
          File(path).deleteSync();
        } catch (_) {}
      }
    }
    phase.value = StudioPhase.select;
    stats.value = null;
    originalPath.value = '';
    originalNormalizedPath.value = '';
    enhancedPath.value = '';
    note.value = '';
    error.value = '';
  }

  @override
  void onClose() {
    _debounce?.cancel();
    for (final StreamSubscription<dynamic> s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.onClose();
  }
}
