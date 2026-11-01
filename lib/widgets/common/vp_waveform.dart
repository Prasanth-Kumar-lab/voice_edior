import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Pro-grade audio waveform widget with interactive scrubbing, dual trim handles,
/// reactive live recording mode with pulsing aura, and a polishing shimmer sweep.
class VpWaveform extends StatefulWidget {
  const VpWaveform({
    super.key,
    required this.samples,
    this.progress = 0,
    this.live = false,
    this.polishing = false,
    this.polishProgress = 0.0,
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
  final bool polishing;
  final double polishProgress;
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

class _VpWaveformState extends State<VpWaveform> with SingleTickerProviderStateMixin {
  String? _drag;
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    if (widget.live || widget.polishing) {
      _pulseCtrl.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(VpWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.live || widget.polishing) && !_pulseCtrl.isAnimating) {
      _pulseCtrl.repeat(reverse: true);
    } else if (!widget.live && !widget.polishing && _pulseCtrl.isAnimating) {
      _pulseCtrl.stop();
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  double _t(Offset local, BoxConstraints c) => (local.dx / c.maxWidth).clamp(0.0, 1.0);

  void _down(Offset local, BoxConstraints c) {
    final double t = _t(local, c);
    if (widget.showTrim) {
      if ((t - widget.trimStart).abs() < 0.05) {
        _drag = 'start';
        widget.onTrimStart?.call(t);
        return;
      }
      if ((t - widget.trimEnd).abs() < 0.05) {
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
      widget.onTrimStart?.call(math.min(t, widget.trimEnd - 0.02));
    } else if (_drag == 'end') {
      widget.onTrimEnd?.call(math.max(t, widget.trimStart + 0.02));
    } else {
      widget.onScrub?.call(t);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;

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
              child: AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (context, _) {
                  return CustomPaint(
                    painter: WaveformPainter(
                      samples: widget.samples.isEmpty
                          ? const [0.2, 0.4, 0.35, 0.5, 0.6, 0.4, 0.3]
                          : widget.samples,
                      progress: widget.progress,
                      live: widget.live,
                      polishing: widget.polishing,
                      polishProgress: widget.polishProgress > 0
                          ? widget.polishProgress
                          : _pulseCtrl.value,
                      pulseVal: _pulseCtrl.value,
                      trimStart: widget.trimStart,
                      trimEnd: widget.trimEnd,
                      showTrim: widget.showTrim,
                      accent: AppColors.accent,
                      accent2: AppColors.accentBright,
                      recordColor: AppColors.record,
                      dim: AppColors.muted(b).withValues(alpha: 0.32),
                    ),
                  );
                },
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
    required this.polishing,
    required this.polishProgress,
    required this.pulseVal,
    required this.trimStart,
    required this.trimEnd,
    required this.showTrim,
    required this.accent,
    required this.accent2,
    required this.recordColor,
    required this.dim,
  });

  final List<double> samples;
  final double progress;
  final bool live;
  final bool polishing;
  final double polishProgress;
  final double pulseVal;
  final double trimStart;
  final double trimEnd;
  final bool showTrim;
  final Color accent;
  final Color accent2;
  final Color recordColor;
  final Color dim;

  @override
  void paint(Canvas canvas, Size size) {
    final int n = samples.length;
    final double gap = 1.8;
    final double barW = math.max(1.8, (size.width - gap * (n - 1)) / n);

    final Paint playedPaint = Paint()
      ..shader = LinearGradient(
        colors: live ? [recordColor, const Color(0xFFFF85A1)] : [accent, accent2],
      ).createShader(Offset.zero & size);

    final Paint restPaint = Paint()..color = dim;
    final Paint outsideTrimPaint = Paint()..color = dim.withValues(alpha: 0.18);

    for (int i = 0; i < n; i++) {
      final double t = n <= 1 ? 0.0 : i / (n - 1);
      double amp = samples[i].clamp(0.06, 1.0);

      // In live mode, add subtle reactive pulse
      if (live) {
        amp = (amp * (0.85 + (pulseVal * 0.22))).clamp(0.08, 1.0);
      }

      final double h = amp * size.height * 0.90;
      final double x = i * (barW + gap);
      final double y = (size.height - h) / 2;

      final RRect r = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barW, h),
        const Radius.circular(2.0),
      );

      final bool inTrim = !showTrim || (t >= trimStart && t <= trimEnd);
      if (!inTrim) {
        canvas.drawRRect(r, outsideTrimPaint);
      } else if (live) {
        canvas.drawRRect(r, playedPaint);
      } else if (polishing) {
        // Polishing sweep: wave changes color and height as shimmer passes
        final double distToShimmer = (t - polishProgress).abs();
        if (distToShimmer < 0.12) {
          final Paint polishGlow = Paint()
            ..color = Colors.white.withValues(alpha: 0.95);
          canvas.drawRRect(r, polishGlow);
        } else if (t < polishProgress) {
          canvas.drawRRect(r, playedPaint);
        } else {
          canvas.drawRRect(r, restPaint);
        }
      } else {
        canvas.drawRRect(r, t <= progress ? playedPaint : restPaint);
      }
    }

    // Interactive scrub playhead with glowing pill cap
    if (progress > 0 && !live && !polishing) {
      final double px = (progress * size.width).clamp(0.0, size.width);
      final Paint linePaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 1.8;
      canvas.drawLine(Offset(px, 0), Offset(px, size.height), linePaint);

      // Pill playhead cap
      final Paint capPaint = Paint()
        ..color = accent2
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(px, 4), width: 10, height: 8),
          const Radius.circular(3),
        ),
        capPaint,
      );
    }

    // Trim handles
    if (showTrim) {
      _drawTrimHandle(canvas, size, trimStart, isLeft: true);
      _drawTrimHandle(canvas, size, trimEnd, isLeft: false);
    }
  }

  void _drawTrimHandle(Canvas canvas, Size size, double t, {required bool isLeft}) {
    final double x = (t * size.width).clamp(0.0, size.width);
    final Paint handlePaint = Paint()..color = accent2;

    // Glowing border bar
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, size.height / 2), width: 4.5, height: size.height),
        const Radius.circular(2),
      ),
      handlePaint,
    );

    // Grab tab
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x + (isLeft ? -4 : 4), size.height / 2),
          width: 8,
          height: 24,
        ),
        const Radius.circular(3),
      ),
      handlePaint,
    );
  }

  @override
  bool shouldRepaint(covariant WaveformPainter old) =>
      old.samples != samples ||
      old.progress != progress ||
      old.live != live ||
      old.polishing != polishing ||
      old.polishProgress != polishProgress ||
      old.pulseVal != pulseVal ||
      old.showTrim != showTrim ||
      old.trimStart != trimStart ||
      old.trimEnd != trimEnd;
}
