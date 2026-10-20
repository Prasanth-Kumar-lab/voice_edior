import 'dart:math';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class VpWaveform extends StatefulWidget {
  const VpWaveform({
    super.key,
    required this.samples,
    this.progress = 0,
    this.live = false,
    this.height = 88,
    this.trimStart = 0,
    this.trimEnd = 1,
    this.showTrim = false,
    this.onScrub,
    this.onTrimStart,
    this.onTrimEnd,
  });

  final List<double> samples;
  final double progress;
  final bool live;
  final double height;
  final double trimStart;
  final double trimEnd;
  final bool showTrim;
  final ValueChanged<double>? onScrub;
  final ValueChanged<double>? onTrimStart;
  final ValueChanged<double>? onTrimEnd;

  @override
  State<VpWaveform> createState() => _VpWaveformState();
}

class _VpWaveformState extends State<VpWaveform> {
  String? _drag;

  double _t(Offset local, BoxConstraints c) => (local.dx / c.maxWidth).clamp(0.0, 1.0);

  void _down(Offset local, BoxConstraints c) {
    final double t = _t(local, c);
    if (widget.showTrim) {
      if ((t - widget.trimStart).abs() < 0.045) {
        _drag = 'start';
        widget.onTrimStart?.call(t);
        return;
      }
      if ((t - widget.trimEnd).abs() < 0.045) {
        _drag = 'end';
        widget.onTrimEnd?.call(t);
        return;
      }
    }
    _drag = 'scrub';
    widget.onScrub?.call(t);
  }

  void _move(Offset local, BoxConstraints c) {
    final double t = _t(local, c);
    if (_drag == 'start') {
      widget.onTrimStart?.call(min(t, widget.trimEnd - 0.02));
    } else if (_drag == 'end') {
      widget.onTrimEnd?.call(max(t, widget.trimStart + 0.02));
    } else {
      widget.onScrub?.call(t);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        return GestureDetector(
          onTapDown: (d) => _down(d.localPosition, c),
          onHorizontalDragStart: (d) => _down(d.localPosition, c),
          onHorizontalDragUpdate: (d) => _move(d.localPosition, c),
          onHorizontalDragEnd: (_) => _drag = null,
          child: SizedBox(
            height: widget.height,
            width: double.infinity,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: WaveformPainter(
                  samples: widget.samples.isEmpty ? const [0.2, 0.4, 0.3] : widget.samples,
                  progress: widget.progress,
                  live: widget.live,
                  trimStart: widget.trimStart,
                  trimEnd: widget.trimEnd,
                  showTrim: widget.showTrim,
                  accent: AppColors.accent,
                  accent2: AppColors.accentBright,
                  dim: AppColors.muted(Theme.of(context).brightness).withValues(alpha: 0.35),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class WaveformPainter extends CustomPainter {
  WaveformPainter({
    required this.samples,
    required this.progress,
    required this.live,
    required this.trimStart,
    required this.trimEnd,
    required this.showTrim,
    required this.accent,
    required this.accent2,
    required this.dim,
  });

  final List<double> samples;
  final double progress;
  final bool live;
  final double trimStart;
  final double trimEnd;
  final bool showTrim;
  final Color accent;
  final Color accent2;
  final Color dim;

  @override
  void paint(Canvas canvas, Size size) {
    final int n = samples.length;
    final double gap = 1.6;
    final double barW = max(1.5, (size.width - gap * (n - 1)) / n);
    final Paint played = Paint()
      ..shader = LinearGradient(colors: [accent, accent2]).createShader(Offset.zero & size);
    final Paint rest = Paint()..color = dim;
    final Paint outside = Paint()..color = dim.withValues(alpha: 0.22);

    for (int i = 0; i < n; i++) {
      final double t = n == 1 ? 0 : i / (n - 1);
      final double amp = samples[i].clamp(0.05, 1);
      final double h = amp * size.height * 0.92;
      final double x = i * (barW + gap);
      final double y = (size.height - h) / 2;
      final RRect r = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barW, h),
        const Radius.circular(1.8),
      );
      final bool inTrim = !showTrim || (t >= trimStart && t <= trimEnd);
      canvas.drawRRect(r, !inTrim ? outside : (t <= progress || live ? played : rest));
    }

    if (progress > 0 && !live) {
      final double px = progress * size.width;
      canvas.drawLine(
        Offset(px, 0),
        Offset(px, size.height),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.9)
          ..strokeWidth = 1.5,
      );
    }

    if (showTrim) {
      _handle(canvas, size, trimStart);
      _handle(canvas, size, trimEnd);
    }
  }

  void _handle(Canvas canvas, Size size, double t) {
    final double x = t * size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, size.height / 2), width: 5, height: size.height),
        const Radius.circular(2),
      ),
      Paint()..color = accent2,
    );
  }

  @override
  bool shouldRepaint(covariant WaveformPainter old) =>
      old.samples != samples ||
      old.progress != progress ||
      old.live != live ||
      old.trimStart != trimStart ||
      old.trimEnd != trimEnd;
}
