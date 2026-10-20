import 'package:flutter/material.dart';

/// Single source of truth for VocalPolish color. Screens never hardcode colors.
class AppColors {
  AppColors._();

  static const Color accent = Color(0xFF7C6CFF);
  static const Color accentBright = Color(0xFF22D3EE);
  static const LinearGradient signature = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7C6CFF), Color(0xFF22D3EE)],
  );

  static const Color darkBg = Color(0xFF0B0D12);
  static const Color darkSurface = Color(0xFF141824);
  static const Color darkSurfaceAlt = Color(0xFF1C2233);
  static const Color darkBorder = Color(0xFF2A3148);
  static const Color darkText = Color(0xFFF4F6FB);
  static const Color darkMuted = Color(0xFF9AA3B8);

  static const Color lightBg = Color(0xFFF4F6FB);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFEBEEF6);
  static const Color lightBorder = Color(0xFFD5DAE8);
  static const Color lightText = Color(0xFF12151E);
  static const Color lightMuted = Color(0xFF5C6478);

  static const Color success = Color(0xFF34D399);
  static const Color warning = Color(0xFFFBBF24);
  static const Color danger = Color(0xFFF87171);
  static const Color record = Color(0xFFFF4D6D);

  static Color bg(Brightness b) => b == Brightness.dark ? darkBg : lightBg;
  static Color surface(Brightness b) =>
      b == Brightness.dark ? darkSurface : lightSurface;
  static Color surfaceAlt(Brightness b) =>
      b == Brightness.dark ? darkSurfaceAlt : lightSurfaceAlt;
  static Color border(Brightness b) =>
      b == Brightness.dark ? darkBorder : lightBorder;
  static Color text(Brightness b) =>
      b == Brightness.dark ? darkText : lightText;
  static Color muted(Brightness b) =>
      b == Brightness.dark ? darkMuted : lightMuted;
}
