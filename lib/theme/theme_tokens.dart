import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class ThemeTokens {
  static Color muted(BuildContext c) => AppColors.muted(Theme.of(c).brightness);
  static Color surfaceAlt(BuildContext c) => AppColors.surfaceAlt(Theme.of(c).brightness);
  static Color border(BuildContext c) => AppColors.border(Theme.of(c).brightness);
  static Color text(BuildContext c) => AppColors.text(Theme.of(c).brightness);
}

class PageGutter extends StatelessWidget {
  const PageGutter({super.key, required this.child, this.maxWidth});
  final Widget child;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth ?? 1100),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: child,
        ),
      ),
    );
  }
}
