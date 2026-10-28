import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';

/// 2D XY controller pad for simultaneous 2-parameter modulation (Reverb Size/Damp, Filter Cutoff/Resonance).
class VpXyPad extends StatelessWidget {
  const VpXyPad({
    super.key,
    required this.x,
    required this.y,
    required this.xLabel,
    required this.yLabel,
    required this.onChanged,
    this.height = 136,
  });

  /// Normalized X coordinate (0.0 .. 1.0).
  final double x;

  /// Normalized Y coordinate (0.0 .. 1.0).
  final double y;
  final String xLabel;
  final String yLabel;
  final void Function(double nx, double ny) onChanged;
  final double height;

  void _update(Offset local, Size size) {
    final double nx = (local.dx / size.width).clamp(0.0, 1.0);
    final double ny = (1.0 - (local.dy / size.height)).clamp(0.0, 1.0);
    onChanged(nx, ny);
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    final TextTheme t = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final Size padSize = Size(constraints.maxWidth, height);
        return GestureDetector(
          onTapDown: (d) => _update(d.localPosition, padSize),
          onPanUpdate: (d) => _update(d.localPosition, padSize),
          child: Container(
            height: height,
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
                    painter: _XyPadPainter(
                      x: x.clamp(0.0, 1.0),
                      y: y.clamp(0.0, 1.0),
                      brightness: b,
                    ),
                  ),
                  Positioned(
                    left: 10,
                    bottom: 6,
                    child: Text(
                      '$xLabel: ${(x * 100).round()}%',
                      style: t.labelSmall?.copyWith(color: AppColors.muted(b)),
                    ),
                  ),
                  Positioned(
                    right: 10,
                    top: 6,
                    child: Text(
                      '$yLabel: ${(y * 100).round()}%',
                      style: t.labelSmall?.copyWith(color: AppColors.accentBright),
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

class _XyPadPainter extends CustomPainter {
  _XyPadPainter({
    required this.x,
    required this.y,
    required this.brightness,
  });

  final double x;
  final double y;
  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint gridPaint = Paint()
      ..color = AppColors.border(brightness).withValues(alpha: 0.5)
      ..strokeWidth = 1;

    for (int i = 1; i <= 3; i++) {
      final double gx = size.width * (i / 4);
      final double gy = size.height * (i / 4);
      canvas.drawLine(Offset(gx, 0), Offset(gx, size.height), gridPaint);
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), gridPaint);
    }

    final Offset pt = Offset(x * size.width, (1.0 - y) * size.height);

    // Crosshairs
    final Paint crossPaint = Paint()
      ..color = AppColors.accentBright.withValues(alpha: 0.35)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(pt.dx, 0), Offset(pt.dx, size.height), crossPaint);
    canvas.drawLine(Offset(0, pt.dy), Offset(size.width, pt.dy), crossPaint);

    // Glow halo
    canvas.drawCircle(
      pt,
      20,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.accentBright.withValues(alpha: 0.42),
            AppColors.accent.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: pt, radius: 20)),
    );

    // Puck
    canvas.drawCircle(pt, 7, Paint()..color = AppColors.accentBright);
    canvas.drawCircle(pt, 3, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _XyPadPainter old) =>
      old.x != x || old.y != y || old.brightness != brightness;
}
