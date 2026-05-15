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
