import 'package:flutter/material.dart';

/// Pick-and-go filters for Podcast. Ids match the Python service and the Kotlin engine.
class PodcastTone {
  const PodcastTone(
    this.id,
    this.label,
    this.blurb, {
    this.proOnly = false,
    this.tag = 'Studio',
    this.icon = Icons.graphic_eq_rounded,
  });

  final String id, label, blurb;
  final bool proOnly;
  final String tag;
  final IconData icon;

  @override
  bool operator ==(Object other) => other is PodcastTone && other.id == id;

  @override
  int get hashCode => id.hashCode;

  static const generalBass = PodcastTone(
    'general_bass',
    'Studio Clarity',
    'Neutral broadcast-mic clarity · zero bass, zero mud · every word articulate',
    tag: 'Broadcast Standard',
    icon: Icons.mic_rounded,
  );
  static const theatrical = PodcastTone(
    'theatrical',
    'Theatrical',
    'Clean cinematic presence · zero bass mud · commanding, crystal-clear voice',
    proOnly: true,
    tag: 'Cinema Clean',
    icon: Icons.movie_filter_rounded,
  );
  static const dolby = PodcastTone(
    'dolby',
    'Dolby Cinema',
    'Immersive cinema spatial field · dialogue leveling · rich sub-bass & crystal 3D air',
    proOnly: true,
    tag: 'Dolby 3D',
    icon: Icons.spatial_audio_rounded,
  );
  static const bassTreble = PodcastTone(
    'bass_treble',
    'Crisp Air & Detail',
    'Modern HD creator sound · open sparkling air · silky consonants',
    proOnly: true,
    tag: 'Modern HD Air',
    icon: Icons.air_rounded,
  );
  static const ultraBass = PodcastTone(
    'ultra_bass',
    'Warm Intimate',
    'Late-night radio · analog tube warmth · smooth, close and velvety',
    proOnly: true,
    tag: 'Analog Tube',
    icon: Icons.radio_rounded,
  );
  static const crystalTreble = PodcastTone(
    'crystal_treble',
    'Crystal Presence',
    'Maximum intelligibility · forward projection · cuts through phone speakers',
    proOnly: true,
    tag: 'Max Articulation',
    icon: Icons.record_voice_over_rounded,
  );
  static const studioBooth = PodcastTone(
    'studio_booth',
    'Studio Booth',
    'Acoustically treated booth · ultra-clean voice isolation · zero room echo',
    proOnly: true,
    tag: 'Ultra-Clean Booth',
    icon: Icons.surround_sound_rounded,
  );

  static const List<PodcastTone> all = [
    generalBass,
    theatrical,
    dolby,
    bassTreble,
    ultraBass,
    crystalTreble,
    studioBooth,
  ];
}

/// How far the voice is taken beyond "cleaned".
class EnhanceLevel {
  const EnhanceLevel(this.id, this.label, this.blurb);
  final String id, label, blurb;

  static const natural = EnhanceLevel('natural', 'Natural', 'Clean, light touch');
  static const enhanced = EnhanceLevel('enhanced', 'Enhanced', 'Clear, present, polished');
  static const max = EnhanceLevel('max', 'Studio Max', 'Full studio-condenser sound');

  static const List<EnhanceLevel> all = [natural, enhanced, max];
}
