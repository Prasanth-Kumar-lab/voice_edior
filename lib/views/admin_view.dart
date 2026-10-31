import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import '../controllers/admin_controller.dart';
import '../services/enhance_server.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../widgets/common/vp_buttons.dart';

class AdminView extends StatelessWidget {
  const AdminView({super.key});

  @override
  Widget build(BuildContext context) {
    final AdminController c = Get.find<AdminController>();
    final TextTheme t = Theme.of(context).textTheme;
    final Brightness b = Theme.of(context).brightness;

    const List<({String label, IconData icon})> tabs = [
      (label: 'Overview', icon: Icons.dashboard_customize_rounded),
      (label: 'Users', icon: Icons.people_alt_rounded),
      (label: 'Plans & Rev', icon: Icons.monetization_on_rounded),
      (label: 'App Features', icon: Icons.extension_rounded),
      (label: 'Usage & DSP', icon: Icons.analytics_rounded),
    ];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: Get.back,
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          tooltip: 'Back to App',
        ),
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                borderRadius: AppRadius.button,
                gradient: AppColors.signature,
              ),
              child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('VocalPolish Admin', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                Text('Command Center · Live Sync', style: t.labelSmall?.copyWith(color: AppColors.accentBright)),
              ],
            ),
          ],
        ),
        actions: [
          Obx(() => Container(
                margin: const EdgeInsets.only(right: AppSpacing.md),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  borderRadius: AppRadius.chip,
                  color: AppColors.surface(b),
                  border: Border.all(color: AppColors.border(b)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.maintenanceMode.value ? AppColors.warning : AppColors.success,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      c.maintenanceMode.value ? 'MAINT' : 'LIVE',
                      style: t.labelSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              )),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              children: [
                // Horizontal Sub-Nav Bar
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                  child: Obx(() => Row(
                        children: [
                          for (int i = 0; i < tabs.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: GestureDetector(
                                onTap: () => c.tabIndex.value = i,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 220),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                                  decoration: BoxDecoration(
                                    borderRadius: AppRadius.chip,
                                    gradient: c.tabIndex.value == i ? AppColors.signature : null,
                                    color: c.tabIndex.value == i ? null : AppColors.surface(b),
                                    border: Border.all(
                                      color: c.tabIndex.value == i ? Colors.transparent : AppColors.border(b),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        tabs[i].icon,
                                        size: 16,
                                        color: c.tabIndex.value == i ? Colors.white : AppColors.muted(b),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        tabs[i].label,
                                        style: t.labelLarge?.copyWith(
                                          color: c.tabIndex.value == i ? Colors.white : AppColors.text(b),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      )),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Obx(() {
                    return switch (c.tabIndex.value) {
                      0 => _OverviewTab(c),
                      1 => _UsersTab(c),
                      2 => _SubscriptionsTab(c),
                      3 => _FeaturesTab(c),
                      _ => _UsageTelemetryTab(c),
                    };
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── 1. OVERVIEW & REVENUE TAB ─────────────────────────────

class _OverviewTab extends StatelessWidget {
  const _OverviewTab(this.c);
  final AdminController c;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final Brightness b = Theme.of(context).brightness;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        // Hero Revenue Banner
        Obx(() => Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                borderRadius: AppRadius.card,
                gradient: AppColors.signature,
                boxShadow: AppShadows.glow(),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'TOTAL ANNUALIZED APP REVENUE',
                        style: t.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.9), letterSpacing: 1.2, fontWeight: FontWeight.w800),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          borderRadius: AppRadius.chip,
                          color: Colors.black.withValues(alpha: 0.25),
                        ),
                        child: Text(
                          '+28.4% MoM',
                          style: t.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '\$${_fmtMoney(c.totalRevenueUsd)}',
                    style: t.displaySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Monthly Recurring Revenue (MRR): \$${_fmtMoney(c.mrrUsd)} / mo  ·  ${c.plans.fold<int>(0, (s, p) => s + p.activeSubscribers)} Total Subscribers',
                    style: t.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
                  ),
                ],
              ),
            )).animate().fadeIn().slideY(begin: 0.06),

        const SizedBox(height: AppSpacing.md),

        // 4 KPI Grid Cards
        Obx(() => GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: AppSpacing.sm,
              crossAxisSpacing: AppSpacing.sm,
              childAspectRatio: 1.65,
              children: [
                _KpiCard(
                  icon: Icons.people_alt_rounded,
                  label: 'Registered Users',
                  value: '${c.users.length}',
                  sub: '${c.totalActiveUsers} active · ${c.totalDeactivatedUsers} paused',
                  color: AppColors.accentBright,
                  onTap: () => c.tabIndex.value = 1,
                ),
                _KpiCard(
                  icon: Icons.workspace_premium_rounded,
                  label: 'Subscription Plans',
                  value: '${c.plans.length} Tiers',
                  sub: '${c.plans.where((p) => p.enabled).length} live in store',
                  color: AppColors.accent,
                  onTap: () => c.tabIndex.value = 2,
                ),
                _KpiCard(
                  icon: Icons.extension_rounded,
                  label: 'Active App Features',
                  value: '${c.features.where((f) => f.enabled).length}/${c.features.length}',
                  sub: 'Podcast & DSP modules',
                  color: AppColors.success,
                  onTap: () => c.tabIndex.value = 3,
                ),
                _KpiCard(
                  icon: Icons.graphic_eq_rounded,
                  label: 'Audio Masters',
                  value: '${c.totalMastersProcessed}',
                  sub: '${c.totalMinutesProcessed} mins processed',
                  color: AppColors.warning,
                  onTap: () => c.tabIndex.value = 4,
                ),
              ],
            )),

        const SizedBox(height: AppSpacing.lg),

        // Monthly Revenue Growth Bar Chart
        VpCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.trending_up_rounded, color: AppColors.accentBright, size: 18),
                  const SizedBox(width: 8),
                  Text('Monthly Revenue Growth (USD)', style: t.titleMedium),
                  const Spacer(),
                  Text('Last 6 Months', style: t.labelSmall?.copyWith(color: AppColors.muted(b))),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: 140,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final item in c.monthlyRevenue)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                '\$${item.revenueK}k',
                                style: t.labelSmall?.copyWith(color: AppColors.accentBright, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                height: (item.revenueK / 28.0 * 92).clamp(16, 92),
                                decoration: const BoxDecoration(
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                                  gradient: AppColors.signature,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(item.month, style: t.labelSmall?.copyWith(color: AppColors.muted(b))),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.lg),

        // Recent Revenue Transactions
        Row(
          children: [
            Text('Recent Subscription Payments', style: t.titleMedium),
            const Spacer(),
            TextButton(
              onPressed: () => c.tabIndex.value = 2,
              child: Text('Manage Plans →', style: t.labelMedium?.copyWith(color: AppColors.accentBright)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Obx(() => Column(
              children: [
                for (final tx in c.transactions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: VpCard(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              borderRadius: AppRadius.button,
                              color: AppColors.surfaceAlt(b),
                              border: Border.all(color: AppColors.border(b)),
                            ),
                            child: const Icon(Icons.receipt_long_rounded, color: AppColors.success, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(tx.userName, style: t.labelLarge),
                                Text('${tx.planName} (${tx.billingCycle}) · ${tx.method}', style: t.bodySmall?.copyWith(color: AppColors.muted(b))),
                                Text(tx.timestamp, style: t.labelSmall?.copyWith(color: AppColors.muted(b))),
                              ],
                            ),
                          ),
                          Text(
                            '+\$${tx.amountUsd.toStringAsFixed(2)}',
                            style: t.titleMedium?.copyWith(color: AppColors.success, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            )),
      ],
    );
  }

  static String _fmtMoney(double v) {
    final String fixed = v.toStringAsFixed(2);
    final List<String> parts = fixed.split('.');
    final String intPart = parts[0].replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    return '$intPart.${parts[1]}';
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label, value, sub;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final Brightness b = Theme.of(context).brightness;
    return VpCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: t.labelSmall?.copyWith(color: AppColors.muted(b)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.arrow_outward_rounded, size: 14, color: AppColors.muted(b)),
            ],
          ),
          Text(value, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          Text(sub, style: t.labelSmall?.copyWith(color: color), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ───────────────────────────── 2. USERS MANAGEMENT TAB ─────────────────────────────

class _UsersTab extends StatelessWidget {
  const _UsersTab(this.c);
  final AdminController c;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final Brightness b = Theme.of(context).brightness;
    const List<String> filters = ['All', 'Active', 'Deactivated', 'Pro'];

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        // Top Header + Provision User Button
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Creator Directory', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  Obx(() => Text(
                        '${c.users.length} total accounts · Tap any user for full profile & logs',
                        style: t.bodySmall?.copyWith(color: AppColors.muted(b)),
                      )),
                ],
              ),
            ),
            VpButton(
              label: 'Add User',
              icon: Icons.person_add_alt_1_rounded,
              expand: false,
              compact: true,
              onPressed: () => _showAddUserDialog(context, c),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        // Search input
        TextField(
          onChanged: (v) => c.userSearch.value = v,
          decoration: const InputDecoration(
            hintText: 'Search by name, email, role or subscription...',
            prefixIcon: Icon(Icons.search_rounded, size: 20),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),

        // Status filter chips
        Obx(() => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in filters)
                  GestureDetector(
                    onTap: () => c.userFilter.value = f,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: AppRadius.chip,
                        gradient: c.userFilter.value == f ? AppColors.signature : null,
                        color: c.userFilter.value == f ? null : AppColors.surface(b),
                        border: Border.all(
                          color: c.userFilter.value == f ? Colors.transparent : AppColors.border(b),
                        ),
                      ),
                      child: Text(
                        f,
                        style: t.labelMedium?.copyWith(
                          color: c.userFilter.value == f ? Colors.white : AppColors.muted(b),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            )),
        const SizedBox(height: AppSpacing.md),

        // Users List
        Obx(() {
          final list = c.filteredUsers;
          if (list.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text('No matching users found.', style: t.bodyMedium?.copyWith(color: AppColors.muted(b))),
              ),
            );
          }
          return Column(
            children: [
              for (final u in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: VpCard(
                    onTap: () => _showUserDetailSheet(context, c, u),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            // Avatar
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: u.status == UserStatus.active ? AppColors.signature : null,
                                color: u.status == UserStatus.active ? null : AppColors.surfaceAlt(b),
                              ),
                              child: Center(
                                child: Text(
                                  _initials(u.name),
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          u.name,
                                          style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          borderRadius: AppRadius.chip,
                                          color: u.status == UserStatus.active
                                              ? AppColors.success.withValues(alpha: 0.16)
                                              : AppColors.danger.withValues(alpha: 0.16),
                                        ),
                                        child: Text(
                                          u.status == UserStatus.active ? 'ACTIVE' : 'DEACTIVATED',
                                          style: t.labelSmall?.copyWith(
                                            color: u.status == UserStatus.active ? AppColors.success : AppColors.danger,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text('${u.email} · ${u.role}', style: t.bodySmall?.copyWith(color: AppColors.muted(b))),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(Icons.workspace_premium_rounded, size: 13, color: AppColors.accentBright),
                                      const SizedBox(width: 4),
                                      Text(u.planName, style: t.labelSmall?.copyWith(color: AppColors.accentBright)),
                                      const SizedBox(width: 10),
                                      Icon(Icons.graphic_eq_rounded, size: 13, color: AppColors.muted(b)),
                                      const SizedBox(width: 4),
                                      Text('${u.mastersCount} masters (${u.minutesProcessed}m)', style: t.labelSmall?.copyWith(color: AppColors.muted(b))),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Divider(color: AppColors.border(b), height: 1),
                        const SizedBox(height: 8),
                        // Quick Actions Row
                        Row(
                          children: [
                            Text(
                              'LTV: \$${u.totalSpentUsd.toStringAsFixed(2)} · Fav: ${u.favoriteFilter}',
                              style: t.labelSmall?.copyWith(color: AppColors.muted(b)),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              onPressed: () => _showUserDetailSheet(context, c, u),
                              icon: const Icon(Icons.visibility_outlined, size: 15),
                              label: const Text('Profile'),
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                foregroundColor: u.status == UserStatus.active ? AppColors.warning : AppColors.success,
                              ),
                              onPressed: () {
                                c.toggleUserStatus(u);
                                Get.snackbar(
                                  u.status == UserStatus.active ? 'Account Reactivated' : 'Account Deactivated',
                                  '${u.name} (${u.email}) is now ${u.status == UserStatus.active ? "Active" : "Deactivated"}.',
                                  snackPosition: SnackPosition.BOTTOM,
                                );
                              },
                              icon: Icon(u.status == UserStatus.active ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded, size: 15),
                              label: Text(u.status == UserStatus.active ? 'Deactivate' : 'Activate'),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Remove User',
                              onPressed: () => _confirmRemoveUser(context, c, u),
                              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        }),
      ],
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : 'U';
  }

  void _confirmRemoveUser(BuildContext context, AdminController c, AdminUser u) {
    Get.dialog(
      AlertDialog(
        title: const Text('Remove User Permanently?'),
        content: Text('Are you sure you want to remove ${u.name} (${u.email}) and revoke their studio license?'),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () {
              c.deleteUser(u);
              Get.back();
              Get.snackbar('User Removed', '${u.name} was deleted from VocalPolish.', snackPosition: SnackPosition.BOTTOM);
            },
            child: const Text('Remove User'),
          ),
        ],
      ),
    );
  }

  void _showAddUserDialog(BuildContext context, AdminController c) {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    String role = 'Podcaster';
    String plan = c.plans.isNotEmpty ? c.plans[1].name : 'Studio AI Pro';

    Get.dialog(
      StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Provision Studio User'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(hintText: 'Full Name')),
                const SizedBox(height: 10),
                TextField(controller: emailCtrl, decoration: const InputDecoration(hintText: 'Email Address')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  items: const [
                    DropdownMenuItem(value: 'Podcaster', child: Text('Podcaster')),
                    DropdownMenuItem(value: 'Vocalist', child: Text('Vocalist')),
                    DropdownMenuItem(value: 'Voiceover', child: Text('Voiceover')),
                    DropdownMenuItem(value: 'Streamer', child: Text('Streamer')),
                  ],
                  onChanged: (v) => setState(() => role = v ?? 'Podcaster'),
                  decoration: const InputDecoration(labelText: 'Creator Role'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: plan,
                  items: [
                    for (final p in c.plans) DropdownMenuItem(value: p.name, child: Text(p.name)),
                  ],
                  onChanged: (v) => setState(() => plan = v ?? plan),
                  decoration: const InputDecoration(labelText: 'Assign Subscription'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: Get.back, child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty || emailCtrl.text.trim().isEmpty) return;
                c.addNewUser(
                  name: nameCtrl.text.trim(),
                  email: emailCtrl.text.trim(),
                  role: role,
                  planName: plan,
                );
                Get.back();
                Get.snackbar('User Provisioned', '${nameCtrl.text.trim()} added with $plan.', snackPosition: SnackPosition.BOTTOM);
              },
              child: const Text('Create User'),
            ),
          ],
        ),
      ),
    );
  }

  void _showUserDetailSheet(BuildContext context, AdminController c, AdminUser u) {
    final TextTheme t = Theme.of(context).textTheme;
    final Brightness b = Theme.of(context).brightness;

    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface(b),
          borderRadius: AppRadius.sheet,
          border: Border.all(color: AppColors.border(b)),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.signature),
                    child: Center(
                      child: Text(_initials(u.name), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${u.name} (${u.id})', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                        Text('${u.email} · ${u.deviceModel}', style: t.bodySmall?.copyWith(color: AppColors.muted(b))),
                        Text('Joined ${u.joinedDate} · Last active ${u.lastActive}', style: t.labelSmall?.copyWith(color: AppColors.accentBright)),
                      ],
                    ),
                  ),
                  IconButton(onPressed: Get.back, icon: const Icon(Icons.close_rounded)),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Usage & Telemetry Grid
              Row(
                children: [
                  Expanded(child: _MiniStat('Masters', '${u.mastersCount}')),
                  const SizedBox(width: 8),
                  Expanded(child: _MiniStat('Audio Mins', '${u.minutesProcessed}m')),
                  const SizedBox(width: 8),
                  Expanded(child: _MiniStat('Storage', '${u.storageUsedMb.toStringAsFixed(0)} MB')),
                  const SizedBox(width: 8),
                  Expanded(child: _MiniStat('Total Spent', '\$${u.totalSpentUsd.toStringAsFixed(0)}')),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Change Subscription Tier directly from Admin
              Text('Assigned Subscription Plan', style: t.labelLarge),
              const SizedBox(height: 8),
              Obx(() => Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in c.plans)
                        GestureDetector(
                          onTap: () => c.changeUserPlan(u, p.name),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              borderRadius: AppRadius.chip,
                              gradient: u.planName == p.name ? AppColors.signature : null,
                              color: u.planName == p.name ? null : AppColors.surfaceAlt(b),
                              border: Border.all(color: AppColors.border(b)),
                            ),
                            child: Text(
                              p.name,
                              style: t.labelMedium?.copyWith(
                                color: u.planName == p.name ? Colors.white : AppColors.text(b),
                              ),
                            ),
                          ),
                        ),
                    ],
                  )),
              const SizedBox(height: AppSpacing.md),

              Text('Recent Audio Processing History', style: t.labelLarge),
              const SizedBox(height: 8),
              if (u.recentJobs.isEmpty)
                Text('No audio jobs recorded yet.', style: t.bodySmall?.copyWith(color: AppColors.muted(b)))
              else
                for (final job in u.recentJobs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, size: 15, color: AppColors.success),
                        const SizedBox(width: 8),
                        Expanded(child: Text(job, style: t.bodySmall)),
                      ],
                    ),
                  ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: VpButton(
                      label: u.status == UserStatus.active ? 'Deactivate Account' : 'Reactivate Account',
                      icon: u.status == UserStatus.active ? Icons.block_rounded : Icons.check_circle_outline_rounded,
                      filled: false,
                      onPressed: () {
                        c.toggleUserStatus(u);
                        Get.back();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: VpButton(
                      label: 'Delete User',
                      icon: Icons.delete_forever_rounded,
                      onPressed: () {
                        Get.back();
                        _confirmRemoveUser(context, c, u);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      isScrollControlled: true,
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.label, this.val);
  final String label, val;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        borderRadius: AppRadius.button,
        color: AppColors.surfaceAlt(b),
        border: Border.all(color: AppColors.border(b)),
      ),
      child: Column(
        children: [
          Text(val, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.accentBright)),
          Text(label, style: t.labelSmall?.copyWith(color: AppColors.muted(b)), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

// ───────────────────────────── 3. SUBSCRIPTIONS & PLANS TAB ─────────────────────────────

class _SubscriptionsTab extends StatelessWidget {
  const _SubscriptionsTab(this.c);
  final AdminController c;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final Brightness b = Theme.of(context).brightness;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Subscription Tiers', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  Text(
                    'Add or edit plans here — changes sync live to the Pro Pass screen.',
                    style: t.bodySmall?.copyWith(color: AppColors.muted(b)),
                  ),
                ],
              ),
            ),
            VpButton(
              label: 'New Plan',
              icon: Icons.add_card_rounded,
              expand: false,
              compact: true,
              onPressed: () => _showCreatePlanDialog(context, c),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        Obx(() => Column(
              children: [
                for (final plan in c.plans)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: VpCard(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(plan.name, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  borderRadius: AppRadius.chip,
                                  gradient: plan.popular ? AppColors.signature : null,
                                  color: plan.popular ? null : AppColors.surfaceAlt(b),
                                ),
                                child: Text(
                                  plan.badge,
                                  style: t.labelSmall?.copyWith(
                                    color: plan.popular ? Colors.white : AppColors.muted(b),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Switch(
                                value: plan.enabled,
                                activeThumbColor: AppColors.accentBright,
                                onChanged: (_) => c.togglePlanEnabled(plan),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              ShaderMask(
                                shaderCallback: (r) => AppColors.signature.createShader(r),
                                child: Text(
                                  plan.monthlyPrice == 0 ? 'Free' : '\$${plan.monthlyPrice.toStringAsFixed(2)}/mo',
                                  style: t.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                                ),
                              ),
                              if (plan.yearlyPrice > 0) ...[
                                const SizedBox(width: 10),
                                Text(
                                  '(\$${plan.yearlyPrice.toStringAsFixed(2)}/mo billed yearly)',
                                  style: t.bodySmall?.copyWith(color: AppColors.accentBright),
                                ),
                              ],
                              const Spacer(),
                              Text(
                                '${plan.activeSubscribers} active users',
                                style: t.labelMedium?.copyWith(color: AppColors.success),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(plan.description, style: t.bodySmall?.copyWith(color: AppColors.muted(b))),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final perk in plan.perks)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    borderRadius: AppRadius.button,
                                    color: AppColors.surfaceAlt(b),
                                  ),
                                  child: Text('✓ $perk', style: t.labelSmall),
                                ),
                            ],
                          ),
                          if (plan.id != 'plan_starter') ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                style: TextButton.styleFrom(foregroundColor: AppColors.danger, visualDensity: VisualDensity.compact),
                                onPressed: () => c.deleteSubscriptionPlan(plan),
                                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                                label: const Text('Remove Tier'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            )),
      ],
    );
  }

  void _showCreatePlanDialog(BuildContext context, AdminController c) {
    final nameCtrl = TextEditingController();
    final badgeCtrl = TextEditingController(text: 'ENTERPRISE');
    final monthlyCtrl = TextEditingController(text: '49.99');
    final yearlyCtrl = TextEditingController(text: '34.99');
    final descCtrl = TextEditingController(text: 'Unlimited neural DSP, custom voice cloning & studio API.');
    final perksCtrl = TextEditingController(text: 'Unlimited 48kHz Masters, API Access, Dedicated Engineer');
    bool popular = false;

    Get.dialog(
      StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add New Subscription Plan'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Plan Name (e.g. Cinema Enterprise)')),
                const SizedBox(height: 10),
                TextField(controller: badgeCtrl, decoration: const InputDecoration(labelText: 'Badge Tag (e.g. BEST VALUE)')),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: monthlyCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Monthly USD'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: yearlyCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Yearly/mo USD'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(controller: descCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Plan Description')),
                const SizedBox(height: 10),
                TextField(controller: perksCtrl, decoration: const InputDecoration(labelText: 'Perks (comma-separated)')),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Highlight as Popular'),
                  value: popular,
                  onChanged: (v) => setState(() => popular = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: Get.back, child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) return;
                c.addSubscriptionPlan(
                  name: nameCtrl.text.trim(),
                  badge: badgeCtrl.text.trim(),
                  monthlyPrice: double.tryParse(monthlyCtrl.text) ?? 19.99,
                  yearlyPrice: double.tryParse(yearlyCtrl.text) ?? 12.99,
                  description: descCtrl.text.trim(),
                  perks: perksCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
                  popular: popular,
                );
                Get.back();
                Get.snackbar('Subscription Added', '${nameCtrl.text.trim()} is now live in the Pro Pass screen!', snackPosition: SnackPosition.BOTTOM);
              },
              child: const Text('Publish Plan'),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── 4. APP FEATURES & DSP FUNCTIONALITIES TAB ─────────────────────────────

class _FeaturesTab extends StatelessWidget {
  const _FeaturesTab(this.c);
  final AdminController c;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final Brightness b = Theme.of(context).brightness;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('App Features & DSP Modules', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  Text(
                    'Roll out new audio functionalities, toggle live modules, or gate features to Pro.',
                    style: t.bodySmall?.copyWith(color: AppColors.muted(b)),
                  ),
                ],
              ),
            ),
            VpButton(
              label: 'Add Feature',
              icon: Icons.add_moderator_rounded,
              expand: false,
              compact: true,
              onPressed: () => _showAddFeatureDialog(context, c),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        // Global App Announcement Banner Control
        VpCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.campaign_rounded, color: AppColors.accentBright, size: 18),
                  const SizedBox(width: 8),
                  Text('Live App Banner Message', style: t.labelLarge),
                ],
              ),
              const SizedBox(height: 6),
              Obx(() => Text(c.broadcastAnnouncement.value, style: t.bodySmall?.copyWith(color: AppColors.accentBright))),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Obx(() => SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text('Cloud GPU Acceleration', style: t.labelMedium),
                          value: c.cloudGpuAcceleration.value,
                          activeThumbColor: AppColors.success,
                          onChanged: (v) => c.cloudGpuAcceleration.value = v,
                        )),
                  ),
                  Expanded(
                    child: Obx(() => SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text('Maintenance Mode', style: t.labelMedium),
                          value: c.maintenanceMode.value,
                          activeThumbColor: AppColors.warning,
                          onChanged: (v) => c.maintenanceMode.value = v,
                        )),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        Obx(() => Column(
              children: [
                for (final f in c.features)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: VpCard(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  borderRadius: AppRadius.button,
                                  gradient: f.enabled ? AppColors.signature : null,
                                  color: f.enabled ? null : AppColors.surfaceAlt(b),
                                ),
                                child: Icon(f.icon, color: Colors.white, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            f.title,
                                            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            borderRadius: AppRadius.chip,
                                            color: AppColors.surfaceAlt(b),
                                          ),
                                          child: Text(f.category, style: t.labelSmall?.copyWith(color: AppColors.accentBright)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(f.description, style: t.bodySmall?.copyWith(color: AppColors.muted(b))),
                                  ],
                                ),
                              ),
                              Switch(
                                value: f.enabled,
                                activeThumbColor: AppColors.accentBright,
                                onChanged: (_) => c.toggleFeature(f),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              borderRadius: AppRadius.button,
                              color: AppColors.surfaceAlt(b),
                            ),
                            child: Text(
                              'DSP Chain: ${f.dspParams}',
                              style: t.labelSmall?.copyWith(fontFamily: 'monospace', color: AppColors.accentBright),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text('${f.usageCount} studio runs', style: t.labelSmall?.copyWith(color: AppColors.muted(b))),
                              const Spacer(),
                              GestureDetector(
                                onTap: () => c.toggleFeatureProOnly(f),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    borderRadius: AppRadius.chip,
                                    gradient: f.proOnly ? AppColors.signature : null,
                                    color: f.proOnly ? null : AppColors.surfaceAlt(b),
                                  ),
                                  child: Text(
                                    f.proOnly ? 'PRO TIER ONLY' : 'ALL USERS (FREE)',
                                    style: t.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: () => c.deleteFeature(f),
                                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            )),
      ],
    );
  }

  void _showAddFeatureDialog(BuildContext context, AdminController c) {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final dspCtrl = TextEditingController(text: 'bass: 0.65 · treble: 0.45 · space: cinema_wide');
    String category = 'Podcast Filter';
    bool proOnly = true;

    Get.dialog(
      StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Deploy New App Feature'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Feature / Filter Name (e.g. Dolby Cinema Bass)'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  items: const [
                    DropdownMenuItem(value: 'Podcast Filter', child: Text('Podcast Filter')),
                    DropdownMenuItem(value: 'DSP Engine', child: Text('DSP Engine')),
                    DropdownMenuItem(value: 'Vocal Space', child: Text('Vocal Space')),
                    DropdownMenuItem(value: 'Mastering', child: Text('Mastering')),
                  ],
                  onChanged: (v) => setState(() => category = v ?? 'Podcast Filter'),
                  decoration: const InputDecoration(labelText: 'Module Category'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'User-facing Description'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: dspCtrl,
                  decoration: const InputDecoration(labelText: 'DSP Parameters'),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Require Pro Subscription'),
                  value: proOnly,
                  onChanged: (v) => setState(() => proOnly = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: Get.back, child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (titleCtrl.text.trim().isEmpty) return;
                c.addAppFeature(
                  title: titleCtrl.text.trim(),
                  category: category,
                  description: descCtrl.text.trim().isEmpty ? 'Custom AI Studio feature deployed by Admin.' : descCtrl.text.trim(),
                  dspParams: dspCtrl.text.trim(),
                  proOnly: proOnly,
                );
                Get.back();
                Get.snackbar('Feature Deployed', '${titleCtrl.text.trim()} is now active in the app!', snackPosition: SnackPosition.BOTTOM);
              },
              child: const Text('Deploy to App'),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── 5. USAGE TELEMETRY & DSP SERVER HEALTH TAB ─────────────────────────────

class _UsageTelemetryTab extends StatelessWidget {
  const _UsageTelemetryTab(this.c);
  final AdminController c;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final Brightness b = Theme.of(context).brightness;
    final EnhanceServer server = Get.find();

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text('DSP Server & Usage Analytics', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          'Real-time Python FastAPI DSP health, filter popularity, and user activity tracking.',
          style: t.bodySmall?.copyWith(color: AppColors.muted(b)),
        ),
        const SizedBox(height: AppSpacing.md),

        // Live DSP Server Node Status Card
        VpCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Obx(() => Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: server.connected.value ? AppColors.success : AppColors.warning,
                        ),
                      )),
                  const SizedBox(width: 8),
                  Obx(() => Text(
                        server.connected.value ? 'Python Studio DSP Node · ONLINE' : 'Python Studio DSP Node · STANDBY',
                        style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      )),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => server.ping(),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Ping'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Obx(() => Text(
                    'Endpoint: ${server.host}  ·  Engine: ${server.engine.value.isEmpty ? "spectral" : server.engine.value}',
                    style: t.bodySmall?.copyWith(color: AppColors.accentBright),
                  )),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(child: _MiniStat('Sample Rate', '48 kHz')),
                  const SizedBox(width: 8),
                  Expanded(child: _MiniStat('Pause Floor', '-60 dB')),
                  const SizedBox(width: 8),
                  Expanded(child: _MiniStat('Avg SNR Gain', '+32.4 dB')),
                  const SizedBox(width: 8),
                  Expanded(child: _MiniStat('Target LUFS', '-16 / -14')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Filter Popularity Breakdown
        VpCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Podcast Filter Usage Breakdown', style: t.titleMedium),
              const SizedBox(height: AppSpacing.md),
              Obx(() {
                final int maxRuns = c.features.fold<int>(1, (m, f) => f.usageCount > m ? f.usageCount : m);
                return Column(
                  children: [
                    for (final f in c.features)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(f.title, style: t.labelLarge),
                                const Spacer(),
                                Text('${f.usageCount} runs', style: t.labelSmall?.copyWith(color: AppColors.accentBright)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: AppRadius.chip,
                              child: LinearProgressIndicator(
                                value: (f.usageCount / maxRuns).clamp(0.05, 1.0),
                                minHeight: 7,
                                backgroundColor: AppColors.surfaceAlt(b),
                                color: AppColors.accentBright,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Top Power Users by Minutes Processed
        VpCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Top Creators by Audio Usage', style: t.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              Obx(() {
                final sorted = List<AdminUser>.of(c.users)..sort((a, b) => b.minutesProcessed.compareTo(a.minutesProcessed));
                return Column(
                  children: [
                    for (final u in sorted)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: AppColors.accent,
                          child: Text(u.name[0], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                        ),
                        title: Text(u.name, style: t.labelLarge),
                        subtitle: Text('${u.planName} · Fav: ${u.favoriteFilter} · ${u.deviceModel}', style: t.bodySmall?.copyWith(color: AppColors.muted(b))),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${u.minutesProcessed} mins', style: t.labelLarge?.copyWith(color: AppColors.accentBright)),
                            Text('${u.mastersCount} files', style: t.labelSmall?.copyWith(color: AppColors.muted(b))),
                          ],
                        ),
                      ),
                  ],
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}
