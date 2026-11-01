import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_radius.dart';

/// Glassmorphism, specular highlights, and translucent surface decorators.
class AppGlass {
  AppGlass._();

  static const double blurStandard = 18.0;
  static const double blurSubtle = 10.0;
  static const double blurDense = 28.0;

  /// Returns frosted background color based on theme brightness.
  static Color background(Brightness b, {double opacity = 0.72}) {
    final Color base = AppColors.surface(b);
    return base.withValues(alpha: opacity);
  }

  /// Returns ultra-thin 1px border with soft gradient falloff.
  static Gradient borderGradient(Brightness b, {bool focused = false}) {
    if (focused) {
      return AppColors.signature;
    }
    if (b == Brightness.dark) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.18),
          Colors.white.withValues(alpha: 0.04),
        ],
      );
    } else {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.black.withValues(alpha: 0.08),
          Colors.black.withValues(alpha: 0.02),
        ],
      );
    }
  }

  /// Pro-grade glass decoration with specular edge and soft colored depth glow.
  static BoxDecoration cardDecoration(
    Brightness b, {
    BorderRadiusGeometry? borderRadius,
    bool glow = false,
    bool selected = false,
    Color? customGlow,
  }) {
    final BorderRadiusGeometry radius = borderRadius ?? AppRadius.card;
    final Color glowColor = customGlow ?? AppColors.accent;

    return BoxDecoration(
      color: background(b, opacity: selected ? 0.85 : 0.70),
      borderRadius: radius,
      border: Border.all(
        color: selected
            ? AppColors.accentBright.withValues(alpha: 0.60)
            : (b == Brightness.dark
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.06)),
        width: selected ? 1.5 : 1.0,
      ),
      boxShadow: [
        if (glow || selected)
          BoxShadow(
            color: glowColor.withValues(alpha: selected ? 0.28 : 0.18),
            blurRadius: selected ? 28 : 20,
            spreadRadius: selected ? 1 : 0,
            offset: const Offset(0, 8),
          ),
        BoxShadow(
          color: Colors.black.withValues(alpha: b == Brightness.dark ? 0.40 : 0.06),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }
}
