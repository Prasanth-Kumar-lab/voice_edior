import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_radius.dart';

enum VpStepStatus { pending, active, completed, error }

class VpStepItem {
  const VpStepItem({
    required this.title,
    required this.status,
    this.subtitle,
  });

  final String title;
  final VpStepStatus status;
  final String? subtitle;
}

/// Pro-grade staged progress stepper with glass chips, pulsing glowing active state,
/// animated checkmark reveal, and connecting gradient pipeline.
class VpProgressStepper extends StatelessWidget {
  const VpProgressStepper({
    super.key,
    required this.steps,
    this.currentStepIndex = 0,
  });

  final List<VpStepItem> steps;
  final int currentStepIndex;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    final bool isDark = b == Brightness.dark;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(steps.length, (index) {
            final VpStepItem step = steps[index];
            final bool isActive = step.status == VpStepStatus.active;
            final bool isDone = step.status == VpStepStatus.completed;
            final bool isError = step.status == VpStepStatus.error;

            Color borderColor;
            Color iconColor;
            Widget statusIcon;

            if (isDone) {
              borderColor = AppColors.success;
              iconColor = AppColors.success;
              statusIcon = const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.success);
            } else if (isActive) {
              borderColor = AppColors.accentBright;
              iconColor = AppColors.accentBright;
              statusIcon = _PulsingStepIndicator(color: AppColors.accentBright);
            } else if (isError) {
              borderColor = AppColors.danger;
              iconColor = AppColors.danger;
              statusIcon = const Icon(Icons.error_outline_rounded, size: 16, color: AppColors.danger);
            } else {
              borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
              iconColor = AppColors.muted(b);
              statusIcon = Text(
                '${index + 1}',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: iconColor,
                ),
              );
            }

            return Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: AnimatedContainer(
                      duration: AppMotion.base,
                      curve: AppMotion.entrance,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      decoration: BoxDecoration(
                        color: isActive
                            ? AppColors.accent.withValues(alpha: isDark ? 0.20 : 0.12)
                            : (isDark
                                ? AppColors.darkSurfaceAlt.withValues(alpha: 0.65)
                                : AppColors.lightSurfaceAlt),
                        borderRadius: AppRadius.button,
                        border: Border.all(color: borderColor, width: isActive ? 1.4 : 1.0),
                        boxShadow: [
                          if (isActive)
                            BoxShadow(
                              color: AppColors.accentBright.withValues(alpha: 0.22),
                              blurRadius: 14,
                              offset: const Offset(0, 3),
                            ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          statusIcon,
                          const SizedBox(height: 4),
                          Text(
                            step.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11,
                              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                              color: isActive
                                  ? (isDark ? Colors.white : AppColors.lightText)
                                  : (isDone ? AppColors.text(b) : AppColors.muted(b)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (index < steps.length - 1)
                    Container(
                      width: 10,
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      color: isDone
                          ? AppColors.success
                          : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                    ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _PulsingStepIndicator extends StatefulWidget {
  const _PulsingStepIndicator({required this.color});
  final Color color;

  @override
  State<_PulsingStepIndicator> createState() => _PulsingStepIndicatorState();
}

class _PulsingStepIndicatorState extends State<_PulsingStepIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
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
        final double scale = 0.85 + (_ctrl.value * 0.30);
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color,
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.6 * _ctrl.value),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
