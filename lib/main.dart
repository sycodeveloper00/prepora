import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:home_widget/home_widget.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/router/app_router.dart';
import 'core/services/firebase_service.dart';
import 'core/services/notification_service.dart';

const _pdfChannel = MethodChannel('com.prepora.academy.prepora/pdf_intent');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    try {
      HomeWidget.registerBackgroundCallback(backgroundCallback);
    } catch (_) {}
    _listenPdfIntent();
  }
  await FirebaseService.initialize();
  await _initStorage();
  runApp(const ProviderScope(child: PrePoraApp()));
}

void _listenPdfIntent() {
  _pdfChannel.setMethodCallHandler((call) async {
    if (call.method == 'openPdf') {
      final uri = call.arguments as String?;
      if (uri != null && uri.isNotEmpty) {
        _navigateToPdf(uri);
      }
    }
  });
  _pdfChannel.invokeMethod<String>('getInitialPdfUri').then((uri) {
    if (uri != null && uri.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigateToPdf(uri);
      });
    }
  }).catchError((_) {});
}

void _navigateToPdf(String uri) async {
  for (int attempt = 0; attempt < 10; attempt++) {
    await Future.delayed(Duration(milliseconds: attempt == 0 ? 500 : 1000));
    final ctx = rootNavigatorKey.currentContext;
    if (ctx != null) {
      ctx.go('/pdf_reader/view', extra: {'url': uri});
      return;
    }
  }
}

@pragma('vm:entry-point')
Future<void> backgroundCallback(Uri? uri) async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseService.initialize();
  await _initStorage();
}

Future<void> _initStorage() async {
  if (kIsWeb) {
    await SharedPreferences.getInstance();
  } else {
    await Hive.initFlutter();
    await Hive.openBox('settings');
  }
}

class _AppLifecycle extends StatefulWidget {
  final Widget child;
  const _AppLifecycle({required this.child});
  @override
  State<_AppLifecycle> createState() => _AppLifecycleState();
}

class _AppLifecycleState extends State<_AppLifecycle> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await NotificationService.initialize();
      await NotificationService.requestNotificationPermission();
      await NotificationService.ensureExactAlarmPermission();
      await NotificationService.scheduleDailyStreakReminder();
      await NotificationService.checkAndNotify();
      final user = FirebaseService.currentUser;
      if (user != null) {
        await FirebaseService.updateStreak(user.uid);
      }
      _startSessionIfAdminOrAssistant();
      await _checkSingleDeviceLogin();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      NotificationService.clearBadge();
      _checkSingleDeviceLogin();
      _updateStreakAndNotify();
    }
  }

  Future<void> _updateStreakAndNotify() async {
    try {
      final user = FirebaseService.currentUser;
      if (user == null) return;
      await NotificationService.scheduleDailyStreakReminder();
      await NotificationService.checkAndNotify();
      await FirebaseService.updateStreak(user.uid);
    } catch (_) {}
  }

  Future<void> _startSessionIfAdminOrAssistant() async {
    // SessionManager is intentionally NOT started on Android.
    // Firebase Auth persists by default — no auto-logout needed.
  }

  Future<void> _checkSingleDeviceLogin() async {
    try {
      final isSameDevice = await FirebaseService.checkSingleDeviceLogin();
      if (!isSameDevice && mounted) {
        await FirebaseService.signOut();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Logged in on another device. Please sign in again.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
          context.go('/auth/login');
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class PrePoraApp extends ConsumerWidget {
  const PrePoraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return _AppLifecycle(
      child: MaterialApp.router(
        title: 'PrePora',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeMode,
        routerConfig: AppRouter.router,
      ),
    );
  }
}
