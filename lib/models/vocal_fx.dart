/// Live-monitor chain settings sent to the native engine (field names mirror `VocalFx.kt`).
/// The offline premium result is produced by the Python service or the native `Enhancer`, not by these.
class VocalFx {
  const VocalFx({
    this.denoise = 0.8,
    this.hpfHz = 80,
    this.gateOn = true,
    this.gateThresholdDb = -56,
    this.deEss = 0.6,
    this.deEssHz = 6500,
    this.eqGains = const [-5, -1.5, -2.5, 0.5, 3, 1.5, -1.5, 1.5],
    this.compThresholdDb = -24,
    this.compRatio = 3,
    this.compMakeupDb = 3,
  });

  final double denoise;
  final double hpfHz;
  final bool gateOn;
  final double gateThresholdDb;
  final double deEss;
  final double deEssHz;
  final List<double> eqGains;
  final double compThresholdDb;
  final double compRatio;
  final double compMakeupDb;

  static const VocalFx podcastLive = VocalFx();
  static const VocalFx vocalsLive = VocalFx(
    denoise: 0.65,
    hpfHz: 90,
    gateThresholdDb: -60,
    deEss: 0.7,
    eqGains: [-6, -1, -2.5, 0, 2.6, 0.8, -1.5, 2],
    compThresholdDb: -22,
    compRatio: 3.2,
  );

  Map<String, dynamic> toMap() => {
        'denoise': denoise,
        'hpfHz': hpfHz,
        'gateOn': gateOn,
        'gateThresholdDb': gateThresholdDb,
        'deEssOn': true,
        'deEss': deEss,
        'deEssHz': deEssHz,
        'eqOn': true,
        'eqGains': eqGains,
        'compOn': true,
        'compThresholdDb': compThresholdDb,
        'compRatio': compRatio,
        'compMakeupDb': compMakeupDb,
      };
}
