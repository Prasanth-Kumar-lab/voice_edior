import 'dart:math';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';

/// Live stereo peak/RMS/LUFS/Correlation meter and 1/3-octave FFT spectrum analyzer for Mix Studio.
class VpMasterMeterBar extends StatelessWidget {
  const VpMasterMeterBar({
    super.key,
    required this.peakL,
    required this.peakR,
    required this.rmsL,
    required this.rmsR,
    required this.lufsMomentary,
    required this.lufsIntegrated,
    required this.truePeakDb,
    required this.correlation,
    this.clipping = false,
  });

  final double peakL;
  final double peakR;
  final double rmsL;
  final double rmsR;
  final double lufsMomentary;
  final double lufsIntegrated;
  final double truePeakDb;
  final double correlation;
  final bool clipping;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    final TextTheme t = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface(b),
        border: Border(
          top: BorderSide(color: AppColors.border(b)),
          bottom: BorderSide(color: AppColors.border(b)),
        ),
      ),
      child: Row(
        children: [
          Text(
            'MASTER',
            style: t.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.muted(b),
              letterSpacing: 0.9,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ChannelBar(label: 'L', peak: peakL, rms: rmsL, brightness: b),
                const SizedBox(height: 3),
                _ChannelBar(label: 'R', peak: peakR, rms: rmsR, brightness: b),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: AppRadius.chip,
              color: AppColors.surfaceAlt(b),
              border: Border.all(
                color: clipping ? AppColors.danger : AppColors.border(b),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  clipping ? Icons.warning_amber_rounded : Icons.speed_rounded,
                  size: 13,
                  color: clipping ? AppColors.danger : AppColors.accentBright,
                ),
                const SizedBox(width: 4),
                Text(
                  '${lufsIntegrated.toStringAsFixed(1)} LUFS',
                  style: t.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: clipping ? AppColors.danger : AppColors.text(b),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${truePeakDb.toStringAsFixed(1)} dBTP',
                  style: t.labelSmall?.copyWith(
                    fontSize: 10,
                    color: AppColors.muted(b),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelBar extends StatelessWidget {
  const _ChannelBar({
    required this.label,
    required this.peak,
    required this.rms,
    required this.brightness,
  });

  final String label;
  final double peak;
  final double rms;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 12,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: AppColors.muted(brightness),
            ),
          ),
        ),
        Expanded(
          child: SizedBox(
            height: 6,
            child: CustomPaint(
              painter: _StereoBarPainter(
                peak: peak.clamp(0.0, 1.0),
                rms: rms.clamp(0.0, 1.0),
                brightness: brightness,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StereoBarPainter extends CustomPainter {
  _StereoBarPainter({
    required this.peak,
    required this.rms,
    required this.brightness,
  });

  final double peak;
  final double rms;
  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect bg = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(3),
    );
    canvas.drawRRect(bg, Paint()..color = AppColors.surfaceAlt(brightness));

    final double rmsW = size.width * rms;
    if (rmsW > 1) {
      final RRect rRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, rmsW, size.height),
        const Radius.circular(3),
      );
      canvas.drawRRect(
        rRect,
        Paint()
          ..shader = const LinearGradient(
            colors: [
              AppColors.success,
              AppColors.accentBright,
              AppColors.warning,
              AppColors.danger,
            ],
            stops: [0.0, 0.65, 0.85, 1.0],
          ).createShader(Offset.zero & size),
      );
    }

    final double peakX = (size.width * peak).clamp(0.0, size.width - 2);
    if (peak > 0.02) {
      canvas.drawRect(
        Rect.fromLTWH(peakX, 0, 2, size.height),
        Paint()..color = peak > 0.92 ? AppColors.danger : Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StereoBarPainter old) =>
      old.peak != peak || old.rms != rms || old.brightness != brightness;
}

/// 1/3-Octave Spectrum Analyzer + Phase Correlation widget for the Master Bus panel.
class VpSpectrumAnalyzer extends StatelessWidget {
  const VpSpectrumAnalyzer({
    super.key,
    required this.bands,
    required this.correlation,
    this.height = 96,
  });

  /// 24 normalized 1/3-octave frequency magnitudes (0.0 .. 1.0).
  final List<double> bands;

  /// Stereo phase correlation (-1.0 out-of-phase .. +1.0 mono/in-phase).
  final double correlation;
  final double height;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    final TextTheme t = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: AppRadius.card,
        color: AppColors.surfaceAlt(b),
        border: Border.all(color: AppColors.border(b)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '1/3-OCTAVE FFT SPECTRUM',
                style: t.labelSmall?.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.muted(b),
                ),
              ),
              Text(
                'PHASE CORR: ${correlation >= 0 ? '+' : ''}${correlation.toStringAsFixed(2)}',
                style: t.labelSmall?.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: correlation < 0 ? AppColors.warning : AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: height,
            width: double.infinity,
            child: CustomPaint(
              painter: _SpectrumPainter(
                bands: bands.isEmpty ? List<double>.filled(24, 0.12) : bands,
                brightness: b,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final String freq in const ['40Hz', '125Hz', '500Hz', '2kHz', '8kHz', '16kHz'])
                Text(
                  freq,
                  style: t.labelSmall?.copyWith(fontSize: 9, color: AppColors.muted(b)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  _SpectrumPainter({required this.bands, required this.brightness});
  final List<double> bands;
  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final int n = bands.length;
    const double gap = 3.0;
    final double barW = max(2.0, (size.width - gap * (n - 1)) / n);
    final Paint barPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          AppColors.accent,
          AppColors.accentBright,
          AppColors.success,
        ],
      ).createShader(Offset.zero & size);

    for (int i = 0; i < n; i++) {
      final double v = bands[i].clamp(0.04, 1.0);
      final double h = v * size.height;
      final double x = i * (barW + gap);
      final RRect r = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, size.height - h, barW, h),
        const Radius.circular(2),
      );
      canvas.drawRRect(r, barPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter old) => old.bands != bands;
}
