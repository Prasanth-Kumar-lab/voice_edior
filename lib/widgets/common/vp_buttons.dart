import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';

class VpButton extends StatelessWidget {
  const VpButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.filled = true,
    this.expand = true,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool filled;
  final bool expand;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final Widget child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: compact ? 16 : 18),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
    final double h = compact ? 40 : 48;
    if (!filled) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: Size(expand ? double.infinity : 0, h),
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : AppSpacing.md),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
        ),
        child: child,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: onPressed == null ? null : AppColors.signature,
        color: onPressed == null ? AppColors.border(Theme.of(context).brightness) : null,
        borderRadius: AppRadius.button,
        boxShadow: onPressed == null ? null : AppShadows.glow(),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: AppRadius.button,
          onTap: onPressed,
          child: SizedBox(
            height: h,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: DefaultTextStyle.merge(
                style: Theme.of(context).textTheme.labelLarge!.copyWith(color: Colors.white),
                child: IconTheme(
                  data: const IconThemeData(color: Colors.white),
                  child: Center(child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
    final Widget core = GestureDetector(
      onTap: onPressed,
      onLongPressStart: onHoldStart == null ? null : (_) => onHoldStart!(),
      onLongPressEnd: onHoldEnd == null ? null : (_) => onHoldEnd!(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: recording ? AppColors.record : AppColors.surfaceAlt(Theme.of(context).brightness),
          border: Border.all(color: AppColors.record, width: 3),
          boxShadow: recording ? AppShadows.glow() : AppShadows.elevation1(Theme.of(context).brightness),
        ),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: recording ? 22 : 28,
            height: recording ? 22 : 28,
            decoration: BoxDecoration(
              color: recording ? Colors.white : AppColors.record,
              borderRadius: BorderRadius.circular(recording ? 4 : 28),
            ),
          ),
        ),
      ),
    );
    if (!recording) return core;
    return core
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scale(begin: const Offset(1, 1), end: const Offset(1.08, 1.08), duration: 700.ms);
  }
}

class VpExportButton extends StatelessWidget {
  const VpExportButton({
    super.key,
    required this.progress,
    required this.done,
    required this.onPressed,
    this.label = 'Export',
  });

  final double progress;
  final bool done;
  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return VpButton(
      label: done ? 'Exported' : (progress > 0 && progress < 1 ? '${(progress * 100).round()}%' : label),
      icon: done ? Icons.check_rounded : Icons.file_download_outlined,
      onPressed: done ? null : onPressed,
    );
  }
}

class VpCard extends StatelessWidget {
  const VpCard({super.key, required this.child, this.onTap, this.padding});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: AppColors.surface(b),
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border(b)),
        boxShadow: AppShadows.elevation1(b),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: AppRadius.card,
          onTap: onTap,
          child: Padding(
            padding: padding ?? const EdgeInsets.all(AppSpacing.md),
            child: child,
          ),
        ),
      ),
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
    return VpCard(
      onTap: onTap,
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
    );
  }
}
