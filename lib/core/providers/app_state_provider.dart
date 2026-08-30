import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import '../services/firebase_service.dart';

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

    // Fetch all in parallel
    final results = await Future.wait([
      FirebaseService.isStudentBlocked(uid),
      FirebaseService.isStudentVerified(uid),
      FirebaseService.getSettings(),
      FirebaseService.getFreeTrial(uid),
      FirebaseService.getStreak(uid),
      FirebaseService.getUser(uid),
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

    // Listen for settings changes
    _settingsSub?.cancel();
    _settingsSub = FirebaseService.firestore
        .collection('settings')
        .doc('general')
        .snapshots()
        .listen((snap) {
      if (!snap.exists) return;
      final data = snap.data() as Map<String, dynamic>;
      final current = state.valueOrNull ?? UserStatus();
      state = AsyncData(current.copyWith(
        isPaidAccess: data['paidAccess'] as bool? ?? false,
      ));
    }, onError: (_) {});

    ref.onDispose(() {
      _userSub?.cancel();
      _settingsSub?.cancel();
    });

    return UserStatus(
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

    _sub?.cancel();
    _sub = FirebaseService.firestore
        .collection('settings')
        .doc('general')
        .snapshots()
        .listen((snap) {
      if (!snap.exists) return;
      final newData = snap.data() as Map<String, dynamic>;
      state = AsyncData(AppSettings.fromMap(newData));
    }, onError: (_) {});

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
