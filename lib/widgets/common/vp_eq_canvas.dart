import 'dart:math';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';

/// Interactive 5-to-8 band parametric EQ frequency-response curve canvas with draggable nodes.
class VpEqCanvas extends StatefulWidget {
  const VpEqCanvas({
    super.key,
    required this.bandGainsDb,
    required this.onBandChanged,
    this.bandFreqsHz = const [80, 250, 1000, 4000, 12000],
    this.bandLabels = const ['80Hz', '250Hz', '1kHz', '4kHz', '12kHz'],
    this.height = 136,
  });

  /// Gain in dB (-15.0 .. +15.0) for each band.
  final List<double> bandGainsDb;
  final List<double> bandFreqsHz;
  final List<String> bandLabels;
  final void Function(int bandIndex, double newGainDb) onBandChanged;
  final double height;

  @override
  State<VpEqCanvas> createState() => _VpEqCanvasState();
}

class _VpEqCanvasState extends State<VpEqCanvas> {
  int? _activeNode;

  static double _freqToNormX(double freqHz) {
    const double minLog = 1.30103; // log10(20)
    const double maxLog = 4.30103; // log10(20000)
    final double l = log(freqHz.clamp(20.0, 20000.0)) / ln10;
    return ((l - minLog) / (maxLog - minLog)).clamp(0.04, 0.96);
  }

  static double _gainToNormY(double gainDb) {
    // +15 dB -> 0.1, 0 dB -> 0.5, -15 dB -> 0.9
    return (0.5 - (gainDb.clamp(-15.0, 15.0) / 37.5)).clamp(0.08, 0.92);
  }

  static double _normYToGain(double ny) {
    return ((0.5 - ny) * 37.5).clamp(-15.0, 15.0);
  }

  int _findNearestBand(Offset localPos, Size size) {
    int bestIdx = 0;
    double bestDist = double.infinity;
    final int n = min(widget.bandGainsDb.length, widget.bandFreqsHz.length);
    for (int i = 0; i < n; i++) {
      final double nx = _freqToNormX(widget.bandFreqsHz[i]) * size.width;
      final double ny = _gainToNormY(widget.bandGainsDb[i]) * size.height;
      final double d = (Offset(nx, ny) - localPos).distance;
      if (d < bestDist) {
        bestDist = d;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  void _updateNodeFromPosition(Offset localPos, Size size) {
    final int idx = _activeNode ?? _findNearestBand(localPos, size);
    _activeNode = idx;
    final double ny = (localPos.dy / size.height).clamp(0.08, 0.92);
    final double gainDb = _normYToGain(ny);
    widget.onBandChanged(idx, gainDb);
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    final TextTheme t = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final Size canvasSize = Size(constraints.maxWidth, widget.height);
        return GestureDetector(
          onPanStart: (d) {
            setState(() {
              _activeNode = _findNearestBand(d.localPosition, canvasSize);
            });
            _updateNodeFromPosition(d.localPosition, canvasSize);
          },
          onPanUpdate: (d) => _updateNodeFromPosition(d.localPosition, canvasSize),
          onPanEnd: (_) => setState(() => _activeNode = null),
          onDoubleTapDown: (d) {
            final int idx = _findNearestBand(d.localPosition, canvasSize);
            widget.onBandChanged(idx, 0.0);
          },
          child: Container(
            height: widget.height,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: AppRadius.card,
              color: AppColors.surfaceAlt(b),
              border: Border.all(color: AppColors.border(b)),
            ),
            child: ClipRRect(
              borderRadius: AppRadius.card,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: _EqCurvePainter(
                      gainsDb: widget.bandGainsDb,
                      freqsHz: widget.bandFreqsHz,
                      labels: widget.bandLabels,
                      activeIndex: _activeNode,
                      brightness: b,
                    ),
                  ),
                  Positioned(
                    left: 8,
                    top: 5,
                    child: Text(
                      'PARAMETRIC EQ CURVE (DRAG NODES · DOUBLE-TAP RESET)',
                      style: t.labelSmall?.copyWith(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: AppColors.muted(b),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EqCurvePainter extends CustomPainter {
  _EqCurvePainter({
    required this.gainsDb,
    required this.freqsHz,
    required this.labels,
    required this.activeIndex,
    required this.brightness,
  });

  final List<double> gainsDb;
  final List<double> freqsHz;
  final List<String> labels;
  final int? activeIndex;
  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint gridPaint = Paint()
      ..color = AppColors.border(brightness).withValues(alpha: 0.45)
      ..strokeWidth = 1.0;

    // 0 dB center line + +/- 6 dB, +/- 12 dB lines
    final double zeroY = size.height * 0.5;
    canvas.drawLine(
      Offset(0, zeroY),
      Offset(size.width, zeroY),
      Paint()
        ..color = AppColors.accentBright.withValues(alpha: 0.35)
        ..strokeWidth = 1.2,
    );
    for (final double frac in const [0.22, 0.78]) {
      final double y = size.height * frac;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final int n = min(gainsDb.length, freqsHz.length);
    if (n == 0) return;

    final List<Offset> nodes = <Offset>[];
    for (int i = 0; i < n; i++) {
      final double x = _VpEqCanvasState._freqToNormX(freqsHz[i]) * size.width;
      final double y = _VpEqCanvasState._gainToNormY(gainsDb[i]) * size.height;
      nodes.add(Offset(x, y));
      canvas.drawLine(Offset(x, 18), Offset(x, size.height - 16), gridPaint);
    }

    // Evaluate smooth composite bell/shelf response across width
    final Path curvePath = Path();
    final Path fillPath = Path()..moveTo(0, zeroY);
    const int steps = 96;
    for (int s = 0; s <= steps; s++) {
      final double px = (s / steps) * size.width;
      double totalDb = 0.0;
      for (int i = 0; i < n; i++) {
        final double distNorm = (px - nodes[i].dx) / (size.width * 0.14);
        totalDb += gainsDb[i] * exp(-0.5 * distNorm * distNorm);
      }
      final double py = _VpEqCanvasState._gainToNormY(totalDb) * size.height;
      if (s == 0) {
        curvePath.moveTo(px, py);
      } else {
        curvePath.lineTo(px, py);
      }
      fillPath.lineTo(px, py);
    }
    fillPath
      ..lineTo(size.width, zeroY)
      ..close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.accentBright.withValues(alpha: 0.26),
            AppColors.accent.withValues(alpha: 0.04),
            AppColors.accentBright.withValues(alpha: 0.22),
          ],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      curvePath,
      Paint()
        ..color = AppColors.accentBright
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );

    // Draw band nodes and frequency labels
    for (int i = 0; i < n; i++) {
      final Offset pt = nodes[i];
      final bool isActive = activeIndex == i;
      canvas.drawCircle(
        pt,
        isActive ? 9.0 : 6.5,
        Paint()..color = isActive ? AppColors.accentBright : AppColors.accent,
      );
      canvas.drawCircle(pt, 3.0, Paint()..color = Colors.white);

      if (i < labels.length) {
        final TextPainter tp = TextPainter(
          text: TextSpan(
            text: '${labels[i]} (${gainsDb[i] >= 0 ? '+' : ''}${gainsDb[i].toStringAsFixed(1)}dB)',
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
              color: isActive ? AppColors.accentBright : AppColors.muted(brightness),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(
            (pt.dx - tp.width / 2).clamp(4.0, size.width - tp.width - 4.0),
            size.height - 14,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EqCurvePainter old) => true;
}
