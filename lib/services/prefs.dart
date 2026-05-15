import 'package:shared_preferences/shared_preferences.dart';

/// Persists the player's display name (the backend's only identity concept).
class Prefs {
  static const _nameKey = 'info_share_name';

  static Future<String?> getName() async {
    final p = await SharedPreferences.getInstance();
    final n = p.getString(_nameKey);
    return (n != null && n.trim().isNotEmpty) ? n : null;
  }

  static Future<void> setName(String name) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_nameKey, name.trim());
  }

  static String randomName() {
    const adj = ['快乐', '勇敢', '神秘', '闪亮', '迅捷', '冷静', '火热', '机灵'];
    const animal = ['老虎', '狐狸', '猫头鹰', '海豚', '猎豹', '雄鹰', '狼', '熊猫'];
    final now = DateTime.now().millisecondsSinceEpoch;
    final a = adj[now % adj.length];
    final b = animal[(now ~/ 7) % animal.length];
    final n = 10 + (now % 90);
    return '$a$b$n';
  }
}
