import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// Self-update via GitHub Releases (the app is sideloaded, not on Play Store).
///
/// Cut a release: bump pubspec `version:`, build APK, then create a GitHub
/// Release whose tag is `vX.Y.Z` and attach the `app-release.apk` asset.
/// This checker compares the running version against the latest release.
class Updater {
  static const String owner = 'hres91101-create';
  static const String repo = 'info_share_app';
  static String get _latestApi =>
      'https://api.github.com/repos/$owner/$repo/releases/latest';

  /// The installed build number. CI bakes GitHub's monotonic run number in via
  /// `flutter build apk --build-number=<run>`, so this just keeps growing —
  /// no human version bumping needed.
  static Future<int> currentBuild() async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }

  /// Releases are auto-tagged `b<runNumber>` by CI on every push to main.
  /// We compare that number to the installed build number.
  static Future<UpdateInfo?> check() async {
    try {
      final cur = await currentBuild();
      final r = await http.get(
        Uri.parse(_latestApi),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final tag = (j['tag_name'] as String? ?? '').trim();
      final m = RegExp(r'(\d+)').firstMatch(tag);
      if (m == null) return null;
      final remote = int.parse(m.group(1)!);
      if (remote <= cur) return null;
      final assets = (j['assets'] as List<dynamic>? ?? []);
      String? apkUrl;
      for (final a in assets) {
        final am = a as Map<String, dynamic>;
        final name = (am['name'] as String? ?? '').toLowerCase();
        if (name.endsWith('.apk')) {
          apkUrl = am['browser_download_url'] as String?;
          break;
        }
      }
      if (apkUrl == null) return null;
      return UpdateInfo(
        version: tag,
        apkUrl: apkUrl,
        notes: (j['body'] as String? ?? '').trim(),
        current: 'build $cur',
      );
    } catch (_) {
      return null;
    }
  }
}

class UpdateInfo {
  final String version;
  final String apkUrl;
  final String notes;
  final String current;
  UpdateInfo({
    required this.version,
    required this.apkUrl,
    required this.notes,
    required this.current,
  });
}
