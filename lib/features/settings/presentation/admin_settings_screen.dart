import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/widgets/professional_loader.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});
  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> with WidgetsBindingObserver {
  bool _autoDownload = true;
  bool _notificationsEnabled = true;
  bool _loading = true;
  bool _loggingOut = false;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed && !kIsWeb) {
      final enabled = await FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.areNotificationsEnabled();
      if (mounted) setState(() => _notificationsEnabled = enabled ?? true);
    }
  }

  Future<void> _load() async {
    try {
      await FirebaseService.getSettings();
      final info = await PackageInfo.fromPlatform();
      _autoDownload = await FirebaseService.getUserAutoDownload();
      if (!kIsWeb) {
        final enabled = await FlutterLocalNotificationsPlugin()
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.areNotificationsEnabled();
        _notificationsEnabled = enabled ?? true;
      }
      if (mounted) {
        setState(() {
        _appVersion = info.version;
        _loading = false;
      });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load settings: $e'), backgroundColor: Colors.redAccent),
        );
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A0533);
    final hintColor = isDark ? Colors.white38 : Colors.black54;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Settings', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => context.pop()),
      ),
      body: _loading
          ? const Center(child: ProfessionalLoader())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: cardColor,
                  child: ListTile(
                    leading: const Icon(Icons.gavel_rounded, color: Colors.teal),
                    title: Text('Terms & Conditions', style: TextStyle(color: textColor)),
                    subtitle: Text('Usage policy & student agreement', style: TextStyle(color: hintColor, fontSize: 12)),
                    trailing: Icon(Icons.chevron_right, color: hintColor, size: 18),
                    onTap: () => _showTermsDialog(context),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  color: cardColor,
                  child: Consumer(builder: (ctx, ref, _) {
                    final themeMode = ref.watch(themeModeProvider);
                    final icon = themeMode == ThemeMode.light ? Icons.light_mode_rounded : (themeMode == ThemeMode.dark ? Icons.dark_mode_rounded : Icons.settings_brightness_rounded);
                    final label = themeMode == ThemeMode.light ? 'Light' : (themeMode == ThemeMode.dark ? 'Dark' : 'System');
                    return ListTile(
                      leading: Icon(icon, color: Colors.amber),
                      title: Text('Theme', style: TextStyle(color: textColor)),
                      subtitle: Text(label, style: TextStyle(color: hintColor, fontSize: 12)),
                      trailing: Icon(Icons.chevron_right, color: hintColor, size: 18),
                      onTap: () => _showThemeDialog(context, ref),
                    );
                  }),
                ),
                const SizedBox(height: 12),
                Card(
                  color: cardColor,
                  child: SwitchListTile(
                    title: Text('Auto Download Files', style: TextStyle(color: textColor)),
                    subtitle: Text('Auto-download files on first open', style: TextStyle(color: hintColor, fontSize: 12)),
                    value: _autoDownload,
                    activeThumbColor: const Color(0xFF4A148C),
                    onChanged: (val) async {
                      setState(() => _autoDownload = val);
                      await FirebaseService.updateUserAutoDownload(val);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  color: cardColor,
                  child: SwitchListTile(
                    secondary: const Icon(Icons.notifications_rounded, color: Colors.purpleAccent),
                    title: Text('Notifications', style: TextStyle(color: textColor)),
                    subtitle: Text(_notificationsEnabled ? 'System notifications ON' : 'System notifications OFF', style: TextStyle(color: hintColor, fontSize: 12)),
                    value: _notificationsEnabled,
                    activeThumbColor: const Color(0xFF4A148C),
                    onChanged: (val) async {
                      if (!kIsWeb) {
                        try {
                          await const MethodChannel('com.prepora.academy.prepora/pdf_intent').invokeMethod('openNotificationSettings');
                        } catch (_) {}
                      }
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  color: cardColor,
                  child: Column(children: [
                    ListTile(
                      leading: const Icon(Icons.info_outline_rounded, color: Colors.grey),
                      title: Text('Version', style: TextStyle(color: textColor)),
                      subtitle: Text('PrePora v$_appVersion', style: TextStyle(color: hintColor, fontSize: 12)),
                    ),
                    Divider(height: 1, color: isDark ? Colors.white12 : Colors.black12),
                    ListTile(
                      leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                      title: Text(_loggingOut ? 'Logging out...' : 'Logout', style: const TextStyle(color: Colors.redAccent)),
                      enabled: !_loggingOut,
                      trailing: _loggingOut
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent))
                          : null,
                      onTap: () async {
                        if (_loggingOut) return;
                        setState(() => _loggingOut = true);
                        try {
                          await FirebaseService.signOut();
                          if (mounted) context.go('/auth/login');
                        } finally {
                          if (mounted) setState(() => _loggingOut = false);
                        }
                      },
                    ),
                  ]),
                ),
              ],
            ),
    );
  }

  void _showTermsDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white70 : Colors.black54;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final terms = [
      ('Acceptance of Terms', 'By using PrePora, you agree to these Terms & Conditions.', Icons.check_circle_outline_rounded, Colors.teal),
      ('Eligibility', 'PrePora is for students preparing for MDCAT, ECAT, NUST, FAST, CSS, IELTS, etc.', Icons.person_outline_rounded, Colors.blue),
      ('Account Responsibility', 'Keep your credentials secure. You are responsible for all account activity.', Icons.lock_outline_rounded, Colors.orange),
      ('Content & Usage', 'Study material is for personal use only. Redistribution is prohibited.', Icons.library_books_rounded, Colors.purple),
      ('Paid Access', 'Payments are non-refundable unless stated by admin.', Icons.payments_rounded, Colors.green),
      ('AI Assistant', 'AI responses may contain errors. Verify critical info from official sources.', Icons.smart_toy_rounded, Colors.amber),
      ('Privacy', 'Your data is used only for app functionality. Not sold to third parties.', Icons.privacy_tip_rounded, Colors.teal),
      ('Prohibited Conduct', 'Misuse or harassment may result in account suspension.', Icons.gpp_bad_rounded, Colors.redAccent),
      ('Disclaimer', 'PrePora is not affiliated with any official exam board.', Icons.warning_amber_rounded, Colors.deepOrange),
      ('Changes to Terms', 'Terms may be updated. Continued use = acceptance.', Icons.update_rounded, Colors.blueGrey),
    ];
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.gavel_rounded, color: Colors.teal, size: 22),
          const SizedBox(width: 10),
          Text('Terms & Conditions', style: TextStyle(color: baseColor, fontSize: 16)),
        ]),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Welcome to PrePora — Pakistan\'s Smart Study App.', style: TextStyle(color: dimColor, fontSize: 13)),
              ),
              ...terms.map((t) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(t.$3, color: t.$4, size: 22),
                title: Text(t.$1, style: TextStyle(color: t.$4, fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text(t.$2, style: TextStyle(color: dimColor, fontSize: 12, height: 1.3)),
                dense: true,
              )),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(d),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            child: const Text('I Understand', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showThemeDialog(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(themeModeProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A0533);
    final hintColor = isDark ? Colors.white38 : Colors.black54;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: bgColor,
        title: Text('Choose Theme', style: TextStyle(color: textColor)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.light_mode_rounded, color: Colors.amber),
            title: Text('Light', style: TextStyle(color: textColor)),
            onTap: () { notifier.set(ThemeMode.light); Navigator.pop(d); },
          ),
          ListTile(
            leading: const Icon(Icons.dark_mode_rounded, color: Colors.blueGrey),
            title: Text('Dark', style: TextStyle(color: textColor)),
            onTap: () { notifier.set(ThemeMode.dark); Navigator.pop(d); },
          ),
          ListTile(
            leading: const Icon(Icons.settings_brightness_rounded, color: Colors.teal),
            title: Text('System', style: TextStyle(color: textColor)),
            subtitle: Text('Follow device theme', style: TextStyle(color: hintColor, fontSize: 11)),
            onTap: () { notifier.set(ThemeMode.system); Navigator.pop(d); },
          ),
        ]),
      ),
    );
  }
}