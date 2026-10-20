import 'dart:math';

List<double> generateWaveform({int bars = 96, int seed = 7}) {
  final Random r = Random(seed);
  return List<double>.generate(bars, (i) {
    final double envelope = sin((i / bars) * pi);
    return (0.18 + r.nextDouble() * 0.82) * envelope.clamp(0.15, 1);
  });
}

List<double> downsample(List<double> samples, int bars) {
  if (samples.isEmpty) return generateWaveform(bars: bars);
  if (samples.length <= bars) return samples;
  final double step = samples.length / bars;
  return List<double>.generate(bars, (i) {
    final int start = (i * step).floor();
    final int end = min(samples.length, ((i + 1) * step).ceil());
    double peak = 0;
    for (int j = start; j < end; j++) {
      peak = max(peak, samples[j].abs());
    }
    return peak;
  });
}
