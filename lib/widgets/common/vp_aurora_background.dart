import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Drifting aurora mesh gradient background using the signature violet & cyan palette.
/// Rendered with CustomPainter and isolated in a RepaintBoundary for maximum 120fps performance.
class VpAuroraBackground extends StatefulWidget {
  const VpAuroraBackground({
    super.key,
    required this.child,
    this.intensity = 1.0,
    this.animate = true,
  });

  final Widget child;
  final double intensity;
  final bool animate;

  @override
  State<VpAuroraBackground> createState() => _VpAuroraBackgroundState();
}

class _VpAuroraBackgroundState extends State<VpAuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    );
    if (widget.animate) {
      _ctrl.repeat();
    }
  }

  @override
  void didUpdateWidget(VpAuroraBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate != oldWidget.animate) {
      if (widget.animate) {
        _ctrl.repeat();
      } else {
        _ctrl.stop();
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Solid root scaffold background
        ColoredBox(color: AppColors.bg(b)),

        // Isolated Aurora CustomPainter
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              return CustomPaint(
                painter: _AuroraMeshPainter(
                  progress: _ctrl.value,
                  brightness: b,
                  intensity: widget.intensity,
                ),
                isComplex: true,
                willChange: widget.animate,
              );
            },
          ),
        ),

        // Foreground content
        widget.child,
      ],
    );
  }
}

class _AuroraMeshPainter extends CustomPainter {
  _AuroraMeshPainter({
    required this.progress,
    required this.brightness,
    required this.intensity,
  });

  final double progress;
  final Brightness brightness;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final double t = progress * 2 * math.pi;
    final bool dark = brightness == Brightness.dark;

    // Base alpha multipliers based on dark vs light theme
    final double violetAlpha = (dark ? 0.22 : 0.12) * intensity;
    final double cyanAlpha = (dark ? 0.18 : 0.09) * intensity;
    final double magentaAlpha = (dark ? 0.12 : 0.06) * intensity;

    // Drifting Orb 1: Violet (Upper-left elliptical drift)
    final Offset p1 = Offset(
      size.width * (0.25 + 0.15 * math.cos(t)),
      size.height * (0.20 + 0.10 * math.sin(t)),
    );
    final double r1 = size.width * 0.70;
    final Paint paint1 = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.accent.withValues(alpha: violetAlpha),
          AppColors.accent.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: p1, radius: r1));
    canvas.drawCircle(p1, r1, paint1);

    // Drifting Orb 2: Cyan (Lower-right elliptical drift)
    final Offset p2 = Offset(
      size.width * (0.75 + 0.12 * math.sin(t * 0.9)),
      size.height * (0.65 + 0.12 * math.cos(t * 0.8)),
    );
    final double r2 = size.width * 0.65;
    final Paint paint2 = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.accentBright.withValues(alpha: cyanAlpha),
          AppColors.accentBright.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: p2, radius: r2));
    canvas.drawCircle(p2, r2, paint2);

    // Drifting Orb 3: Subtle Sub-bass Magenta/Violet Accent (Bottom center)
    final Offset p3 = Offset(
      size.width * (0.45 + 0.10 * math.cos(t * 1.2)),
      size.height * (0.85 + 0.08 * math.sin(t * 1.1)),
    );
    final double r3 = size.width * 0.55;
    final Paint paint3 = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFA855F7).withValues(alpha: magentaAlpha),
          const Color(0xFFA855F7).withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: p3, radius: r3));
    canvas.drawCircle(p3, r3, paint3);
  }

  @override
  bool shouldRepaint(covariant _AuroraMeshPainter old) =>
      old.progress != progress ||
      old.brightness != brightness ||
      old.intensity != intensity;
}
