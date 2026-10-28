import 'package:flutter/material.dart';

/// All 17 DAW FX types supported per-clip, per-track, and on the master bus.
enum FxType {
  eq8('eq8', '8-Band Parametric EQ', Icons.equalizer_rounded, 'EQ & Filter'),
  compressor('compressor', 'Studio Compressor', Icons.compress_rounded, 'Dynamics'),
  gate('gate', 'Noise Gate / Expander', Icons.door_sliding_rounded, 'Dynamics'),
  deEsser('de_esser', 'Split-Band De-Esser', Icons.hearing_rounded, 'Dynamics'),
  reverb('reverb', 'Stereo Reverb', Icons.waves_rounded, 'Space'),
  delay('delay', 'Ping-Pong / Sync Delay', Icons.av_timer_rounded, 'Space'),
  chorus('chorus', 'Stereo Chorus', Icons.blur_on_rounded, 'Modulation'),
  flanger('flanger', 'Jet Flanger', Icons.air_rounded, 'Modulation'),
  phaser('phaser', '6-Stage Phaser', Icons.cyclone_rounded, 'Modulation'),
  saturator('saturator', 'Tube / Tape Saturator', Icons.local_fire_department_rounded, 'Color'),
  bitcrusher('bitcrusher', 'Lo-Fi Bitcrusher', Icons.grid_4x4_rounded, 'Color'),
  pitchCorrection('pitch_correction', 'Auto-Tune Pitch', Icons.music_note_rounded, 'Vocal'),
  vocalDoubler('vocal_doubler', 'Haas Vocal Doubler', Icons.people_alt_rounded, 'Vocal'),
  stereoWidener('stereo_widener', 'Mid/Side Widener', Icons.surround_sound_rounded, 'Space'),
  noiseReduction('noise_reduction', 'Spectral Denoiser', Icons.blur_off_rounded, 'Clean'),
  limiter('limiter', 'Lookahead Limiter', Icons.vertical_align_top_rounded, 'Master'),
  filter('filter', 'Resonant Filter (LP/HP/BP)', Icons.filter_alt_rounded, 'EQ & Filter');

  const FxType(this.id, this.title, this.icon, this.category);
  final String id;
  final String title;
  final IconData icon;
  final String category;

  static FxType fromId(String id) =>
      FxType.values.firstWhere((e) => e.id == id, orElse: () => FxType.eq8);
}

/// Single insert effect slot in a clip, track, or master FX rack.
class FxSlot {
  FxSlot({
    required this.id,
    required this.type,
    this.enabled = true,
    this.wetDry = 1.0,
    this.preset = 'Default',
    Map<String, double>? params,
  }) : params = params ?? defaultParamsFor(type);

  final String id;
  final FxType type;
  bool enabled;
  double wetDry;
  String preset;
  Map<String, double> params;

  static Map<String, double> defaultParamsFor(FxType type) {
    return switch (type) {
      FxType.eq8 => <String, double>{
          'lowCutHz': 80.0,
          'lowShelfGainDb': 1.5,
          'lowMidHz': 250.0,
          'lowMidGainDb': -1.5,
          'midHz': 1200.0,
          'midGainDb': 1.0,
          'highMidHz': 4200.0,
          'highMidGainDb': 2.0,
          'airGainDb': 2.5,
          'highCutHz': 18000.0,
        },
      FxType.compressor => <String, double>{
          'thresholdDb': -18.0,
          'ratio': 3.2,
          'attackMs': 8.0,
          'releaseMs': 110.0,
          'kneeDb': 6.0,
          'makeupDb': 2.5,
        },
      FxType.gate => <String, double>{
          'thresholdDb': -45.0,
          'floorDb': -60.0,
          'attackMs': 3.0,
          'holdMs': 90.0,
          'releaseMs': 140.0,
        },
      FxType.deEsser => <String, double>{
          'freqHz': 6800.0,
          'thresholdDb': -24.0,
          'amountDb': 7.0,
        },
      FxType.reverb => <String, double>{
          'roomType': 1.0, // 0=Room, 1=Plate, 2=Hall, 3=Chamber, 4=Cathedral, 5=Spring
          'size': 0.55,
          'decaySec': 1.4,
          'preDelayMs': 22.0,
          'damping': 0.45,
          'width': 1.0,
        },
      FxType.delay => <String, double>{
          'timeMs': 320.0,
          'feedback': 0.32,
          'pingPong': 1.0,
          'lowCutHz': 180.0,
          'highCutHz': 5200.0,
        },
      FxType.chorus => <String, double>{
          'rateHz': 0.85,
          'depthMs': 6.5,
          'voices': 3.0,
          'width': 0.9,
        },
      FxType.flanger => <String, double>{
          'rateHz': 0.35,
          'depthMs': 3.2,
          'feedback': 0.55,
        },
      FxType.phaser => <String, double>{
          'rateHz': 0.5,
          'depth': 0.75,
          'feedback': 0.45,
          'stages': 6.0,
        },
      FxType.saturator => <String, double>{
          'mode': 0.0, // 0=Tube, 1=Tape, 2=Warm, 3=Overdrive
          'driveDb': 6.0,
          'tone': 0.55,
        },
      FxType.bitcrusher => <String, double>{
          'bitDepth': 10.0,
          'downsample': 4.0,
        },
      FxType.pitchCorrection => <String, double>{
          'keyRoot': 0.0, // 0=C, 1=C#, ... 11=B
          'scaleType': 0.0, // 0=Chromatic, 1=Major, 2=Minor
          'retuneSpeedMs': 25.0,
          'humanize': 0.25,
          'formantPreserve': 1.0,
        },
      FxType.vocalDoubler => <String, double>{
          'detuneCents': 9.0,
          'haasDelayMs': 18.0,
          'width': 0.85,
        },
      FxType.stereoWidener => <String, double>{
          'width': 1.35, // 0..2.0
          'monoBassHz': 120.0,
        },
      FxType.noiseReduction => <String, double>{
          'amount': 0.65,
        },
      FxType.limiter => <String, double>{
          'ceilingDb': -1.0,
          'releaseMs': 65.0,
          'lookaheadMs': 12.0,
        },
      FxType.filter => <String, double>{
          'mode': 0.0, // 0=LP, 1=HP, 2=BP
          'cutoffHz': 2400.0,
          'resonanceQ': 1.4,
        },
    };
  }

  FxSlot copyWith({
    String? id,
    FxType? type,
    bool? enabled,
    double? wetDry,
    String? preset,
    Map<String, double>? params,
  }) =>
      FxSlot(
        id: id ?? this.id,
        type: type ?? this.type,
        enabled: enabled ?? this.enabled,
        wetDry: wetDry ?? this.wetDry,
        preset: preset ?? this.preset,
        params: Map<String, double>.from(params ?? this.params),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type.id,
        'enabled': enabled,
        'wetDry': wetDry,
        'preset': preset,
        'params': params,
      };

  factory FxSlot.fromJson(Map<String, dynamic> j) {
    final FxType t = FxType.fromId((j['type'] as String?) ?? 'eq8');
    final Map<String, double> def = defaultParamsFor(t);
    final Map<String, dynamic> rawParams =
        Map<String, dynamic>.from((j['params'] as Map?) ?? const {});
    for (final MapEntry<String, dynamic> e in rawParams.entries) {
      if (e.value is num) def[e.key] = (e.value as num).toDouble();
    }
    return FxSlot(
      id: (j['id'] as String?) ?? 'fx_${DateTime.now().microsecondsSinceEpoch}',
      type: t,
      enabled: (j['enabled'] as bool?) ?? true,
      wetDry: ((j['wetDry'] as num?) ?? 1.0).toDouble().clamp(0.0, 1.0),
      preset: (j['preset'] as String?) ?? 'Default',
      params: def,
    );
  }
}

/// 10 Creative Voice-Changer / Character Presets (Macro FX Chains).
class VoiceChangerPreset {
  const VoiceChangerPreset({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.pitchSemitones = 0.0,
    this.preserveFormants = true,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final double pitchSemitones;
  final bool preserveFormants;

  static const List<VoiceChangerPreset> all = <VoiceChangerPreset>[
    VoiceChangerPreset(
      id: 'robot',
      title: 'Robot',
      subtitle: 'Ring-mod flanger + hard zero-ms Auto-Tune',
      icon: Icons.smart_toy_rounded,
    ),
    VoiceChangerPreset(
      id: 'radio',
      title: 'Radio / Walkie',
      subtitle: '300 Hz–3.4 kHz bandpass + overdrive + comp',
      icon: Icons.radio_rounded,
    ),
    VoiceChangerPreset(
      id: 'megaphone',
      title: 'Megaphone / Lo-Fi',
      subtitle: 'Narrow horn resonance + bitcrush grit',
      icon: Icons.campaign_rounded,
    ),
    VoiceChangerPreset(
      id: 'chipmunk',
      title: 'Chipmunk',
      subtitle: '+7 semitones pitch shift with bright air',
      icon: Icons.pets_rounded,
      pitchSemitones: 7.0,
      preserveFormants: false,
    ),
    VoiceChangerPreset(
      id: 'monster',
      title: 'Deep Monster',
      subtitle: '-6 semitones + sub-bass boost + dark hall',
      icon: Icons.bolt_rounded,
      pitchSemitones: -6.0,
      preserveFormants: false,
    ),
    VoiceChangerPreset(
      id: 'synth80s',
      title: '80s Synth Lead',
      subtitle: 'Stereo chorus + slapback delay + plate',
      icon: Icons.piano_rounded,
    ),
    VoiceChangerPreset(
      id: 'angel',
      title: 'Ethereal Angel',
      subtitle: 'Shimmer octave + cathedral hall + air shelf',
      icon: Icons.auto_awesome_rounded,
    ),
    VoiceChangerPreset(
      id: 'bedroom_pop',
      title: 'Bedroom Pop',
      subtitle: 'Warm tape saturation + vocal doubler + room',
      icon: Icons.headphones_rounded,
    ),
    VoiceChangerPreset(
      id: 'asmr',
      title: 'ASMR Whisper',
      subtitle: 'De-esser + stereo widener + +6 dB 10 kHz air',
      icon: Icons.spa_rounded,
    ),
    VoiceChangerPreset(
      id: 'stadium',
      title: 'Stadium Announcer',
      subtitle: 'Band-limited + multi-tap arena echo + hall',
      icon: Icons.stadium_rounded,
    ),
  ];

  /// Build the macro FX chain corresponding to this voice-changer preset.
  List<FxSlot> buildChain() {
    final String ts = DateTime.now().microsecondsSinceEpoch.toString();
    return switch (id) {
      'robot' => <FxSlot>[
          FxSlot(
            id: 'fx_rob_pitch_$ts',
            type: FxType.pitchCorrection,
            preset: 'Hard Robot 0ms',
            params: <String, double>{
              'keyRoot': 0,
              'scaleType': 0,
              'retuneSpeedMs': 0.0,
              'humanize': 0.0,
              'formantPreserve': 0.0,
            },
          ),
          FxSlot(
            id: 'fx_rob_flg_$ts',
            type: FxType.flanger,
            preset: 'Metallic Ring',
            wetDry: 0.75,
            params: <String, double>{'rateHz': 4.5, 'depthMs': 4.8, 'feedback': 0.78},
          ),
          FxSlot(
            id: 'fx_rob_bit_$ts',
            type: FxType.bitcrusher,
            preset: '8-Bit Droid',
            wetDry: 0.45,
            params: <String, double>{'bitDepth': 8.0, 'downsample': 3.0},
          ),
        ],
      'radio' => <FxSlot>[
          FxSlot(
            id: 'fx_rad_flt_$ts',
            type: FxType.filter,
            preset: 'Walkie Bandpass',
            params: <String, double>{'mode': 2.0, 'cutoffHz': 1350.0, 'resonanceQ': 2.2},
          ),
          FxSlot(
            id: 'fx_rad_sat_$ts',
            type: FxType.saturator,
            preset: 'Transistor Drive',
            wetDry: 0.85,
            params: <String, double>{'mode': 3.0, 'driveDb': 14.0, 'tone': 0.7},
          ),
          FxSlot(
            id: 'fx_rad_cmp_$ts',
            type: FxType.compressor,
            preset: 'Squash 8:1',
            params: <String, double>{
              'thresholdDb': -26.0,
              'ratio': 8.0,
              'attackMs': 2.0,
              'releaseMs': 60.0,
              'kneeDb': 3.0,
              'makeupDb': 5.0,
            },
          ),
        ],
      'megaphone' => <FxSlot>[
          FxSlot(
            id: 'fx_meg_flt_$ts',
            type: FxType.filter,
            preset: 'Bullhorn Peak',
            params: <String, double>{'mode': 2.0, 'cutoffHz': 1850.0, 'resonanceQ': 3.4},
          ),
          FxSlot(
            id: 'fx_meg_bit_$ts',
            type: FxType.bitcrusher,
            preset: 'Lo-Fi Crunch',
            wetDry: 0.65,
            params: <String, double>{'bitDepth': 7.0, 'downsample': 5.0},
          ),
          FxSlot(
            id: 'fx_meg_dly_$ts',
            type: FxType.delay,
            preset: 'Street Slap',
            wetDry: 0.28,
            params: <String, double>{
              'timeMs': 115.0,
              'feedback': 0.22,
              'pingPong': 0.0,
              'lowCutHz': 500.0,
              'highCutHz': 3200.0,
            },
          ),
        ],
      'chipmunk' => <FxSlot>[
          FxSlot(
            id: 'fx_chp_eq_$ts',
            type: FxType.eq8,
            preset: 'Bright Helium',
            params: <String, double>{
              ...FxSlot.defaultParamsFor(FxType.eq8),
              'lowCutHz': 180.0,
              'highMidGainDb': 4.0,
              'airGainDb': 5.5,
            },
          ),
          FxSlot(
            id: 'fx_chp_cmp_$ts',
            type: FxType.compressor,
            preset: 'Pop Vocal',
          ),
        ],
      'monster' => <FxSlot>[
          FxSlot(
            id: 'fx_mon_eq_$ts',
            type: FxType.eq8,
            preset: 'Titan Sub-Bass',
            params: <String, double>{
              ...FxSlot.defaultParamsFor(FxType.eq8),
              'lowCutHz': 35.0,
              'lowShelfGainDb': 7.5,
              'lowMidGainDb': 3.5,
              'airGainDb': -3.0,
            },
          ),
          FxSlot(
            id: 'fx_mon_sat_$ts',
            type: FxType.saturator,
            preset: 'Dark Growl',
            wetDry: 0.6,
            params: <String, double>{'mode': 2.0, 'driveDb': 9.5, 'tone': 0.25},
          ),
          FxSlot(
            id: 'fx_mon_rev_$ts',
            type: FxType.reverb,
            preset: 'Abyss Hall',
            wetDry: 0.35,
            params: <String, double>{
              'roomType': 2.0,
              'size': 0.88,
              'decaySec': 2.8,
              'preDelayMs': 35.0,
              'damping': 0.72,
              'width': 1.0,
            },
          ),
        ],
      'synth80s' => <FxSlot>[
          FxSlot(
            id: 'fx_s80_cho_$ts',
            type: FxType.chorus,
            preset: 'Juno Dimension',
            wetDry: 0.65,
            params: <String, double>{
              'rateHz': 1.1,
              'depthMs': 8.5,
              'voices': 4.0,
              'width': 1.0,
            },
          ),
          FxSlot(
            id: 'fx_s80_dly_$ts',
            type: FxType.delay,
            preset: 'Slapback 140ms',
            wetDry: 0.32,
            params: <String, double>{
              'timeMs': 140.0,
              'feedback': 0.28,
              'pingPong': 1.0,
              'lowCutHz': 220.0,
              'highCutHz': 6400.0,
            },
          ),
          FxSlot(
            id: 'fx_s80_rev_$ts',
            type: FxType.reverb,
            preset: '80s Lexicon Plate',
            wetDry: 0.30,
          ),
        ],
      'angel' => <FxSlot>[
          FxSlot(
            id: 'fx_ang_eq_$ts',
            type: FxType.eq8,
            preset: 'Celestial Air',
            params: <String, double>{
              ...FxSlot.defaultParamsFor(FxType.eq8),
              'lowCutHz': 130.0,
              'airGainDb': 6.5,
            },
          ),
          FxSlot(
            id: 'fx_ang_dbl_$ts',
            type: FxType.vocalDoubler,
            preset: 'Halo Choir',
            wetDry: 0.55,
            params: <String, double>{
              'detuneCents': 12.0,
              'haasDelayMs': 24.0,
              'width': 1.0,
            },
          ),
          FxSlot(
            id: 'fx_ang_rev_$ts',
            type: FxType.reverb,
            preset: 'Cathedral Shimmer',
            wetDry: 0.48,
            params: <String, double>{
              'roomType': 4.0,
              'size': 0.94,
              'decaySec': 3.6,
              'preDelayMs': 42.0,
              'damping': 0.22,
              'width': 1.0,
            },
          ),
        ],
      'bedroom_pop' => <FxSlot>[
          FxSlot(
            id: 'fx_bed_sat_$ts',
            type: FxType.saturator,
            preset: 'Warm Cassette Tape',
            wetDry: 0.65,
            params: <String, double>{'mode': 1.0, 'driveDb': 5.5, 'tone': 0.4},
          ),
          FxSlot(
            id: 'fx_bed_dbl_$ts',
            type: FxType.vocalDoubler,
            preset: 'Intimate Double',
            wetDry: 0.42,
          ),
          FxSlot(
            id: 'fx_bed_rev_$ts',
            type: FxType.reverb,
            preset: 'Cozy Bedroom',
            wetDry: 0.22,
            params: <String, double>{
              'roomType': 0.0,
              'size': 0.35,
              'decaySec': 0.65,
              'preDelayMs': 12.0,
              'damping': 0.6,
              'width': 0.8,
            },
          ),
        ],
      'asmr' => <FxSlot>[
          FxSlot(
            id: 'fx_asm_des_$ts',
            type: FxType.deEsser,
            preset: 'Velvet Silk',
            params: <String, double>{
              'freqHz': 6200.0,
              'thresholdDb': -28.0,
              'amountDb': 9.0,
            },
          ),
          FxSlot(
            id: 'fx_asm_eq_$ts',
            type: FxType.eq8,
            preset: '10kHz Binaural Air',
            params: <String, double>{
              ...FxSlot.defaultParamsFor(FxType.eq8),
              'lowShelfGainDb': 3.0,
              'airGainDb': 6.0,
            },
          ),
          FxSlot(
            id: 'fx_asm_wid_$ts',
            type: FxType.stereoWidener,
            preset: 'Ultra Wide Ear-to-Ear',
            params: <String, double>{'width': 1.65, 'monoBassHz': 90.0},
          ),
        ],
      'stadium' || _ => <FxSlot>[
          FxSlot(
            id: 'fx_std_flt_$ts',
            type: FxType.filter,
            preset: 'PA Horn',
            params: <String, double>{'mode': 2.0, 'cutoffHz': 1400.0, 'resonanceQ': 1.5},
          ),
          FxSlot(
            id: 'fx_std_dly_$ts',
            type: FxType.delay,
            preset: 'Arena Multi-Tap 280ms',
            wetDry: 0.45,
            params: <String, double>{
              'timeMs': 280.0,
              'feedback': 0.48,
              'pingPong': 1.0,
              'lowCutHz': 300.0,
              'highCutHz': 4200.0,
            },
          ),
          FxSlot(
            id: 'fx_std_rev_$ts',
            type: FxType.reverb,
            preset: 'Wembley Bowl',
            wetDry: 0.42,
            params: <String, double>{
              'roomType': 2.0,
              'size': 0.90,
              'decaySec': 2.9,
              'preDelayMs': 48.0,
              'damping': 0.45,
              'width': 1.0,
            },
          ),
        ],
    };
  }
}
