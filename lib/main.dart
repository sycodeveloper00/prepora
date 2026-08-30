import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:home_widget/home_widget.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/router/app_router.dart';
import 'core/services/firebase_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/storage_account_keep_alive.dart';

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
  StorageAccountKeepAliveService.start();
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
  StreamSubscription? _deviceSub;
  StreamSubscription? _authSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authSub = FirebaseAuth.instance.authStateChanges().listen((_) {
      _listenForDeviceLogout();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Run notification + session checks in parallel
      await Future.wait([
        NotificationService.initialize(),
        _initSessionData(),
      ]);
      // Then do sequential permission-dependent tasks
      await NotificationService.requestNotificationPermission();
      await NotificationService.ensureExactAlarmPermission();
      await NotificationService.scheduleDailyStreakReminder();
      await NotificationService.checkAndNotify();
      _listenForDeviceLogout();
    });
  }

  Future<void> _initSessionData() async {
    try {
      final user = FirebaseService.currentUser;
      if (user != null) {
        await Future.wait([
          FirebaseService.updateStreak(user.uid),
          _checkSingleDeviceLogin(),
        ]);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _deviceSub?.cancel();
    _authSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      NotificationService.clearBadge();
      // Only check critical security (device login) on resume
      // Streak/notifications are handled by the dashboard provider refresh
      _checkSingleDeviceLogin();
    }
  }

  Future<void> _listenForDeviceLogout() async {
    try {
      final user = FirebaseService.currentUser;
      if (user == null) return;
      final deviceId = await FirebaseService.getDeviceId();
      _deviceSub?.cancel();
      _deviceSub = FirebaseService.firestore
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen((snap) async {
        if (!snap.exists) return;
        final data = snap.data() as Map<String, dynamic>;
        final currentDeviceId = data['currentDeviceId'] as String? ?? '';
        if (currentDeviceId.isEmpty) return;
        if (currentDeviceId != deviceId) {
          await _forceLogout();
        }
      }, onError: (_) {});
    } catch (_) {}
  }

  Future<void> _forceLogout() async {
    _deviceSub?.cancel();
    await FirebaseService.signOut();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You were logged out because you signed in on another device.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );
      context.go('/auth/login');
    }
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
