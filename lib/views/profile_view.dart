import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import '../controllers/admin_controller.dart';
import '../services/enhance_server.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../utils/app_localization.dart';
import '../widgets/common/vp_buttons.dart';
import 'login_view.dart';

class ProfileView extends StatefulWidget {
  const ProfileView({super.key, this.onOpenUpgrade});
  final VoidCallback? onOpenUpgrade;

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  bool _zeroPauseGate = true;
  bool _autoNormalizeLufs = true;
  bool _wav24BitExport = true;
  String _defaultFilter = 'Studio Clarity';

  static String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : 'U';
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final Brightness b = Theme.of(context).brightness;
    final EnhanceServer server = Get.find();
    final AdminController adm = Get.find<AdminController>();

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
            children: [
              // Header
              Row(
                children: [
                  Text('Creator Profile', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => adm.syncFromMongo(),
                    tooltip: 'Sync with MongoDB',
                    icon: const Icon(Icons.sync_rounded, size: 20, color: AppColors.accentBright),
                  ),
                  IconButton(
                    onPressed: () => Get.offAll(() => const LoginView(), transition: Transition.fadeIn),
                    tooltip: 'Sign Out',
                    icon: const Icon(Icons.logout_rounded, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Dynamic Creator Hero Card synced from MongoDB `vocalpolish_studio.users`
              Obx(() {
                final AdminUser? u = adm.currentUser.value;
                final String name = u?.name ?? 'Alex Rivera';
                final String email = u?.email ?? 'alex@podcaststudio.io';
                final String plan = u?.planName ?? 'Studio AI Pro';
                final int masters = u?.mastersCount ?? 148;
                final int mins = u?.minutesProcessed ?? 842;

                return VpCard(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: AppColors.signature,
                              boxShadow: AppShadows.glow(),
                            ),
                            child: Center(
                              child: Text(
                                _initials(name),
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        name,
                                        style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: const BoxDecoration(
                                        borderRadius: AppRadius.chip,
                                        gradient: AppColors.signature,
                                      ),
                                      child: Text(
                                        plan.toUpperCase(),
                                        style: t.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(email, style: t.bodySmall?.copyWith(color: AppColors.muted(b))),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: server.connected.value ? AppColors.success : AppColors.warning,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        server.connected.value
                                            ? 'MongoDB Synced · ${server.engine.value}'
                                            : 'On-device fallback',
                                        style: t.labelSmall?.copyWith(color: AppColors.accentBright),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      // Studio Metrics Row
                      Row(
                        children: [
                          Expanded(child: _StatBox(value: '$masters', label: 'Masters')),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(child: _StatBox(value: '${mins}m', label: 'Audio Mins')),
                          const SizedBox(width: AppSpacing.sm),
                          const Expanded(child: _StatBox(value: '48 kHz', label: 'Sample Rate')),
                        ],
                      ),
                    ],
                  ),
                );
              }).animate().fadeIn().slideY(begin: 0.06),

              const SizedBox(height: AppSpacing.md),

              // Upgrade Banner
              GestureDetector(
                onTap: widget.onOpenUpgrade,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.card,
                    gradient: AppColors.signature,
                    boxShadow: AppShadows.glow(),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 30),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Obx(() {
                          final String plan = adm.currentUser.value?.planName ?? 'Studio AI Pro';
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$plan Active',
                                style: t.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                              ),
                              Text(
                                'Theatrical Bass, Crystal Treble & Stereo Booth unlocked',
                                style: t.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.88)),
                              ),
                            ],
                          );
                        }),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 16),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.lg),
              Text('Audio & DSP Preferences', style: t.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              VpCard(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Zero-Noise Pause Gate (-60 dB)', style: t.labelLarge),
                      subtitle: Text('Pitch-black studio silence when you stop speaking', style: t.bodySmall?.copyWith(color: AppColors.muted(b))),
                      value: _zeroPauseGate,
                      activeThumbColor: AppColors.accentBright,
                      onChanged: (v) => setState(() => _zeroPauseGate = v),
                    ),
                    Divider(color: AppColors.border(b), height: 1),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Broadcast Loudness (-16 LUFS)', style: t.labelLarge),
                      subtitle: Text('True-peak ceiling protection at -1.0 dBTP', style: t.bodySmall?.copyWith(color: AppColors.muted(b))),
                      value: _autoNormalizeLufs,
                      activeThumbColor: AppColors.accentBright,
                      onChanged: (v) => setState(() => _autoNormalizeLufs = v),
                    ),
                    Divider(color: AppColors.border(b), height: 1),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Lossless 48 kHz WAV Export', style: t.labelLarge),
                      subtitle: Text('Uncompressed master quality for video & podcasts', style: t.bodySmall?.copyWith(color: AppColors.muted(b))),
                      value: _wav24BitExport,
                      activeThumbColor: AppColors.accentBright,
                      onChanged: (v) => setState(() => _wav24BitExport = v),
                    ),
                    Divider(color: AppColors.border(b), height: 1),
                    Obx(() {
                      final tones = adm.dynamicPodcastTones;
                      final bool hasDefault = tones.any((e) => e.label == _defaultFilter);
                      final String currentVal = hasDefault ? _defaultFilter : (tones.isNotEmpty ? tones.first.label : 'General + Bass');
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Default Podcast Filter', style: t.labelLarge),
                        subtitle: Text(currentVal, style: t.bodySmall?.copyWith(color: AppColors.accentBright)),
                        trailing: DropdownButton<String>(
                          value: currentVal,
                          underline: const SizedBox.shrink(),
                          dropdownColor: AppColors.surfaceAlt(b),
                          items: [
                            for (final tone in tones)
                              DropdownMenuItem(value: tone.label, child: Text(tone.label)),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _defaultFilter = v);
                          },
                        ),
                      );
                    }),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.lg),
              Obx(() {
                final AppPreferencesController prefs =
                    Get.find<AppPreferencesController>();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(prefs.trKey('appearance_language'), style: t.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    VpCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(prefs.trKey('theme_mode'), style: t.labelLarge),
                            trailing: SegmentedButton<ThemeMode>(
                              segments: const [
                                ButtonSegment(
                                  value: ThemeMode.dark,
                                  label: Text('Dark', style: TextStyle(fontSize: 11)),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.light,
                                  label: Text('Light', style: TextStyle(fontSize: 11)),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.system,
                                  label: Text('Auto', style: TextStyle(fontSize: 11)),
                                ),
                              ],
                              selected: {prefs.themeMode.value},
                              onSelectionChanged: (s) => prefs.setThemeMode(s.first),
                            ),
                          ),
                          Divider(color: AppColors.border(b), height: 1),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(prefs.trKey('language'), style: t.labelLarge),
                            trailing: DropdownButton<String>(
                              value: prefs.languageCode.value,
                              underline: const SizedBox.shrink(),
                              dropdownColor: AppColors.surfaceAlt(b),
                              items: const [
                                DropdownMenuItem(value: 'en', child: Text('English')),
                                DropdownMenuItem(value: 'hi', child: Text('हिन्दी (Hindi)')),
                                DropdownMenuItem(value: 'te', child: Text('తెలుగు (Telugu)')),
                              ],
                              onChanged: (v) {
                                if (v != null) prefs.setLanguage(v);
                              },
                            ),
                          ),
                          Divider(color: AppColors.border(b), height: 1),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.verified_user_outlined,
                              color: AppColors.accentBright,
                              size: 20,
                            ),
                            title: Text(prefs.trKey('privacy_terms'), style: t.labelLarge),
                            subtitle: Text(
                              'Google Play Data Safety, Terms of Service & Account Deletion',
                              style: t.bodySmall?.copyWith(color: AppColors.muted(b)),
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                            onTap: () => _showPrivacyAndAccountDeletionDialog(context, prefs),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }),

              const SizedBox(height: AppSpacing.lg),
              Text('Recent Studio Masters (MongoDB Live)', style: t.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              Obx(() {
                final List<String> jobs = adm.currentUser.value?.recentJobs ?? const [];
                if (jobs.isEmpty) {
                  return VpCard(
                    child: Text(
                      'No audio masters recorded yet. Record or upload a clip in the Studio tab!',
                      style: t.bodySmall?.copyWith(color: AppColors.muted(b)),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final String job in jobs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: VpCard(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  borderRadius: AppRadius.button,
                                  color: AppColors.surfaceAlt(b),
                                  border: Border.all(color: AppColors.border(b)),
                                ),
                                child: const Icon(Icons.graphic_eq_rounded, color: AppColors.accentBright, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(job, style: t.labelLarge),
                              ),
                              const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 22),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              }),

              const SizedBox(height: AppSpacing.md),
              VpButton(
                label: 'Sign Out of Studio',
                icon: Icons.logout_rounded,
                filled: false,
                onPressed: () => Get.offAll(() => const LoginView(), transition: Transition.fadeIn),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }

  void _showPrivacyAndAccountDeletionDialog(
    BuildContext context,
    AppPreferencesController prefs,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(prefs.trKey('privacy_terms')),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '1. Audio Privacy & Ephemeral Processing\n'
                'Uploaded takes are processed in isolated memory and automatically purged after enhancement. On-device mixes stay strictly on your phone unless you explicitly share them.\n\n'
                '2. Google Play Data Safety\n'
                'VocalPolish collects only your account email and subscription tier for Studio AI Pro entitlement sync. Passwords are protected with per-user salted scrypt hashes.\n\n'
                '3. Account & Cloud Data Deletion\n'
                'You can permanently delete your account and all cloud history at any time below.',
                style: TextStyle(fontSize: 12.5, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Get.offAll(() => const LoginView(), transition: Transition.fadeIn);
            },
            child: Text(
              prefs.trKey('delete_account'),
              style: const TextStyle(color: AppColors.danger),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.value, required this.label});
  final String value, label;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: AppRadius.button,
        color: AppColors.surfaceAlt(b),
        border: Border.all(color: AppColors.border(b)),
      ),
      child: Column(
        children: [
          ShaderMask(
            shaderCallback: (r) => AppColors.signature.createShader(r),
            child: Text(value, style: t.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 2),
          Text(label, style: t.labelSmall?.copyWith(color: AppColors.muted(b)), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
