import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api.dart';

/// Shared 3-zone map + hotspot picker. Used BOTH in the floating overlay and
/// in the main app. Mirrors the website exactly: /api/pages + /api/settings,
/// position = (50 + (x-50)*scaleX + offsetX, y), circle Ø = outerPct% of the
/// image width. Tap a hotspot → onTapTower(towerId).
class ZoneMapView extends StatefulWidget {
  final void Function(int towerId) onTapTower;
  const ZoneMapView({super.key, required this.onTapTower});
  @override
  State<ZoneMapView> createState() => _ZoneMapViewState();
}

class _MapData {
  final List<PageData> pages;
  final HotspotSettings settings;
  _MapData(this.pages, this.settings);
}

class _ZoneMapViewState extends State<ZoneMapView> {
  int _pageIdx = 0;
  // Last good data kept in state so periodic refresh updates silently
  // (no reload spinner / flicker), like the website's diff refresh.
  _MapData? _data;
  Object? _err;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    // Poll like the website (it softRefreshes every 5s) so lock state /
    // who-took-what / new content stays current.
    _timer = Timer.periodic(
        const Duration(seconds: 8), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final r = await Future.wait([Api.fetchPages(), Api.fetchSettings()]);
      if (!mounted) return;
      setState(() {
        _data = _MapData(r[0] as List<PageData>, r[1] as HotspotSettings);
        _err = null;
      });
    } catch (e) {
      if (!mounted || silent) return; // silent poll failure → keep old data
      setState(() => _err = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_data == null && _err != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('地图读取失败：$_err', textAlign: TextAlign.center),
          TextButton(onPressed: () => _load(), child: const Text('重试')),
        ]),
      );
    }
    if (_data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final pages = _data!.pages;
    if (pages.isEmpty) {
      return const Center(child: Text('管理员还没设置地图'));
    }
    final idx = _pageIdx.clamp(0, pages.length - 1);
    final page = pages[idx];
    return Column(
      children: [
        SizedBox(
          height: 46,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: pages.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (c, i) => Center(
              child: ChoiceChip(
                label: Text(pages[i].name),
                selected: i == idx,
                onSelected: (_) => setState(() => _pageIdx = i),
              ),
            ),
          ),
        ),
        Expanded(
          child: page.imagePath == null
              ? const Center(child: Text('这个城区还没有地图图片'))
              : HotspotMap(
                  page: page,
                  settings: _data!.settings,
                  onTapTower: widget.onTapTower,
                ),
        ),
      ],
    );
  }
}

/// One zone's map image with circular hotspot buttons.
class HotspotMap extends StatefulWidget {
  final PageData page;
  final HotspotSettings settings;
  final void Function(int towerId) onTapTower;
  const HotspotMap({
    super.key,
    required this.page,
    required this.settings,
    required this.onTapTower,
  });
  @override
  State<HotspotMap> createState() => _HotspotMapState();
}

class _HotspotMapState extends State<HotspotMap> {
  double? _aspect;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant HotspotMap old) {
    super.didUpdateWidget(old);
    if (old.page.imagePath != widget.page.imagePath) {
      _aspect = null;
      _resolve();
    }
  }

  void _resolve() {
    final src = widget.page.imagePath;
    if (src == null) return;
    final stream =
        NetworkImage(src).resolve(const ImageConfiguration());
    late final ImageStreamListener l;
    l = ImageStreamListener((info, _) {
      if (mounted) {
        setState(() => _aspect = info.image.width / info.image.height);
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
      return const Center(child: CircularProgressIndicator());
    }
    final s = widget.settings;
    final offsetX = widget.page.offsetXPct;
    final scaleX = widget.page.scaleX;
    final spots = widget.page.hotspots.where((h) => !h.hidden).toList();

    return LayoutBuilder(
      builder: (ctx, c) {
        // Always size the map to FILL THE AVAILABLE HEIGHT and keep its native
        // aspect ratio. We never scale it to the (narrow) viewport width, so a
        // wide zone map is never squashed/distorted on a portrait screen — it
        // simply overflows horizontally and the user pans left-right.
        final vw = c.maxWidth;
        final h = c.maxHeight;
        final w = h * _aspect!;
        final d = s.outerPct / 100.0 * w;
        final innerD = (s.innerPct / s.outerPct) * d;
        final map = SizedBox(
          width: w,
          height: h,
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.network(src,
                    fit: BoxFit.fill,
                    errorBuilder: (a, b, cc) =>
                        const Center(child: Text('地图加载失败'))),
              ),
              ...spots.map((hp) {
                final leftPct = 50 + (hp.xPct - 50) * scaleX + offsetX;
                final cx = leftPct / 100.0 * w;
                final cy = hp.yPct / 100.0 * h;
                final Color ring = hp.locked
                    ? const Color(0xFFDC2626)
                    : hp.hasContent
                        ? const Color(0xFF10B981)
                        : const Color(0xFFF59E0B);
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
                        color: ring.withOpacity(hp.locked ? 0.55 : 0.45),
                        border: Border.all(
                            color: ring, width: hp.locked ? 3 : 1.5),
                        boxShadow: hp.locked
                            ? [
                                BoxShadow(
                                    color: const Color(0xFFDC2626)
                                        .withOpacity(0.7),
                                    blurRadius: d * 0.18,
                                    spreadRadius: d * 0.02),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: Container(
                          width: innerD,
                          height: innerD,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: hp.locked
                                ? const Color(0xCC7F1D1D)
                                : const Color(0xCC000000),
                          ),
                          alignment: Alignment.center,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              // Locked = "in battle": show the 🔥⚔ icon like
                              // the website (it hides the number when locked).
                              child: hp.locked
                                  ? const Text('🔥',
                                      style: TextStyle(height: 1))
                                  : Text('${hp.towerId}',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
        // Pan freely (horizontal drag reveals the rest of a wide map) and keep
        // pinch-zoom. constrained:false → the map keeps its own w×h instead of
        // being shrunk to the viewport, so it never distorts.
        return InteractiveViewer(
          constrained: false,
          minScale: 1,
          maxScale: 4,
          boundaryMargin: EdgeInsets.symmetric(
              horizontal: (vw > w ? (vw - w) / 2 : 0.0) + 12.0,
              vertical: 12.0),
          child: map,
        );
      },
    );
  }
}
