import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Single source of truth for all animation and motion physics across VocalPolish.
/// Designed for pro-grade feel (Spotify, Linear, Arc, Apple Music).
class AppMotion {
  AppMotion._();

  // ─── Durations ───
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration base = Duration(milliseconds: 320);
  static const Duration slow = Duration(milliseconds: 600);
  static const Duration pulse = Duration(milliseconds: 1200);
  static const Duration aurora = Duration(seconds: 14);

  // ─── Stagger Delays ───
  static const Duration staggerFast = Duration(milliseconds: 40);
  static const Duration staggerBase = Duration(milliseconds: 60);
  static const Duration staggerSlow = Duration(milliseconds: 100);

  // ─── Easing Curves ───
  static const Curve entrance = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve emphasis = Curves.easeInOutCubic;
  static const Curve spring = Curves.elasticOut;

  // ─── Spring Simulation Physics ───
  static const SpringDescription pressSpring = SpringDescription(
    mass: 1.0,
    stiffness: 500.0,
    damping: 28.0,
  );

  static const SpringDescription bouncierSpring = SpringDescription(
    mass: 1.0,
    stiffness: 380.0,
    damping: 22.0,
  );

  // ─── Accessibility: Global Reduce Motion Flag ───
  static final RxBool reduceMotion = false.obs;

  /// Helper to return zero or minimal duration when user has enabled reduce motion.
  static Duration duration(Duration normal) {
    if (reduceMotion.value) return const Duration(milliseconds: 50);
    return normal;
  }
}
