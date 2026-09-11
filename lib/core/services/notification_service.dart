import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_service.dart';
import 'supabase_read_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('FCM: background message received: ${message.messageId}');
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  static const String _badgeChannelId = 'app_badge_channel';
  static const String _studentChannelId = 'student_notifications';
  static const String _adminChannelId = 'admin_notifications';
  static const int _badgeNotificationId = 9999;
  static const int _dailyStreakNotificationId = 8888;
  static const int _streakEveningNotificationId = 8889;
  static StreamSubscription? _studentSub;
  static StreamSubscription? _adminSub;
  static StreamSubscription? _fcmMessageSub;

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

      // Firebase Cloud Messaging (FCM) setup for live push notifications
      try {
        await _fcm.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );
        debugPrint('FCM: permission requested');
      } catch (e) {
        debugPrint('FCM: permission request FAILED: $e');
      }

      try {
        final token = await _fcm.getToken();
        if (token != null) {
          debugPrint('FCM: token obtained (${token.length} chars)');
          await _saveFcmToken(token);
        }
        _fcm.onTokenRefresh.listen((newToken) {
          debugPrint('FCM: token refreshed');
          _saveFcmToken(newToken);
        });
      } catch (e) {
        debugPrint('FCM: token retrieval FAILED: $e');
      }

      // Handle foreground messages
      _fcmMessageSub?.cancel();
      _fcmMessageSub = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('FCM: foreground message: ${message.notification?.title}');
        _handleFcmMessage(message);
      });

      // Handle notification tap when app is in background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('FCM: onMessageOpenedApp: ${message.notification?.title}');
        _handleFcmTap(message);
      });

      // Check if app opened from notification (terminated state)
      final initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('FCM: initial message (terminated): ${initialMessage.notification?.title}');
        _handleFcmTap(initialMessage);
      }

      // Register background handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    } catch (e) {
      debugPrint('NFS: initialize outer FAILED: $e');
    }
  }

  static Future<void> _saveFcmToken(String token) async {
    try {
      final user = FirebaseService.currentUser;
      if (user == null) return;
      await SupabaseReadService.writeToAll('users', user.uid, {
        'fcmToken': token,
        'fcmTokenUpdatedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('FCM: save token FAILED: $e');
    }
  }

  static void _handleFcmMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;
    final data = message.data;
    final type = data['type'] as String? ?? '';

    // Show as local notification so it appears in notification tray
    String channelId;
    String channelName;
    switch (type) {
      case 'streak':
      case 'streak_warning':
      case 'streak_reset':
        channelId = 'streak_channel';
        channelName = 'Daily Streak';
        break;
      case 'study_reminder':
      case 'new_content':
        channelId = _studentChannelId;
        channelName = 'Student Notifications';
        break;
      case 'feedback':
        channelId = 'feedback_channel';
        channelName = 'Feedbacks';
        break;
      default:
        channelId = _studentChannelId;
        channelName = 'Student Notifications';
    }

    _showFcmLocalNotification(
      title: notification.title ?? 'PrePora',
      body: notification.body ?? '',
      channelId: channelId,
      channelName: channelName,
      data: data,
    );
  }

  static Future<void> _showFcmLocalNotification({
    required String title,
    required String body,
    required String channelId,
    required String channelName,
    Map<String, dynamic>? data,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelId, channelName,
      channelDescription: 'PrePora notifications',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_notification',
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(),
    );
    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  static void _handleFcmTap(RemoteMessage message) {
    final data = message.data;
    final type = data['type'] as String? ?? '';
    // Navigation will be handled by the app's router based on data payload
    debugPrint('FCM tap: type=$type, data=$data');
  }

  static Future<void> sendPushToUser({
    required String targetUid,
    required String title,
    required String body,
    String type = 'general',
    Map<String, dynamic>? extraData,
  }) async {
    try {
      final id = 'fcm_${DateTime.now().millisecondsSinceEpoch}_${targetUid.substring(0, 8.clamp(0, targetUid.length))}';
      await SupabaseReadService.writeToAll('fcm_notifications', id, {
        'targetUid': targetUid,
        'title': title,
        'body': body,
        'type': type,
        'data': extraData ?? {},
        'createdAt': DateTime.now().toIso8601String(),
        'sent': false,
      });
    } catch (e) {
      debugPrint('FCM: sendPushToUser FAILED: $e');
    }
  }

  /// Send streak notification to user (called when streak events happen)
  static Future<void> sendStreakNotification({
    required String uid,
    required String title,
    required String body,
    String type = 'streak',
  }) async {
    await sendPushToUser(targetUid: uid, title: title, body: body, type: type);
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
          title: '🔥 Don\'t break your streak!',
          body: 'You\'re on a roll! Keep studying — your future self will thank you.',
          scheduledDate: scheduledDate,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      } else {
        await _plugin.zonedSchedule(
          id: _dailyStreakNotificationId,
          title: '🔥 Don\'t break your streak!',
          body: 'You\'re on a roll! Keep studying — your future self will thank you.',
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
          title: '🌙 Night owl study time!',
          body: 'A quick revision before bed = better retention. Open PrePora for 10 mins!',
          scheduledDate: scheduledDate,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      } else {
        await _plugin.zonedSchedule(
          id: _streakEveningNotificationId,
          title: '🌙 Night owl study time!',
          body: 'A quick revision before bed = better retention. Open PrePora for 10 mins!',
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
    bool _isFirstSnapshot = true;
    Set<String> _seenIds = {};
    _studentSub = SupabaseReadService.streamNotifications(uid, userCreatedAt, interval: const Duration(seconds: 15))
        .listen((rows) async {
      int unreadCount = 0;
      for (final row in rows) {
        if (row['read'] != true) unreadCount++;
      }
      await setBadgeCount(unreadCount);
      if (_isFirstSnapshot) {
        _isFirstSnapshot = false;
        for (final row in rows) {
          _seenIds.add(row['id'] as String? ?? '');
        }
        return;
      }
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final enabled = await androidPlugin?.areNotificationsEnabled() ?? true;
      if (!enabled) return;
      for (final row in rows) {
        final id = row['id'] as String? ?? '';
        if (_seenIds.contains(id)) continue;
        _seenIds.add(id);
        final read = row['read'] as bool? ?? false;
        final message = row['message'] as String? ?? '';
        if (!read && !message.contains('Web app disconnected')) {
          final userName = row['userName'] as String? ?? 'Admin';
          await _showStudentNotification(message, userName);
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
    bool _isFirstSnapshot = true;
    Set<String> _seenIds = {};
    _adminSub = SupabaseReadService.streamAdminNotifications(interval: const Duration(seconds: 15))
        .listen((rows) async {
      int unreadCount = 0;
      for (final row in rows) {
        if (row['read'] != true) unreadCount++;
      }
      await setBadgeCount(unreadCount);
      if (_isFirstSnapshot) {
        _isFirstSnapshot = false;
        for (final row in rows) {
          _seenIds.add(row['id'] as String? ?? '');
        }
        return;
      }
      for (final row in rows) {
        final id = row['id'] as String? ?? '';
        if (_seenIds.contains(id)) continue;
        _seenIds.add(id);
        final read = row['read'] as bool? ?? false;
        if (!read) {
          final message = row['message'] as String? ?? '';
          final type = row['type'] as String? ?? '';
          await _showAdminNotification(message, type);
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

      final userData = await SupabaseReadService.getUser(user.uid);
      if (userData == null) return;

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final lastLoginStr = userData['lastLogin'] as String?;
      final lastStreakNotifiedStr = userData['lastStreakNotified'] as String?;
      final lastLogin = lastLoginStr != null ? DateTime.tryParse(lastLoginStr) : null;
      final lastStreakNotified = lastStreakNotifiedStr != null ? DateTime.tryParse(lastStreakNotifiedStr) : null;
      final lastStreakDate = lastStreakNotified != null
          ? DateTime(lastStreakNotified.year, lastStreakNotified.month, lastStreakNotified.day)
          : null;

      await scheduleDailyStreakReminder();

      if (lastLogin == null) return;

      final lastLoginDate = DateTime(lastLogin.year, lastLogin.month, lastLogin.day);
      final daysSinceLogin = today.difference(lastLoginDate).inDays;

      if (daysSinceLogin < 1) return;
      if (lastStreakDate != null && !lastStreakDate.isBefore(today)) return;

      final plugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final enabled = await plugin?.areNotificationsEnabled() ?? true;
      if (!enabled) return;

      if (daysSinceLogin >= 2) {
        await sendStreakNotification(
          uid: user.uid,
          title: 'Your streak was reset!',
          body: 'You missed a day. Start a new streak today — open PrePora now!',
          type: 'streak_reset',
        );
      } else {
        await sendStreakNotification(
          uid: user.uid,
          title: 'Keep your streak alive!',
          body: 'Don\'t let your progress slip away. Open PrePora today!',
          type: 'streak_warning',
        );
      }

      try {
        await SupabaseReadService.writeToAll('users', user.uid, {
          'lastStreakNotified': now.toIso8601String(),
          'lastLogin': now.toIso8601String(),
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
    _fcmMessageSub?.cancel();
  }
}
