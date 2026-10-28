import 'package:flutter/material.dart';
import '../../models/mix_track.dart';
import '../../theme/app_colors.dart';

/// Interactive timeline overlay for drawing and dragging Volume (dB) automation breakpoints.
class VpAutomationLane extends StatefulWidget {
  const VpAutomationLane({
    super.key,
    required this.points,
    required this.pixelsPerSecond,
    required this.color,
    required this.onAddOrUpdatePoint,
    required this.onDeletePointAt,
  });

  final List<AutomationPoint> points;
  final double pixelsPerSecond;
  final Color color;
  final void Function(int index, int timeMs, double valueDb, {bool? toggleCurve})
      onAddOrUpdatePoint;
  final void Function(int index) onDeletePointAt;

  @override
  State<VpAutomationLane> createState() => _VpAutomationLaneState();
}

class _VpAutomationLaneState extends State<VpAutomationLane> {
  int? _draggingIndex;

  static double _dbToNormY(double db) {
    // +12 dB -> 0.1, 0 dB -> 0.35, -36 dB -> 0.92
    final double clamped = db.clamp(-36.0, 12.0);
    return (0.35 - (clamped / 48.0) * 0.78).clamp(0.08, 0.92);
  }

  static double _normYToDb(double ny) {
    return (((0.35 - ny) / 0.78) * 48.0).clamp(-36.0, 12.0);
  }

  int? _hitTestPoint(Offset localPos, Size size) {
    for (int i = 0; i < widget.points.length; i++) {
      final AutomationPoint pt = widget.points[i];
      final double px = (pt.timeMs / 1000.0) * widget.pixelsPerSecond;
      final double py = _dbToNormY(pt.value) * size.height;
      if ((Offset(px, py) - localPos).distance <= 16.0) {
        return i;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final Size size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp: (d) {
            final int? hit = _hitTestPoint(d.localPosition, size);
            if (hit != null) {
              // Toggle S-curve vs Linear on single tap of an existing node
              final AutomationPoint p = widget.points[hit];
              widget.onAddOrUpdatePoint(
                hit,
                p.timeMs,
                p.value,
                toggleCurve: !p.curved,
              );
            } else {
              final int timeMs =
                  ((d.localPosition.dx / widget.pixelsPerSecond) * 1000).round();
              final double db = _normYToDb(d.localPosition.dy / size.height);
              widget.onAddOrUpdatePoint(-1, timeMs, db);
            }
          },
          onDoubleTapDown: (d) {
            final int? hit = _hitTestPoint(d.localPosition, size);
            if (hit != null) {
              widget.onDeletePointAt(hit);
            }
          },
          onPanStart: (d) {
            _draggingIndex = _hitTestPoint(d.localPosition, size);
          },
          onPanUpdate: (d) {
            final int? idx = _draggingIndex;
            if (idx == null || idx < 0 || idx >= widget.points.length) return;
            final int timeMs =
                ((d.localPosition.dx / widget.pixelsPerSecond) * 1000)
                    .round()
                    .clamp(0, 600000);
            final double db = _normYToDb(d.localPosition.dy / size.height);
            widget.onAddOrUpdatePoint(idx, timeMs, db);
          },
          onPanEnd: (_) => _draggingIndex = null,
          child: CustomPaint(
            size: size,
            painter: _AutomationLanePainter(
              points: widget.points,
              pixelsPerSecond: widget.pixelsPerSecond,
              color: widget.color,
            ),
          ),
        );
      },
    );
  }
}

class _AutomationLanePainter extends CustomPainter {
  _AutomationLanePainter({
    required this.points,
    required this.pixelsPerSecond,
    required this.color,
  });

  final List<AutomationPoint> points;
  final double pixelsPerSecond;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // 0 dB unity reference dashed/tinted line
    final double zeroY = _VpAutomationLaneState._dbToNormY(0.0) * size.height;
    canvas.drawLine(
      Offset(0, zeroY),
      Offset(size.width, zeroY),
      Paint()
        ..color = AppColors.warning.withValues(alpha: 0.35)
        ..strokeWidth = 1.0,
    );

    if (points.isEmpty) return;

    final List<AutomationPoint> sorted = List<AutomationPoint>.from(points)
      ..sort((a, b) => a.timeMs.compareTo(b.timeMs));

    final Path linePath = Path();
    final double firstX = (sorted.first.timeMs / 1000.0) * pixelsPerSecond;
    final double firstY =
        _VpAutomationLaneState._dbToNormY(sorted.first.value) * size.height;

    linePath.moveTo(0, firstY);
    linePath.lineTo(firstX, firstY);

    for (int i = 0; i < sorted.length - 1; i++) {
      final AutomationPoint a = sorted[i];
      final AutomationPoint b = sorted[i + 1];
      final double ax = (a.timeMs / 1000.0) * pixelsPerSecond;
      final double ay = _VpAutomationLaneState._dbToNormY(a.value) * size.height;
      final double bx = (b.timeMs / 1000.0) * pixelsPerSecond;
      final double by = _VpAutomationLaneState._dbToNormY(b.value) * size.height;

      if (a.curved) {
        final double midX = (ax + bx) * 0.5;
        linePath.cubicTo(midX, ay, midX, by, bx, by);
      } else {
        linePath.lineTo(bx, by);
      }
    }

    final double lastY =
        _VpAutomationLaneState._dbToNormY(sorted.last.value) * size.height;
    linePath.lineTo(size.width, lastY);

    canvas.drawPath(
      linePath,
      Paint()
        ..color = AppColors.warning
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // Draw breakpoint handles
    for (final AutomationPoint p in sorted) {
      final double px = (p.timeMs / 1000.0) * pixelsPerSecond;
      final double py = _VpAutomationLaneState._dbToNormY(p.value) * size.height;
      canvas.drawCircle(
        Offset(px, py),
        5.5,
        Paint()..color = p.curved ? AppColors.accentBright : AppColors.warning,
      );
      canvas.drawCircle(
        Offset(px, py),
        2.5,
        Paint()..color = Colors.black,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AutomationLanePainter oldDelegate) => true;
}
