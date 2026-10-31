/// Live-monitor and manual Audacity-style studio chain settings (field names mirror `VocalFx.kt`).
class VocalFx {
  const VocalFx({
    this.bypass = false,
    this.inputGainDb = 0.0,
    this.hpfHz = 80.0,
    this.denoise = 0.65,
    this.gateThresholdDb = -52.0,
    this.gateOn = true,
    this.gateDepthDb = 38.0,
    this.gateReleaseMs = 120.0,
    this.deEss = 0.65,
    this.deEssHz = 6400.0,
    this.deEssOn = true,
    this.eqOn = true,
    this.eqGains = const [-3.0, 1.0, -1.5, 1.0, 2.5, 2.0, 1.5, 1.5],
    this.compOn = true,
    this.compThresholdDb = -22.0,
    this.compRatio = 2.8,
    this.compAttackMs = 10.0,
    this.compReleaseMs = 150.0,
    this.compMakeupDb = 2.0,
    this.warmth = 0.10,
    this.exciter = 0.25,
    this.reverbMix = 0.0,
    this.reverbSize = 0.45,
    this.reverbDamp = 0.50,
    this.reverbPreMs = 16.0,
    this.limiterCeilingDb = -1.0,
    this.outputGainDb = 0.0,
    this.targetLufs = -16.0,
  });

  static const List<double> kEqFrequencies = [
    60.0,
    150.0,
    400.0,
    1000.0,
    2400.0,
    5000.0,
    8000.0,
    12000.0,
  ];

  static const List<String> kEqLabels = [
    '60Hz',
    '150Hz',
    '400Hz',
    '1kHz',
    '2.4kHz',
    '5kHz',
    '8kHz',
    '12kHz',
  ];

  static const List<String> kEqRoleLabels = [
    'Sub Bass',
    'Bass Body',
    'Warmth',
    'Presence',
    'Vowel Cut',
    'Bite',
    'Air',
    'Brilliance',
  ];

  static const VocalFx podcastLive = VocalFx();
  static const VocalFx vocalsLive = VocalFx(
    denoise: 0.65,
    hpfHz: 90.0,
    gateThresholdDb: -60.0,
    deEss: 0.7,
    eqGains: [-6.0, -1.0, -2.5, 0.0, 2.6, 0.8, -1.5, 2.0],
    compThresholdDb: -22.0,
    compRatio: 3.2,
  );

  final bool bypass;
  final double inputGainDb;
  final double hpfHz;
  final double denoise;
  final double gateThresholdDb;
  final bool gateOn;
  final double gateDepthDb;
  final double gateReleaseMs;
  final double deEss;
  final double deEssHz;
  final bool deEssOn;
  final bool eqOn;
  final List<double> eqGains;
  final bool compOn;
  final double compThresholdDb;
  final double compRatio;
  final double compAttackMs;
  final double compReleaseMs;
  final double compMakeupDb;
  final double warmth;
  final double exciter;
  final double reverbMix;
  final double reverbSize;
  final double reverbDamp;
  final double reverbPreMs;
  final double limiterCeilingDb;
  final double outputGainDb;
  final double targetLufs;

  VocalFx copyWith({
    bool? bypass,
    double? inputGainDb,
    double? hpfHz,
    double? denoise,
    double? gateThresholdDb,
    bool? gateOn,
    double? gateDepthDb,
    double? gateReleaseMs,
    double? deEss,
    double? deEssHz,
    bool? deEssOn,
    bool? eqOn,
    List<double>? eqGains,
    bool? compOn,
    double? compThresholdDb,
    double? compRatio,
    double? compAttackMs,
    double? compReleaseMs,
    double? compMakeupDb,
    double? warmth,
    double? exciter,
    double? reverbMix,
    double? reverbSize,
    double? reverbDamp,
    double? reverbPreMs,
    double? limiterCeilingDb,
    double? outputGainDb,
    double? targetLufs,
  }) {
    return VocalFx(
      bypass: bypass ?? this.bypass,
      inputGainDb: inputGainDb ?? this.inputGainDb,
      hpfHz: hpfHz ?? this.hpfHz,
      denoise: denoise ?? this.denoise,
      gateThresholdDb: gateThresholdDb ?? this.gateThresholdDb,
      gateOn: gateOn ?? this.gateOn,
      gateDepthDb: gateDepthDb ?? this.gateDepthDb,
      gateReleaseMs: gateReleaseMs ?? this.gateReleaseMs,
      deEss: deEss ?? this.deEss,
      deEssHz: deEssHz ?? this.deEssHz,
      deEssOn: deEssOn ?? this.deEssOn,
      eqOn: eqOn ?? this.eqOn,
      eqGains: eqGains ?? this.eqGains,
      compOn: compOn ?? this.compOn,
      compThresholdDb: compThresholdDb ?? this.compThresholdDb,
      compRatio: compRatio ?? this.compRatio,
      compAttackMs: compAttackMs ?? this.compAttackMs,
      compReleaseMs: compReleaseMs ?? this.compReleaseMs,
      compMakeupDb: compMakeupDb ?? this.compMakeupDb,
      warmth: warmth ?? this.warmth,
      exciter: exciter ?? this.exciter,
      reverbMix: reverbMix ?? this.reverbMix,
      reverbSize: reverbSize ?? this.reverbSize,
      reverbDamp: reverbDamp ?? this.reverbDamp,
      reverbPreMs: reverbPreMs ?? this.reverbPreMs,
      limiterCeilingDb: limiterCeilingDb ?? this.limiterCeilingDb,
      outputGainDb: outputGainDb ?? this.outputGainDb,
      targetLufs: targetLufs ?? this.targetLufs,
    );
  }

  Map<String, dynamic> toMap() => {
        'bypass': bypass,
        'inputGainDb': inputGainDb,
        'denoise': denoise,
        'hpfHz': hpfHz,
        'gateOn': gateOn,
        'gateThresholdDb': gateThresholdDb,
        'gateDepthDb': gateDepthDb,
        'gateReleaseMs': gateReleaseMs,
        'deEssOn': deEssOn,
        'deEss': deEss,
        'deEssHz': deEssHz,
        'eqOn': eqOn,
        'eqGains': eqGains,
        'compOn': compOn,
        'compThresholdDb': compThresholdDb,
        'compRatio': compRatio,
        'compAttackMs': compAttackMs,
        'compReleaseMs': compReleaseMs,
        'compMakeupDb': compMakeupDb,
        'warmth': warmth,
        'exciter': exciter,
        'reverbMix': reverbMix,
        'reverbSize': reverbSize,
        'reverbDamp': reverbDamp,
        'reverbPreMs': reverbPreMs,
        'limiterCeilingDb': limiterCeilingDb,
        'outputGainDb': outputGainDb,
        'targetLufs': targetLufs,
      };
}
