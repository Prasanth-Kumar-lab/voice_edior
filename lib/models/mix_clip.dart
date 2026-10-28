import 'dart:math';
import 'fx_slot.dart';

/// Fade-in / fade-out envelope shape for clips and crossfades.
enum FadeCurve {
  linear('linear', 'Linear'),
  exponential('exponential', 'Exponential'),
  sCurve('s_curve', 'S-Curve (Equal Power)');

  const FadeCurve(this.id, this.label);
  final String id;
  final String label;

  static FadeCurve fromId(String id) =>
      FadeCurve.values.firstWhere((e) => e.id == id, orElse: () => FadeCurve.sCurve);

  /// Evaluate gain multiplier (0.0 .. 1.0) at normalized progress `t` in [0, 1].
  double gainAt(double t) {
    final double x = t.clamp(0.0, 1.0);
    return switch (this) {
      FadeCurve.linear => x,
      FadeCurve.exponential => x * x,
      FadeCurve.sCurve => sin(x * pi * 0.5),
    };
  }
}

/// Non-destructive audio clip placed on a [MixTrack] timeline.
class MixClip {
  MixClip({
    required this.id,
    required this.name,
    required this.sourcePath,
    this.enhancedPath,
    this.useEnhanced = false,
    this.timelineStartMs = 0,
    this.offsetStartMs = 0,
    required this.durationMs,
    int? sourceDurationMs,
    this.gainDb = 0.0,
    this.muted = false,
    this.reversed = false,
    this.normalized = false,
    this.fadeInMs = 20,
    this.fadeOutMs = 40,
    this.fadeInCurve = FadeCurve.sCurve,
    this.fadeOutCurve = FadeCurve.sCurve,
    this.stretchRate = 1.0,
    this.pitchSemitones = 0.0,
    this.preserveFormants = true,
    List<double>? peaks,
    List<FxSlot>? fxChain,
  })  : sourceDurationMs = sourceDurationMs ?? durationMs,
        peaks = peaks ?? List<double>.filled(96, 0.25),
        fxChain = fxChain ?? <FxSlot>[];

  final String id;
  String name;
  final String sourcePath;
  String? enhancedPath;
  bool useEnhanced;

  /// Position on the project timeline where this clip begins (milliseconds).
  int timelineStartMs;

  /// Trim offset into the source audio file where playback begins (milliseconds).
  int offsetStartMs;

  /// Active playable duration on the timeline (milliseconds).
  int durationMs;

  /// Total duration of the underlying source audio file (milliseconds).
  final int sourceDurationMs;

  /// Clip gain in dB (-60.0 to +12.0).
  double gainDb;
  bool muted;
  bool reversed;
  bool normalized;

  int fadeInMs;
  int fadeOutMs;
  FadeCurve fadeInCurve;
  FadeCurve fadeOutCurve;

  /// Time-stretch speed ratio (0.5x to 2.0x, pitch-preserving WSOLA).
  double stretchRate;

  /// Pitch shift in semitones (-12.0 to +12.0).
  double pitchSemitones;
  bool preserveFormants;

  /// Cached normalized peak amplitude bars (0.0..1.0) for fast 60fps rendering.
  List<double> peaks;

  /// Per-clip non-destructive insert FX rack.
  List<FxSlot> fxChain;

  int get timelineEndMs => timelineStartMs + durationMs;

  String get activeAudioPath =>
      (useEnhanced && enhancedPath != null && enhancedPath!.isNotEmpty)
          ? enhancedPath!
          : sourcePath;

  MixClip copyWith({
    String? id,
    String? name,
    String? sourcePath,
    String? enhancedPath,
    bool? useEnhanced,
    int? timelineStartMs,
    int? offsetStartMs,
    int? durationMs,
    int? sourceDurationMs,
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
    List<double>? peaks,
    List<FxSlot>? fxChain,
  }) =>
      MixClip(
        id: id ?? this.id,
        name: name ?? this.name,
        sourcePath: sourcePath ?? this.sourcePath,
        enhancedPath: enhancedPath ?? this.enhancedPath,
        useEnhanced: useEnhanced ?? this.useEnhanced,
        timelineStartMs: timelineStartMs ?? this.timelineStartMs,
        offsetStartMs: offsetStartMs ?? this.offsetStartMs,
        durationMs: durationMs ?? this.durationMs,
        sourceDurationMs: sourceDurationMs ?? this.sourceDurationMs,
        gainDb: gainDb ?? this.gainDb,
        muted: muted ?? this.muted,
        reversed: reversed ?? this.reversed,
        normalized: normalized ?? this.normalized,
        fadeInMs: fadeInMs ?? this.fadeInMs,
        fadeOutMs: fadeOutMs ?? this.fadeOutMs,
        fadeInCurve: fadeInCurve ?? this.fadeInCurve,
        fadeOutCurve: fadeOutCurve ?? this.fadeOutCurve,
        stretchRate: stretchRate ?? this.stretchRate,
        pitchSemitones: pitchSemitones ?? this.pitchSemitones,
        preserveFormants: preserveFormants ?? this.preserveFormants,
        peaks: List<double>.from(peaks ?? this.peaks),
        fxChain: (fxChain ?? this.fxChain).map((f) => f.copyWith()).toList(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'sourcePath': sourcePath,
        'enhancedPath': enhancedPath,
        'useEnhanced': useEnhanced,
        'timelineStartMs': timelineStartMs,
        'offsetStartMs': offsetStartMs,
        'durationMs': durationMs,
        'sourceDurationMs': sourceDurationMs,
        'gainDb': gainDb,
        'muted': muted,
        'reversed': reversed,
        'normalized': normalized,
        'fadeInMs': fadeInMs,
        'fadeOutMs': fadeOutMs,
        'fadeInCurve': fadeInCurve.id,
        'fadeOutCurve': fadeOutCurve.id,
        'stretchRate': stretchRate,
        'pitchSemitones': pitchSemitones,
        'preserveFormants': preserveFormants,
        'peaks': peaks,
        'fxChain': fxChain.map((e) => e.toJson()).toList(),
      };

  factory MixClip.fromJson(Map<String, dynamic> j) => MixClip(
        id: (j['id'] as String?) ?? 'clip_${DateTime.now().microsecondsSinceEpoch}',
        name: (j['name'] as String?) ?? 'Audio Clip',
        sourcePath: (j['sourcePath'] as String?) ?? '',
        enhancedPath: j['enhancedPath'] as String?,
        useEnhanced: (j['useEnhanced'] as bool?) ?? false,
        timelineStartMs: ((j['timelineStartMs'] as num?) ?? 0).toInt(),
        offsetStartMs: ((j['offsetStartMs'] as num?) ?? 0).toInt(),
        durationMs: max(50, ((j['durationMs'] as num?) ?? 1000).toInt()),
        sourceDurationMs: ((j['sourceDurationMs'] as num?) ?? 1000).toInt(),
        gainDb: ((j['gainDb'] as num?) ?? 0.0).toDouble(),
        muted: (j['muted'] as bool?) ?? false,
        reversed: (j['reversed'] as bool?) ?? false,
        normalized: (j['normalized'] as bool?) ?? false,
        fadeInMs: ((j['fadeInMs'] as num?) ?? 20).toInt(),
        fadeOutMs: ((j['fadeOutMs'] as num?) ?? 40).toInt(),
        fadeInCurve: FadeCurve.fromId((j['fadeInCurve'] as String?) ?? 's_curve'),
        fadeOutCurve: FadeCurve.fromId((j['fadeOutCurve'] as String?) ?? 's_curve'),
        stretchRate: ((j['stretchRate'] as num?) ?? 1.0).toDouble().clamp(0.5, 2.0),
        pitchSemitones: ((j['pitchSemitones'] as num?) ?? 0.0).toDouble().clamp(-12.0, 12.0),
        preserveFormants: (j['preserveFormants'] as bool?) ?? true,
        peaks: ((j['peaks'] as List?) ?? const [])
            .map((e) => (e as num).toDouble())
            .toList(),
        fxChain: ((j['fxChain'] as List?) ?? const [])
            .map((e) => FxSlot.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}
