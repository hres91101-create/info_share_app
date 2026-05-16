import 'package:flutter/material.dart';
import '../services/api.dart';
import 'recent_feed.dart';
import 'zone_map.dart';

/// In-overlay browser: shared 3-zone map + hotspots (ZoneMapView) plus a
/// 最新动态 tab. Tap a hotspot → that tower's notes/images. Pure Flutter
/// (no PlatformView) so it renders inside the system overlay window.
class OverlayBrowser extends StatefulWidget {
  const OverlayBrowser({super.key});
  @override
  State<OverlayBrowser> createState() => _OverlayBrowserState();
}

class _OverlayBrowserState extends State<OverlayBrowser> {
  int _view = 0; // 0 = maps, 1 = recent feed
  int? _towerId;
  Future<TowerDetail>? _detailF;

  void _openTower(int id) => setState(() {
        _towerId = id;
        _detailF = Api.fetchTowerDetail(id);
      });

  void _back() => setState(() {
        _towerId = null;
        _detailF = null;
      });

  String _fmt(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  void _zoom(String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Center(
            child: Image.network(url,
                fit: BoxFit.contain,
                errorBuilder: (c, e, s) => const Text('（图片加载失败）',
                    style: TextStyle(color: Colors.white))),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [_toolbar(), Expanded(child: _body())]);
  }

  Widget _toolbar() {
    if (_towerId != null) {
      return Container(
        color: const Color(0xFFF3F4F6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(children: [
          IconButton(
              icon: const Icon(Icons.arrow_back, size: 20),
              onPressed: _back),
          Text('塔 $_towerId',
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
      );
    }
    Widget tab(String label, int v) {
      final on = _view == v;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _view = v),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: on ? const Color(0xFF1E2A47) : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontWeight: on ? FontWeight.bold : FontWeight.normal,
                    color: on ? const Color(0xFF1E2A47) : Colors.grey)),
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFFF3F4F6),
      child: Row(children: [tab('地图选塔', 0), tab('最新动态', 1)]),
    );
  }

  Widget _body() {
    if (_towerId != null) return _towerDetail();
    if (_view == 1) return const RecentFeed(compact: true);
    return ZoneMapView(onTapTower: _openTower);
  }

  Widget _towerDetail() {
    return FutureBuilder<TowerDetail>(
      future: _detailF,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('读取失败：${snap.error}'));
        }
        final d = snap.data!;
        final items = <_E>[
          ...d.notes
              .map((n) => _E(n.createdAt, n.author, '笔记', n.content, null)),
          ...d.images.map((im) =>
              _E(im.createdAt, im.author, '图', im.caption, im.filePath)),
        ]..sort((a, b) => a.at.compareTo(b.at));
        if (items.isEmpty && !d.locked) {
          return const Center(child: Text('这座塔暂无笔记或图片'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(10),
          itemCount: items.length + (d.locked ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (c, i) {
            if (d.locked && i == 0) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                color: const Color(0xFFFEE2E2),
                child: Text('🔥 ${d.lockBy} 进攻中',
                    style: const TextStyle(
                        color: Color(0xFF991B1B),
                        fontWeight: FontWeight.w600)),
              );
            }
            final e = items[i - (d.locked ? 1 : 0)];
            return Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                border: Border.all(color: const Color(0xFFE5E7EB)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: e.kind == '笔记'
                            ? const Color(0xFFDBEAFE)
                            : const Color(0xFFD1FAE5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child:
                          Text(e.kind, style: const TextStyle(fontSize: 10)),
                    ),
                    const SizedBox(width: 6),
                    Text(e.author,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text(_fmt(e.at),
                        style: const TextStyle(
                            fontSize: 10, color: Colors.grey)),
                  ]),
                  if (e.img != null) ...[
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () => _zoom(e.img!),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(e.img!,
                            fit: BoxFit.contain,
                            errorBuilder: (c, x, s) =>
                                const Text('（图片加载失败）')),
                      ),
                    ),
                  ],
                  if (e.text != null && e.text!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(e.text!, style: const TextStyle(fontSize: 13)),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _E {
  final int at;
  final String author;
  final String kind;
  final String? text;
  final String? img;
  _E(this.at, this.author, this.kind, this.text, this.img);
}
