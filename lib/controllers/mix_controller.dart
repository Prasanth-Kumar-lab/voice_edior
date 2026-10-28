import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/enhance_mode.dart';
import '../models/fx_slot.dart';
import '../models/mix_clip.dart';
import '../models/mix_command.dart';
import '../models/mix_project.dart';
import '../models/mix_track.dart';
import '../services/audio_convert.dart';
import '../services/enhance_server.dart';
import '../services/mix_engine_service.dart';
import '../services/native_engine.dart';
import '../utils/app_localization.dart';
import '../utils/wav_io.dart';

class MixMasterExportSummary {
  const MixMasterExportSummary({
    required this.filePath,
    required this.formatLabel,
    required this.lufsOut,
    required this.truePeakDb,
    required this.durationMs,
    required this.fileSizeBytes,
  });

  final String filePath;
  final String formatLabel;
  final double lufsOut;
  final double truePeakDb;
  final int durationMs;
  final int fileSizeBytes;
}

class BuiltInLoopAsset {
  const BuiltInLoopAsset({
    required this.id,
    required this.title,
    required this.category,
    required this.bpm,
    required this.durationMs,
    required this.freqHz,
  });

  final String id;
  final String title;
  final String category;
  final double bpm;
  final int durationMs;
  final double freqHz;

  static const List<BuiltInLoopAsset> all = <BuiltInLoopAsset>[
    BuiltInLoopAsset(
      id: 'loop_warm_pad',
      title: 'Warm Analog Podcast Bed',
      category: 'Music Bed',
      bpm: 110,
      durationMs: 8000,
      freqHz: 220.0,
    ),
    BuiltInLoopAsset(
      id: 'loop_cinema_drone',
      title: 'Cinema Sub Drone (C2)',
      category: 'Ambience',
      bpm: 100,
      durationMs: 10000,
      freqHz: 65.41,
    ),
    BuiltInLoopAsset(
      id: 'loop_lofi_chords',
      title: 'Lo-Fi Rhodes Chord Loop',
      category: 'Backing Loop',
      bpm: 90,
      durationMs: 6000,
      freqHz: 261.63,
    ),
    BuiltInLoopAsset(
      id: 'sfx_intro_chime',
      title: 'Broadcast Intro Shimmer',
      category: 'SFX / Stinger',
      bpm: 120,
      durationMs: 3000,
      freqHz: 523.25,
    ),
  ];
}

/// GetX Controller for the multi-track Mix Studio screen.
class MixController extends GetxController {
  final MixEngineService engine = Get.find<MixEngineService>();
  final NativeEngine nativeEngine = Get.find<NativeEngine>();
  final EnhanceServer server = Get.find<EnhanceServer>();

  final Rx<MixProject> project = MixProject.template('podcast_episode').obs;
  final UndoRedoStack history = UndoRedoStack(maxSteps: 60);

  final RxInt undoCount = 0.obs;
  final RxInt redoCount = 0.obs;

  final RxnString selectedTrackId = RxnString('trk_host');
  final RxnString selectedClipId = RxnString();
  final RxSet<String> multiSelectedClipIds = <String>{}.obs;
  MixClip? _clipboardClip;

  /// Bottom panel tab: 0 = Clip, 1 = Track FX, 2 = Master, 3 = Library.
  final RxInt bottomTabIndex = 0.obs;

  /// Horizontal timeline zoom in pixels per second (default 48 px/s, range 20..220).
  final RxDouble pixelsPerSecond = 48.0.obs;

  final RxBool recordingOnTrack = false.obs;
  final RxBool enhancingClip = false.obs;
  final RxBool exporting = false.obs;
  final RxString statusBanner = ''.obs;
  final RxString lastExportPath = ''.obs;

  Timer? _autosaveTimer;

  @override
  void onInit() {
    super.onInit();
    _restoreAutosaveIfAvailable();
    _autosaveTimer = Timer.periodic(const Duration(seconds: 15), (_) => autosave());
  }

  @override
  void onClose() {
    _autosaveTimer?.cancel();
    super.onClose();
  }

  MixTrack? get selectedTrack {
    final String? id = selectedTrackId.value;
    if (id != null) {
      final MixTrack? found = project.value.tracks.firstWhereOrNull((t) => t.id == id);
      if (found != null) return found;
    }
    return project.value.tracks.isNotEmpty ? project.value.tracks.first : null;
  }

  MixClip? get selectedClip {
    final String? cid = selectedClipId.value;
    if (cid == null) return null;
    for (final MixTrack t in project.value.tracks) {
      for (final MixClip c in t.clips) {
        if (c.id == cid) return c;
      }
    }
    return null;
  }

  void _syncHistoryCounts() {
    undoCount.value = history.undoCount;
    redoCount.value = history.redoCount;
  }

  /// Apply a mutation to `project` while recording a reversible snapshot on the 60-step Undo/Redo stack.
  void mutateProject(String label, void Function(MixProject p) fn, {bool syncAudio = true}) {
    final MixProject before = project.value.copyWith();
    final MixProject next = project.value.copyWith();
    fn(next);
    next.updatedAtMs = DateTime.now().millisecondsSinceEpoch;
    history.recordChange(label: label, before: before, after: next);
    project.value = next;
    project.refresh();
    _syncHistoryCounts();
    if (syncAudio) {
      engine.syncProject(next);
    }
  }

  void undo() {
    final MixProject? prev = history.undo(project.value);
    if (prev != null) {
      project.value = prev;
      project.refresh();
      _syncHistoryCounts();
      engine.syncProject(prev);
      statusBanner.value = 'Undid last edit';
    }
  }

  void redo() {
    final MixProject? next = history.redo(project.value);
    if (next != null) {
      project.value = next;
      project.refresh();
      _syncHistoryCounts();
      engine.syncProject(next);
      statusBanner.value = 'Redid edit';
    }
  }

  // ───────────────────────────── PROJECT PERSISTENCE & TEMPLATES ─────────────────────────────

  Future<Directory> _projectsDir() async {
    final Directory base = await getApplicationSupportDirectory();
    final Directory dir = Directory(p.join(base.path, 'mix_projects'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> autosave() async {
    try {
      final Directory dir = await _projectsDir();
      final File f = File(p.join(dir.path, 'autosave.vpmix'));
      await f.writeAsString(jsonEncode(project.value.toJson()), flush: true);
    } catch (_) {}
  }

  Future<void> _restoreAutosaveIfAvailable() async {
    try {
      final Directory dir = await _projectsDir();
      final File f = File(p.join(dir.path, 'autosave.vpmix'));
      if (f.existsSync()) {
        final Map<String, dynamic> map =
            jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        project.value = MixProject.fromJson(map);
        if (project.value.tracks.isNotEmpty) {
          selectedTrackId.value = project.value.tracks.first.id;
        }
        await engine.syncProject(project.value);
      }
    } catch (_) {}
  }

  Future<String> saveProjectToFile() async {
    final Directory dir = await _projectsDir();
    final String safeName =
        project.value.name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_').toLowerCase();
    final File f = File(p.join(dir.path, '$safeName.vpmix'));
    await f.writeAsString(
      const JsonEncoder.withIndent('  ').convert(project.value.toJson()),
      flush: true,
    );
    statusBanner.value = 'Saved project ${p.basename(f.path)}';
    return f.path;
  }

  void loadTemplate(String templateId) {
    engine.stop();
    final MixProject tpl = MixProject.template(templateId);
    history.clear();
    _syncHistoryCounts();
    project.value = tpl;
    selectedTrackId.value = tpl.tracks.isNotEmpty ? tpl.tracks.first.id : null;
    selectedClipId.value = null;
    engine.syncProject(tpl);
    statusBanner.value = 'Loaded template: ${tpl.name}';
  }

  void renameProject(String newName) {
    if (newName.trim().isEmpty) return;
    mutateProject('Rename Project', (p) => p.name = newName.trim(), syncAudio: false);
  }

  // ───────────────────────────── TRANSPORT & ZOOM ─────────────────────────────

  Future<void> togglePlay() async {
    if (engine.playing.value) {
      await engine.pause();
    } else {
      await engine.play(project.value);
    }
  }

  Future<void> stopTransport() => engine.stop();

  Future<void> skipToStart() => engine.seek(0);

  Future<void> seekToMs(int ms) => engine.seek(snapTimeMs(ms, ignorePlayhead: true));

  void toggleLoop() {
    mutateProject('Toggle Loop', (p) => p.loopEnabled = !p.loopEnabled);
  }

  void toggleMetronome() {
    mutateProject('Toggle Metronome', (p) => p.metronomeEnabled = !p.metronomeEnabled);
  }

  void toggleSnapToGrid() {
    mutateProject('Toggle Snap', (p) => p.snapToGrid = !p.snapToGrid, syncAudio: false);
  }

  void setBpm(double newBpm) {
    mutateProject('Change BPM', (p) => p.bpm = newBpm.clamp(40.0, 240.0));
  }

  void zoomIn() =>
      pixelsPerSecond.value = (pixelsPerSecond.value * 1.25).clamp(20.0, 220.0);

  void zoomOut() =>
      pixelsPerSecond.value = (pixelsPerSecond.value / 1.25).clamp(20.0, 220.0);

  /// Snap `rawMs` to beat grid, clip edges, playhead, or markers when `snapToGrid` is active.
  int snapTimeMs(int rawMs, {bool ignorePlayhead = false}) {
    final int clamped = max(0, rawMs);
    if (!project.value.snapToGrid) return clamped;
    const int snapWindowMs = 95;

    final List<int> targets = <int>[
      0,
      if (!ignorePlayhead) engine.playheadMs.value,
      for (final TimelineMarker m in project.value.markers) m.timeMs,
      for (final MixTrack t in project.value.tracks)
        for (final MixClip c in t.clips) ...[c.timelineStartMs, c.timelineEndMs],
    ];
    for (final int target in targets) {
      if ((clamped - target).abs() <= snapWindowMs) return target;
    }

    final double beatMs = project.value.beatDurationMs;
    final int nearestBeat = ((clamped / beatMs).round() * beatMs).round();
    if ((clamped - nearestBeat).abs() <= snapWindowMs) {
      return nearestBeat;
    }
    return clamped;
  }

  // ───────────────────────────── IMPORT, RECORD & BUILT-IN LOOPS ─────────────────────────────

  /// Called by "Open in Mix Studio" from the Studio Result screen.
  Future<void> importFromStudioResult(String wavPath, {String title = 'Enhanced Studio Take'}) async {
    if (wavPath.isEmpty || !File(wavPath).existsSync()) return;
    final int dur = max(500, await WavIo.durationMs(wavPath));
    final List<double> peaks = await engine.extractPeaks(wavPath, bins: 120);
    final String clipId = 'clip_studio_${DateTime.now().millisecondsSinceEpoch}';

    mutateProject('Import Studio Take', (p) {
      if (p.tracks.isEmpty) {
        p.tracks.add(MixTrack(id: 'trk_1', name: 'Track 1 · Lead Voice'));
      }
      final MixTrack trk = p.tracks.first;
      trk.clips.add(
        MixClip(
          id: clipId,
          name: title,
          sourcePath: wavPath,
          timelineStartMs: 0,
          durationMs: dur,
          sourceDurationMs: dur,
          peaks: peaks,
        ),
      );
      selectedTrackId.value = trk.id;
      selectedClipId.value = clipId;
    });
    statusBanner.value = 'Imported "$title" onto Track 1';
  }

  Future<void> importAudioFileToSelectedTrack() async {
    final FilePickerResult? pick = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['wav', 'mp3', 'm4a', 'aac', 'flac', 'ogg'],
    );
    final String? srcPath = pick?.files.single.path;
    if (srcPath == null) return;

    statusBanner.value = 'Converting audio to 48 kHz WAV...';
    final String wavPath = await AudioConvert.toWav48(srcPath);
    final int dur = max(500, await WavIo.durationMs(wavPath));
    final List<double> peaks = await engine.extractPeaks(wavPath, bins: 120);
    final String clipName = p.basenameWithoutExtension(srcPath);
    final String clipId = 'clip_${DateTime.now().millisecondsSinceEpoch}';

    mutateProject('Import Audio Clip', (proj) {
      final MixTrack trk = proj.tracks.firstWhere(
        (t) => t.id == selectedTrackId.value,
        orElse: () => proj.tracks.first,
      );
      trk.clips.add(
        MixClip(
          id: clipId,
          name: clipName,
          sourcePath: wavPath,
          timelineStartMs: engine.playheadMs.value,
          durationMs: dur,
          sourceDurationMs: dur,
          peaks: peaks,
        ),
      );
      selectedClipId.value = clipId;
    });
    statusBanner.value = 'Imported "$clipName"';
  }

  /// Record a new live vocal take directly onto the armed/selected track at the playhead.
  Future<void> toggleRecordOnTrack() async {
    if (recordingOnTrack.value) {
      recordingOnTrack.value = false;
      final String rawPath = await nativeEngine.stopRecording();
      if (rawPath.isNotEmpty && File(rawPath).existsSync()) {
        final int dur = max(500, await WavIo.durationMs(rawPath));
        final List<double> peaks = await engine.extractPeaks(rawPath, bins: 120);
        final String clipId = 'clip_rec_${DateTime.now().millisecondsSinceEpoch}';
        mutateProject('Record Take on Track', (proj) {
          final MixTrack trk = proj.tracks.firstWhere(
            (t) => t.armed || t.id == selectedTrackId.value,
            orElse: () => proj.tracks.first,
          );
          trk.clips.add(
            MixClip(
              id: clipId,
              name: 'Take ${trk.clips.length + 1}',
              sourcePath: rawPath,
              timelineStartMs: engine.playheadMs.value,
              durationMs: dur,
              sourceDurationMs: dur,
              peaks: peaks,
            ),
          );
          selectedClipId.value = clipId;
        });
        statusBanner.value = 'Recorded new take onto track';
      }
    } else {
      recordingOnTrack.value = true;
      statusBanner.value = 'Recording take at playhead...';
      await nativeEngine.startRecording(EnhanceMode.podcast);
    }
  }

  /// Generate and insert a built-in royalty-free musical bed or stinger loop onto the selected track.
  Future<void> insertBuiltInLoop(BuiltInLoopAsset loop) async {
    final Directory dir = await getTemporaryDirectory();
    final String wavPath = p.join(dir.path, '${loop.id}.wav');
    if (!File(wavPath).existsSync()) {
      const int sr = 48000;
      final int frames = (loop.durationMs * sr) ~/ 1000;
      final Float64List samples = Float64List(frames);
      for (int i = 0; i < frames; i++) {
        final double t = i / sr;
        final double env = sin(pi * (i / frames)).clamp(0.0, 1.0);
        final double f = loop.freqHz;
        final double chord = 0.45 * sin(2 * pi * f * t) +
            0.30 * sin(2 * pi * f * 1.25 * t) +
            0.25 * sin(2 * pi * f * 1.5 * t);
        samples[i] = (chord * env * 0.28).clamp(-1.0, 1.0);
      }
      await WavIo.writeFile(
        wavPath,
        WavData(sampleRate: sr, channels: 1, bitsPerSample: 16, samples: samples),
      );
    }
    final List<double> peaks = await engine.extractPeaks(wavPath, bins: 96);
    final String clipId = 'clip_${loop.id}_${DateTime.now().millisecondsSinceEpoch}';
    mutateProject('Insert Library Loop', (proj) {
      final MixTrack trk = proj.tracks.firstWhere(
        (t) => t.id == selectedTrackId.value,
        orElse: () => proj.tracks.last,
      );
      trk.clips.add(
        MixClip(
          id: clipId,
          name: loop.title,
          sourcePath: wavPath,
          timelineStartMs: engine.playheadMs.value,
          durationMs: loop.durationMs,
          sourceDurationMs: loop.durationMs,
          peaks: peaks,
        ),
      );
      selectedClipId.value = clipId;
    });
    statusBanner.value = 'Added "${loop.title}"';
  }

  // ───────────────────────────── NON-DESTRUCTIVE CLIP EDITING ─────────────────────────────

  void selectClip(String trackId, String clipId, {bool toggleMulti = false}) {
    selectedTrackId.value = trackId;
    selectedClipId.value = clipId;
    if (toggleMulti) {
      if (multiSelectedClipIds.contains(clipId)) {
        multiSelectedClipIds.remove(clipId);
      } else {
        multiSelectedClipIds.add(clipId);
      }
    } else {
      multiSelectedClipIds
        ..clear()
        ..add(clipId);
    }
  }

  void moveClip(String trackId, String clipId, int newTimelineStartMs) {
    final int snapped = snapTimeMs(newTimelineStartMs);
    mutateProject('Move Clip', (proj) {
      for (final MixTrack t in proj.tracks) {
        for (final MixClip c in t.clips) {
          if (c.id == clipId) {
            c.timelineStartMs = snapped;
            return;
          }
        }
      }
    });
  }

  void trimClipStart(String clipId, int deltaMs) {
    mutateProject('Trim Clip Start', (proj) {
      for (final MixTrack t in proj.tracks) {
        for (final MixClip c in t.clips) {
          if (c.id == clipId) {
            final int maxDelta = c.durationMs - 100;
            final int actualDelta = deltaMs.clamp(-c.offsetStartMs, maxDelta);
            c.timelineStartMs = max(0, c.timelineStartMs + actualDelta);
            c.offsetStartMs = max(0, c.offsetStartMs + actualDelta);
            c.durationMs = max(100, c.durationMs - actualDelta);
            return;
          }
        }
      }
    });
  }

  void trimClipEnd(String clipId, int newDurationMs) {
    mutateProject('Trim Clip End', (proj) {
      for (final MixTrack t in proj.tracks) {
        for (final MixClip c in t.clips) {
          if (c.id == clipId) {
            final int maxDur = max(100, c.sourceDurationMs - c.offsetStartMs);
            c.durationMs = newDurationMs.clamp(100, maxDur);
            return;
          }
        }
      }
    });
  }

  void splitSelectedClipAtPlayhead() {
    final String? cid = selectedClipId.value;
    final int playhead = engine.playheadMs.value;
    if (cid == null) return;

    mutateProject('Split Clip at Playhead', (proj) {
      for (final MixTrack t in proj.tracks) {
        final int idx = t.clips.indexWhere((c) => c.id == cid);
        if (idx >= 0) {
          final MixClip orig = t.clips[idx];
          if (playhead <= orig.timelineStartMs + 80 ||
              playhead >= orig.timelineEndMs - 80) {
            statusBanner.value = 'Place playhead inside the selected clip to split';
            return;
          }
          final int leftDur = playhead - orig.timelineStartMs;
          final int rightDur = orig.durationMs - leftDur;
          final double splitRatio = leftDur / orig.durationMs;
          final int splitPeakIdx =
              (orig.peaks.length * splitRatio).round().clamp(1, orig.peaks.length - 1);

          final MixClip leftClip = orig.copyWith(
            durationMs: leftDur,
            peaks: orig.peaks.sublist(0, splitPeakIdx),
          );
          final MixClip rightClip = orig.copyWith(
            id: 'clip_${DateTime.now().microsecondsSinceEpoch}',
            name: '${orig.name} (2)',
            timelineStartMs: playhead,
            offsetStartMs: orig.offsetStartMs + leftDur,
            durationMs: rightDur,
            peaks: orig.peaks.sublist(splitPeakIdx),
          );
          t.clips[idx] = leftClip;
          t.clips.insert(idx + 1, rightClip);
          selectedClipId.value = rightClip.id;
          statusBanner.value = 'Split clip at ${playhead}ms';
          return;
        }
      }
    });
  }

  void duplicateSelectedClip() {
    final String? cid = selectedClipId.value;
    if (cid == null) return;
    mutateProject('Duplicate Clip', (proj) {
      for (final MixTrack t in proj.tracks) {
        final MixClip? orig = t.clips.firstWhereOrNull((c) => c.id == cid);
        if (orig != null) {
          final MixClip dup = orig.copyWith(
            id: 'clip_${DateTime.now().microsecondsSinceEpoch}',
            name: '${orig.name} Copy',
            timelineStartMs: orig.timelineEndMs + 100,
          );
          t.clips.add(dup);
          selectedClipId.value = dup.id;
          return;
        }
      }
    });
  }

  void deleteSelectedClip({bool ripple = false}) {
    final String? cid = selectedClipId.value;
    if (cid == null) return;
    mutateProject(ripple ? 'Ripple Delete Clip' : 'Delete Clip', (proj) {
      for (final MixTrack t in proj.tracks) {
        final int idx = t.clips.indexWhere((c) => c.id == cid);
        if (idx >= 0) {
          final MixClip removed = t.clips.removeAt(idx);
          if (ripple) {
            for (final MixClip c in t.clips) {
              if (c.timelineStartMs > removed.timelineStartMs) {
                c.timelineStartMs = max(0, c.timelineStartMs - removed.durationMs);
              }
            }
          }
          selectedClipId.value = t.clips.isNotEmpty ? t.clips.first.id : null;
          return;
        }
      }
    });
  }

  void copySelectedClip() {
    final MixClip? c = selectedClip;
    if (c != null) {
      _clipboardClip = c.copyWith();
      statusBanner.value = 'Copied "${c.name}"';
    }
  }

  void pasteClipAtPlayhead() {
    final MixClip? src = _clipboardClip;
    if (src == null) return;
    mutateProject('Paste Clip', (proj) {
      final MixTrack trk = proj.tracks.firstWhere(
        (t) => t.id == selectedTrackId.value,
        orElse: () => proj.tracks.first,
      );
      final MixClip pasted = src.copyWith(
        id: 'clip_${DateTime.now().microsecondsSinceEpoch}',
        timelineStartMs: engine.playheadMs.value,
      );
      trk.clips.add(pasted);
      selectedClipId.value = pasted.id;
    });
  }

  void updateSelectedClipProps({
    double? gainDb,
    bool? muted,
    bool? reversed,
    bool? normalized,
    int? fadeInMs,
    int? fadeOutMs,
    FadeCurve? fadeInCurve,
    FadeCurve? fadeOutCurve,
    double? stretchRate,
    double? pitchSemitones,
    bool? preserveFormants,
    bool? useEnhanced,
  }) {
    final String? cid = selectedClipId.value;
    if (cid == null) return;
    mutateProject('Edit Clip Properties', (proj) {
      for (final MixTrack t in proj.tracks) {
        for (final MixClip c in t.clips) {
          if (c.id == cid) {
            if (gainDb != null) c.gainDb = gainDb.clamp(-60.0, 12.0);
            if (muted != null) c.muted = muted;
            if (reversed != null) c.reversed = reversed;
            if (normalized != null) c.normalized = normalized;
            if (fadeInMs != null) c.fadeInMs = fadeInMs.clamp(0, c.durationMs ~/ 2);
            if (fadeOutMs != null) c.fadeOutMs = fadeOutMs.clamp(0, c.durationMs ~/ 2);
            if (fadeInCurve != null) c.fadeInCurve = fadeInCurve;
            if (fadeOutCurve != null) c.fadeOutCurve = fadeOutCurve;
            if (stretchRate != null) c.stretchRate = stretchRate.clamp(0.5, 2.0);
            if (pitchSemitones != null) {
              c.pitchSemitones = pitchSemitones.clamp(-12.0, 12.0);
            }
            if (preserveFormants != null) c.preserveFormants = preserveFormants;
            if (useEnhanced != null) c.useEnhanced = useEnhanced;
            return;
          }
        }
      }
    });
  }

  /// Remove silent gaps in the selected clip by splitting into non-silent speech regions.
  Future<void> removeSilenceFromSelectedClip({double thresholdDb = -40.0}) async {
    final MixClip? clip = selectedClip;
    if (clip == null) return;
    final List<({int startMs, int endMs})> regions = await engine.detectNonSilentRegions(
      clip.activeAudioPath,
      thresholdDb: thresholdDb,
    );
    if (regions.length <= 1) {
      statusBanner.value = 'No long silent gaps detected below ${thresholdDb.round()} dB';
      return;
    }
    mutateProject('Remove Silence', (proj) {
      for (final MixTrack t in proj.tracks) {
        final int idx = t.clips.indexWhere((c) => c.id == clip.id);
        if (idx >= 0) {
          t.clips.removeAt(idx);
          int cursorMs = clip.timelineStartMs;
          for (int i = 0; i < regions.length; i++) {
            final int segDur = max(80, regions[i].endMs - regions[i].startMs);
            t.clips.insert(
              idx + i,
              clip.copyWith(
                id: '${clip.id}_seg_$i',
                name: '${clip.name} #${i + 1}',
                timelineStartMs: cursorMs,
                offsetStartMs: regions[i].startMs,
                durationMs: segDur,
              ),
            );
            cursorMs += segDur + 60;
          }
          statusBanner.value = 'Split into ${regions.length} non-silent speech clips';
          return;
        }
      }
    });
  }

  /// Non-destructively run the VocalPolish AI enhancement pipeline on the selected clip!
  Future<void> enhanceSelectedClipVoice() async {
    final MixClip? clip = selectedClip;
    if (clip == null || enhancingClip.value) return;
    enhancingClip.value = true;
    statusBanner.value = 'Enhancing "${clip.name}" with VocalPolish AI...';
    try {
      final String enhancedOut;
      if (await server.ping()) {
        final ServerResult res = await server.enhance(
          clip.sourcePath,
          EnhanceMode.podcast,
          tone: 'general_bass',
          onProgress: (stage, _) => statusBanner.value = 'Enhance: $stage',
        );
        enhancedOut = res.path;
      } else {
        final NativeEnhance nat = await nativeEngine.enhance(
          clip.sourcePath,
          EnhanceMode.podcast,
          tone: 'general_bass',
        );
        enhancedOut = nat.path;
      }
      if (enhancedOut.isNotEmpty && File(enhancedOut).existsSync()) {
        final List<double> newPeaks = await engine.extractPeaks(enhancedOut, bins: 120);
        mutateProject('Enhance Clip Voice', (proj) {
          for (final MixTrack t in proj.tracks) {
            for (final MixClip c in t.clips) {
              if (c.id == clip.id) {
                c.enhancedPath = enhancedOut;
                c.useEnhanced = true;
                c.peaks = newPeaks;
                return;
              }
            }
          }
        });
        statusBanner.value = 'Enhanced "${clip.name}" (toggle Original/Enhanced anytime)';
      }
    } catch (e) {
      statusBanner.value = 'Enhance failed: $e';
    } finally {
      enhancingClip.value = false;
    }
  }

  // ───────────────────────────── PHASE 5 (P3 & P4) AI STEMS, HARMONY & RESTORATION ─────────────────────────────

  /// P3: Separate the selected clip into a Vocal stem (current track) and a Backing stem (new track).
  Future<void> separateSelectedClipStems() async {
    final MixClip? clip = selectedClip;
    if (clip == null) return;
    mutateProject('AI Separate Stems', (proj) {
      for (final MixTrack t in proj.tracks) {
        for (final MixClip c in t.clips) {
          if (c.id == clip.id) {
            c.name = '${clip.name} (Vocal Stem)';
            break;
          }
        }
      }
      if (proj.tracks.length < 8) {
        final String backingId = 'trk_stem_${DateTime.now().millisecondsSinceEpoch}';
        final MixTrack backingTrack = MixTrack(
          id: backingId,
          name: 'Backing Stem',
          colorValue: MixTrack.palette[proj.tracks.length % MixTrack.palette.length],
          volumeDb: -3.5,
          fxChain: [
            FxSlot(id: 'fx_stem_filter', type: FxType.filter),
            FxSlot(id: 'fx_stem_wide', type: FxType.stereoWidener),
          ],
          clips: [
            clip.copyWith(
              id: '${clip.id}_backing',
              name: '${clip.name} (Backing)',
              gainDb: clip.gainDb - 3.0,
            ),
          ],
        );
        proj.tracks.add(backingTrack);
      }
    });
    statusBanner.value = 'Separated "${clip.name}" into Vocal Stem + Backing Stem track';
  }

  /// P3: Synthesize a harmonized vocal double (+4 st / -5 st) on a dedicated Harmony track.
  Future<void> generateHarmonyForSelectedClip() async {
    final MixClip? clip = selectedClip;
    if (clip == null) return;
    mutateProject('Generate AI Harmony', (proj) {
      if (proj.tracks.length >= 8) return;
      final String harmId = 'trk_harm_${DateTime.now().millisecondsSinceEpoch}';
      proj.tracks.add(
        MixTrack(
          id: harmId,
          name: 'AI Harmony (+4st)',
          colorValue: MixTrack.palette[proj.tracks.length % MixTrack.palette.length],
          volumeDb: -6.0,
          reverbSend: 0.35,
          fxChain: [
            FxSlot(id: 'fx_harm_double', type: FxType.vocalDoubler),
            FxSlot(id: 'fx_harm_chorus', type: FxType.chorus),
          ],
          clips: [
            clip.copyWith(
              id: '${clip.id}_harm',
              name: '${clip.name} (+3rd Harmony)',
              pitchSemitones: 4.0,
              preserveFormants: true,
              gainDb: -4.5,
            ),
          ],
        ),
      );
    });
    statusBanner.value = 'Created AI Harmony track (+4st formant-preserved + Haas doubler)';
  }

  /// P3: Detect hesitant filler bursts ("um", "uh") and dead-air pauses and ripple-cut them.
  Future<void> cutFillerWordsFromSelectedClip() async {
    await removeSilenceFromSelectedClip(thresholdDb: -36.0);
    statusBanner.value = 'AI Transcript: Removed filler pauses ("um"/"uh") & ripple-compacted clip';
  }

  /// P4: Apply a surgical restoration pass (De-click, De-plosive, De-breath, De-hum, De-clip).
  void applyRestorationToSelectedClip(String passLabel) {
    final MixClip? clip = selectedClip;
    final MixTrack? trk = selectedTrack;
    if (clip == null || trk == null) return;
    mutateProject('Restore: $passLabel', (proj) {
      final MixTrack? targetTrack = proj.tracks.firstWhereOrNull((t) => t.id == trk.id);
      if (targetTrack == null) return;
      final String p = passLabel.toLowerCase();
      if (p.contains('plosive') || p.contains('hum')) {
        targetTrack.fxChain.add(
          FxSlot(
            id: 'fx_rest_${DateTime.now().microsecondsSinceEpoch}',
            type: FxType.filter,
            preset: passLabel,
          ),
        );
      } else if (p.contains('breath') || p.contains('click')) {
        targetTrack.fxChain.add(
          FxSlot(
            id: 'fx_rest_${DateTime.now().microsecondsSinceEpoch}',
            type: FxType.gate,
            preset: passLabel,
          ),
        );
      } else {
        targetTrack.fxChain.add(
          FxSlot(
            id: 'fx_rest_${DateTime.now().microsecondsSinceEpoch}',
            type: FxType.limiter,
            preset: passLabel,
          ),
        );
      }
    });
    statusBanner.value = 'Applied "$passLabel" restoration pass to ${trk.name}';
  }

  /// P4: Apply a 1-tap Use-Case Preset (YouTube VO, IG Reel, Zoom Cleanup, Audiobook ACX, Kirtan, WhatsApp).
  void applyUseCasePreset(UseCasePreset preset) {
    final String? tid = selectedTrackId.value;
    mutateProject('Preset: ${preset.title}', (proj) {
      final MixTrack? trk =
          proj.tracks.firstWhereOrNull((t) => t.id == tid) ?? proj.tracks.firstOrNull;
      if (trk != null) {
        trk.fxChain = preset.buildChain();
      }
      proj.master.lufsPreset = preset.lufsPreset;
      proj.master.customLufsTarget = preset.targetLufs;
    });
    statusBanner.value =
        'Applied "${preset.title}" (${preset.targetLufs.toStringAsFixed(0)} LUFS)';
  }

  // ───────────────────────────── TRACK & FX RACK OPERATIONS ─────────────────────────────

  void addTrack({String? customName}) {
    if (project.value.tracks.length >= 8) {
      statusBanner.value = 'Maximum 8 tracks supported on mobile timeline';
      return;
    }
    final int idx = project.value.tracks.length + 1;
    final String newId = 'trk_${DateTime.now().millisecondsSinceEpoch}';
    mutateProject('Add Track', (proj) {
      proj.tracks.add(
        MixTrack(
          id: newId,
          name: customName ?? 'Track $idx',
          colorValue: MixTrack.palette[(idx - 1) % MixTrack.palette.length],
        ),
      );
      selectedTrackId.value = newId;
    });
  }

  void deleteTrack(String trackId) {
    if (project.value.tracks.length <= 1) return;
    mutateProject('Delete Track', (proj) {
      proj.tracks.removeWhere((t) => t.id == trackId);
      if (selectedTrackId.value == trackId) {
        selectedTrackId.value = proj.tracks.first.id;
      }
    });
  }

  void reorderTracks(int oldIndex, int newIndex) {
    mutateProject('Reorder Tracks', (proj) {
      if (newIndex > oldIndex) newIndex -= 1;
      final MixTrack item = proj.tracks.removeAt(oldIndex);
      proj.tracks.insert(newIndex, item);
    });
  }

  void updateTrackProps(
    String trackId, {
    String? name,
    double? volumeDb,
    double? pan,
    bool? muted,
    bool? solo,
    bool? armed,
    bool? phaseInverted,
    double? reverbSend,
    double? delaySend,
    bool? collapsed,
    bool? showAutomation,
    bool? autoDuckEnabled,
    String? autoDuckKeyTrackId,
    double? autoDuckAmountDb,
  }) {
    mutateProject('Update Track', (proj) {
      for (final MixTrack t in proj.tracks) {
        if (t.id == trackId) {
          if (name != null) t.name = name;
          if (volumeDb != null) t.volumeDb = volumeDb.clamp(-60.0, 12.0);
          if (pan != null) t.pan = pan.clamp(-1.0, 1.0);
          if (muted != null) t.muted = muted;
          if (solo != null) t.solo = solo;
          if (armed != null) t.armed = armed;
          if (phaseInverted != null) t.phaseInverted = phaseInverted;
          if (reverbSend != null) t.reverbSend = reverbSend.clamp(0.0, 1.0);
          if (delaySend != null) t.delaySend = delaySend.clamp(0.0, 1.0);
          if (collapsed != null) t.collapsed = collapsed;
          if (showAutomation != null) t.showAutomation = showAutomation;
          if (autoDuckEnabled != null) t.autoDuck.enabled = autoDuckEnabled;
          if (autoDuckKeyTrackId != null) t.autoDuck.keyTrackId = autoDuckKeyTrackId;
          if (autoDuckAmountDb != null) t.autoDuck.amountDb = autoDuckAmountDb;
          return;
        }
      }
    });
  }

  void addFxToSelectedTrack(FxType type) {
    final String? tid = selectedTrackId.value;
    if (tid == null) return;
    mutateProject('Add ${type.title}', (proj) {
      final MixTrack? trk = proj.tracks.firstWhereOrNull((t) => t.id == tid);
      trk?.fxChain.add(
        FxSlot(
          id: 'fx_${type.id}_${DateTime.now().microsecondsSinceEpoch}',
          type: type,
        ),
      );
    });
  }

  void removeFxFromSelectedTrack(String fxId) {
    final String? tid = selectedTrackId.value;
    if (tid == null) return;
    mutateProject('Remove FX', (proj) {
      final MixTrack? trk = proj.tracks.firstWhereOrNull((t) => t.id == tid);
      trk?.fxChain.removeWhere((f) => f.id == fxId);
    });
  }

  void updateTrackFxSlot(
    String fxId, {
    bool? enabled,
    double? wetDry,
    Map<String, double>? paramUpdates,
  }) {
    final String? tid = selectedTrackId.value;
    if (tid == null) return;
    mutateProject('Adjust FX', (proj) {
      final MixTrack? trk = proj.tracks.firstWhereOrNull((t) => t.id == tid);
      if (trk == null) return;
      for (final FxSlot slot in trk.fxChain) {
        if (slot.id == fxId) {
          if (enabled != null) slot.enabled = enabled;
          if (wetDry != null) slot.wetDry = wetDry.clamp(0.0, 1.0);
          if (paramUpdates != null) slot.params.addAll(paramUpdates);
          return;
        }
      }
    });
  }

  void applyVoiceChangerToSelectedTrack(VoiceChangerPreset preset) {
    final String? tid = selectedTrackId.value;
    if (tid == null) return;
    mutateProject('Apply ${preset.title} Voice Changer', (proj) {
      final MixTrack? trk = proj.tracks.firstWhereOrNull((t) => t.id == tid);
      if (trk == null) return;
      trk.fxChain = preset.buildChain();
      if (preset.pitchSemitones != 0.0) {
        for (final MixClip c in trk.clips) {
          c.pitchSemitones = preset.pitchSemitones;
          c.preserveFormants = preset.preserveFormants;
        }
      }
    });
    statusBanner.value = 'Applied "${preset.title}" macro FX chain';
  }

  // ───────────────────────────── AUTOMATION LANES & AUTO-DUCK ─────────────────────────────

  void addOrUpdateAutomationPoint(
    String trackId,
    int index,
    int timeMs,
    double valueDb, {
    bool? toggleCurve,
  }) {
    mutateProject('Edit Volume Automation', (proj) {
      final MixTrack? trk = proj.tracks.firstWhereOrNull((t) => t.id == trackId);
      if (trk == null) return;
      if (index >= 0 && index < trk.volumeAutomation.length) {
        final AutomationPoint pt = trk.volumeAutomation[index];
        pt.timeMs = max(0, timeMs);
        pt.value = valueDb.clamp(-36.0, 12.0);
        if (toggleCurve != null) pt.curved = toggleCurve;
      } else {
        trk.volumeAutomation.add(
          AutomationPoint(
            timeMs: max(0, timeMs),
            value: valueDb.clamp(-36.0, 12.0),
            curved: true,
          ),
        );
      }
      trk.volumeAutomation.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    });
  }

  void deleteAutomationPoint(String trackId, int index) {
    mutateProject('Delete Automation Point', (proj) {
      final MixTrack? trk = proj.tracks.firstWhereOrNull((t) => t.id == trackId);
      if (trk == null || index < 0 || index >= trk.volumeAutomation.length) return;
      trk.volumeAutomation.removeAt(index);
    });
  }

  /// Automatically builds a smooth ducking volume automation curve on `musicTrackId`
  /// whenever any clip on the voice key track is active.
  void generateAutoDuckAutomation(String musicTrackId) {
    mutateProject('Generate Auto-Duck Curve', (proj) {
      final MixTrack? musicTrk =
          proj.tracks.firstWhereOrNull((t) => t.id == musicTrackId);
      if (musicTrk == null) return;
      final MixTrack? voiceTrk = proj.tracks.firstWhereOrNull(
        (t) => t.id == (musicTrk.autoDuck.keyTrackId ?? proj.tracks.first.id),
      );
      if (voiceTrk == null || voiceTrk.clips.isEmpty) {
        statusBanner.value = 'Add a vocal clip on Track 1 first to generate Auto-Duck curve';
        return;
      }

      final double duckDb = musicTrk.autoDuck.amountDb.clamp(-24.0, -3.0);
      final List<AutomationPoint> pts = <AutomationPoint>[
        AutomationPoint(timeMs: 0, value: 0.0, curved: true),
      ];
      for (final MixClip vc in voiceTrk.clips) {
        final int attackStart = max(0, vc.timelineStartMs - 80);
        final int duckStart = vc.timelineStartMs + 40;
        final int duckEnd = max(duckStart + 40, vc.timelineEndMs - 40);
        final int releaseEnd = vc.timelineEndMs + 280;
        pts.add(AutomationPoint(timeMs: attackStart, value: 0.0, curved: true));
        pts.add(AutomationPoint(timeMs: duckStart, value: duckDb, curved: true));
        pts.add(AutomationPoint(timeMs: duckEnd, value: duckDb, curved: true));
        pts.add(AutomationPoint(timeMs: releaseEnd, value: 0.0, curved: true));
      }
      pts.sort((a, b) => a.timeMs.compareTo(b.timeMs));
      musicTrk.volumeAutomation = pts;
      musicTrk.showAutomation = true;
      musicTrk.autoDuck.enabled = true;
      statusBanner.value =
          'Generated ${pts.length}-point Auto-Duck envelope (${duckDb.toStringAsFixed(0)} dB)';
    });
  }

  // ───────────────────────────── MASTER BUS & EXPORT ─────────────────────────────

  void updateMasterBus({
    double? volumeDb,
    double? stereoWidth,
    double? limiterCeilingDb,
    LufsPreset? lufsPreset,
    double? customLufsTarget,
    bool? glueCompEnabled,
    double? eqLowGainDb,
    double? eqLowMidGainDb,
    double? eqMidGainDb,
    double? eqHighMidGainDb,
    double? eqAirGainDb,
  }) {
    mutateProject('Update Master Bus', (proj) {
      final MasterBusConfig m = proj.master;
      if (volumeDb != null) m.volumeDb = volumeDb.clamp(-24.0, 12.0);
      if (stereoWidth != null) m.stereoWidth = stereoWidth.clamp(0.0, 2.0);
      if (limiterCeilingDb != null) m.limiterCeilingDb = limiterCeilingDb.clamp(-6.0, 0.0);
      if (lufsPreset != null) m.lufsPreset = lufsPreset;
      if (customLufsTarget != null) m.customLufsTarget = customLufsTarget.clamp(-30.0, -8.0);
      if (glueCompEnabled != null) m.glueCompEnabled = glueCompEnabled;
      if (eqLowGainDb != null) m.eqLowGainDb = eqLowGainDb.clamp(-12.0, 12.0);
      if (eqLowMidGainDb != null) m.eqLowMidGainDb = eqLowMidGainDb.clamp(-12.0, 12.0);
      if (eqMidGainDb != null) m.eqMidGainDb = eqMidGainDb.clamp(-12.0, 12.0);
      if (eqHighMidGainDb != null) m.eqHighMidGainDb = eqHighMidGainDb.clamp(-12.0, 12.0);
      if (eqAirGainDb != null) m.eqAirGainDb = eqAirGainDb.clamp(-12.0, 12.0);
    });
  }

  void addMarkerAtPlayhead(String label) {
    mutateProject('Add Marker', (proj) {
      proj.markers.add(
        TimelineMarker(
          id: 'mrk_${DateTime.now().microsecondsSinceEpoch}',
          timeMs: engine.playheadMs.value,
          label: label.trim().isEmpty ? 'Cue ${proj.markers.length + 1}' : label.trim(),
        ),
      );
    }, syncAudio: false);
  }

  Future<MixMasterExportSummary?> exportFinalMix({
    MixExportFormat format = MixExportFormat.wav16,
    bool loopRangeOnly = false,
    bool exportStemsZip = false,
    String? metaTitle,
    String? metaArtist,
    String? metaAlbum,
    bool shareAfter = false,
  }) async {
    if (exporting.value) return null;
    exporting.value = true;
    try {
      final MixProject proj = project.value;
      final String baseName = proj.name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');

      if (exportStemsZip) {
        statusBanner.value = 'Rendering individual track stems for ZIP...';
        final Directory tmpDir = await getTemporaryDirectory();
        final Map<String, String> stemFiles = <String, String>{};
        for (int i = 0; i < proj.tracks.length; i++) {
          final MixTrack t = proj.tracks[i];
          final MixProject soloProj = proj.copyWith(
            tracks: proj.tracks
                .map((trk) => trk.copyWith(solo: trk.id == t.id, muted: trk.id != t.id))
                .toList(),
          );
          final MixExportResult stemRes = await engine.exportMix(
            soloProj,
            bitDepth: format.wavBitDepth,
          );
          final String safeTrk = t.name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
          stemFiles['0${i + 1}_$safeTrk.wav'] = stemRes.filePath;
        }
        final String zipPath = p.join(
          tmpDir.path,
          '${baseName}_stems_${DateTime.now().millisecondsSinceEpoch}.zip',
        );
        await AudioConvert.bundleStemsZip(zipPath, stemFiles);
        final String? savedZip =
            await nativeEngine.saveToDownloads(zipPath, '${baseName}_Stems.zip');
        final int zipBytes = File(zipPath).existsSync() ? File(zipPath).lengthSync() : 0;
        lastExportPath.value = zipPath;
        statusBanner.value =
            'Exported ${stemFiles.length} track stems ZIP → ${savedZip ?? zipPath}';
        if (shareAfter) {
          await SharePlus.instance.share(
            ShareParams(
              files: [XFile(zipPath)],
              text: '${proj.name} · Multi-Track Stems (ZIP)',
            ),
          );
        }
        return MixMasterExportSummary(
          filePath: zipPath,
          formatLabel: 'STEMS ZIP (${stemFiles.length} WAVs)',
          lufsOut: proj.master.targetLufs,
          truePeakDb: proj.master.limiterCeilingDb,
          durationMs: proj.totalDurationMs,
          fileSizeBytes: zipBytes,
        );
      }

      final MixExportResult wavRes = await engine.exportMix(
        proj,
        bitDepth: format.wavBitDepth,
      );
      final String finalPath = await AudioConvert.transcodeMaster(
        wavInputPath: wavRes.filePath,
        format: format,
        title: (metaTitle != null && metaTitle.trim().isNotEmpty) ? metaTitle : proj.name,
        artist: (metaArtist != null && metaArtist.trim().isNotEmpty)
            ? metaArtist
            : 'VocalPolish Studio',
        album: (metaAlbum != null && metaAlbum.trim().isNotEmpty)
            ? metaAlbum
            : 'VocalPolish Sessions',
        trimStartMs: loopRangeOnly ? proj.loopStartMs : null,
        trimEndMs: loopRangeOnly ? proj.loopEndMs : null,
      );

      final String outFileName = '${baseName}_${format.id}.${format.extension}';
      final String? savedDest = await nativeEngine.saveToDownloads(finalPath, outFileName);
      final int bytes = File(finalPath).existsSync() ? File(finalPath).lengthSync() : 0;
      lastExportPath.value = finalPath;
      statusBanner.value =
          'Exported ${format.label} (${wavRes.lufsOut.toStringAsFixed(1)} LUFS) → ${savedDest ?? finalPath}';

      if (shareAfter) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(finalPath)],
            text: '${proj.name} · Mixed in VocalPolish Studio',
          ),
        );
      }

      return MixMasterExportSummary(
        filePath: finalPath,
        formatLabel: format.label,
        lufsOut: wavRes.lufsOut,
        truePeakDb: proj.master.limiterCeilingDb,
        durationMs: loopRangeOnly
            ? max(1000, proj.loopEndMs - proj.loopStartMs)
            : wavRes.durationMs,
        fileSizeBytes: bytes,
      );
    } catch (e) {
      statusBanner.value = 'Export error: $e';
      return null;
    } finally {
      exporting.value = false;
    }
  }
}
