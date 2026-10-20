import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import 'login_view.dart';

class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 2800), _goNext);
  }

  void _goNext() {
    if (!mounted) return;
    Get.off(() => const LoginView(), transition: Transition.fadeIn, duration: const Duration(milliseconds: 500));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final Brightness b = Theme.of(context).brightness;
    const List<double> waveHeights = [0.22, 0.42, 0.72, 1.0, 0.64, 0.88, 0.50, 0.30];

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Ambient background glows
          Positioned(
            top: -110,
            left: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [AppColors.accent.withValues(alpha: 0.28), Colors.transparent],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -120,
            right: -70,
            child: Container(
              width: 340,
              height: 340,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [AppColors.accentBright.withValues(alpha: 0.20), Colors.transparent],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        _timer?.cancel();
                        _goNext();
                      },
                      child: Text('Skip →', style: t.labelLarge?.copyWith(color: AppColors.muted(b))),
                    ),
                  ),
                  const Spacer(),
                  // Animated Studio Emblem
                  Container(
                    width: 118,
                    height: 118,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(34),
                      gradient: AppColors.signature,
                      boxShadow: [
                        ...AppShadows.glow(),
                        BoxShadow(
                          color: AppColors.accentBright.withValues(alpha: 0.25),
                          blurRadius: 42,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 108,
                          height: 108,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(30),
                            color: AppColors.darkBg.withValues(alpha: 0.86),
                          ),
                        ),
                        ShaderMask(
                          shaderCallback: (r) => AppColors.signature.createShader(r),
                          child: const Icon(Icons.graphic_eq_rounded, size: 58, color: Colors.white),
                        ),
                      ],
                    ),
                  )
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .scale(begin: const Offset(0.96, 0.96), end: const Offset(1.04, 1.04), duration: 1400.ms, curve: Curves.easeInOut),
                  const SizedBox(height: AppSpacing.lg),
                  // Brand Title
                  ShaderMask(
                    shaderCallback: (r) => AppColors.signature.createShader(r),
                    child: Text(
                      'VocalPolish',
                      style: t.displayMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                      ),
                    ),
                  ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.15),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      borderRadius: AppRadius.chip,
                      color: AppColors.surface(b),
                      border: Border.all(color: AppColors.border(b)),
                    ),
                    child: Text(
                      'AI STUDIO VOICE & PODCAST ENGINE',
                      style: t.labelSmall?.copyWith(
                        color: AppColors.accentBright,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ).animate().fadeIn(delay: 180.ms),
                  const SizedBox(height: AppSpacing.xl),
                  // Animated equalizer bars
                  SizedBox(
                    height: 44,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (int i = 0; i < waveHeights.length; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Container(
                              width: 5,
                              height: 12 + 30 * waveHeights[i],
                              decoration: BoxDecoration(
                                borderRadius: AppRadius.chip,
                                gradient: AppColors.signature,
                              ),
                            )
                                .animate(onPlay: (c) => c.repeat(reverse: true))
                                .scaleY(
                                  begin: 0.35,
                                  end: 1.0,
                                  delay: (i * 90).ms,
                                  duration: 650.ms,
                                  curve: Curves.easeInOut,
                                ),
                          ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Bottom studio specs badge
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.bolt_rounded, size: 16, color: AppColors.accentBright),
                      const SizedBox(width: 6),
                      Text(
                        '48 kHz Mastering  ·  Zero-Noise Gate  ·  Theatrical Bass',
                        style: t.bodySmall?.copyWith(color: AppColors.muted(b)),
                      ),
                    ],
                  ).animate().fadeIn(delay: 320.ms),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
