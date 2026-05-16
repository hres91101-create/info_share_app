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

  static Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version; // e.g. "0.1.0"
  }

  /// Returns null when up to date or check fails (fail-soft: never blocks app).
  static Future<UpdateInfo?> check() async {
    try {
      final cur = await currentVersion();
      final r = await http.get(
        Uri.parse(_latestApi),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final tag = (j['tag_name'] as String? ?? '').replaceFirst('v', '').trim();
      if (tag.isEmpty) return null;
      if (!_isNewer(tag, cur)) return null;
      final assets = (j['assets'] as List<dynamic>? ?? []);
      String? apkUrl;
      for (final a in assets) {
        final m = a as Map<String, dynamic>;
        final name = (m['name'] as String? ?? '').toLowerCase();
        if (name.endsWith('.apk')) {
          apkUrl = m['browser_download_url'] as String?;
          break;
        }
      }
      if (apkUrl == null) return null;
      return UpdateInfo(
        version: tag,
        apkUrl: apkUrl,
        notes: (j['body'] as String? ?? '').trim(),
        current: cur,
      );
    } catch (_) {
      return null;
    }
  }

  /// true if [remote] semver is strictly greater than [local].
  static bool _isNewer(String remote, String local) {
    List<int> parse(String v) => v
        .split(RegExp(r'[.\-+]'))
        .take(3)
        .map((s) => int.tryParse(s) ?? 0)
        .toList();
    final a = parse(remote);
    final b = parse(local);
    while (a.length < 3) a.add(0);
    while (b.length < 3) b.add(0);
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
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
