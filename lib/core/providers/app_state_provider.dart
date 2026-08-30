import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:hive_flutter/hive_flutter.dart';
import '../services/firebase_service.dart';
import '../services/supabase_read_service.dart';

/// Cached user status (blocked, verified, paid, trial, streak).
/// Fetched once on login, updated via Firestore snapshots.
class UserStatus {
  final bool isBlocked;
  final bool isVerified;
  final bool isPaidAccess;
  final bool isFreeTrialActive;
  final DateTime? trialEndsAt;
  final int streakCount;
  final int totalActiveDays;
  final DateTime userCreatedAt;
  final String userName;

  UserStatus({
    this.isBlocked = false,
    this.isVerified = false,
    this.isPaidAccess = false,
    this.isFreeTrialActive = false,
    this.trialEndsAt,
    this.streakCount = 0,
    this.totalActiveDays = 0,
    DateTime? userCreatedAt,
    this.userName = '',
  }) : userCreatedAt = userCreatedAt ?? DateTime(2020);

  UserStatus copyWith({
    bool? isBlocked,
    bool? isVerified,
    bool? isPaidAccess,
    bool? isFreeTrialActive,
    DateTime? trialEndsAt,
    int? streakCount,
    int? totalActiveDays,
    DateTime? userCreatedAt,
    String? userName,
  }) {
    return UserStatus(
      isBlocked: isBlocked ?? this.isBlocked,
      isVerified: isVerified ?? this.isVerified,
      isPaidAccess: isPaidAccess ?? this.isPaidAccess,
      isFreeTrialActive: isFreeTrialActive ?? this.isFreeTrialActive,
      trialEndsAt: trialEndsAt ?? this.trialEndsAt,
      streakCount: streakCount ?? this.streakCount,
      totalActiveDays: totalActiveDays ?? this.totalActiveDays,
      userCreatedAt: userCreatedAt ?? this.userCreatedAt,
      userName: userName ?? this.userName,
    );
  }
}

/// Cached settings from Firestore/Supabase.
class AppSettings {
  final bool paidAccess;
  final double price;
  final String accountTitle;
  final String accountNo;
  final String bankName;
  final Map<String, dynamic> raw;

  const AppSettings({
    this.paidAccess = false,
    this.price = 0,
    this.accountTitle = '',
    this.accountNo = '',
    this.bankName = '',
    this.raw = const {},
  });

  factory AppSettings.fromMap(Map<String, dynamic> data) {
    return AppSettings(
      paidAccess: data['paidAccess'] as bool? ?? false,
      price: (data['price'] as num?)?.toDouble() ?? 0,
      accountTitle: data['accountTitle'] as String? ?? '',
      accountNo: data['accountNo'] as String? ?? '',
      bankName: data['bankName'] as String? ?? '',
      raw: data,
    );
  }
}

/// Notifier that fetches + caches user status, listens to Firestore snapshots
/// for real-time updates (blocked/verified changes from admin).
class UserStatusNotifier extends AutoDisposeAsyncNotifier<UserStatus> {
  StreamSubscription? _userSub;
  StreamSubscription? _settingsSub;

  @override
  Future<UserStatus> build() async {
    final uid = fb_auth.FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return UserStatus();

    // Try loading cached status from Hive for instant offline display
    UserStatus? cached;
    try {
      final box = Hive.box('settings');
      final cachedJson = box.get('user_status_$uid') as String?;
      if (cachedJson != null) {
        final map = json.decode(cachedJson) as Map<String, dynamic>;
        cached = UserStatus(
          isBlocked: map['isBlocked'] ?? false,
          isVerified: map['isVerified'] ?? false,
          isPaidAccess: map['isPaidAccess'] ?? false,
          isFreeTrialActive: map['isFreeTrialActive'] ?? false,
          trialEndsAt: map['trialEndsAt'] != null ? DateTime.tryParse(map['trialEndsAt']) : null,
          streakCount: map['streakCount'] ?? 0,
          totalActiveDays: map['totalActiveDays'] ?? 0,
          userCreatedAt: map['userCreatedAt'] != null ? DateTime.tryParse(map['userCreatedAt']) ?? DateTime(2020) : DateTime(2020),
          userName: map['userName'] ?? '',
        );
        // Return cached immediately so UI renders offline
        state = AsyncData(cached);
      }
    } catch (_) {}

    // Fetch fresh data in parallel with 10s timeout for offline resilience
    final results = await Future.wait([
      FirebaseService.isStudentBlocked(uid).timeout(const Duration(seconds: 10), onTimeout: () => cached?.isBlocked ?? false),
      FirebaseService.isStudentVerified(uid).timeout(const Duration(seconds: 10), onTimeout: () => cached?.isVerified ?? false),
      FirebaseService.getSettings().timeout(const Duration(seconds: 10), onTimeout: () => <String, dynamic>{}),
      FirebaseService.getFreeTrial(uid).timeout(const Duration(seconds: 10), onTimeout: () => <String, dynamic>{}),
      FirebaseService.getStreak(uid).timeout(const Duration(seconds: 10), onTimeout: () => <String, dynamic>{}),
      FirebaseService.getUser(uid).timeout(const Duration(seconds: 10), onTimeout: () => null),
    ]);

    final blocked = results[0] as bool;
    final verified = results[1] as bool;
    final settings = results[2] as Map<String, dynamic>;
    final trial = results[3] as Map<String, dynamic>;
    final streakData = results[4] as Map<String, dynamic>;
    final userDoc = results[5] as dynamic;

    final paidAccess = settings['paidAccess'] as bool? ?? false;
    final trialActive = trial['active'] == true;
    final trialEnd = trial['endsAt'] as DateTime?;

    // Expire trial if needed
    if (trialActive && trialEnd != null && !trialEnd.isAfter(DateTime.now())) {
      FirebaseService.expireFreeTrial(uid);
    }

    final createdAt = (userDoc?.data() as Map<String, dynamic>?)?['createdAt'] as Timestamp?;
    final userName = fb_auth.FirebaseAuth.instance.currentUser?.displayName ?? '';

    // Listen for real-time user doc changes (blocked/verified)
    _userSub?.cancel();
    _userSub = FirebaseService.firestore
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) {
      if (!snap.exists) return;
      final data = snap.data() as Map<String, dynamic>;
      final newBlocked = data['blocked'] as bool? ?? false;
      final newVerified = data['verified'] as bool? ?? false;
      final newTrialActive = data['freeTrialActive'] == true;
      final endsAt = data['freeTrialEndsAt'];
      final newTrialEnd = endsAt is Timestamp ? endsAt.toDate() : null;

      final current = state.valueOrNull ?? UserStatus();
      state = AsyncData(current.copyWith(
        isBlocked: newBlocked,
        isVerified: newVerified,
        isFreeTrialActive: newTrialActive && (newTrialEnd?.isAfter(DateTime.now()) ?? false),
        trialEndsAt: newTrialEnd,
      ));
    }, onError: (_) {});

    // Poll Supabase for settings changes (paidAccess etc.)
    _settingsSub?.cancel();
    _settingsSub = Stream.periodic(const Duration(seconds: 15)).asyncMap((_) async {
      try {
        final data = await SupabaseReadService.getSettings('general');
        if (data != null) {
          final current = state.valueOrNull ?? UserStatus();
          final newPaidAccess = data['paidAccess'] as bool? ?? false;
          if (current.isPaidAccess != newPaidAccess) {
            state = AsyncData(current.copyWith(isPaidAccess: newPaidAccess));
          }
        }
      } catch (_) {}
    }).listen((_) {}, onError: (_) {});

    ref.onDispose(() {
      _userSub?.cancel();
      _settingsSub?.cancel();
    });

    final status = UserStatus(
      isBlocked: blocked,
      isVerified: verified,
      isPaidAccess: paidAccess,
      isFreeTrialActive: trialActive && (trialEnd?.isAfter(DateTime.now()) ?? false),
      trialEndsAt: trialEnd,
      streakCount: streakData['streakCount'] as int? ?? 0,
      totalActiveDays: streakData['totalActiveDays'] as int? ?? 0,
      userCreatedAt: createdAt?.toDate() ?? DateTime(2020),
      userName: userName,
    );

    // Cache status in Hive for offline use
    try {
      final box = Hive.box('settings');
      await box.put('user_status_$uid', json.encode({
        'isBlocked': status.isBlocked,
        'isVerified': status.isVerified,
        'isPaidAccess': status.isPaidAccess,
        'isFreeTrialActive': status.isFreeTrialActive,
        'trialEndsAt': status.trialEndsAt?.toIso8601String(),
        'streakCount': status.streakCount,
        'totalActiveDays': status.totalActiveDays,
        'userCreatedAt': status.userCreatedAt.toIso8601String(),
        'userName': status.userName,
      }));
    } catch (_) {}

    return status;
  }

  /// Manually refresh (e.g. after payment or admin action).
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build());
  }

  /// Force update settings portion without full refetch.
  void updateSettings(AppSettings settings) {
    final current = state.valueOrNull ?? UserStatus();
    state = AsyncData(current.copyWith(
      isPaidAccess: settings.paidAccess,
    ));
  }
}

/// Notifier for cached app settings.
class AppSettingsNotifier extends AutoDisposeAsyncNotifier<AppSettings> {
  StreamSubscription? _sub;

  @override
  Future<AppSettings> build() async {
    final data = await FirebaseService.getSettings();
    final settings = AppSettings.fromMap(data);

    // Poll Supabase for settings changes instead of Firestore listener
    _sub?.cancel();
    _sub = Stream.periodic(const Duration(seconds: 15)).asyncMap((_) async {
      try {
        final newData = await SupabaseReadService.getSettings('general');
        if (newData != null) {
          state = AsyncData(AppSettings.fromMap(newData));
        }
      } catch (_) {}
    }).listen((_) {}, onError: (_) {});

    ref.onDispose(() => _sub?.cancel());
    return settings;
  }
}

/// Providers
final userStatusProvider =
    AsyncNotifierProvider.autoDispose<UserStatusNotifier, UserStatus>(
  UserStatusNotifier.new,
);

final appSettingsProvider =
    AsyncNotifierProvider.autoDispose<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);
