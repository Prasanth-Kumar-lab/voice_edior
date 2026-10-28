import 'dart:math';
import 'fx_slot.dart';
import 'mix_clip.dart';
import 'mix_track.dart';

/// Standard streaming & broadcast LUFS loudness targets for the Master Bus.
enum LufsPreset {
  spotify14('spotify_14', 'Spotify (-14 LUFS)', -14.0),
  youtube14('youtube_14', 'YouTube (-14 LUFS)', -14.0),
  podcast16('podcast_16', 'Podcast (-16 LUFS)', -16.0),
  appleMusic16('apple_16', 'Apple Music (-16 LUFS)', -16.0),
  broadcast23('ebu_23', 'Broadcast EBU R128 (-23 LUFS)', -23.0),
  custom('custom', 'Custom LUFS', -15.0);

  const LufsPreset(this.id, this.label, this.targetLufs);
  final String id;
  final String label;
  final double targetLufs;

  static LufsPreset fromId(String id) =>
      LufsPreset.values.firstWhere((e) => e.id == id, orElse: () => LufsPreset.podcast16);
}

/// Named timeline marker / cue label for snapping and section navigation.
class TimelineMarker {
  TimelineMarker({
    required this.id,
    required this.timeMs,
    required this.label,
    this.colorValue = 0xFF22D3EE,
  });

  final String id;
  int timeMs;
  String label;
  int colorValue;

  TimelineMarker copyWith({
    String? id,
    int? timeMs,
    String? label,
    int? colorValue,
  }) =>
      TimelineMarker(
        id: id ?? this.id,
        timeMs: timeMs ?? this.timeMs,
        label: label ?? this.label,
        colorValue: colorValue ?? this.colorValue,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'timeMs': timeMs,
        'label': label,
        'colorValue': colorValue,
      };

  factory TimelineMarker.fromJson(Map<String, dynamic> j) => TimelineMarker(
        id: (j['id'] as String?) ?? 'mrk_${DateTime.now().microsecondsSinceEpoch}',
        timeMs: ((j['timeMs'] as num?) ?? 0).toInt(),
        label: (j['label'] as String?) ?? 'Marker',
        colorValue: ((j['colorValue'] as num?) ?? 0xFF22D3EE).toInt(),
      );
}

/// Master bus configuration (5-band EQ, glue compressor, stereo width, lookahead limiter, LUFS target).
class MasterBusConfig {
  MasterBusConfig({
    this.volumeDb = 0.0,
    this.stereoWidth = 1.0,
    this.limiterCeilingDb = -1.0,
    this.lufsPreset = LufsPreset.podcast16,
    this.customLufsTarget = -16.0,
    this.glueCompEnabled = true,
    this.glueThresholdDb = -14.0,
    this.glueRatio = 2.0,
    this.eqLowGainDb = 0.5,
    this.eqLowMidGainDb = 0.0,
    this.eqMidGainDb = 0.0,
    this.eqHighMidGainDb = 0.5,
    this.eqAirGainDb = 1.0,
    List<FxSlot>? fxChain,
  }) : fxChain = fxChain ??
            <FxSlot>[
              FxSlot(id: 'master_eq', type: FxType.eq8, preset: 'Master Broadcast'),
              FxSlot(id: 'master_comp', type: FxType.compressor, preset: 'Bus Glue 2:1'),
              FxSlot(id: 'master_lim', type: FxType.limiter, preset: 'Brickwall -1 dBTP'),
            ];

  double volumeDb;
  double stereoWidth;
  double limiterCeilingDb;
  LufsPreset lufsPreset;
  double customLufsTarget;

  bool glueCompEnabled;
  double glueThresholdDb;
  double glueRatio;

  double eqLowGainDb;
  double eqLowMidGainDb;
  double eqMidGainDb;
  double eqHighMidGainDb;
  double eqAirGainDb;

  List<FxSlot> fxChain;

  double get targetLufs =>
      lufsPreset == LufsPreset.custom ? customLufsTarget : lufsPreset.targetLufs;

  MasterBusConfig copyWith({
    double? volumeDb,
    double? stereoWidth,
    double? limiterCeilingDb,
    LufsPreset? lufsPreset,
    double? customLufsTarget,
    bool? glueCompEnabled,
    double? glueThresholdDb,
    double? glueRatio,
    double? eqLowGainDb,
    double? eqLowMidGainDb,
    double? eqMidGainDb,
    double? eqHighMidGainDb,
    double? eqAirGainDb,
    List<FxSlot>? fxChain,
  }) =>
      MasterBusConfig(
        volumeDb: volumeDb ?? this.volumeDb,
        stereoWidth: stereoWidth ?? this.stereoWidth,
        limiterCeilingDb: limiterCeilingDb ?? this.limiterCeilingDb,
        lufsPreset: lufsPreset ?? this.lufsPreset,
        customLufsTarget: customLufsTarget ?? this.customLufsTarget,
        glueCompEnabled: glueCompEnabled ?? this.glueCompEnabled,
        glueThresholdDb: glueThresholdDb ?? this.glueThresholdDb,
        glueRatio: glueRatio ?? this.glueRatio,
        eqLowGainDb: eqLowGainDb ?? this.eqLowGainDb,
        eqLowMidGainDb: eqLowMidGainDb ?? this.eqLowMidGainDb,
        eqMidGainDb: eqMidGainDb ?? this.eqMidGainDb,
        eqHighMidGainDb: eqHighMidGainDb ?? this.eqHighMidGainDb,
        eqAirGainDb: eqAirGainDb ?? this.eqAirGainDb,
        fxChain: (fxChain ?? this.fxChain).map((f) => f.copyWith()).toList(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'volumeDb': volumeDb,
        'stereoWidth': stereoWidth,
        'limiterCeilingDb': limiterCeilingDb,
        'lufsPreset': lufsPreset.id,
        'customLufsTarget': customLufsTarget,
        'glueCompEnabled': glueCompEnabled,
        'glueThresholdDb': glueThresholdDb,
        'glueRatio': glueRatio,
        'eqLowGainDb': eqLowGainDb,
        'eqLowMidGainDb': eqLowMidGainDb,
        'eqMidGainDb': eqMidGainDb,
        'eqHighMidGainDb': eqHighMidGainDb,
        'eqAirGainDb': eqAirGainDb,
        'fxChain': fxChain.map((e) => e.toJson()).toList(),
      };

  factory MasterBusConfig.fromJson(Map<String, dynamic> j) => MasterBusConfig(
        volumeDb: ((j['volumeDb'] as num?) ?? 0.0).toDouble(),
        stereoWidth: ((j['stereoWidth'] as num?) ?? 1.0).toDouble().clamp(0.0, 2.0),
        limiterCeilingDb:
            ((j['limiterCeilingDb'] as num?) ?? -1.0).toDouble().clamp(-6.0, 0.0),
        lufsPreset: LufsPreset.fromId((j['lufsPreset'] as String?) ?? 'podcast_16'),
        customLufsTarget: ((j['customLufsTarget'] as num?) ?? -16.0).toDouble(),
        glueCompEnabled: (j['glueCompEnabled'] as bool?) ?? true,
        glueThresholdDb: ((j['glueThresholdDb'] as num?) ?? -14.0).toDouble(),
        glueRatio: ((j['glueRatio'] as num?) ?? 2.0).toDouble(),
        eqLowGainDb: ((j['eqLowGainDb'] as num?) ?? 0.5).toDouble(),
        eqLowMidGainDb: ((j['eqLowMidGainDb'] as num?) ?? 0.0).toDouble(),
        eqMidGainDb: ((j['eqMidGainDb'] as num?) ?? 0.0).toDouble(),
        eqHighMidGainDb: ((j['eqHighMidGainDb'] as num?) ?? 0.5).toDouble(),
        eqAirGainDb: ((j['eqAirGainDb'] as num?) ?? 1.0).toDouble(),
        fxChain: ((j['fxChain'] as List?) ?? const []).isEmpty
            ? null
            : ((j['fxChain'] as List?) ?? const [])
                .map((e) => FxSlot.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList(),
      );
}

/// Versioned `.vpmix` multi-track project model (`schemaVersion: 1`).
class MixProject {
  MixProject({
    this.schemaVersion = 1,
    required this.id,
    required this.name,
    this.sampleRate = 48000,
    this.bpm = 120.0,
    this.timeSigNumerator = 4,
    this.timeSigDenominator = 4,
    this.loopEnabled = false,
    this.loopStartMs = 0,
    this.loopEndMs = 15000,
    this.metronomeEnabled = false,
    this.snapToGrid = true,
    List<MixTrack>? tracks,
    List<TimelineMarker>? markers,
    MasterBusConfig? master,
    int? createdAtMs,
    int? updatedAtMs,
  })  : tracks = tracks ?? <MixTrack>[],
        markers = markers ?? <TimelineMarker>[],
        master = master ?? MasterBusConfig(),
        createdAtMs = createdAtMs ?? DateTime.now().millisecondsSinceEpoch,
        updatedAtMs = updatedAtMs ?? DateTime.now().millisecondsSinceEpoch;

  final int schemaVersion;
  final String id;
  String name;
  final int sampleRate;
  double bpm;
  int timeSigNumerator;
  int timeSigDenominator;
  bool loopEnabled;
  int loopStartMs;
  int loopEndMs;
  bool metronomeEnabled;
  bool snapToGrid;

  List<MixTrack> tracks;
  List<TimelineMarker> markers;
  MasterBusConfig master;
  final int createdAtMs;
  int updatedAtMs;

  /// Total timeline duration across all clips (minimum 30 seconds for visual canvas).
  int get totalDurationMs {
    int maxEnd = 15000;
    for (final MixTrack t in tracks) {
      for (final MixClip c in t.clips) {
        maxEnd = max(maxEnd, c.timelineEndMs);
      }
    }
    return maxEnd;
  }

  /// Duration of one beat in milliseconds at the current BPM.
  double get beatDurationMs => 60000.0 / bpm.clamp(40.0, 240.0);

  MixProject copyWith({
    String? id,
    String? name,
    double? bpm,
    int? timeSigNumerator,
    int? timeSigDenominator,
    bool? loopEnabled,
    int? loopStartMs,
    int? loopEndMs,
    bool? metronomeEnabled,
    bool? snapToGrid,
    List<MixTrack>? tracks,
    List<TimelineMarker>? markers,
    MasterBusConfig? master,
    int? updatedAtMs,
  }) =>
      MixProject(
        schemaVersion: schemaVersion,
        id: id ?? this.id,
        name: name ?? this.name,
        sampleRate: sampleRate,
        bpm: bpm ?? this.bpm,
        timeSigNumerator: timeSigNumerator ?? this.timeSigNumerator,
        timeSigDenominator: timeSigDenominator ?? this.timeSigDenominator,
        loopEnabled: loopEnabled ?? this.loopEnabled,
        loopStartMs: loopStartMs ?? this.loopStartMs,
        loopEndMs: loopEndMs ?? this.loopEndMs,
        metronomeEnabled: metronomeEnabled ?? this.metronomeEnabled,
        snapToGrid: snapToGrid ?? this.snapToGrid,
        tracks: (tracks ?? this.tracks).map((t) => t.copyWith()).toList(),
        markers: (markers ?? this.markers).map((m) => m.copyWith()).toList(),
        master: (master ?? this.master).copyWith(),
        createdAtMs: createdAtMs,
        updatedAtMs: updatedAtMs ?? DateTime.now().millisecondsSinceEpoch,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schemaVersion': schemaVersion,
        'id': id,
        'name': name,
        'sampleRate': sampleRate,
        'bpm': bpm,
        'timeSigNumerator': timeSigNumerator,
        'timeSigDenominator': timeSigDenominator,
        'loopEnabled': loopEnabled,
        'loopStartMs': loopStartMs,
        'loopEndMs': loopEndMs,
        'metronomeEnabled': metronomeEnabled,
        'snapToGrid': snapToGrid,
        'tracks': tracks.map((e) => e.toJson()).toList(),
        'markers': markers.map((e) => e.toJson()).toList(),
        'master': master.toJson(),
        'createdAtMs': createdAtMs,
        'updatedAtMs': updatedAtMs,
      };

  factory MixProject.fromJson(Map<String, dynamic> j) => MixProject(
        schemaVersion: ((j['schemaVersion'] as num?) ?? 1).toInt(),
        id: (j['id'] as String?) ?? 'proj_${DateTime.now().millisecondsSinceEpoch}',
        name: (j['name'] as String?) ?? 'Untitled Mix Session',
        sampleRate: ((j['sampleRate'] as num?) ?? 48000).toInt(),
        bpm: ((j['bpm'] as num?) ?? 120.0).toDouble().clamp(40.0, 240.0),
        timeSigNumerator: ((j['timeSigNumerator'] as num?) ?? 4).toInt(),
        timeSigDenominator: ((j['timeSigDenominator'] as num?) ?? 4).toInt(),
        loopEnabled: (j['loopEnabled'] as bool?) ?? false,
        loopStartMs: ((j['loopStartMs'] as num?) ?? 0).toInt(),
        loopEndMs: ((j['loopEndMs'] as num?) ?? 15000).toInt(),
        metronomeEnabled: (j['metronomeEnabled'] as bool?) ?? false,
        snapToGrid: (j['snapToGrid'] as bool?) ?? true,
        tracks: ((j['tracks'] as List?) ?? const [])
            .map((e) => MixTrack.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        markers: ((j['markers'] as List?) ?? const [])
            .map((e) => TimelineMarker.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        master: j['master'] is Map
            ? MasterBusConfig.fromJson(Map<String, dynamic>.from(j['master'] as Map))
            : MasterBusConfig(),
        createdAtMs: ((j['createdAtMs'] as num?) ?? DateTime.now().millisecondsSinceEpoch)
            .toInt(),
        updatedAtMs: ((j['updatedAtMs'] as num?) ?? DateTime.now().millisecondsSinceEpoch)
            .toInt(),
      );

  /// Built-in Project Templates (Podcast Episode, Song Vocal + Backing, Voiceover + Ducking, Blank).
  static MixProject template(String templateId) {
    final String now = DateTime.now().millisecondsSinceEpoch.toString();
    return switch (templateId) {
      'podcast_episode' => MixProject(
          id: 'proj_pod_$now',
          name: 'Podcast Episode Mix',
          bpm: 110.0,
          markers: <TimelineMarker>[
            TimelineMarker(id: 'm1', timeMs: 0, label: 'Intro Theme'),
            TimelineMarker(id: 'm2', timeMs: 5000, label: 'Host Monologue'),
            TimelineMarker(id: 'm3', timeMs: 25000, label: 'Outro Bed'),
          ],
          tracks: <MixTrack>[
            MixTrack(
              id: 'trk_host',
              name: 'Host Voice',
              colorValue: MixTrack.palette[0],
              armed: true,
              fxChain: <FxSlot>[
                FxSlot(id: 'fx_h_eq', type: FxType.eq8, preset: 'Broadcast Warmth'),
                FxSlot(id: 'fx_h_cmp', type: FxType.compressor, preset: 'Voice Leveler'),
                FxSlot(id: 'fx_h_des', type: FxType.deEsser, preset: 'Smooth Sibilance'),
              ],
            ),
            MixTrack(
              id: 'trk_intro',
              name: 'Intro / Jingle',
              colorValue: MixTrack.palette[1],
              volumeDb: -3.0,
            ),
            MixTrack(
              id: 'trk_bed',
              name: 'Music Bed (Auto-Duck)',
              colorValue: MixTrack.palette[2],
              volumeDb: -9.0,
              autoDuck: AutoDuckConfig(
                enabled: true,
                keyTrackId: 'trk_host',
                thresholdDb: -30.0,
                amountDb: -12.0,
              ),
            ),
          ],
        ),
      'song_vocal' => MixProject(
          id: 'proj_song_$now',
          name: 'Vocal + Backing Mix',
          bpm: 124.0,
          master: MasterBusConfig(lufsPreset: LufsPreset.spotify14),
          tracks: <MixTrack>[
            MixTrack(
              id: 'trk_lead',
              name: 'Lead Vocal',
              colorValue: MixTrack.palette[0],
              armed: true,
              reverbSend: 0.28,
              delaySend: 0.18,
              fxChain: <FxSlot>[
                FxSlot(id: 'fx_v_pitch', type: FxType.pitchCorrection, preset: 'Modern Pop'),
                FxSlot(id: 'fx_v_eq', type: FxType.eq8, preset: 'Condenser Air'),
                FxSlot(id: 'fx_v_cmp', type: FxType.compressor, preset: 'Vocal 4:1'),
              ],
            ),
            MixTrack(
              id: 'trk_double',
              name: 'Harmony / Double',
              colorValue: MixTrack.palette[5],
              volumeDb: -4.5,
              fxChain: <FxSlot>[
                FxSlot(id: 'fx_d_dbl', type: FxType.vocalDoubler, preset: 'Wide Stereo'),
              ],
            ),
            MixTrack(
              id: 'trk_beat',
              name: 'Instrumental Stem',
              colorValue: MixTrack.palette[1],
              volumeDb: -2.0,
            ),
          ],
        ),
      'voiceover_duck' => MixProject(
          id: 'proj_vo_$now',
          name: 'Voiceover + Ducking Bed',
          bpm: 100.0,
          tracks: <MixTrack>[
            MixTrack(
              id: 'trk_vo',
              name: 'Narration Voice',
              colorValue: MixTrack.palette[0],
              armed: true,
              fxChain: <FxSlot>[
                FxSlot(id: 'fx_vo_gate', type: FxType.gate, preset: 'Silent Floor'),
                FxSlot(id: 'fx_vo_eq', type: FxType.eq8, preset: 'Cinema Trailer'),
                FxSlot(id: 'fx_vo_cmp', type: FxType.compressor, preset: 'Broadcast Punch'),
              ],
            ),
            MixTrack(
              id: 'trk_music',
              name: 'Cinematic Score',
              colorValue: MixTrack.palette[3],
              volumeDb: -6.0,
              autoDuck: AutoDuckConfig(
                enabled: true,
                keyTrackId: 'trk_vo',
                thresholdDb: -28.0,
                amountDb: -11.0,
              ),
            ),
          ],
        ),
      'blank' || _ => MixProject(
          id: 'proj_blank_$now',
          name: 'Studio Mix Session',
          bpm: 120.0,
          tracks: <MixTrack>[
            MixTrack(
              id: 'trk_1',
              name: 'Track 1 · Lead Voice',
              colorValue: MixTrack.palette[0],
              armed: true,
            ),
            MixTrack(
              id: 'trk_2',
              name: 'Track 2 · Music / Backing',
              colorValue: MixTrack.palette[1],
              volumeDb: -4.0,
              autoDuck: AutoDuckConfig(
                enabled: true,
                keyTrackId: 'trk_1',
                thresholdDb: -28.0,
                amountDb: -10.0,
              ),
            ),
          ],
        ),
    };
  }
}
