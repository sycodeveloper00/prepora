import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/services/app_update_service.dart';

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
  bool _showInstallScreen = false;

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
      final userDoc = await FirebaseFirestore.instance
          .collection('students')
          .doc(user.uid)
          .get()
          .timeout(const Duration(seconds: 5), onTimeout: () => throw Exception('timeout'));

      if (!userDoc.exists) {
        setState(() { _error = 'Account not found'; _processing = false; });
        return;
      }

      final userData = userDoc.data()!;
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

      final isVerified = userData['isVerified'] == true;
      final paidAccess = userData['paid_access'] == true;
      final trialStart = userData['trial_start'] as Timestamp?;
      final freeTrialDays = (userData['free_trial_days'] as num?)?.toInt() ?? 5;
      bool hasPaidAccess = false;
      if (paidAccess) {
        if (isVerified) {
          hasPaidAccess = true;
        } else if (trialStart != null) {
          final trialEnd = trialStart.toDate().add(Duration(days: freeTrialDays));
          if (DateTime.now().isBefore(trialEnd)) {
            hasPaidAccess = true;
          }
        }
      }

      if (paidAccess && !hasPaidAccess) {
        if (!mounted) return;
        setState(() { _showInstallScreen = false; });
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

      final updateInfo = await AppUpdateService.checkForUpdate().timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );
      if (updateInfo != null && mounted) {
        setState(() { _showUpdatePopup = true; });
      }

      if (type == 'folder') {
        if (!mounted) return;
        context.go('/folders/$id');
      } else {
        final parentFolderId = widget.parent ?? '';
        if (!mounted) return;
        if (parentFolderId.isNotEmpty) {
          context.go('/folders/$parentFolderId/sub/$id');
        } else {
          context.go('/dashboard');
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = 'Failed to load link'; _processing = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showInstallScreen) {
      return _buildInstallScreen();
    }
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

  Widget _buildInstallScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/images/app_icon.png', width: 100, height: 100),
              const SizedBox(height: 24),
              const Text(
                'PrePora App Not Found',
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'Please install the PrePora app to view this content.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () async {
                  AppUpdateService.openPlayStore();
                },
                icon: const Icon(Icons.download_rounded, color: Colors.white),
                label: const Text('Install PrePora', style: TextStyle(color: Colors.white, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A148C),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => launchWebsite(),
                child: const Text('Visit prepora.pages.dev', style: TextStyle(color: Color(0xFF00B8D4), fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void launchWebsite() async {
    final Uri url = Uri.parse('https://prepora.pages.dev');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}
