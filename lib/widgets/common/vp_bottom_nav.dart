import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_glass.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_radius.dart';

/// Pro-grade floating glass bottom navigation bar with a sliding gradient active indicator,
/// prominent center Record button with breathing glow, and a floating "Reconnecting…" pill.
class VpBottomNav extends StatelessWidget {
  const VpBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
    required this.onRecordPressed,
    this.isReconnecting = false,
  });

  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onRecordPressed;
  final bool isReconnecting;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    final bool isDark = b == Brightness.dark;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Floating "Reconnecting…" pill banner
            AnimatedSwitcher(
              duration: AppMotion.base,
              switchInCurve: AppMotion.entrance,
              switchOutCurve: AppMotion.exit,
              child: isReconnecting
                  ? Container(
                      key: const ValueKey('reconnecting_pill'),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.5),
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.warning.withValues(alpha: 0.18),
                            blurRadius: 12,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.warning,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Reconnecting to studio server…',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.warning,
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),

            // Floating Glass Navigation Bar Container
            Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // Glass Capsule
                Container(
                  height: 68,
                  decoration: BoxDecoration(
                    color: AppGlass.background(b, opacity: isDark ? 0.78 : 0.88),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.14)
                          : Colors.black.withValues(alpha: 0.08),
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.10),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: AppGlass.blurDense,
                        sigmaY: AppGlass.blurDense,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            // Left Tab 0: Studio
                            Expanded(
                              child: _NavTabItem(
                                icon: Icons.graphic_eq_rounded,
                                label: 'Studio',
                                selected: currentIndex == 0,
                                onTap: () => onTabSelected(0),
                              ),
                            ),
                            // Left Tab 1: Mix
                            Expanded(
                              child: _NavTabItem(
                                icon: Icons.tune_rounded,
                                label: 'Mix',
                                selected: currentIndex == 1,
                                onTap: () => onTabSelected(1),
                              ),
                            ),

                            // Center Spacer for elevated Record FAB
                            const SizedBox(width: 60),

                            // Right Tab 2: Pro Pass
                            Expanded(
                              child: _NavTabItem(
                                icon: Icons.workspace_premium_rounded,
                                label: 'Pro Pass',
                                selected: currentIndex == 2,
                                onTap: () => onTabSelected(2),
                              ),
                            ),
                            // Right Tab 3: Profile
                            Expanded(
                              child: _NavTabItem(
                                icon: Icons.person_rounded,
                                label: 'Profile',
                                selected: currentIndex == 3,
                                onTap: () => onTabSelected(3),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Center Prominent Floating Record Button
                Positioned(
                  top: -14,
                  child: _CenterRecordFab(onPressed: onRecordPressed),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NavTabItem extends StatelessWidget {
  const _NavTabItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    final bool isDark = b == Brightness.dark;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Center(
        child: AnimatedContainer(
          duration: AppMotion.base,
          curve: AppMotion.entrance,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            gradient: selected ? AppColors.signature : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected
                    ? Colors.white
                    : (isDark ? AppColors.darkMuted : AppColors.lightMuted),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? Colors.white
                      : (isDark ? AppColors.darkMuted : AppColors.lightMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenterRecordFab extends StatefulWidget {
  const _CenterRecordFab({required this.onPressed});
  final VoidCallback onPressed;

  @override
  State<_CenterRecordFab> createState() => _CenterRecordFabState();
}

class _CenterRecordFabState extends State<_CenterRecordFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _auraCtrl;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _auraCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _auraCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.92 : 1.0,
      duration: AppMotion.fast,
      curve: AppMotion.entrance,
      child: GestureDetector(
        onTapDown: (_) {
          HapticFeedback.heavyImpact();
          setState(() => _pressed = true);
        },
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onPressed,
        child: AnimatedBuilder(
          animation: _auraCtrl,
          builder: (context, _) {
            final double glowSpread = 4.0 + (_auraCtrl.value * 6.0);
            return Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [
                    Color(0xFFFF4D6D),
                    Color(0xFFE11D48),
                  ],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 2.0),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF4D6D).withValues(alpha: 0.45),
                    blurRadius: 18 + glowSpread,
                    spreadRadius: glowSpread * 0.5,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.mic_rounded,
                color: Colors.white,
                size: 28,
              ),
            );
          },
        ),
      ),
    );
  }
}
