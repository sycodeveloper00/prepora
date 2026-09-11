import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppUpdateService {
  static Future<Map<String, dynamic>?> checkForUpdate() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('android')
          .get()
          .timeout(const Duration(seconds: 5), onTimeout: () => throw Exception('timeout'));
      if (!doc.exists) return null;
      final data = doc.data()!;
      final minVersion = data['min_version'] as String? ?? '';
      final latestVersion = data['latest_version'] as String? ?? '';
      final updateUrl = data['update_url'] as String? ?? 'https://prepora.pages.dev';
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      if (minVersion.isNotEmpty && _isNewer(minVersion, currentVersion)) {
        return {
          'minVersion': minVersion,
          'latestVersion': latestVersion,
          'updateUrl': updateUrl,
          'mandatory': true,
        };
      }
      if (latestVersion.isNotEmpty && _isNewer(latestVersion, currentVersion)) {
        return {
          'minVersion': minVersion,
          'latestVersion': latestVersion,
          'updateUrl': updateUrl,
          'mandatory': false,
        };
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static bool _isNewer(String v1, String v2) {
    final p1 = v1.split('.').map(int.tryParse).whereType<int>().toList();
    final p2 = v2.split('.').map(int.tryParse).whereType<int>().toList();
    for (var i = 0; i < (p1.length > p2.length ? p1.length : p2.length); i++) {
      final a = i < p1.length ? p1[i] : 0;
      final b = i < p2.length ? p2[i] : 0;
      if (a > b) return true;
      if (a < b) return false;
    }
    return false;
  }

  static Future<void> openPlayStore() async {
    final url = Uri.parse('https://play.google.com/store/apps/details?id=com.prepora.app');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}
