import 'dart:math';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Studio rotary knob with vertical drag, double-tap reset, and signature arc indicator.
class VpKnob extends StatefulWidget {
  const VpKnob({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.defaultValue,
    required this.onChanged,
    this.unit = '',
    this.size = 54,
    this.bipolar = false,
    this.formatter,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final double defaultValue;
  final ValueChanged<double> onChanged;
  final String unit;
  final double size;
  final bool bipolar;
  final String Function(double)? formatter;

  @override
  State<VpKnob> createState() => _VpKnobState();
}

class _VpKnobState extends State<VpKnob> {
  bool _dragging = false;

  double get _normalized =>
      ((widget.value - widget.min) / max(1e-6, widget.max - widget.min)).clamp(0.0, 1.0);

  String get _formattedValue {
    if (widget.formatter != null) return widget.formatter!(widget.value);
    if (widget.unit == 'pan') {
      final int p = (widget.value * 100).round();
      if (p.abs() <= 2) return 'C';
      return p < 0 ? '${p.abs()}L' : '${p}R';
    }
    final String numStr = widget.value.abs() >= 100
        ? widget.value.round().toString()
        : widget.value.toStringAsFixed(1);
    return widget.unit.isEmpty ? numStr : '$numStr ${widget.unit}';
  }

  void _handleDragUpdate(DragUpdateDetails d) {
    final double span = widget.max - widget.min;
    final double delta = (-d.delta.dy / 130.0) * span;
    final double next = (widget.value + delta).clamp(widget.min, widget.max);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    final TextTheme t = Theme.of(context).textTheme;

    return GestureDetector(
      onDoubleTap: () => widget.onChanged(widget.defaultValue),
      onVerticalDragStart: (_) => setState(() => _dragging = true),
      onVerticalDragUpdate: _handleDragUpdate,
      onVerticalDragEnd: (_) => setState(() => _dragging = false),
      onVerticalDragCancel: () => setState(() => _dragging = false),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: widget.size,
            height: widget.size,
            child: CustomPaint(
              painter: _KnobPainter(
                normalized: _normalized,
                bipolar: widget.bipolar,
                active: _dragging,
                brightness: b,
              ),
              child: Center(
                child: Text(
                  _formattedValue,
                  textAlign: TextAlign.center,
                  style: t.labelSmall?.copyWith(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: _dragging ? AppColors.accentBright : AppColors.text(b),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.labelSmall?.copyWith(
              fontSize: 10,
              color: _dragging ? AppColors.accentBright : AppColors.muted(b),
            ),
          ),
        ],
      ),
    );
  }
}

class _KnobPainter extends CustomPainter {
  _KnobPainter({
    required this.normalized,
    required this.bipolar,
    required this.active,
    required this.brightness,
  });

  final double normalized;
  final bool bipolar;
  final bool active;
  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = (size.width / 2) - 4;
    const double startAngle = 0.75 * pi; // 135 deg
    const double totalSweep = 1.5 * pi; // 270 deg

    // Track background arc
    final Paint trackPaint = Paint()
      ..color = AppColors.border(brightness)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.6
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      totalSweep,
      false,
      trackPaint,
    );

    // Value arc
    final Paint arcPaint = Paint()
      ..shader = AppColors.signature.createShader(
        Rect.fromCircle(center: center, radius: radius),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = active ? 4.4 : 3.6
      ..strokeCap = StrokeCap.round;

    if (bipolar) {
      const double midAngle = startAngle + totalSweep * 0.5;
      final double sweep = (normalized - 0.5) * totalSweep;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        midAngle,
        sweep,
        false,
        arcPaint,
      );
    } else {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        normalized * totalSweep,
        false,
        arcPaint,
      );
    }

    // Inner cap
    final Paint bodyPaint = Paint()
      ..color = AppColors.surfaceAlt(brightness)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius - 5, bodyPaint);

    // Pointer tick
    final double pointerAngle = startAngle + normalized * totalSweep;
    final Offset p1 = Offset(
      center.dx + cos(pointerAngle) * (radius - 11),
      center.dy + sin(pointerAngle) * (radius - 11),
    );
    final Offset p2 = Offset(
      center.dx + cos(pointerAngle) * (radius - 5),
      center.dy + sin(pointerAngle) * (radius - 5),
    );
    canvas.drawLine(
      p1,
      p2,
      Paint()
        ..color = AppColors.accentBright
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _KnobPainter old) =>
      old.normalized != normalized ||
      old.bipolar != bipolar ||
      old.active != active ||
      old.brightness != brightness;
}
