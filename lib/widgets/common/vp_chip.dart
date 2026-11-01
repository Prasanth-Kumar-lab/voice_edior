import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';

/// Pro-grade interactive filter chip with fluid morphing gradient, active depth glow,
/// and tactile spring press feedback. Used for Mode, Tone, Space, and Role selection.
class VpChip extends StatefulWidget {
  const VpChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.badge,
    this.badgeColor,
    this.compact = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final String? badge;
  final Color? badgeColor;
  final bool compact;

  @override
  State<VpChip> createState() => _VpChipState();
}

class _VpChipState extends State<VpChip> {
  bool _pressed = false;

  void _onTapDown(TapDownDetails _) {
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
    final bool isDark = b == Brightness.dark;
    final double h = widget.compact ? 34.0 : 42.0;

    final Color textColor = widget.selected
        ? Colors.white
        : (isDark ? AppColors.darkText : AppColors.lightText);

    return AnimatedScale(
      scale: _pressed ? 0.94 : (widget.selected ? 1.03 : 1.0),
      duration: AppMotion.fast,
      curve: AppMotion.entrance,
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.base,
          curve: AppMotion.entrance,
          height: h,
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 10.0 : AppSpacing.md,
          ),
          decoration: BoxDecoration(
            borderRadius: AppRadius.chip,
            gradient: widget.selected ? AppColors.signature : null,
            color: widget.selected
                ? null
                : (isDark
                    ? AppColors.darkSurfaceAlt.withValues(alpha: 0.70)
                    : AppColors.lightSurfaceAlt),
            border: Border.all(
              color: widget.selected
                  ? Colors.white.withValues(alpha: 0.35)
                  : (isDark
                      ? AppColors.darkBorder.withValues(alpha: 0.8)
                      : AppColors.lightBorder),
              width: 1.0,
            ),
            boxShadow: [
              if (widget.selected)
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: isDark ? 0.38 : 0.22),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  size: widget.compact ? 14 : 16,
                  color: widget.selected ? Colors.white : AppColors.accentBright,
                ),
                const SizedBox(width: 6.0),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: widget.compact ? 12.0 : 13.5,
                  fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
                  color: textColor,
                  letterSpacing: 0.2,
                ),
              ),
              if (widget.badge != null) ...[
                const SizedBox(width: 6.0),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: widget.badgeColor ??
                        (widget.selected
                            ? Colors.white.withValues(alpha: 0.25)
                            : AppColors.accent.withValues(alpha: 0.20)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    widget.badge!,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: widget.selected
                          ? Colors.white
                          : (widget.badgeColor != null ? Colors.black : AppColors.accentBright),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
