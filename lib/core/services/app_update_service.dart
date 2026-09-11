import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'supabase_read_service.dart';

class AppUpdateService {
  static Future<Map<String, dynamic>?> checkForUpdate() async {
    try {
      final data = await SupabaseReadService.getSettings('app_config')
          .timeout(const Duration(seconds: 5), onTimeout: () => null);
      if (data == null) return null;

      final androidData = data['android'] as Map<String, dynamic>?;
      if (androidData == null) return null;

      final minVersion = androidData['min_version'] as String? ?? '';
      final latestVersion = androidData['latest_version'] as String? ?? '';
      final updateUrl = androidData['update_url'] as String? ?? '';
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

  static Future<void> openUpdateLink(String url) async {
    if (url.isEmpty) {
      await openPlayStore();
      return;
    }
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  static Future<void> openPlayStore() async {
    final url = Uri.parse('https://play.google.com/store/apps/details?id=com.prepora.academy.prepora');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}
