import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  String? _error;

  @override
  void initState() {
    super.initState();
    _handleDeepLink();
  }

  Future<void> _handleDeepLink() async {
    final id = widget.id;
    final type = widget.type;
    if (id == null || id.isEmpty) {
      setState(() { _error = 'Invalid link'; });
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
          .timeout(const Duration(seconds: 3), onTimeout: () => null);

      if (userData != null) {
        final isVerified = userData['verified'] == true || userData['isVerified'] == true;
        final freeTrialActive = userData['free_trial_active'] == true;
        final paidAccess = freeTrialActive || isVerified;

        if (!paidAccess) {
          final freeTrialEndsAt = userData['free_trial_ends_at'];
          if (freeTrialEndsAt != null) {
            final endDate = DateTime.tryParse(freeTrialEndsAt.toString());
            if (endDate != null && DateTime.now().isAfter(endDate)) {
              if (!mounted) return;
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
                    'Your free trial has expired. Please get verified or subscribe.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        context.go('/dashboard');
                      },
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

      _navigateToContent(id, type, widget.parent);
    } catch (e) {
      if (!mounted) return;
      _navigateToContent(id, type, widget.parent);
    }
  }

  void _navigateToContent(String id, String? type, String? parent) {
    if (!mounted) return;

    if (type == 'folder') {
      context.go('/dashboard');
      context.push('/folders/$id', extra: {'canEdit': false, 'canManage': false});
    } else if (type == 'subfolder') {
      final parentFolderId = parent ?? '';
      if (parentFolderId.isNotEmpty) {
        context.go('/dashboard');
        context.push('/folders/$parentFolderId', extra: {'canEdit': false, 'canManage': false});
        context.push('/folders/$parentFolderId/sub/$id', extra: {'canEdit': false, 'canManage': false});
      } else {
        context.go('/dashboard');
      }
    } else {
      final parentFolderId = parent ?? '';
      if (parentFolderId.isNotEmpty) {
        context.go('/dashboard');
        context.push('/folders/$parentFolderId', extra: {'canEdit': false, 'canManage': false});
        context.push('/folders/$parentFolderId/sub/$id', extra: {'canEdit': false, 'canManage': false});
      } else {
        context.go('/dashboard');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: Center(
        child: _error != null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () => context.go('/dashboard'),
                    child: const Text('Go to Dashboard', style: TextStyle(color: Color(0xFF00B8D4))),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset('assets/images/app_icon.png', width: 64, height: 64),
                  const SizedBox(height: 16),
                  const CircularProgressIndicator(color: Color(0xFF00B8D4), strokeWidth: 2),
                  const SizedBox(height: 12),
                  const Text('Opening...', style: TextStyle(color: Colors.white38, fontSize: 13)),
                ],
              ),
      ),
    );
  }
}
