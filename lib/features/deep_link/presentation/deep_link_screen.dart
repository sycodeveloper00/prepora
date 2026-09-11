import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/services/app_update_service.dart';
import '../../../core/services/supabase_read_service.dart';

class DeepLinkScreen extends StatefulWidget {
  final String? id;
  final String? type;
  final String? parent;
  const DeepLinkScreen({super.key, this.id, this.type, this.parent});

  @override
  State<DeepLinkScreen> createState() => _DeepLinkScreenState();
}

class _DeepLinkScreenState extends State<DeepLinkScreen> {
  bool _processing = true;
  String? _error;
  bool _showUpdatePopup = false;

  @override
  void initState() {
    super.initState();
    _handleDeepLink();
  }

  Future<void> _handleDeepLink() async {
    final id = widget.id;
    final type = widget.type;
    if (id == null || id.isEmpty) {
      setState(() { _error = 'Invalid link — no ID found'; _processing = false; });
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      context.go('/auth/login');
      return;
    }

    try {
      final userData = await SupabaseReadService.getUser(user.uid)
          .timeout(const Duration(seconds: 5), onTimeout: () => null);

      if (userData != null) {
        final role = userData['role'] as String? ?? 'student';
        if (role == 'admin') {
          if (!mounted) return;
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Access Denied'),
              content: const Text('Admin accounts cannot access the student app.'),
              actions: [TextButton(onPressed: () { Navigator.pop(ctx); context.go('/auth/login'); }, child: const Text('OK'))],
            ),
          );
          return;
        }

        final isVerified = userData['verified'] == true || userData['isVerified'] == true;
        final freeTrialActive = userData['free_trial_active'] == true;
        final paidAccess = freeTrialActive || isVerified;

        if (!paidAccess) {
          final freeTrialEndsAt = userData['free_trial_ends_at'];
          if (freeTrialEndsAt != null) {
            final endDate = DateTime.tryParse(freeTrialEndsAt.toString());
            if (endDate != null && DateTime.now().isBefore(endDate)) {
              // trial still active
            } else if (!mounted) {
              return;
            } else {
              await showDialog(
                context: context,
                barrierDismissible: false,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1E1E2F),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: const Row(children: [
                    Icon(Icons.lock_rounded, color: Colors.redAccent),
                    SizedBox(width: 8),
                    Text('Paid Access Required', style: TextStyle(color: Colors.white)),
                  ]),
                  content: const Text(
                    'Your free trial has expired. Please get verified or subscribe to access content.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () { Navigator.pop(ctx); context.go('/dashboard'); },
                      child: const Text('Go to Dashboard', style: TextStyle(color: Colors.cyanAccent)),
                    ),
                  ],
                ),
              );
              return;
            }
          }
        }
      }

      final updateInfo = await AppUpdateService.checkForUpdate().timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );
      if (updateInfo != null && mounted) {
        setState(() { _showUpdatePopup = true; });
      }

      _navigateToContent(id, type, widget.parent);
    } catch (e) {
      if (!mounted) return;
      _navigateToContent(id, type, widget.parent);
    }
  }

  void _navigateToContent(String id, String? type, String? parent) {
    if (!mounted) return;
    if (type == 'folder') {
      context.go('/folders/$id', extra: {
        'canEdit': false,
        'canManage': false,
        'isAdmin': false,
      });
    } else {
      final parentFolderId = parent ?? '';
      if (parentFolderId.isNotEmpty) {
        context.go('/folders/$parentFolderId/sub/$id', extra: {
          'canEdit': false,
          'canManage': false,
          'isAdmin': false,
        });
      } else {
        context.go('/dashboard');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showUpdatePopup) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showUpdateDialog());
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: Center(
        child: _error != null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: Colors.white70, fontSize: 16)),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => context.go('/dashboard'),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A148C)),
                    child: const Text('Go to Dashboard', style: TextStyle(color: Colors.white)),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset('assets/images/app_icon.png', width: 80, height: 80),
                  const SizedBox(height: 20),
                  const CircularProgressIndicator(color: Color(0xFF00B8D4)),
                  const SizedBox(height: 16),
                  const Text('Opening content...', style: TextStyle(color: Colors.white54, fontSize: 14)),
                ],
              ),
      ),
    );
  }

  void _showUpdateDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.system_update_rounded, color: Colors.orange),
          SizedBox(width: 8),
          Text('Update Available', style: TextStyle(color: Colors.white)),
        ]),
        content: const Text(
          'A new version of PrePora is available. Please update to continue.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () { Navigator.pop(ctx); setState(() { _showUpdatePopup = false; }); },
            child: const Text('Later', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              AppUpdateService.openPlayStore();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A148C)),
            child: const Text('Update Now', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
