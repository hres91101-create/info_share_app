import 'package:flutter/material.dart';
import '../services/api.dart';
import 'recent_feed.dart';

/// In-overlay browser: the real 3-zone maps with clickable hotspot buttons
/// (mirrors the website exactly — same /api/pages data + positioning math),
/// plus a 最新动态 tab. Tap a hotspot → that tower's notes/images.
/// Pure Flutter (no PlatformView) so it renders inside the system overlay.
class OverlayBrowser extends StatefulWidget {
  const OverlayBrowser({super.key});
  @override
  State<OverlayBrowser> createState() => _OverlayBrowserState();
}

class _OverlayBrowserState extends State<OverlayBrowser> {
  int _view = 0; // 0 = maps, 1 = recent feed
  int _pageIdx = 0;
  int? _towerId;
  Future<TowerDetail>? _detailF;

  late Future<_MapData> _mapF;

  @override
  void initState() {
    super.initState();
    _mapF = _loadMap();
  }

  Future<_MapData> _loadMap() async {
    final results = await Future.wait([
      Api.fetchPages(),
      Api.fetchSettings(),
    ]);
    return _MapData(results[0] as List<PageData>,
        results[1] as HotspotSettings);
  }

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
    return _maps();
  }

  Widget _maps() {
    return FutureBuilder<_MapData>(
      future: _mapF,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('地图读取失败：${snap.error}', textAlign: TextAlign.center),
              TextButton(
                  onPressed: () => setState(() => _mapF = _loadMap()),
                  child: const Text('重试')),
            ]),
          );
        }
        final data = snap.data!;
        final pages = data.pages;
        if (pages.isEmpty) {
          return const Center(child: Text('管理员还没设置地图'));
        }
        final idx = _pageIdx.clamp(0, pages.length - 1);
        final page = pages[idx];
        return Column(
          children: [
            // zone selector
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: pages.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (c, i) {
                  final on = i == idx;
                  return Center(
                    child: ChoiceChip(
                      label: Text(pages[i].name),
                      selected: on,
                      onSelected: (_) => setState(() => _pageIdx = i),
                    ),
                  );
                },
              ),
            ),
            Expanded(
              child: page.imagePath == null
                  ? const Center(child: Text('这个城区还没有地图图片'))
                  : InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: _HotspotMap(
                        page: page,
                        settings: data.settings,
                        onTapTower: _openTower,
                      ),
                    ),
            ),
          ],
        );
      },
    );
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
          ...d.images.map(
              (im) => _E(im.createdAt, im.author, '图', im.caption, im.filePath)),
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
                        style:
                            const TextStyle(fontSize: 10, color: Colors.grey)),
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

/// Renders one zone's map image with circular hotspot buttons positioned
/// exactly like the website: leftPct = 50 + (x-50)*scaleX + offsetX,
/// topPct = y; circle diameter = outerPct% of the image WIDTH.
class _HotspotMap extends StatefulWidget {
  final PageData page;
  final HotspotSettings settings;
  final void Function(int towerId) onTapTower;
  const _HotspotMap({
    required this.page,
    required this.settings,
    required this.onTapTower,
  });
  @override
  State<_HotspotMap> createState() => _HotspotMapState();
}

class _HotspotMapState extends State<_HotspotMap> {
  double? _aspect; // width / height

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _HotspotMap old) {
    super.didUpdateWidget(old);
    if (old.page.imagePath != widget.page.imagePath) {
      _aspect = null;
      _resolve();
    }
  }

  void _resolve() {
    final src = widget.page.imagePath;
    if (src == null) return;
    final img = NetworkImage(src);
    final stream = img.resolve(const ImageConfiguration());
    late final ImageStreamListener l;
    l = ImageStreamListener((info, _) {
      if (mounted) {
        setState(() => _aspect =
            info.image.width / info.image.height);
      }
      stream.removeListener(l);
    }, onError: (_, __) {
      if (mounted) setState(() => _aspect = 16 / 9);
      stream.removeListener(l);
    });
    stream.addListener(l);
  }

  @override
  Widget build(BuildContext context) {
    final src = widget.page.imagePath!;
    if (_aspect == null) {
      return const SizedBox(
          height: 200, child: Center(child: CircularProgressIndicator()));
    }
    final s = widget.settings;
    final offsetX = widget.page.offsetXPct;
    final scaleX = widget.page.scaleX;
    final spots = widget.page.hotspots.where((h) => !h.hidden).toList();

    return AspectRatio(
      aspectRatio: _aspect!,
      child: LayoutBuilder(
        builder: (ctx, c) {
          final w = c.maxWidth;
          final h = c.maxHeight;
          final d = s.outerPct / 100.0 * w; // outer circle diameter
          final innerD = (s.innerPct / s.outerPct) * d;
          return Stack(
            children: [
              Positioned.fill(
                child: Image.network(src,
                    fit: BoxFit.fill,
                    errorBuilder: (a, b, cc) =>
                        const Center(child: Text('地图加载失败'))),
              ),
              ...spots.map((hp) {
                final leftPct =
                    50 + (hp.xPct - 50) * scaleX + offsetX;
                final cx = leftPct / 100.0 * w;
                final cy = hp.yPct / 100.0 * h;
                final Color ring;
                if (hp.locked) {
                  ring = const Color(0xFFDC2626);
                } else if (hp.hasContent) {
                  ring = const Color(0xFF10B981);
                } else {
                  ring = const Color(0xFFF59E0B);
                }
                return Positioned(
                  left: cx - d / 2,
                  top: cy - d / 2,
                  width: d,
                  height: d,
                  child: GestureDetector(
                    onTap: () => widget.onTapTower(hp.towerId),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ring.withOpacity(0.45),
                        border: Border.all(color: ring, width: 1.5),
                      ),
                      child: Center(
                        child: Container(
                          width: innerD,
                          height: innerD,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xCC000000),
                          ),
                          alignment: Alignment.center,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Text(
                                '${hp.towerId}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

class _MapData {
  final List<PageData> pages;
  final HotspotSettings settings;
  _MapData(this.pages, this.settings);
}

class _E {
  final int at;
  final String author;
  final String kind;
  final String? text;
  final String? img;
  _E(this.at, this.author, this.kind, this.text, this.img);
}
