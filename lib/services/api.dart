import 'dart:convert';
import 'package:http/http.dart' as http;

/// Talks to the deployed info-share backend.
/// The web app has no real auth — it just sends an `author` name string.
/// We replicate that here.
class Api {
  static const String baseUrl = 'https://info-share.onrender.com';

  static Future<List<Tower>> fetchTowers() async {
    final r = await http.get(Uri.parse('$baseUrl/api/towers'));
    if (r.statusCode != 200) {
      throw ApiException('塔列表读取失败 (${r.statusCode})');
    }
    final list = jsonDecode(r.body) as List<dynamic>;
    return list.map((e) => Tower.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<HotspotSettings> fetchSettings() async {
    try {
      final r = await http.get(Uri.parse('$baseUrl/api/settings'));
      if (r.statusCode != 200) return HotspotSettings(9, 4.5);
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      return HotspotSettings(
        (j['outerPct'] as num?)?.toDouble() ?? 9,
        (j['innerPct'] as num?)?.toDouble() ?? 4.5,
      );
    } catch (_) {
      return HotspotSettings(9, 4.5);
    }
  }

  static Future<List<PageData>> fetchPages() async {
    final r = await http.get(Uri.parse('$baseUrl/api/pages'));
    if (r.statusCode != 200) {
      throw ApiException('地图读取失败 (${r.statusCode})');
    }
    final list = jsonDecode(r.body) as List<dynamic>;
    return list
        .map((e) => PageData.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.position.compareTo(b.position));
  }

  static Future<List<RecentItem>> fetchRecent({int limit = 30}) async {
    final r = await http.get(Uri.parse('$baseUrl/api/recent?limit=$limit'));
    if (r.statusCode != 200) {
      throw ApiException('最新动态读取失败 (${r.statusCode})');
    }
    final list = jsonDecode(r.body) as List<dynamic>;
    return list
        .map((e) => RecentItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<TowerDetail> fetchTowerDetail(int id) async {
    final results = await Future.wait([
      http.get(Uri.parse('$baseUrl/api/towers/$id')),
      http.get(Uri.parse('$baseUrl/api/towers/$id/notes')),
    ]);
    final tr = results[0];
    final nr = results[1];
    if (tr.statusCode != 200) {
      throw ApiException('塔资料读取失败 (${tr.statusCode})');
    }
    final tower = jsonDecode(tr.body) as Map<String, dynamic>;
    final notes = nr.statusCode == 200
        ? (jsonDecode(nr.body) as List<dynamic>)
        : const <dynamic>[];
    return TowerDetail.fromJson(tower, notes);
  }

  static Future<void> postNote(int towerId, String author, String content) async {
    final r = await http.post(
      Uri.parse('$baseUrl/api/towers/$towerId/notes'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'author': author, 'content': content}),
    );
    if (r.statusCode != 200) {
      throw ApiException(_errorOf(r.body) ?? '送出失败 (${r.statusCode})');
    }
  }

  static Future<void> lockTower(int towerId, String author) async {
    final r = await http.post(
      Uri.parse('$baseUrl/api/towers/$towerId/lock'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'author': author}),
    );
    if (r.statusCode != 200) {
      throw ApiException(_errorOf(r.body) ?? '锁定失败 (${r.statusCode})');
    }
  }

  static Future<void> unlockTower(int towerId, String author) async {
    final r = await http.post(
      Uri.parse('$baseUrl/api/towers/$towerId/unlock'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'author': author}),
    );
    if (r.statusCode != 200) {
      throw ApiException(_errorOf(r.body) ?? '解锁失败 (${r.statusCode})');
    }
  }

  static String? _errorOf(String body) {
    try {
      final m = jsonDecode(body);
      if (m is Map && m['error'] is String) return m['error'] as String;
    } catch (_) {}
    return null;
  }
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class Tower {
  final int id;
  final String? name;
  final bool hidden;
  final int noteCount;
  final int imageCount;
  final String? lockBy;
  final int? lockUntil;

  Tower({
    required this.id,
    this.name,
    this.hidden = false,
    this.noteCount = 0,
    this.imageCount = 0,
    this.lockBy,
    this.lockUntil,
  });

  bool get locked =>
      lockUntil != null && lockUntil! > DateTime.now().millisecondsSinceEpoch;

  factory Tower.fromJson(Map<String, dynamic> j) => Tower(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String?,
        hidden: j['hidden'] == true || j['hidden'] == 1,
        noteCount: (j['note_count'] as num?)?.toInt() ?? 0,
        imageCount: (j['image_count'] as num?)?.toInt() ?? 0,
        lockBy: j['lock_by'] as String?,
        lockUntil: (j['lock_until'] as num?)?.toInt(),
      );
}

class NoteItem {
  final int id;
  final String author;
  final String content;
  final int createdAt;
  NoteItem(this.id, this.author, this.content, this.createdAt);
  factory NoteItem.fromJson(Map<String, dynamic> j) => NoteItem(
        (j['id'] as num).toInt(),
        j['author'] as String? ?? '',
        j['content'] as String? ?? '',
        (j['created_at'] as num?)?.toInt() ?? 0,
      );
}

class ImageItem {
  final int id;
  final String author;
  final String filePath;
  final String? caption;
  final int createdAt;
  ImageItem(this.id, this.author, this.filePath, this.caption, this.createdAt);
  factory ImageItem.fromJson(Map<String, dynamic> j) => ImageItem(
        (j['id'] as num).toInt(),
        j['author'] as String? ?? '',
        j['file_path'] as String? ?? '',
        j['caption'] as String?,
        (j['created_at'] as num?)?.toInt() ?? 0,
      );
}

class HotspotSettings {
  final double outerPct;
  final double innerPct;
  HotspotSettings(this.outerPct, this.innerPct);
}

class Hotspot {
  final int towerId;
  final double xPct;
  final double yPct;
  final String? towerName;
  final bool hidden;
  final int noteCount;
  final int imageCount;
  final String? lockBy;
  final int? lockUntil;
  Hotspot({
    required this.towerId,
    required this.xPct,
    required this.yPct,
    this.towerName,
    this.hidden = false,
    this.noteCount = 0,
    this.imageCount = 0,
    this.lockBy,
    this.lockUntil,
  });
  bool get locked =>
      lockUntil != null && lockUntil! > DateTime.now().millisecondsSinceEpoch;
  bool get hasContent => noteCount > 0 || imageCount > 0;
  factory Hotspot.fromJson(Map<String, dynamic> j) {
    final tw = j['tower'] as Map<String, dynamic>?;
    return Hotspot(
      towerId: (j['tower_id'] as num).toInt(),
      xPct: (j['x_pct'] as num?)?.toDouble() ?? 50,
      yPct: (j['y_pct'] as num?)?.toDouble() ?? 50,
      towerName: tw?['name'] as String?,
      hidden: tw?['hidden'] == true || tw?['hidden'] == 1,
      noteCount: (tw?['note_count'] as num?)?.toInt() ?? 0,
      imageCount: (tw?['image_count'] as num?)?.toInt() ?? 0,
      lockBy: tw?['lock_by'] as String?,
      lockUntil: (tw?['lock_until'] as num?)?.toInt(),
    );
  }
}

class PageData {
  final int id;
  final String name;
  final int position;
  final String? imagePath;
  final double offsetXPct;
  final double scaleX;
  final List<Hotspot> hotspots;
  PageData({
    required this.id,
    required this.name,
    required this.position,
    required this.imagePath,
    required this.offsetXPct,
    required this.scaleX,
    required this.hotspots,
  });
  factory PageData.fromJson(Map<String, dynamic> j) => PageData(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String? ?? '',
        position: (j['position'] as num?)?.toInt() ?? 0,
        imagePath: j['image_path'] as String?,
        offsetXPct: (j['offset_x_pct'] as num?)?.toDouble() ?? 0,
        scaleX: (j['scale_x'] as num?)?.toDouble() ?? 1,
        hotspots: (j['hotspots'] as List<dynamic>? ?? [])
            .map((e) => Hotspot.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class RecentItem {
  final String kind; // 'note' | 'image'
  final int towerId;
  final String author;
  final String? text;
  final String? filePath;
  final int createdAt;
  RecentItem(this.kind, this.towerId, this.author, this.text, this.filePath,
      this.createdAt);
  bool get isImage => kind == 'image';
  factory RecentItem.fromJson(Map<String, dynamic> j) => RecentItem(
        j['kind'] as String? ?? 'note',
        (j['tower_id'] as num?)?.toInt() ?? 0,
        j['author'] as String? ?? '',
        j['text'] as String?,
        j['file_path'] as String?,
        (j['created_at'] as num?)?.toInt() ?? 0,
      );
}

class TowerDetail {
  final int id;
  final String? name;
  final String? lockBy;
  final int? lockUntil;
  final List<NoteItem> notes;
  final List<ImageItem> images;

  TowerDetail({
    required this.id,
    this.name,
    this.lockBy,
    this.lockUntil,
    required this.notes,
    required this.images,
  });

  bool get locked =>
      lockUntil != null && lockUntil! > DateTime.now().millisecondsSinceEpoch;

  factory TowerDetail.fromJson(
      Map<String, dynamic> towerResp, List<dynamic> notesResp) {
    final tw = towerResp['tower'] as Map<String, dynamic>;
    final images = (towerResp['images'] as List<dynamic>? ?? [])
        .map((e) => ImageItem.fromJson(e as Map<String, dynamic>))
        .toList();
    final notes = notesResp
        .map((e) => NoteItem.fromJson(e as Map<String, dynamic>))
        .toList();
    return TowerDetail(
      id: (tw['id'] as num).toInt(),
      name: tw['name'] as String?,
      lockBy: tw['lock_by'] as String?,
      lockUntil: (tw['lock_until'] as num?)?.toInt(),
      notes: notes,
      images: images,
    );
  }
}
