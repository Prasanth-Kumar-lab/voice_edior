import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;
import '../models/podcast_presets.dart';
import '../services/enhance_server.dart';

enum UserStatus { active, deactivated, suspended }

class AdminUser {
  AdminUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.planName,
    required this.status,
    required this.mastersCount,
    required this.minutesProcessed,
    required this.storageUsedMb,
    required this.totalSpentUsd,
    required this.favoriteFilter,
    required this.joinedDate,
    required this.lastActive,
    required this.deviceModel,
    required this.recentJobs,
  });

  factory AdminUser.fromJson(Map<String, dynamic> j) => AdminUser(
        id: (j['id'] as String?) ?? 'USR-1000',
        name: (j['name'] as String?) ?? 'Studio Creator',
        email: (j['email'] as String?) ?? '',
        role: (j['role'] as String?) ?? 'Podcaster',
        planName: (j['plan_name'] as String?) ?? 'Creator Starter',
        status: (j['status'] as String?) == 'deactivated' ? UserStatus.deactivated : UserStatus.active,
        mastersCount: ((j['masters_count'] as num?) ?? 0).toInt(),
        minutesProcessed: ((j['minutes_processed'] as num?) ?? 0).toInt(),
        storageUsedMb: ((j['storage_used_mb'] as num?) ?? 0).toDouble(),
        totalSpentUsd: ((j['total_spent_usd'] as num?) ?? 0).toDouble(),
        favoriteFilter: (j['favorite_filter'] as String?) ?? 'General + Bass',
        joinedDate: (j['joined_date'] as String?) ?? '2026',
        lastActive: (j['last_active'] as String?) ?? 'Online',
        deviceModel: (j['device_model'] as String?) ?? 'Android Device',
        recentJobs: ((j['recent_jobs'] as List?) ?? const []).map((e) => e.toString()).toList(),
      );

  final String id;
  String name;
  String email;
  String role;
  String planName;
  UserStatus status;
  int mastersCount;
  int minutesProcessed;
  double storageUsedMb;
  double totalSpentUsd;
  String favoriteFilter;
  final String joinedDate;
  String lastActive;
  final String deviceModel;
  final List<String> recentJobs;
}

class AdminSubscriptionPlan {
  AdminSubscriptionPlan({
    required this.id,
    required this.name,
    required this.badge,
    required this.monthlyPrice,
    required this.yearlyPrice,
    required this.description,
    required this.perks,
    this.popular = false,
    this.activeSubscribers = 0,
    this.enabled = true,
  });

  factory AdminSubscriptionPlan.fromJson(Map<String, dynamic> j) => AdminSubscriptionPlan(
        id: (j['id'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        badge: (j['badge'] as String?) ?? 'PRO',
        monthlyPrice: ((j['monthly_price'] as num?) ?? 0).toDouble(),
        yearlyPrice: ((j['yearly_price'] as num?) ?? 0).toDouble(),
        description: (j['description'] as String?) ?? '',
        perks: ((j['perks'] as List?) ?? const []).map((e) => e.toString()).toList(),
        popular: (j['popular'] as bool?) ?? false,
        activeSubscribers: ((j['active_subscribers'] as num?) ?? 0).toInt(),
        enabled: (j['enabled'] as bool?) ?? true,
      );

  final String id;
  String name;
  String badge;
  double monthlyPrice;
  double yearlyPrice;
  String description;
  List<String> perks;
  bool popular;
  int activeSubscribers;
  bool enabled;
}

class AdminAppFeature {
  AdminAppFeature({
    required this.id,
    required this.title,
    required this.category,
    required this.description,
    required this.dspParams,
    required this.enabled,
    required this.proOnly,
    required this.usageCount,
    required this.icon,
  });

  factory AdminAppFeature.fromJson(Map<String, dynamic> j) {
    final String cat = (j['category'] as String?) ?? 'Podcast Filter';
    return AdminAppFeature(
      id: (j['id'] as String?) ?? '',
      title: (j['title'] as String?) ?? '',
      category: cat,
      description: (j['description'] as String?) ?? '',
      dspParams: (j['dsp_params'] as String?) ?? '',
      enabled: (j['enabled'] as bool?) ?? true,
      proOnly: (j['pro_only'] as bool?) ?? false,
      usageCount: ((j['usage_count'] as num?) ?? 0).toInt(),
      icon: cat.contains('Podcast')
          ? Icons.graphic_eq_rounded
          : cat.contains('DSP')
              ? Icons.blur_off_rounded
              : Icons.auto_awesome_rounded,
    );
  }

  final String id;
  String title;
  String category;
  String description;
  String dspParams;
  bool enabled;
  bool proOnly;
  int usageCount;
  final IconData icon;
}

class AdminTransaction {
  const AdminTransaction({
    required this.id,
    required this.userName,
    required this.userEmail,
    required this.planName,
    required this.amountUsd,
    required this.billingCycle,
    required this.timestamp,
    required this.method,
  });

  factory AdminTransaction.fromJson(Map<String, dynamic> j) => AdminTransaction(
        id: (j['id'] as String?) ?? '',
        userName: (j['user_name'] as String?) ?? '',
        userEmail: (j['user_email'] as String?) ?? '',
        planName: (j['plan_name'] as String?) ?? '',
        amountUsd: ((j['amount_usd'] as num?) ?? 0).toDouble(),
        billingCycle: (j['billing_cycle'] as String?) ?? 'Yearly',
        timestamp: (j['timestamp'] as String?) ?? '',
        method: (j['method'] as String?) ?? 'Stripe',
      );

  final String id;
  final String userName;
  final String userEmail;
  final String planName;
  final double amountUsd;
  final String billingCycle;
  final String timestamp;
  final String method;
}

/// Live MongoDB Sync Controller for both the Flutter Mobile App and Flutter Web Admin.
class AdminController extends GetxController {
  final EnhanceServer server = Get.find<EnhanceServer>();

  final RxInt tabIndex = 0.obs;
  final RxString userSearch = ''.obs;
  final RxString userFilter = 'All'.obs;

  final RxBool maintenanceMode = false.obs;
  final RxBool cloudGpuAcceleration = true.obs;
  final RxBool allowFreeExports = true.obs;
  final RxString broadcastAnnouncement = 'AI Engine v2.5: Theatrical Sub-Bass & Crystal Treble now live!'.obs;

  final Rxn<AdminUser> currentUser = Rxn<AdminUser>();
  final RxList<AdminUser> users = <AdminUser>[].obs;
  final RxList<AdminSubscriptionPlan> plans = <AdminSubscriptionPlan>[].obs;
  final RxList<AdminAppFeature> features = <AdminAppFeature>[].obs;
  final RxList<AdminTransaction> transactions = <AdminTransaction>[].obs;
  final RxList<({String month, double revenueK})> monthlyRevenue = <({String month, double revenueK})>[
    (month: 'May', revenueK: 8.4),
    (month: 'Jun', revenueK: 11.2),
    (month: 'Jul', revenueK: 14.8),
    (month: 'Aug', revenueK: 17.5),
    (month: 'Sep', revenueK: 21.9),
    (month: 'Oct', revenueK: 26.4),
  ].obs;

  final RxDouble serverTotalRevenue = 0.0.obs;
  final RxDouble serverMrr = 0.0.obs;

  Timer? _pollTimer;

  @override
  void onInit() {
    super.onInit();
    _loadFallbackDefaults();
    syncFromMongo();
    // Poll MongoDB every 5 seconds so changes made in Web Admin or Compass appear in the user app automatically
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => syncFromMongo());
  }

  @override
  void onClose() {
    _pollTimer?.cancel();
    super.onClose();
  }

  void _loadFallbackDefaults() {
    plans.assignAll([
      AdminSubscriptionPlan(
        id: 'plan_starter',
        name: 'Creator Starter',
        badge: 'FREE',
        monthlyPrice: 0.0,
        yearlyPrice: 0.0,
        description: 'On-device voice clean & standard mono export up to 3 mins.',
        perks: ['Standard Spectral Denoise', 'General + Bass Podcast Filter'],
        popular: false,
        activeSubscribers: 1420,
      ),
      AdminSubscriptionPlan(
        id: 'plan_pro',
        name: 'Studio AI Pro',
        badge: 'MOST POPULAR',
        monthlyPrice: 14.99,
        yearlyPrice: 7.99,
        description: 'All 6 Podcast Bass/Treble filters, Theatrical stereo hall & unlimited 48 kHz WAV exports.',
        perks: ['All Podcast Filters', 'Zero-Noise Pause Gate (-60 dB)', 'Unlimited 48 kHz WAV'],
        popular: true,
        activeSubscribers: 864,
      ),
      AdminSubscriptionPlan(
        id: 'plan_master',
        name: 'Broadcast Master Suite',
        badge: 'TEAMS & STUDIOS',
        monthlyPrice: 29.99,
        yearlyPrice: 19.99,
        description: 'Priority GPU cloud DSP queue, batch episode mastering & multi-device studio seats.',
        perks: ['Dedicated Cloud GPU Queue', 'Batch Multi-Episode Mastering'],
        popular: false,
        activeSubscribers: 218,
      ),
    ]);
  }

  /// Dynamic Podcast Filters driven by MongoDB `vocalpolish_studio.features`!
  List<PodcastTone> get dynamicPodcastTones {
    final List<AdminAppFeature> podFeats = features
        .where((f) => f.category == 'Podcast Filter' && f.enabled)
        .toList();
    if (podFeats.isEmpty) return PodcastTone.all;
    return podFeats
        .map((f) => PodcastTone(f.id, f.title, f.description, proOnly: f.proOnly))
        .toList();
  }

  Future<void> syncFromMongo() async {
    if (!server.connected.value) {
      await server.ping();
    }
    if (!server.connected.value) return;
    try {
      final Response<dynamic> res = await server.dio.get<dynamic>('${server.host}/api/admin/state');
      if (res.statusCode == 200 && res.data is Map) {
        final Map<String, dynamic> data = Map<String, dynamic>.from(res.data as Map);

        final List<dynamic> uList = (data['users'] as List?) ?? const [];
        users.assignAll(uList.map((e) => AdminUser.fromJson(Map<String, dynamic>.from(e as Map))));

        // Update current logged-in user profile from MongoDB
        if (currentUser.value != null) {
          final match = users.firstWhereOrNull((u) => u.email.toLowerCase() == currentUser.value!.email.toLowerCase());
          if (match != null) currentUser.value = match;
        } else if (users.isNotEmpty) {
          currentUser.value = users.first;
        }

        final List<dynamic> pList = (data['plans'] as List?) ?? const [];
        if (pList.isNotEmpty) {
          plans.assignAll(pList.map((e) => AdminSubscriptionPlan.fromJson(Map<String, dynamic>.from(e as Map))));
        }

        final List<dynamic> fList = (data['features'] as List?) ?? const [];
        if (fList.isNotEmpty) {
          features.assignAll(fList.map((e) => AdminAppFeature.fromJson(Map<String, dynamic>.from(e as Map))));
        }

        final List<dynamic> tList = (data['transactions'] as List?) ?? const [];
        transactions.assignAll(tList.map((e) => AdminTransaction.fromJson(Map<String, dynamic>.from(e as Map))));

        final Map<String, dynamic> cfg = Map<String, dynamic>.from((data['settings'] as Map?) ?? const {});
        if (cfg.isNotEmpty) {
          maintenanceMode.value = (cfg['maintenance_mode'] as bool?) ?? false;
          cloudGpuAcceleration.value = (cfg['cloud_gpu_acceleration'] as bool?) ?? true;
          broadcastAnnouncement.value = (cfg['broadcast_announcement'] as String?) ?? broadcastAnnouncement.value;
          final List<dynamic> rev = (cfg['monthly_revenue'] as List?) ?? const [];
          if (rev.isNotEmpty) {
            monthlyRevenue.assignAll(rev.map((r) {
              final m = Map<String, dynamic>.from(r as Map);
              return (month: (m['month'] as String?) ?? '', revenueK: ((m['revenue_k'] as num?) ?? 0).toDouble());
            }));
          }
        }

        final Map<String, dynamic> met = Map<String, dynamic>.from((data['metrics'] as Map?) ?? const {});
        serverTotalRevenue.value = ((met['total_revenue_usd'] as num?) ?? 0).toDouble();
        serverMrr.value = ((met['mrr_usd'] as num?) ?? 0).toDouble();
      }
    } catch (_) {}
  }

  // ── User Auth & Subscriptions (Persisted to MongoDB) ──

  Future<String?> loginWithMongo(String email, String password) async {
    try {
      await server.ping();
      final Response<dynamic> res = await server.dio.post<dynamic>(
        '${server.host}/api/auth/login',
        data: {'email': email, 'password': password, 'device_model': 'vivo V2336 · Android 16'},
      );
      if (res.statusCode == 200 && res.data is Map) {
        final uMap = Map<String, dynamic>.from((res.data as Map)['user'] as Map);
        currentUser.value = AdminUser.fromJson(uMap);
        await syncFromMongo();
        return null;
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        return (e.response?.data is Map ? e.response?.data['detail']?.toString() : null) ??
            'Account deactivated by Administrator.';
      }
    } catch (_) {}
    return null;
  }

  Future<void> signupWithMongo({
    required String name,
    required String email,
    required String password,
    required String role,
  }) async {
    try {
      await server.ping();
      final Response<dynamic> res = await server.dio.post<dynamic>(
        '${server.host}/api/auth/signup',
        data: {'name': name, 'email': email, 'password': password, 'role': role, 'device_model': 'vivo V2336 · Android 16'},
      );
      if (res.statusCode == 200 && res.data is Map) {
        final uMap = Map<String, dynamic>.from((res.data as Map)['user'] as Map);
        currentUser.value = AdminUser.fromJson(uMap);
        await syncFromMongo();
      }
    } catch (_) {}
  }

  Future<void> subscribeCurrentUser(AdminSubscriptionPlan plan, {required bool yearly}) async {
    final AdminUser? u = currentUser.value;
    if (u == null) return;
    final double amount = yearly ? plan.yearlyPrice * 12 : plan.monthlyPrice;
    try {
      await server.dio.post<dynamic>(
        '${server.host}/api/users/${u.id}/subscribe',
        data: {
          'plan_name': plan.name,
          'amount_usd': amount,
          'billing_cycle': yearly ? 'Yearly' : 'Monthly',
        },
      );
      await syncFromMongo();
    } catch (_) {
      u.planName = plan.name;
      currentUser.refresh();
    }
  }

  // ── Computed Metrics ──

  double get totalRevenueUsd {
    if (serverTotalRevenue.value > 0) return serverTotalRevenue.value;
    double planRev = 0;
    for (final p in plans) {
      planRev += p.activeSubscribers * (p.yearlyPrice > 0 ? p.yearlyPrice * 12 : p.monthlyPrice);
    }
    return planRev;
  }

  double get mrrUsd {
    if (serverMrr.value > 0) return serverMrr.value;
    double mrr = 0;
    for (final p in plans) {
      mrr += p.activeSubscribers * (p.yearlyPrice > 0 ? p.yearlyPrice : p.monthlyPrice);
    }
    return mrr;
  }

  int get totalActiveUsers => users.where((u) => u.status == UserStatus.active).length;
  int get totalDeactivatedUsers => users.where((u) => u.status != UserStatus.active).length;
  int get totalMastersProcessed => users.fold(0, (sum, u) => sum + u.mastersCount);
  int get totalMinutesProcessed => users.fold(0, (sum, u) => sum + u.minutesProcessed);

  List<AdminUser> get filteredUsers {
    final String q = userSearch.value.trim().toLowerCase();
    final String f = userFilter.value;
    return users.where((u) {
      final bool matchesQuery = q.isEmpty ||
          u.name.toLowerCase().contains(q) ||
          u.email.toLowerCase().contains(q) ||
          u.role.toLowerCase().contains(q) ||
          u.planName.toLowerCase().contains(q);
      if (!matchesQuery) return false;
      if (f == 'Active') return u.status == UserStatus.active;
      if (f == 'Deactivated') return u.status != UserStatus.active;
      if (f == 'Pro') return u.planName != 'Creator Starter';
      return true;
    }).toList();
  }

  // ── Admin Actions (Persisted to MongoDB) ──

  Future<void> toggleUserStatus(AdminUser user) async {
    try {
      await server.dio.post<dynamic>('${server.host}/api/admin/users/${user.id}/toggle-status');
      await syncFromMongo();
    } catch (_) {
      user.status = user.status == UserStatus.active ? UserStatus.deactivated : UserStatus.active;
      users.refresh();
    }
  }

  Future<void> deleteUser(AdminUser user) async {
    try {
      await server.dio.delete<dynamic>('${server.host}/api/admin/users/${user.id}');
      await syncFromMongo();
    } catch (_) {
      users.removeWhere((u) => u.id == user.id);
    }
  }

  Future<void> changeUserPlan(AdminUser user, String newPlan) async {
    try {
      await server.dio.post<dynamic>('${server.host}/api/admin/users/${user.id}/plan', data: {'plan_name': newPlan});
      await syncFromMongo();
    } catch (_) {
      user.planName = newPlan;
      users.refresh();
    }
  }

  Future<void> addNewUser({
    required String name,
    required String email,
    required String role,
    required String planName,
  }) async {
    try {
      await server.dio.post<dynamic>(
        '${server.host}/api/admin/users',
        data: {'name': name, 'email': email, 'role': role, 'plan_name': planName},
      );
      await syncFromMongo();
    } catch (_) {}
  }

  Future<void> addSubscriptionPlan({
    required String name,
    required String badge,
    required double monthlyPrice,
    required double yearlyPrice,
    required String description,
    required List<String> perks,
    bool popular = false,
  }) async {
    try {
      await server.dio.post<dynamic>(
        '${server.host}/api/admin/plans',
        data: {
          'name': name,
          'badge': badge,
          'monthly_price': monthlyPrice,
          'yearly_price': yearlyPrice,
          'description': description,
          'perks': perks,
          'popular': popular,
        },
      );
      await syncFromMongo();
    } catch (_) {}
  }

  Future<void> togglePlanEnabled(AdminSubscriptionPlan plan) async {
    try {
      await server.dio.post<dynamic>('${server.host}/api/admin/plans/${plan.id}/toggle');
      await syncFromMongo();
    } catch (_) {
      plan.enabled = !plan.enabled;
      plans.refresh();
    }
  }

  Future<void> deleteSubscriptionPlan(AdminSubscriptionPlan plan) async {
    try {
      await server.dio.delete<dynamic>('${server.host}/api/admin/plans/${plan.id}');
      await syncFromMongo();
    } catch (_) {
      plans.removeWhere((p) => p.id == plan.id);
    }
  }

  Future<void> toggleFeature(AdminAppFeature feature) async {
    try {
      await server.dio.post<dynamic>('${server.host}/api/admin/features/${feature.id}/toggle');
      await syncFromMongo();
    } catch (_) {
      feature.enabled = !feature.enabled;
      features.refresh();
    }
  }

  Future<void> toggleFeatureProOnly(AdminAppFeature feature) async {
    try {
      await server.dio.post<dynamic>('${server.host}/api/admin/features/${feature.id}/toggle-pro');
      await syncFromMongo();
    } catch (_) {
      feature.proOnly = !feature.proOnly;
      features.refresh();
    }
  }

  Future<void> addAppFeature({
    required String title,
    required String category,
    required String description,
    required String dspParams,
    required bool proOnly,
  }) async {
    try {
      await server.dio.post<dynamic>(
        '${server.host}/api/admin/features',
        data: {
          'title': title,
          'category': category,
          'description': description,
          'bass': 0.75,
          'treble': 0.55,
          'warmth': 0.20,
          'pro_only': proOnly,
        },
      );
      await syncFromMongo();
    } catch (_) {}
  }

  Future<void> deleteFeature(AdminAppFeature feature) async {
    try {
      await server.dio.delete<dynamic>('${server.host}/api/admin/features/${feature.id}');
      await syncFromMongo();
    } catch (_) {
      features.removeWhere((f) => f.id == feature.id);
    }
  }
}
