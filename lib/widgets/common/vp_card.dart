import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_glass.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';

/// Pro-grade glassmorphic card with translucent backdrop blur, 1px gradient border,
/// soft specular inner highlight, depth-based glow, and interactive press-tilt feedback.
class VpCard extends StatefulWidget {
  const VpCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.margin,
    this.borderRadius,
    this.glow = false,
    this.selected = false,
    this.loading = false,
    this.customGlow,
    this.blur = AppGlass.blurStandard,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadiusGeometry? borderRadius;
  final bool glow;
  final bool selected;
  final bool loading;
  final Color? customGlow;
  final double blur;

  @override
  State<VpCard> createState() => _VpCardState();
}

class _VpCardState extends State<VpCard> with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late final AnimationController _skeletonCtrl;

  @override
  void initState() {
    super.initState();
    _skeletonCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.loading) {
      _skeletonCtrl.repeat();
    }
  }

  @override
  void didUpdateWidget(VpCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loading != oldWidget.loading) {
      if (widget.loading) {
        _skeletonCtrl.repeat();
      } else {
        _skeletonCtrl.stop();
      }
    }
  }

  @override
  void dispose() {
    _skeletonCtrl.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    if (widget.onTap == null || widget.loading) return;
    HapticFeedback.selectionClick();
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
    final BorderRadiusGeometry radius = widget.borderRadius ?? AppRadius.card;
    final bool isDark = b == Brightness.dark;

    final BoxDecoration glassBox = AppGlass.cardDecoration(
      b,
      borderRadius: radius,
      glow: widget.glow,
      selected: widget.selected,
      customGlow: widget.customGlow,
    );

    return Padding(
      padding: widget.margin ?? EdgeInsets.zero,
      child: AnimatedScale(
        scale: _pressed ? 0.982 : 1.0,
        duration: AppMotion.fast,
        curve: AppMotion.entrance,
        child: GestureDetector(
          onTapDown: _onTapDown,
          onTapUp: _onTapUp,
          onTapCancel: _onTapCancel,
          onTap: widget.loading ? null : widget.onTap,
          child: Container(
            decoration: glassBox,
            child: ClipRRect(
              borderRadius: radius,
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: widget.blur,
                  sigmaY: widget.blur,
                ),
                child: Container(
                  padding: widget.padding ?? const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: isDark ? 0.05 : 0.08),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.35],
                    ),
                  ),
                  child: widget.loading
                      ? _SkeletonShimmer(
                          progress: _skeletonCtrl,
                          isDark: isDark,
                          child: widget.child,
                        )
                      : widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SkeletonShimmer extends StatelessWidget {
  const _SkeletonShimmer({
    required this.progress,
    required this.isDark,
    required this.child,
  });

  final Animation<double> progress;
  final bool isDark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      builder: (context, _) {
        final double sweep = progress.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: const Alignment(-1.0, -0.3),
              end: const Alignment(2.0, 0.3),
              colors: [
                Colors.white.withValues(alpha: 0.3),
                Colors.white.withValues(alpha: 0.8),
                Colors.white.withValues(alpha: 0.3),
              ],
              stops: [
                (sweep - 0.25).clamp(0.0, 1.0),
                sweep.clamp(0.0, 1.0),
                (sweep + 0.25).clamp(0.0, 1.0),
              ],
            ).createShader(bounds);
          },
          child: Opacity(
            opacity: 0.45,
            child: child,
          ),
        );
      },
    );
  }
}
