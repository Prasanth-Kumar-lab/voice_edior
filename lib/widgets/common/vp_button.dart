import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';

enum VpButtonVariant { filled, outlined, ghost, danger }

/// Pro-grade interactive button with press-scale feedback, gradient shimmer sweep,
/// and smooth loading state morphing into a lively mini audio waveform.
class VpButton extends StatefulWidget {
  const VpButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = VpButtonVariant.filled,
    this.filled = true, // Backward-compat convenience
    this.expand = true,
    this.compact = false,
    this.loading = false,
    this.shimmer = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final VpButtonVariant variant;
  final bool filled;
  final bool expand;
  final bool compact;
  final bool loading;
  final bool shimmer;

  @override
  State<VpButton> createState() => _VpButtonState();
}

class _VpButtonState extends State<VpButton> with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late final AnimationController _shimmerCtrl;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    if (widget.shimmer || widget.variant == VpButtonVariant.filled) {
      _shimmerCtrl.repeat();
    }
  }

  @override
  void didUpdateWidget(VpButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.shimmer != oldWidget.shimmer) || (widget.variant != oldWidget.variant)) {
      if (widget.shimmer || widget.variant == VpButtonVariant.filled) {
        _shimmerCtrl.repeat();
      } else {
        _shimmerCtrl.stop();
      }
    }
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    if (widget.onPressed == null || widget.loading) return;
    HapticFeedback.lightImpact();
    setState(() => _pressed = true);
  }

  void _onTapUp(TapUpDetails _) {
    if (_pressed) setState(() => _pressed = false);
  }

  void _onTapCancel() {
    if (_pressed) setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    final bool isDark = b == Brightness.dark;
    final double h = widget.compact ? 42.0 : 52.0;

    // Resolve variant (supporting both `variant` and legacy `filled` flag)
    final VpButtonVariant effectiveVariant =
        !widget.filled ? VpButtonVariant.outlined : widget.variant;

    final bool isDisabled = widget.onPressed == null && !widget.loading;

    // Color decisions
    Color textColor;
    Gradient? bgGradient;
    Color? bgColor;
    Border? border;
    List<BoxShadow> shadows = [];

    switch (effectiveVariant) {
      case VpButtonVariant.filled:
        textColor = Colors.white;
        bgGradient = AppColors.signature;
        if (!isDisabled) {
          shadows = [
            BoxShadow(
              color: AppColors.accent.withValues(alpha: isDark ? 0.35 : 0.25),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ];
        }
        break;
      case VpButtonVariant.outlined:
        textColor = AppColors.text(b);
        bgColor = Colors.transparent;
        border = Border.all(
          color: AppColors.border(b),
          width: 1.2,
        );
        break;
      case VpButtonVariant.ghost:
        textColor = AppColors.accentBright;
        bgColor = AppColors.surfaceAlt(b).withValues(alpha: 0.6);
        break;
      case VpButtonVariant.danger:
        textColor = Colors.white;
        bgColor = AppColors.danger;
        if (!isDisabled) {
          shadows = [
            BoxShadow(
              color: AppColors.danger.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ];
        }
        break;
    }

    if (isDisabled) {
      textColor = AppColors.muted(b);
      bgGradient = null;
      bgColor = AppColors.surfaceAlt(b);
      shadows = [];
    }

    final Widget content = AnimatedSwitcher(
      duration: AppMotion.fast,
      switchInCurve: AppMotion.entrance,
      switchOutCurve: AppMotion.exit,
      child: widget.loading
          ? _MiniWaveformLoader(color: textColor, key: const ValueKey('loader'))
          : Row(
              key: const ValueKey('content'),
              mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: widget.compact ? 17 : 20, color: textColor),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: widget.compact ? 13 : 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                      color: textColor,
                    ),
                  ),
                ),
              ],
            ),
    );

    return AnimatedScale(
      scale: _pressed ? 0.965 : 1.0,
      duration: AppMotion.fast,
      curve: AppMotion.entrance,
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        onTap: widget.loading ? null : widget.onPressed,
        child: Container(
          height: h,
          width: widget.expand ? double.infinity : null,
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? AppSpacing.sm : AppSpacing.lg,
          ),
          decoration: BoxDecoration(
            gradient: bgGradient,
            color: bgGradient == null ? bgColor : null,
            borderRadius: AppRadius.button,
            border: border,
            boxShadow: shadows,
          ),
          child: ClipRRect(
            borderRadius: AppRadius.button,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Shimmer sweep across the gradient surface
                if (effectiveVariant == VpButtonVariant.filled &&
                    !isDisabled &&
                    !widget.loading)
                  AnimatedBuilder(
                    animation: _shimmerCtrl,
                    builder: (context, _) {
                      return Positioned.fill(
                        child: CustomPaint(
                          painter: _ShimmerSweepPainter(progress: _shimmerCtrl.value),
                        ),
                      );
                    },
                  ),
                content,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Mini 4-bar equalizer that plays smoothly while a button is in loading state.
class _MiniWaveformLoader extends StatefulWidget {
  const _MiniWaveformLoader({super.key, required this.color});
  final Color color;

  @override
  State<_MiniWaveformLoader> createState() => _MiniWaveformLoaderState();
}

class _MiniWaveformLoaderState extends State<_MiniWaveformLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(4, (i) {
            final double phase = (i * 0.28);
            final double val =
                (math.sin((_ctrl.value * 2 * math.pi) + phase).abs() * 0.75) + 0.25;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2.2),
              width: 3.2,
              height: 18.0 * val,
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(2.0),
              ),
            );
          }),
        );
      },
    );
  }
}

class _ShimmerSweepPainter extends CustomPainter {
  _ShimmerSweepPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    // 0 to 1 progress moves a slanted highlight from left to right
    final double sweepWidth = size.width * 0.45;
    final double startX = -sweepWidth + (size.width + sweepWidth * 2) * progress;

    final Paint p = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.16),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(startX, 0, sweepWidth, size.height));

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), p);
  }

  @override
  bool shouldRepaint(covariant _ShimmerSweepPainter old) => old.progress != progress;
}
