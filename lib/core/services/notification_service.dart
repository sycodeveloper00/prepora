import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_service.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static const String _badgeChannelId = 'app_badge_channel';
  static const String _studentChannelId = 'student_notifications';
  static const String _adminChannelId = 'admin_notifications';
  static const int _badgeNotificationId = 9999;
  static const int _dailyStreakNotificationId = 8888;
  static StreamSubscription? _studentSub;
  static StreamSubscription? _adminSub;

  static Future<void> initialize() async {
    if (kIsWeb) return;
    try {
      tz_data.initializeTimeZones();
      try {
        final timezoneName = await FlutterTimezone.getLocalTimezone();
        if (timezoneName != null && timezoneName.isNotEmpty) {
          tz.setLocalLocation(tz.getLocation(timezoneName));
        }
      } catch (_) {
        tz.setLocalLocation(tz.getLocation('UTC'));
      }
      const androidSettings = AndroidInitializationSettings('@drawable/ic_notification');
      const iosSettings = DarwinInitializationSettings();
      await _plugin.initialize(settings: const InitializationSettings(android: androidSettings, iOS: iosSettings));
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      const badgeChannel = AndroidNotificationChannel(
        _badgeChannelId, 'App Badge',
        description: 'App icon badge count',
        importance: Importance.min,
        playSound: false,
        enableVibration: false,
        enableLights: false,
        showBadge: true,
      );
      await androidPlugin?.createNotificationChannel(badgeChannel);
      const studentChannel = AndroidNotificationChannel(
        _studentChannelId, 'Student Notifications',
        description: 'Notifications from admin',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );
      await androidPlugin?.createNotificationChannel(studentChannel);
      const adminChannel = AndroidNotificationChannel(
        _adminChannelId, 'Admin Notifications',
        description: 'Student activity notifications',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );
      await androidPlugin?.createNotificationChannel(adminChannel);
      const streakChannel = AndroidNotificationChannel(
        'streak_channel', 'Daily Streak',
        description: 'Daily streak reminders',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );
      await androidPlugin?.createNotificationChannel(streakChannel);
      const feedbackChannel = AndroidNotificationChannel(
        'feedback_channel', 'Feedbacks',
        description: 'New student feedbacks',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );
      await androidPlugin?.createNotificationChannel(feedbackChannel);
    } catch (_) {}
  }

  // ─── Notification Permission (Android 13+) ────────────────────────────────

  static Future<void> requestNotificationPermission() async {
    if (kIsWeb) return;
    try {
      final status = await Permission.notification.status;
      if (status.isPermanentlyDenied) {
        await openAppSettings();
        return;
      }
      if (status.isDenied) {
        await Permission.notification.request();
      }
    } catch (_) {}
  }

  // ─── Daily Streak Reminder Scheduling ─────────────────────────────────────

  static Future<void> scheduleDailyStreakReminder() async {
    if (kIsWeb) return;
    try {
      final user = FirebaseService.currentUser;
      if (user == null) return;

      await _plugin.cancel(id: _dailyStreakNotificationId);

      // User is opening the app right now, so today's 9 AM reminder is not needed.
      // Always schedule the NEXT day at 9 AM (kept daily-repeating).
      final nowTz = tz.TZDateTime.now(tz.local);
      final tomorrow = nowTz.add(const Duration(days: 1));
      final scheduledDate = tz.TZDateTime(tz.local, tomorrow.year, tomorrow.month, tomorrow.day, 9, 0, 0);
      const androidDetails = AndroidNotificationDetails(
        'streak_channel', 'Daily Streak',
        channelDescription: 'Daily streak reminders',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@drawable/ic_notification',
      );
      const details = NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());

      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      bool exactGranted = false;
      try {
        final canExact = await androidPlugin?.canScheduleExactNotifications();
        exactGranted = canExact == true;
      } catch (_) {}

      if (exactGranted) {
        await _plugin.zonedSchedule(
          id: _dailyStreakNotificationId,
          title: 'Time to study!',
          body: 'Your learning journey is waiting. Open PrePora and continue where you left off.',
          scheduledDate: scheduledDate,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      } else {
        await _plugin.zonedSchedule(
          id: _dailyStreakNotificationId,
          title: 'Time to study!',
          body: 'Your learning journey is waiting. Open PrePora and continue where you left off.',
          scheduledDate: scheduledDate,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      }
    } catch (_) {}
  }

  static Future<void> ensureExactAlarmPermission() async {
    if (kIsWeb) return;
    try {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final canExact = await androidPlugin?.canScheduleExactNotifications();
      if (canExact == false) {
        await androidPlugin?.requestExactAlarmsPermission();
      }
    } catch (_) {}
  }

  static Future<void> cancelDailyStreakReminder() async {
    if (kIsWeb) return;
    await _plugin.cancel(id: _dailyStreakNotificationId);
  }

  // ─── Student Notification Listener (badge + mobile panel) ──────────────────

  static void startStudentNotificationListener(String uid, DateTime userCreatedAt) {
    if (kIsWeb) return;
    _studentSub?.cancel();
    _studentSub = FirebaseService.firestore
        .collection('notifications')
        .where('uid', isEqualTo: uid)
        .where('createdAt', isGreaterThanOrEqualTo: userCreatedAt)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snap) async {
      int unreadCount = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['read'] != true) unreadCount++;
      }
      await setBadgeCount(unreadCount);
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final enabled = await androidPlugin?.areNotificationsEnabled() ?? true;
      if (!enabled) return;
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>;
          final read = data['read'] as bool? ?? false;
          if (!read) {
            final message = data['message'] as String? ?? '';
            final userName = data['userName'] as String? ?? 'Admin';
            await _showStudentNotification(message, userName);
          }
        }
      }
    });
  }

  static Future<void> _showStudentNotification(String message, String sender) async {
    if (kIsWeb) return;
    const androidDetails = AndroidNotificationDetails(
      _studentChannelId, 'Student Notifications',
      channelDescription: 'Notifications from admin',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_notification',
    );
    const details = NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());
    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: 'New Notification',
      body: '$sender: $message',
      notificationDetails: details,
    );
  }

  // ─── Admin Notification Listener (badge + mobile panel) ────────────────────

  static void startAdminNotificationListener() {
    if (kIsWeb) return;
    _adminSub?.cancel();
    _adminSub = FirebaseService.firestore
        .collection('admin_notifications')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snap) async {
      int unreadCount = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['read'] != true) unreadCount++;
      }
      await setBadgeCount(unreadCount);
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>;
          final read = data['read'] as bool? ?? false;
          if (!read) {
            final message = data['message'] as String? ?? '';
            final type = data['type'] as String? ?? '';
            await _showAdminNotification(message, type);
          }
        }
      }
    });
  }

  static Future<void> _showAdminNotification(String message, String type) async {
    if (kIsWeb) return;
    String title;
    switch (type) {
      case 'registration': title = 'New Registration'; break;
      case 'feedback': title = 'New Feedback'; break;
      case 'login': title = 'User Login'; break;
      case 'logout': title = 'User Logout'; break;
      case 'blocked': title = 'Account Blocked'; break;
      default: title = 'Admin Notification';
    }
    const androidDetails = AndroidNotificationDetails(
      _adminChannelId, 'Admin Notifications',
      channelDescription: 'Student activity notifications',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_notification',
    );
    const details = NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());
    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: message,
      notificationDetails: details,
    );
  }

  // ─── Streak Reminders ──────────────────────────────────────────────────────

  static Future<void> checkAndNotify() async {
    if (kIsWeb) return;
    try {
      final user = FirebaseService.currentUser;
      if (user == null) return;

      final doc = await FirebaseService.firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) return;

      final userData = doc.data();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final lastLogin = (userData?['lastLogin'] as Timestamp?)?.toDate();
      final lastStreakNotified = (userData?['lastStreakNotified'] as Timestamp?)?.toDate();
      final lastStreakDate = lastStreakNotified != null
          ? DateTime(lastStreakNotified.year, lastStreakNotified.month, lastStreakNotified.day)
          : null;

      // Always reschedule 9 AM daily reminder for next occurrence
      await scheduleDailyStreakReminder();

      if (lastLogin == null) return;

      final lastLoginDate = DateTime(lastLogin.year, lastLogin.month, lastLogin.day);
      final daysSinceLogin = today.difference(lastLoginDate).inDays;

      // Same day → no notification needed
      if (daysSinceLogin < 1) return;

      // Already notified today → skip
      if (lastStreakDate != null && !lastStreakDate.isBefore(today)) return;

      final plugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final enabled = await plugin?.areNotificationsEnabled() ?? true;
      if (!enabled) return;

      // Duolingo style: 1 day gap = streak needs attention, 2+ days = streak reset
      if (daysSinceLogin >= 2) {
        await _showStreakNotification(
          'Your streak was reset!',
          'You missed a day. Start a new streak today — open PrePora now!',
        );
      } else {
        await _showStreakNotification(
          'Keep your streak alive!',
          'Don\'t let your progress slip away. Open PrePora today!',
        );
      }

      try {
        await FirebaseService.firestore.collection('users').doc(user.uid).update({
          'lastStreakNotified': Timestamp.fromDate(now),
          'lastLogin': Timestamp.fromDate(now),
        });
      } catch (_) {}
    } catch (_) {}
  }

  static Future<void> _showStreakNotification(String title, String body) async {
    if (kIsWeb) return;
    const androidDetails = AndroidNotificationDetails('streak_channel', 'Daily Streak',
 channelDescription: 'Daily streak reminders', importance: Importance.high, priority: Priority.high, icon: '@drawable/ic_notification');
    const details = NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());
    await _plugin.show(id: DateTime.now().millisecondsSinceEpoch ~/ 1000, title: title, body: body, notificationDetails: details);
  }

  static Future<void> showFeedbackNotification(String studentName, String message) async {
    if (kIsWeb) return;
    const androidDetails = AndroidNotificationDetails('feedback_channel', 'Feedbacks',
      channelDescription: 'New student feedbacks', importance: Importance.high, priority: Priority.high);
    const details = NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());
    await _plugin.show(id: DateTime.now().millisecondsSinceEpoch ~/ 1000, title: 'New Feedback from $studentName', body: message, notificationDetails: details);
  }

  // ─── Badge Count ───────────────────────────────────────────────────────────

  static Future<void> setBadgeCount(int count) async {
    if (kIsWeb) return;
    if (count > 0) {
      final androidDetails = AndroidNotificationDetails(
        _badgeChannelId, 'App Badge',
        channelDescription: 'App icon badge count',
        importance: Importance.min,
        priority: Priority.min,
        playSound: false,
        enableVibration: false,
        number: count,
      );
      final details = NotificationDetails(android: androidDetails);
      await _plugin.show(id: _badgeNotificationId, title: '', body: '', notificationDetails: details);
    } else {
      await _plugin.cancel(id: _badgeNotificationId);
    }
  }

  static Future<void> clearBadge() async {
    if (kIsWeb) return;
    await _plugin.cancel(id: _badgeNotificationId);
  }

  static void dispose() {
    _studentSub?.cancel();
    _adminSub?.cancel();
  }
}
