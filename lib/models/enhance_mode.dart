import 'package:flutter/material.dart';

enum EnhanceMode { podcast, vocals }

extension EnhanceModeInfo on EnhanceMode {
  String get id => name;

  String get title => this == EnhanceMode.podcast ? 'Podcast' : 'Vocals / Sing';

  String get tagline => this == EnhanceMode.podcast
      ? 'Studio-clean speech. Strong noise and echo removal, broadcast loudness.'
      : 'Pitch-aware polish. Tuned to your voice, clean background, streaming loudness.';

  IconData get icon => this == EnhanceMode.podcast ? Icons.mic_rounded : Icons.music_note_rounded;

  String get target => this == EnhanceMode.podcast ? '-16 LUFS' : '-14 LUFS';
}
