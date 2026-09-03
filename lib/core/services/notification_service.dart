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
  static const int _streakEveningNotificationId = 8889;
  static StreamSubscription? _studentSub;
  static StreamSubscription? _adminSub;

  static Future<void> initialize() async {
    if (kIsWeb) return;
    try {
      tz_data.initializeTimeZones();
      try {
        final timezoneName = await FlutterTimezone.getLocalTimezone();
        if (timezoneName.isNotEmpty) {
          tz.setLocalLocation(tz.getLocation(timezoneName));
        }
      } catch (_) {
        tz.setLocalLocation(tz.getLocation('UTC'));
      }
      const androidSettings = AndroidInitializationSettings('@drawable/ic_notification');
      const iosSettings = DarwinInitializationSettings();
      try {
        await _plugin.initialize(settings: const InitializationSettings(android: androidSettings, iOS: iosSettings));
        debugPrint('NFS: plugin initialized');
      } catch (e) {
        debugPrint('NFS: plugin init FAILED: $e');
      }
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin == null) {
        debugPrint('NFS: androidPlugin is NULL');
      }
      const badgeChannel = AndroidNotificationChannel(
        _badgeChannelId, 'App Badge',
        description: 'App icon badge count',
        importance: Importance.min,
        playSound: false,
        enableVibration: false,
        enableLights: false,
        showBadge: true,
      );
      try { await androidPlugin?.createNotificationChannel(badgeChannel); debugPrint('NFS: badge channel created'); } catch (e) { debugPrint('NFS: badge channel FAILED: $e'); }
      const studentChannel = AndroidNotificationChannel(
        _studentChannelId, 'Student Notifications',
        description: 'Notifications from admin',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );
      try { await androidPlugin?.createNotificationChannel(studentChannel); debugPrint('NFS: student channel created'); } catch (e) { debugPrint('NFS: student channel FAILED: $e'); }
      const adminChannel = AndroidNotificationChannel(
        _adminChannelId, 'Admin Notifications',
        description: 'Student activity notifications',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );
      try { await androidPlugin?.createNotificationChannel(adminChannel); debugPrint('NFS: admin channel created'); } catch (e) { debugPrint('NFS: admin channel FAILED: $e'); }
      const streakChannel = AndroidNotificationChannel(
        'streak_channel', 'Daily Streak',
        description: 'Daily streak reminders',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );
      try { await androidPlugin?.createNotificationChannel(streakChannel); debugPrint('NFS: streak channel created'); } catch (e) { debugPrint('NFS: streak channel FAILED: $e'); }
      const feedbackChannel = AndroidNotificationChannel(
        'feedback_channel', 'Feedbacks',
        description: 'New student feedbacks',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );
      try { await androidPlugin?.createNotificationChannel(feedbackChannel); debugPrint('NFS: feedback channel created'); } catch (e) { debugPrint('NFS: feedback channel FAILED: $e'); }
    } catch (e) {
      debugPrint('NFS: initialize outer FAILED: $e');
    }
  }

  // ΓöÇΓöÇΓöÇ Notification Permission (Android 13+) ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ

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

  // ΓöÇΓöÇΓöÇ Daily Streak Reminder Scheduling ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ

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

  // ─── Streak Evening Reminder (8 PM daily) ──────────────────────────────────

  static Future<void> scheduleStreakEveningReminder() async {
    if (kIsWeb) return;
    try {
      final user = FirebaseService.currentUser;
      if (user == null) return;

      await _plugin.cancel(id: _streakEveningNotificationId);

      final nowTz = tz.TZDateTime.now(tz.local);
      final today8PM = tz.TZDateTime(tz.local, nowTz.year, nowTz.month, nowTz.day, 20, 0, 0);

      tz.TZDateTime scheduledDate;
      if (nowTz.isBefore(today8PM)) {
        scheduledDate = today8PM;
      } else {
        final tomorrow = nowTz.add(const Duration(days: 1));
        scheduledDate = tz.TZDateTime(tz.local, tomorrow.year, tomorrow.month, tomorrow.day, 20, 0, 0);
      }

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
          id: _streakEveningNotificationId,
          title: "Don't forget to study!",
          body: 'Open PrePora now to keep your streak alive. A few minutes of study is all it takes!',
          scheduledDate: scheduledDate,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      } else {
        await _plugin.zonedSchedule(
          id: _streakEveningNotificationId,
          title: "Don't forget to study!",
          body: 'Open PrePora now to keep your streak alive. A few minutes of study is all it takes!',
          scheduledDate: scheduledDate,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      }
    } catch (_) {}
  }

  static Future<void> cancelStreakEveningReminder() async {
    if (kIsWeb) return;
    await _plugin.cancel(id: _streakEveningNotificationId);
  }

  // ΓöÇΓöÇΓöÇ Student Notification Listener (badge + mobile panel) ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ

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

  // ΓöÇΓöÇΓöÇ Admin Notification Listener (badge + mobile panel) ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ

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

  // ΓöÇΓöÇΓöÇ Streak Reminders ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ

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

      // Same day ΓåÆ no notification needed
      if (daysSinceLogin < 1) return;

      // Already notified today ΓåÆ skip
      if (lastStreakDate != null && !lastStreakDate.isBefore(today)) return;

      final plugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final enabled = await plugin?.areNotificationsEnabled() ?? true;
      if (!enabled) return;

      // Duolingo style: 1 day gap = streak needs attention, 2+ days = streak reset
      if (daysSinceLogin >= 2) {
        await _showStreakNotification(
          'Your streak was reset!',
          'You missed a day. Start a new streak today ΓÇö open PrePora now!',
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

  static Future<void> showDisconnectNotification(String message) async {
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
      title: 'PrePora',
      body: message,
      notificationDetails: details,
    );
  }

  static Future<void> showFeedbackNotification(String studentName, String message) async {
    if (kIsWeb) return;
    const androidDetails = AndroidNotificationDetails('feedback_channel', 'Feedbacks',
      channelDescription: 'New student feedbacks', importance: Importance.high, priority: Priority.high);
    const details = NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());
    await _plugin.show(id: DateTime.now().millisecondsSinceEpoch ~/ 1000, title: 'New Feedback from $studentName', body: message, notificationDetails: details);
  }

  // ΓöÇΓöÇΓöÇ Badge Count ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ

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
