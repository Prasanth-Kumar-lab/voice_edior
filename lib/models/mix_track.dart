import 'package:flutter/material.dart';
import 'fx_slot.dart';
import 'mix_clip.dart';

/// Single breakpoint on a track's Volume or Pan automation lane.
class AutomationPoint {
  AutomationPoint({
    required this.timeMs,
    required this.value,
    this.curved = false,
  });

  int timeMs;
  double value;
  bool curved;

  AutomationPoint copyWith({int? timeMs, double? value, bool? curved}) =>
      AutomationPoint(
        timeMs: timeMs ?? this.timeMs,
        value: value ?? this.value,
        curved: curved ?? this.curved,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'timeMs': timeMs,
        'value': value,
        'curved': curved,
      };

  factory AutomationPoint.fromJson(Map<String, dynamic> j) => AutomationPoint(
        timeMs: ((j['timeMs'] as num?) ?? 0).toInt(),
        value: ((j['value'] as num?) ?? 0.0).toDouble(),
        curved: (j['curved'] as bool?) ?? false,
      );
}

/// Sidechain-style Auto-Duck configuration (lowers music track when voice track speaks).
class AutoDuckConfig {
  AutoDuckConfig({
    this.enabled = false,
    this.keyTrackId,
    this.thresholdDb = -28.0,
    this.ratio = 4.0,
    this.attackMs = 25.0,
    this.releaseMs = 320.0,
    this.amountDb = -10.0,
  });

  bool enabled;
  String? keyTrackId;
  double thresholdDb;
  double ratio;
  double attackMs;
  double releaseMs;
  double amountDb;

  AutoDuckConfig copyWith({
    bool? enabled,
    String? keyTrackId,
    double? thresholdDb,
    double? ratio,
    double? attackMs,
    double? releaseMs,
    double? amountDb,
  }) =>
      AutoDuckConfig(
        enabled: enabled ?? this.enabled,
        keyTrackId: keyTrackId ?? this.keyTrackId,
        thresholdDb: thresholdDb ?? this.thresholdDb,
        ratio: ratio ?? this.ratio,
        attackMs: attackMs ?? this.attackMs,
        releaseMs: releaseMs ?? this.releaseMs,
        amountDb: amountDb ?? this.amountDb,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'enabled': enabled,
        'keyTrackId': keyTrackId,
        'thresholdDb': thresholdDb,
        'ratio': ratio,
        'attackMs': attackMs,
        'releaseMs': releaseMs,
        'amountDb': amountDb,
      };

  factory AutoDuckConfig.fromJson(Map<String, dynamic> j) => AutoDuckConfig(
        enabled: (j['enabled'] as bool?) ?? false,
        keyTrackId: j['keyTrackId'] as String?,
        thresholdDb: ((j['thresholdDb'] as num?) ?? -28.0).toDouble(),
        ratio: ((j['ratio'] as num?) ?? 4.0).toDouble(),
        attackMs: ((j['attackMs'] as num?) ?? 25.0).toDouble(),
        releaseMs: ((j['releaseMs'] as num?) ?? 320.0).toDouble(),
        amountDb: ((j['amountDb'] as num?) ?? -10.0).toDouble(),
      );
}

/// Multi-track timeline lane (supports up to 8 tracks on phone).
class MixTrack {
  MixTrack({
    required this.id,
    required this.name,
    this.colorValue = 0xFF7C6CFF,
    this.volumeDb = 0.0,
    this.pan = 0.0,
    this.muted = false,
    this.solo = false,
    this.armed = false,
    this.phaseInverted = false,
    this.inputGainDb = 0.0,
    this.reverbSend = 0.15,
    this.delaySend = 0.0,
    this.collapsed = false,
    this.showAutomation = false,
    List<MixClip>? clips,
    List<FxSlot>? fxChain,
    List<AutomationPoint>? volumeAutomation,
    List<AutomationPoint>? panAutomation,
    AutoDuckConfig? autoDuck,
  })  : clips = clips ?? <MixClip>[],
        fxChain = fxChain ?? <FxSlot>[],
        volumeAutomation = volumeAutomation ?? <AutomationPoint>[],
        panAutomation = panAutomation ?? <AutomationPoint>[],
        autoDuck = autoDuck ?? AutoDuckConfig();

  final String id;
  String name;
  int colorValue;

  /// Track fader level in dB (-60.0 to +12.0).
  double volumeDb;

  /// Constant-power stereo pan (-1.0 = 100% Left, 0.0 = Center, +1.0 = 100% Right).
  double pan;

  bool muted;
  bool solo;
  bool armed;
  bool phaseInverted;
  double inputGainDb;

  /// Shared send bus levels (0.0 to 1.0).
  double reverbSend;
  double delaySend;

  bool collapsed;
  bool showAutomation;

  List<MixClip> clips;
  List<FxSlot> fxChain;
  List<AutomationPoint> volumeAutomation;
  List<AutomationPoint> panAutomation;
  AutoDuckConfig autoDuck;

  Color get color => Color(colorValue);

  static const List<int> palette = <int>[
    0xFF7C6CFF, // Signature Violet
    0xFF22D3EE, // Electric Cyan
    0xFF34D399, // Studio Emerald
    0xFFFBBF24, // Amber Gold
    0xFFF87171, // Coral Rose
    0xFFA78BFA, // Soft Lavender
    0xFF38BDF8, // Sky Blue
    0xFFF472B6, // Neon Pink
  ];

  /// Evaluate interpolated volume automation offset (in dB) at `timeMs`.
  double automatedVolumeDbAt(int timeMs) {
    if (volumeAutomation.isEmpty) return volumeDb;
    final List<AutomationPoint> pts = List<AutomationPoint>.from(volumeAutomation)
      ..sort((a, b) => a.timeMs.compareTo(b.timeMs));
    if (timeMs <= pts.first.timeMs) return pts.first.value;
    if (timeMs >= pts.last.timeMs) return pts.last.value;
    for (int i = 0; i < pts.length - 1; i++) {
      final AutomationPoint a = pts[i];
      final AutomationPoint b = pts[i + 1];
      if (timeMs >= a.timeMs && timeMs <= b.timeMs) {
        final double span = (b.timeMs - a.timeMs).toDouble();
        if (span <= 0) return b.value;
        double t = (timeMs - a.timeMs) / span;
        if (a.curved) {
          t = t * t * (3.0 - 2.0 * t); // smoothstep S-curve
        }
        return a.value + (b.value - a.value) * t;
      }
    }
    return volumeDb;
  }

  MixTrack copyWith({
    String? id,
    String? name,
    int? colorValue,
    double? volumeDb,
    double? pan,
    bool? muted,
    bool? solo,
    bool? armed,
    bool? phaseInverted,
    double? inputGainDb,
    double? reverbSend,
    double? delaySend,
    bool? collapsed,
    bool? showAutomation,
    List<MixClip>? clips,
    List<FxSlot>? fxChain,
    List<AutomationPoint>? volumeAutomation,
    List<AutomationPoint>? panAutomation,
    AutoDuckConfig? autoDuck,
  }) =>
      MixTrack(
        id: id ?? this.id,
        name: name ?? this.name,
        colorValue: colorValue ?? this.colorValue,
        volumeDb: volumeDb ?? this.volumeDb,
        pan: pan ?? this.pan,
        muted: muted ?? this.muted,
        solo: solo ?? this.solo,
        armed: armed ?? this.armed,
        phaseInverted: phaseInverted ?? this.phaseInverted,
        inputGainDb: inputGainDb ?? this.inputGainDb,
        reverbSend: reverbSend ?? this.reverbSend,
        delaySend: delaySend ?? this.delaySend,
        collapsed: collapsed ?? this.collapsed,
        showAutomation: showAutomation ?? this.showAutomation,
        clips: (clips ?? this.clips).map((c) => c.copyWith()).toList(),
        fxChain: (fxChain ?? this.fxChain).map((f) => f.copyWith()).toList(),
        volumeAutomation:
            (volumeAutomation ?? this.volumeAutomation).map((p) => p.copyWith()).toList(),
        panAutomation:
            (panAutomation ?? this.panAutomation).map((p) => p.copyWith()).toList(),
        autoDuck: (autoDuck ?? this.autoDuck).copyWith(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'colorValue': colorValue,
        'volumeDb': volumeDb,
        'pan': pan,
        'muted': muted,
        'solo': solo,
        'armed': armed,
        'phaseInverted': phaseInverted,
        'inputGainDb': inputGainDb,
        'reverbSend': reverbSend,
        'delaySend': delaySend,
        'collapsed': collapsed,
        'showAutomation': showAutomation,
        'clips': clips.map((e) => e.toJson()).toList(),
        'fxChain': fxChain.map((e) => e.toJson()).toList(),
        'volumeAutomation': volumeAutomation.map((e) => e.toJson()).toList(),
        'panAutomation': panAutomation.map((e) => e.toJson()).toList(),
        'autoDuck': autoDuck.toJson(),
      };

  factory MixTrack.fromJson(Map<String, dynamic> j) => MixTrack(
        id: (j['id'] as String?) ?? 'trk_${DateTime.now().microsecondsSinceEpoch}',
        name: (j['name'] as String?) ?? 'Track',
        colorValue: ((j['colorValue'] as num?) ?? 0xFF7C6CFF).toInt(),
        volumeDb: ((j['volumeDb'] as num?) ?? 0.0).toDouble().clamp(-60.0, 12.0),
        pan: ((j['pan'] as num?) ?? 0.0).toDouble().clamp(-1.0, 1.0),
        muted: (j['muted'] as bool?) ?? false,
        solo: (j['solo'] as bool?) ?? false,
        armed: (j['armed'] as bool?) ?? false,
        phaseInverted: (j['phaseInverted'] as bool?) ?? false,
        inputGainDb: ((j['inputGainDb'] as num?) ?? 0.0).toDouble(),
        reverbSend: ((j['reverbSend'] as num?) ?? 0.15).toDouble().clamp(0.0, 1.0),
        delaySend: ((j['delaySend'] as num?) ?? 0.0).toDouble().clamp(0.0, 1.0),
        collapsed: (j['collapsed'] as bool?) ?? false,
        showAutomation: (j['showAutomation'] as bool?) ?? false,
        clips: ((j['clips'] as List?) ?? const [])
            .map((e) => MixClip.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        fxChain: ((j['fxChain'] as List?) ?? const [])
            .map((e) => FxSlot.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        volumeAutomation: ((j['volumeAutomation'] as List?) ?? const [])
            .map((e) => AutomationPoint.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        panAutomation: ((j['panAutomation'] as List?) ?? const [])
            .map((e) => AutomationPoint.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        autoDuck: j['autoDuck'] is Map
            ? AutoDuckConfig.fromJson(Map<String, dynamic>.from(j['autoDuck'] as Map))
            : AutoDuckConfig(),
      );
}
