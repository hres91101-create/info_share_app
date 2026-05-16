import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'api.dart';

/// Fire-and-forget diagnostics → website /api/clientlog. Lets us see device /
/// OS / errors online even when the app won't open on some OEM device.
class Diag {
  static String _os = '';
  static String _appv = '';

  static Future<void> init() async {
    try {
      _os = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } catch (_) {}
    try {
      final i = await PackageInfo.fromPlatform();
      _appv = '${i.version}+${i.buildNumber}';
    } catch (_) {}
  }

  static void log(String tag, [String msg = '']) {
    try {
      http
          .post(Uri.parse('${Api.baseUrl}/api/clientlog'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'tag': tag,
                'msg': msg,
                'os': _os,
                'appv': _appv,
              }))
          .timeout(const Duration(seconds: 6))
          .catchError((_) => http.Response('', 0));
    } catch (_) {}
  }
}
