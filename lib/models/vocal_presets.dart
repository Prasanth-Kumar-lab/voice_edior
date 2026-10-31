/// Pick-and-go presets for Vocals. Ids match the Python service and the Kotlin engine.
class VocalTone {
  const VocalTone(this.id, this.label, this.blurb);
  final String id, label, blurb;

  static const natural = VocalTone('natural', 'Natural', 'Your voice, cleaned and balanced');
  static const smooth = VocalTone('smooth', 'Smooth', 'Silky, softens harshness');
  static const warm = VocalTone('warm', 'Warm', 'Fuller, rounder, intimate');
  static const bright = VocalTone('bright', 'Bright', 'Airy, forward, sparkly');
  static const deep = VocalTone('deep', 'Deep', 'Weight and body in the low end');
  static const radio = VocalTone('radio', 'Radio', 'Punchy mid-range, broadcast feel');
  static const dolby = VocalTone('dolby', 'Dolby Spatial', 'Immersive 3D vocal aura · pristine harmonic air · wide spatial depth');

  static const List<VocalTone> all = [natural, smooth, warm, bright, deep, radio, dolby];
}

class VocalSpace {
  const VocalSpace(this.id, this.label, this.blurb, {this.stereo = false});
  final String id, label, blurb;
  final bool stereo;

  static const dry = VocalSpace('dry', 'Dry', 'Clean, no space');
  static const room = VocalSpace('room', 'Studio Room', 'Close and natural', stereo: true);
  static const plate = VocalSpace('plate', 'Plate', 'Classic vocal shine', stereo: true);
  static const hall = VocalSpace('hall', 'Hall', 'Big and cinematic', stereo: true);
  static const wide = VocalSpace('wide', 'Surround', 'Wide immersive stereo field', stereo: true);
  static const dolby = VocalSpace('dolby', 'Dolby Atmos', 'Signature 3D immersive surround field', stereo: true);

  static const List<VocalSpace> all = [dry, room, plate, hall, wide, dolby];
}
