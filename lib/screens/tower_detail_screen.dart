import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api.dart';

class TowerDetailScreen extends StatefulWidget {
  final int towerId;
  final String name;
  const TowerDetailScreen(
      {super.key, required this.towerId, required this.name});

  @override
  State<TowerDetailScreen> createState() => _TowerDetailScreenState();
}

class _TowerDetailScreenState extends State<TowerDetailScreen> {
  late Future<TowerDetail> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = Api.fetchTowerDetail(widget.towerId);
  }

  void _reload() {
    setState(() => _future = Api.fetchTowerDetail(widget.towerId));
  }

  Future<void> _runAction(Future<void> Function() fn, String okMsg) async {
    setState(() => _busy = true);
    try {
      await fn();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(okMsg)));
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _writeNote() async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('写笔记'),
        content: TextField(
          controller: ctrl,
          maxLines: 5,
          maxLength: 4000,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入攻略信息...'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('送出')),
        ],
      ),
    );
    if (text == null || text.isEmpty) return;
    await _runAction(
        () => Api.postNote(widget.towerId, widget.name, text), '已送出');
  }

  Future<void> _uploadImages() async {
    final List<XFile> picked =
        await ImagePicker().pickMultiImage(imageQuality: 85);
    if (picked.isEmpty) return;
    await _runAction(
      () => Api.uploadImages(
          widget.towerId, widget.name, picked.map((x) => x.path).toList()),
      '已上传 ${picked.length} 张图片',
    );
  }

  String _fmt(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('塔 ${widget.towerId}')),
      body: FutureBuilder<TowerDetail>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('读取失败：${snap.error}'));
          }
          final d = snap.data!;
          final feed = <_FeedEntry>[
            ...d.notes.map((n) => _FeedEntry(
                n.createdAt, n.author, '笔记', n.content, null)),
            ...d.images.map((im) => _FeedEntry(
                im.createdAt, im.author, '图', im.caption, im.filePath)),
          ]..sort((a, b) => a.at.compareTo(b.at));

          return Column(
            children: [
              if (d.locked)
                Container(
                  width: double.infinity,
                  color: const Color(0xFFFEE2E2),
                  padding: const EdgeInsets.all(10),
                  child: Text('🔥 ${d.lockBy} 进攻中',
                      style: const TextStyle(
                          color: Color(0xFF991B1B),
                          fontWeight: FontWeight.w600)),
                ),
              Expanded(
                child: feed.isEmpty
                    ? const Center(child: Text('尚无留言或图片'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: feed.length,
                        itemBuilder: (c, i) {
                          final e = feed[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Text(_fmt(e.at),
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey)),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                          color: e.kind == '笔记'
                                              ? const Color(0xFFDBEAFE)
                                              : const Color(0xFFD1FAE5),
                                          borderRadius:
                                              BorderRadius.circular(4)),
                                      child: Text(e.kind,
                                          style:
                                              const TextStyle(fontSize: 11)),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(e.author,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                  ]),
                                  const SizedBox(height: 8),
                                  if (e.imageUrl != null)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(e.imageUrl!,
                                          fit: BoxFit.contain),
                                    ),
                                  if (e.text != null && e.text!.isNotEmpty)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(top: 6),
                                      child: Text(e.text!),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _busy ? null : _writeNote,
                            icon: const Icon(Icons.edit),
                            label: const Text('写笔记'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF7C3AED)),
                            onPressed: _busy ? null : _uploadImages,
                            icon: const Icon(Icons.add_photo_alternate),
                            label: const Text('上传图片'),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: d.locked
                            ? OutlinedButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => _runAction(
                                        () => Api.unlockTower(
                                            widget.towerId, widget.name),
                                        '已解锁'),
                                icon: const Icon(Icons.lock_open),
                                label: const Text('解锁'),
                              )
                            : ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        const Color(0xFFDC2626)),
                                onPressed: _busy
                                    ? null
                                    : () => _runAction(
                                        () => Api.lockTower(
                                            widget.towerId, widget.name),
                                        '已锁定（30 分钟）'),
                                icon:
                                    const Icon(Icons.local_fire_department),
                                label: const Text('进攻锁定'),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FeedEntry {
  final int at;
  final String author;
  final String kind;
  final String? text;
  final String? imageUrl;
  _FeedEntry(this.at, this.author, this.kind, this.text, this.imageUrl);
}
