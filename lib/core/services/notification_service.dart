import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_service.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static const String _badgeChannelId = 'app_badge_channel';
  static const String _studentChannelId = 'student_notifications';
  static const String _adminChannelId = 'admin_notifications';
  static const int _badgeNotificationId = 9999;
  static StreamSubscription? _studentSub;
  static StreamSubscription? _adminSub;

  static Future<void> initialize() async {
    if (kIsWeb) return;
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    await _plugin.initialize(settings: const InitializationSettings(android: androidSettings, iOS: iosSettings));
    const badgeChannel = AndroidNotificationChannel(
      _badgeChannelId, 'App Badge',
      description: 'App icon badge count',
      importance: Importance.min,
      playSound: false,
      enableVibration: false,
      enableLights: false,
      showBadge: true,
    );
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(badgeChannel);
    const studentChannel = AndroidNotificationChannel(
      _studentChannelId, 'Student Notifications',
      description: 'Notifications from admin',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(studentChannel);
    const adminChannel = AndroidNotificationChannel(
      _adminChannelId, 'Admin Notifications',
      description: 'Student activity notifications',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(adminChannel);
    const streakChannel = AndroidNotificationChannel(
      'streak_channel', 'Daily Streak',
      channelDescription: 'Daily streak reminders',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(streakChannel);
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
      final userDoc = await FirebaseService.firestore.collection('users').doc(uid).get();
      final notificationsEnabled = (userDoc.data()?['notificationsEnabled'] as bool?) ?? true;

      int unreadCount = 0;
      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        if (data['read'] != true) unreadCount++;
      }
      await setBadgeCount(unreadCount);
      if (!notificationsEnabled) return;
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

    if (hoursSince >= 72) {
      await _showStreakNotification('Long time no see!', "I am frustrated, when will you come back? Your streak is waiting.");
    } else if (hoursSince >= 24) {
      await _showStreakNotification("Let's Come Back to Learn", "I am waiting for you. Waiting for your return, I am tired!");
    }
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

  static void dispose() {
    _studentSub?.cancel();
    _adminSub?.cancel();
  }
}
