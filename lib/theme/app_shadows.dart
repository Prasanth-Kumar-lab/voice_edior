import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppShadows {
  AppShadows._();

  static List<BoxShadow> elevation1(Brightness b) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: b == Brightness.dark ? 0.35 : 0.08),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> elevation2(Brightness b) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: b == Brightness.dark ? 0.45 : 0.12),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ];

  static List<BoxShadow> glow() => [
        BoxShadow(
          color: AppColors.accent.withValues(alpha: 0.35),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];
}
