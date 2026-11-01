import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';

// Re-export pro-grade design system components
export 'vp_aurora_background.dart';
export 'vp_bottom_nav.dart';
export 'vp_button.dart';
export 'vp_card.dart';
export 'vp_chip.dart';
export 'vp_input.dart';
export 'vp_progress_stepper.dart';

class VpRecordButton extends StatelessWidget {
  const VpRecordButton({
    super.key,
    required this.recording,
    required this.onPressed,
    this.onHoldStart,
    this.onHoldEnd,
  });

  final bool recording;
  final VoidCallback onPressed;
  final VoidCallback? onHoldStart;
  final VoidCallback? onHoldEnd;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    return GestureDetector(
      onLongPressStart: onHoldStart != null ? (_) => onHoldStart!() : null,
      onLongPressEnd: onHoldEnd != null ? (_) => onHoldEnd!() : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: recording ? AppColors.record : AppColors.surface(b),
          border: Border.all(
            color: recording ? Colors.white : AppColors.record,
            width: 3.5,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.record.withValues(alpha: recording ? 0.45 : 0.25),
              blurRadius: recording ? 28 : 16,
              spreadRadius: recording ? 4 : 0,
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: recording ? 26 : 38,
                height: recording ? 26 : 38,
                decoration: BoxDecoration(
                  color: recording ? Colors.white : AppColors.record,
                  borderRadius: BorderRadius.circular(recording ? 6 : 999),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class VpExportButton extends StatelessWidget {
  const VpExportButton({
    super.key,
    required this.onPressed,
    this.done = false,
  });

  final VoidCallback? onPressed;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      icon: Icon(done ? Icons.check : Icons.share_rounded),
      onPressed: done ? null : onPressed,
    );
  }
}

class VpProgressRing extends StatelessWidget {
  const VpProgressRing({super.key, required this.progress, this.size = 128, this.child});
  final double progress;
  final double size;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: progress.clamp(0, 1),
            strokeWidth: 6,
            backgroundColor: AppColors.border(Theme.of(context).brightness),
            color: AppColors.accent,
          ),
          ?child,
        ],
      ),
    );
  }
}

class VpPresetCard extends StatelessWidget {
  const VpPresetCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.selected = false,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    final bool isDark = b == Brightness.dark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.accent.withValues(alpha: isDark ? 0.22 : 0.12)
            : AppColors.surface(b),
        borderRadius: AppRadius.card,
        border: Border.all(
          color: selected
              ? AppColors.accentBright
              : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
          width: selected ? 1.4 : 1.0,
        ),
        boxShadow: [
          if (selected)
            BoxShadow(
              color: AppColors.accentBright.withValues(alpha: 0.2),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.card,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: selected ? AppColors.signature : null,
                color: selected ? null : AppColors.surfaceAlt(b),
                borderRadius: AppRadius.button,
              ),
              child: Icon(Icons.graphic_eq_rounded, color: selected ? Colors.white : AppColors.accent),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall, maxLines: 2),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
