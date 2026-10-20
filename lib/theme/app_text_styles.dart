import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTextStyles {
  AppTextStyles._();

  static TextTheme textTheme(Brightness brightness) {
    final Color on = AppColors.text(brightness);
    final Color muted = AppColors.muted(brightness);
    final TextStyle display = GoogleFonts.outfit(color: on, fontWeight: FontWeight.w600);
    final TextStyle body = GoogleFonts.inter(color: on, fontWeight: FontWeight.w400);

    return TextTheme(
      displayLarge: display.copyWith(fontSize: 48, height: 1.1, letterSpacing: -1.2),
      displayMedium: display.copyWith(fontSize: 36, height: 1.15, letterSpacing: -0.8),
      displaySmall: display.copyWith(fontSize: 28, height: 1.2, letterSpacing: -0.4),
      headlineLarge: display.copyWith(fontSize: 24, height: 1.25),
      headlineMedium: display.copyWith(fontSize: 20, height: 1.3),
      headlineSmall: display.copyWith(fontSize: 18, height: 1.3),
      titleLarge: display.copyWith(fontSize: 16, fontWeight: FontWeight.w500),
      titleMedium: body.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
      titleSmall: body.copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: muted),
      bodyLarge: body.copyWith(fontSize: 16, height: 1.5),
      bodyMedium: body.copyWith(fontSize: 14, height: 1.5),
      bodySmall: body.copyWith(fontSize: 12, height: 1.45, color: muted),
      labelLarge: body.copyWith(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.2),
      labelMedium: body.copyWith(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.3),
      labelSmall: body.copyWith(fontSize: 10, fontWeight: FontWeight.w500, color: muted, letterSpacing: 0.4),
    );
  }
}
