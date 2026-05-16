import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api.dart';

/// Read-only "what's new across the site" list: images + text, newest first.
/// Used both by the in-app panel and the Android system-overlay panel.
class RecentFeed extends StatefulWidget {
  final bool compact;
  const RecentFeed({super.key, this.compact = false});

  @override
  State<RecentFeed> createState() => _RecentFeedState();
}

class _RecentFeedState extends State<RecentFeed> {
  List<RecentItem>? _items;
  Object? _err;
  Timer? _timer;

  int get _limit => widget.compact ? 20 : 40;

  @override
  void initState() {
    super.initState();
    _load();
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
      final r = await Api.fetchRecent(limit: _limit);
      if (!mounted) return;
      setState(() {
        _items = r;
        _err = null;
      });
    } catch (e) {
      if (!mounted || silent) return;
      setState(() => _err = e);
    }
  }

  void reload() => _load();

  String _fmt(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  /// Tap an image → fill the whole current window, pinch/drag to zoom,
  /// tap anywhere to close. Works in the system overlay (full-screen when
  /// expanded) and the in-app panel alike.
  void _openImage(BuildContext context, String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.of(ctx).pop(),
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: Image.network(url, fit: BoxFit.contain,
                      errorBuilder: (c, e, s) => const Text('（图片加载失败）',
                          style: TextStyle(color: Colors.white))),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: SafeArea(
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_items == null && _err != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('读取失败：$_err', textAlign: TextAlign.center),
            TextButton(onPressed: reload, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_items == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final items = _items!;
    if (items.isEmpty) {
      return const Center(child: Text('暂无最新动态'));
    }
    return RefreshIndicator(
      onRefresh: () async => reload(),
      child: ListView.separated(
        padding: const EdgeInsets.all(10),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (c, i) {
          final it = items[i];
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
                      Text('塔 ${it.towerId}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: it.isImage
                              ? const Color(0xFFD1FAE5)
                              : const Color(0xFFDBEAFE),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(it.isImage ? '图' : '笔记',
                            style: const TextStyle(fontSize: 10)),
                      ),
                      const Spacer(),
                      Text(_fmt(it.createdAt),
                          style: const TextStyle(
                              fontSize: 10, color: Colors.grey)),
                    ]),
                    const SizedBox(height: 4),
                    Text(it.author,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF374151))),
                    if (it.isImage && it.filePath != null) ...[
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: () => _openImage(context, it.filePath!),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            it.filePath!,
                            fit: BoxFit.contain,
                            loadingBuilder: (c, w, p) => p == null
                                ? w
                                : const SizedBox(
                                    height: 80,
                                    child: Center(
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2))),
                            errorBuilder: (c, e, s) =>
                                const Text('（图片加载失败）'),
                          ),
                        ),
                      ),
                    ],
                    if (it.text != null && it.text!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(it.text!,
                          style: const TextStyle(fontSize: 13)),
                    ],
                  ],
                ),
              );
            },
          ),
        );
  }
}
