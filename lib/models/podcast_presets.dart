/// Pick-and-go filters for Podcast. Ids match the Python service and the Kotlin engine.
class PodcastTone {
  const PodcastTone(this.id, this.label, this.blurb, {this.proOnly = false});
  final String id, label, blurb;
  final bool proOnly;

  @override
  bool operator ==(Object other) => other is PodcastTone && other.id == id;

  @override
  int get hashCode => id.hashCode;

  static const generalBass = PodcastTone(
    'general_bass',
    'General + Bass',
    'Clean studio voice with warm, speaking-driven bass',
  );
  static const theatrical = PodcastTone(
    'theatrical',
    'Theatrical',
    'Voice-tuned bass, cinema-hall stereo depth',
    proOnly: true,
  );
  static const bassTreble = PodcastTone(
    'bass_treble',
    'Bass + Treble',
    'Punchy dynamic bass paired with crisp HD treble',
    proOnly: true,
  );
  static const ultraBass = PodcastTone(
    'ultra_bass',
    'Ultra Bass',
    'Deepest sub-octave chest resonance, dark and heavy',
    proOnly: true,
  );
  static const crystalTreble = PodcastTone(
    'crystal_treble',
    'Crystal Treble',
    'Ultra-crisp treble, articulation and condenser air',
    proOnly: true,
  );
  static const studioBooth = PodcastTone(
    'studio_booth',
    'Studio Booth',
    'Wide stereo acoustic booth with warm bass & treble',
    proOnly: true,
  );

  static const List<PodcastTone> all = [
    generalBass,
    theatrical,
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
