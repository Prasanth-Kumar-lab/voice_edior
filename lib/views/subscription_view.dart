import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import '../controllers/admin_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../widgets/common/vp_buttons.dart';

class SubscriptionView extends StatefulWidget {
  const SubscriptionView({super.key});

  @override
  State<SubscriptionView> createState() => _SubscriptionViewState();
}

class _SubscriptionViewState extends State<SubscriptionView> {
  bool _yearly = true;
  int _selectedTier = 1;

  static const List<({String icon, String title, String subtitle})> _proFeatures = [
    (
      icon: '🎭',
      title: 'Theatrical & Ultra-Bass Engine',
      subtitle: 'Pitch-tracked sub-octave synthesis & stereo cinema-hall depth',
    ),
    (
      icon: '🔇',
      title: 'Zero-Noise Pause Gate (-60 dB)',
      subtitle: 'Pin-drop studio silence between words + transient click removal',
    ),
    (
      icon: '✨',
      title: 'Crystal Treble & Studio Booth',
      subtitle: 'Speech-gated 16 kHz air shimmer & wide Haas acoustic booth',
    ),
    (
      icon: '📻',
      title: 'Broadcast & Streaming Mastering',
      subtitle: 'True-peak safe -16 LUFS (Podcast) & -14 LUFS (Vocals) export',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final Brightness b = Theme.of(context).brightness;
    final AdminController admin = Get.find<AdminController>();

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
            children: [
              // Top badge + header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: AppRadius.chip,
                      gradient: AppColors.signature,
                      boxShadow: AppShadows.glow(),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.workspace_premium_rounded, size: 16, color: Colors.white),
                        const SizedBox(width: 6),
                        Text(
                          'VOCALPOLISH PRO',
                          style: t.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1.1),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Get.snackbar(
                      'Purchases Restored',
                      'Your Studio Pro license is active on this device.',
                      snackPosition: SnackPosition.BOTTOM,
                    ),
                    child: Text('Restore', style: t.labelMedium?.copyWith(color: AppColors.muted(b))),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Upgrade to Cinema &\nBroadcast Sound',
                style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.15),
              ).animate().fadeIn().slideY(begin: 0.08),
              const SizedBox(height: 6),
              Text(
                'Unlimited 48 kHz AI denoising, speaking-driven sub-bass, and stereo hall mastering with zero watermarks.',
                style: t.bodyMedium?.copyWith(color: AppColors.muted(b)),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Billing cycle toggle
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt(b),
                  borderRadius: AppRadius.chip,
                  border: Border.all(color: AppColors.border(b)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _yearly = false),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            borderRadius: AppRadius.chip,
                            gradient: !_yearly ? AppColors.signature : null,
                          ),
                          child: Center(
                            child: Text(
                              'Monthly Billing',
                              style: t.labelLarge?.copyWith(color: !_yearly ? Colors.white : AppColors.muted(b)),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _yearly = true),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            borderRadius: AppRadius.chip,
                            gradient: _yearly ? AppColors.signature : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Yearly',
                                style: t.labelLarge?.copyWith(color: _yearly ? Colors.white : AppColors.muted(b)),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  borderRadius: AppRadius.chip,
                                  color: _yearly ? Colors.black.withValues(alpha: 0.28) : AppColors.surface(b),
                                ),
                                child: Text(
                                  'SAVE 45%',
                                  style: t.labelSmall?.copyWith(
                                    color: _yearly ? AppColors.accentBright : AppColors.accent,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Dynamic Plan Cards synced from AdminController
              Obx(() {
                final enabledPlans = admin.plans.where((p) => p.enabled).toList();
                return Column(
                  children: [
                    for (int i = 0; i < enabledPlans.length; i++) ...[
                      _PlanCard(
                        title: enabledPlans[i].name,
                        badge: enabledPlans[i].badge,
                        price: enabledPlans[i].monthlyPrice == 0
                            ? '\$0'
                            : '\$${(_yearly ? enabledPlans[i].yearlyPrice : enabledPlans[i].monthlyPrice).toStringAsFixed(2)}',
                        period: enabledPlans[i].monthlyPrice == 0
                            ? 'forever'
                            : (_yearly
                                ? '/ month · billed \$${(enabledPlans[i].yearlyPrice * 12).toStringAsFixed(2)}/yr'
                                : '/ month'),
                        description: enabledPlans[i].description,
                        selected: _selectedTier == i,
                        popular: enabledPlans[i].popular,
                        onTap: () => setState(() => _selectedTier = i),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ],
                );
              }),
              const SizedBox(height: AppSpacing.md),

              // Included DSP Features Card
              VpCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.tune_rounded, size: 18, color: AppColors.accentBright),
                        const SizedBox(width: 8),
                        Text('What’s unlocked in Studio AI Pro', style: t.titleMedium),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    for (final item in _proFeatures)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                borderRadius: AppRadius.button,
                                color: AppColors.surfaceAlt(b),
                                border: Border.all(color: AppColors.border(b)),
                              ),
                              child: Center(child: Text(item.icon, style: const TextStyle(fontSize: 16))),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.title, style: t.labelLarge),
                                  const SizedBox(height: 2),
                                  Text(item.subtitle, style: t.bodySmall?.copyWith(color: AppColors.muted(b))),
                                ],
                              ),
                            ),
                            const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.success),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              VpButton(
                label: _selectedTier == 0 ? 'Continue with Starter' : 'Activate Selected Plan',
                icon: Icons.bolt_rounded,
                onPressed: () async {
                  final enabledPlans = admin.plans.where((p) => p.enabled).toList();
                  if (_selectedTier >= 0 && _selectedTier < enabledPlans.length) {
                    final plan = enabledPlans[_selectedTier];
                    await admin.subscribeCurrentUser(plan, yearly: _yearly);
                    Get.snackbar(
                      'Plan Updated in MongoDB',
                      'Your account is now on ${plan.name}!',
                      snackPosition: SnackPosition.BOTTOM,
                    );
                  }
                },
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Cancel anytime in 1 tap · No charge for 7 days',
                  style: t.bodySmall?.copyWith(color: AppColors.muted(b)),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.title,
    required this.badge,
    required this.price,
    required this.period,
    required this.description,
    required this.selected,
    required this.popular,
    required this.onTap,
  });

  final String title, badge, price, period, description;
  final bool selected, popular;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    final TextTheme t = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: AppRadius.card,
          color: AppColors.surface(b),
          border: Border.all(
            color: selected ? AppColors.accentBright : AppColors.border(b),
            width: selected ? 1.8 : 1,
          ),
          boxShadow: selected ? AppShadows.glow() : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title, style: t.titleLarge),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.chip,
                    gradient: popular ? AppColors.signature : null,
                    color: popular ? null : AppColors.surfaceAlt(b),
                  ),
                  child: Text(
                    badge,
                    style: t.labelSmall?.copyWith(
                      color: popular ? Colors.white : AppColors.muted(b),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(
                  selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: selected ? AppColors.accentBright : AppColors.border(b),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                ShaderMask(
                  shaderCallback: (r) => AppColors.signature.createShader(r),
                  child: Text(
                    price,
                    style: t.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 6),
                Text(period, style: t.bodySmall?.copyWith(color: AppColors.muted(b))),
              ],
            ),
            const SizedBox(height: 6),
            Text(description, style: t.bodySmall?.copyWith(color: AppColors.muted(b))),
          ],
        ),
      ),
    );
  }
}
