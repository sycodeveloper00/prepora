import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
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
      await _plugin.cancel(id: _dailyStreakNotificationId);
      final now = tz.TZDateTime.now(tz.local);
      var scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, 9, 0, 0);
      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }
      const androidDetails = AndroidNotificationDetails(
        'streak_channel', 'Daily Streak',
        channelDescription: 'Daily streak reminders',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );
      const details = NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());
      await _plugin.zonedSchedule(
        id: _dailyStreakNotificationId,
        title: 'Don\'t break your streak!',
        body: 'Open PrePora today and keep learning. Your streak is waiting for you!',
        scheduledDate: scheduledDate,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
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
        final data = doc.data() as Map<String, dynamic>;
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
      icon: '@mipmap/ic_launcher',
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
        final data = doc.data() as Map<String, dynamic>;
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
      icon: '@mipmap/ic_launcher',
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
      final lastLogin = (userData?['lastLogin'] as Timestamp?)?.toDate();
      final now = DateTime.now();

      await FirebaseService.firestore.collection('users').doc(user.uid).update({
        'lastLogin': Timestamp.fromDate(now),
      });

      if (lastLogin == null) return;

      final hoursSince = now.difference(lastLogin).inHours;

      final plugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final enabled = await plugin?.areNotificationsEnabled() ?? true;

      if (hoursSince >= 72) {
        if (enabled) await _showStreakNotification('Long time no see!', "I am frustrated, when will you come back? Your streak is waiting.");
      } else if (hoursSince >= 24) {
        if (enabled) await _showStreakNotification("Let's Come Back to Learn", "I am waiting for you. Waiting for your return, I am tired!");
      }
    } catch (_) {}
  }

  static Future<void> _showStreakNotification(String title, String body) async {
    if (kIsWeb) return;
    const androidDetails = AndroidNotificationDetails('streak_channel', 'Daily Streak',
      channelDescription: 'Daily streak reminders', importance: Importance.high, priority: Priority.high);
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

  // ─── Test Notification ──────────────────────────────────────────────────────

  static Future<void> testNotification() async {
    if (kIsWeb) return;
    try {
      const androidDetails = AndroidNotificationDetails(
        'streak_channel', 'Daily Streak',
        channelDescription: 'Daily streak reminders',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );
      const details = NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());
      await _plugin.show(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: 'PrePora Test Notification',
        body: 'Notifications are working! You will receive daily streak reminders.',
        notificationDetails: details,
      );
    } catch (_) {}
  }

  static void dispose() {
    _studentSub?.cancel();
    _adminSub?.cancel();
  }
}
