import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';
import 'app_radius.dart';
import 'app_text_styles.dart';

class AppTheme {
  AppTheme._();

  static ThemeData dark() => _build(Brightness.dark);
  static ThemeData light() => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final bool dark = brightness == Brightness.dark;
    final ColorScheme scheme = ColorScheme(
      brightness: brightness,
      primary: AppColors.accent,
      onPrimary: Colors.white,
      secondary: AppColors.accentBright,
      onSecondary: const Color(0xFF0B0D12),
      error: AppColors.danger,
      onError: Colors.white,
      surface: AppColors.surface(brightness),
      onSurface: AppColors.text(brightness),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg(brightness),
      textTheme: AppTextStyles.textTheme(brightness),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bg(brightness),
        foregroundColor: AppColors.text(brightness),
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      dividerColor: AppColors.border(brightness),
      cardTheme: CardThemeData(
        color: AppColors.surface(brightness),
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.card),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.accent,
        inactiveTrackColor: AppColors.border(brightness),
        thumbColor: AppColors.accentBright,
        overlayColor: AppColors.accent.withValues(alpha: 0.16),
        trackHeight: 4,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceAlt(brightness),
        border: OutlineInputBorder(
          borderRadius: AppRadius.button,
          borderSide: BorderSide(color: AppColors.border(brightness)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.button,
          borderSide: BorderSide(color: AppColors.border(brightness)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: AppRadius.button,
          borderSide: BorderSide(color: AppColors.accent, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceAlt(brightness),
        contentTextStyle: AppTextStyles.textTheme(brightness).bodyMedium,
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface(brightness),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.card),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surface(brightness),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      ),
    );
  }
}
