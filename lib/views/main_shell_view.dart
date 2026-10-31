import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import 'profile_view.dart';
import 'studio_view.dart';
import 'subscription_view.dart';

class MainShellView extends StatefulWidget {
  const MainShellView({super.key, this.initialIndex = 0});
  final int initialIndex;

  @override
  State<MainShellView> createState() => _MainShellViewState();
}

class _MainShellViewState extends State<MainShellView> {
  late int _index = widget.initialIndex.clamp(0, 2);

  void _setTab(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    final TextTheme t = Theme.of(context).textTheme;

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          StudioView(
            onOpenSubscription: () => _setTab(1),
            onOpenProfile: () => _setTab(2),
          ),
          const SubscriptionView(),
          ProfileView(onOpenUpgrade: () => _setTab(1)),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.surface(b),
          border: Border(top: BorderSide(color: AppColors.border(b))),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Flexible(
                  child: _NavPill(
                    icon: Icons.graphic_eq_rounded,
                    label: 'Studio',
                    selected: _index == 0,
                    onTap: () => _setTab(0),
                    textTheme: t,
                    brightness: b,
                  ),
                ),
                Flexible(
                  child: _NavPill(
                    icon: Icons.workspace_premium_rounded,
                    label: 'Pro Pass',
                    selected: _index == 1,
                    onTap: () => _setTab(1),
                    textTheme: t,
                    brightness: b,
                  ),
                ),
                Flexible(
                  child: _NavPill(
                    icon: Icons.person_rounded,
                    label: 'Profile',
                    selected: _index == 2,
                    onTap: () => _setTab(2),
                    textTheme: t,
                    brightness: b,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavPill extends StatelessWidget {
  const _NavPill({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.textTheme,
    required this.brightness,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final TextTheme textTheme;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: AppRadius.chip,
          gradient: selected ? AppColors.signature : null,
          color: selected ? null : Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 19,
              color: selected ? Colors.white : AppColors.muted(brightness),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelLarge?.copyWith(
                  color: selected ? Colors.white : AppColors.muted(brightness),
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
