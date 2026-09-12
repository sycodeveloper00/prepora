import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/widgets/professional_loader.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _navigate());
  }

  void _navigate() async {
    // Hard timeout: 20 seconds max for entire splash sequence
    final splashTimeout = Future.delayed(const Duration(seconds: 20), () {
      if (mounted && !_navigating) {
        _navigating = true;
        context.go('/auth/login');
      }
    });

    // Wait for Firebase init (max 15 seconds)
    for (int i = 0; i < 75; i++) {
      try {
        if (Firebase.apps.isNotEmpty) break;
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 200));
    }

    final user = FirebaseService.currentUser;
    if (user != null) {
      await _checkRoleAndRedirect(user.uid);
    } else {
      _navigateToLogin();
    }
  }

  Future<void> _checkRoleAndRedirect(String uid) async {
    if (_navigating) return;
    try {
      // Try cached role first (instant)
      String? role = await FirebaseService.getCachedUserRole(uid);
      if (role != null) {
        if (!mounted || _navigating) return;
        _navigating = true;
        _redirectByRole(role, uid);
        return;
      }

      // Fetch role with shorter timeout (5 seconds)
      role = await FirebaseService.getUserRole(uid)
          .timeout(const Duration(seconds: 5), onTimeout: () => null);
      if (role != null) {
        FirebaseService.cacheUserRole(uid, role);
      }

      if (!mounted || _navigating) return;
      _navigating = true;

      if (role == null) {
        // Offline or error — default to student dashboard
        context.go('/dashboard');
        return;
      }
      _redirectByRole(role, uid);
    } catch (_) {
      if (mounted && !_navigating) {
        _navigating = true;
        context.go('/dashboard');
      }
    }
  }

  void _redirectByRole(String role, String uid) {
    if (role == 'assistant' || role == 'Assistant') {
      // For assistant, try cached data first, then fetch with timeout
      _loadAssistantData(uid);
    } else {
      context.go('/dashboard');
    }
  }

  Future<void> _loadAssistantData(String uid) async {
    try {
      final snapshot = await FirebaseService.getUser(uid)
          .timeout(const Duration(seconds: 5), onTimeout: () => null);
      final data = snapshot?.data() as Map<String, dynamic>?;
      final folderIds = (data?['folderIds'] as List<dynamic>?)?.cast<String>() ?? <String>[];
      final assistantName = data?['name'] as String? ?? 'Assistant';
      if (mounted) {
        context.go('/assistant', extra: {'folderIds': folderIds, 'assistantName': assistantName});
      }
    } catch (_) {
      if (mounted) {
        context.go('/assistant', extra: {'folderIds': <String>[], 'assistantName': 'Assistant'});
      }
    }
  }

  void _navigateToLogin() {
    if (mounted && !_navigating) {
      _navigating = true;
      context.go('/auth/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D2E),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/logo.png', height: 180, width: 180),
            const SizedBox(height: 24),
            const Text('PrePora',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 48),
            const ProfessionalLoader(size: 28, color: Color(0xFFB388FF)),
            const SizedBox(height: 16),
            Text(
              'Loading...',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
