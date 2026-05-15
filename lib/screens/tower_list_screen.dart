import 'package:flutter/material.dart';
import '../services/api.dart';
import 'tower_detail_screen.dart';

class TowerListScreen extends StatefulWidget {
  final String name;
  const TowerListScreen({super.key, required this.name});

  @override
  State<TowerListScreen> createState() => _TowerListScreenState();
}

class _TowerListScreenState extends State<TowerListScreen> {
  late Future<List<Tower>> _future;

  @override
  void initState() {
    super.initState();
    _future = Api.fetchTowers();
  }

  Future<void> _refresh() async {
    setState(() => _future = Api.fetchTowers());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('防御塔攻略'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(widget.name,
                  style: const TextStyle(fontSize: 13, color: Colors.white70)),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Tower>>(
          future: _future,
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(children: [
                const SizedBox(height: 120),
                Center(child: Text('读取失败：${snap.error}')),
                const SizedBox(height: 12),
                Center(
                  child: ElevatedButton(
                    onPressed: _refresh,
                    child: const Text('重试'),
                  ),
                ),
              ]);
            }
            final towers =
                (snap.data ?? []).where((t) => !t.hidden).toList()
                  ..sort((a, b) => a.id.compareTo(b.id));
            if (towers.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 120),
                Center(child: Text('暂无塔')),
              ]);
            }
            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate:
                  const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisExtent: 92,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: towers.length,
              itemBuilder: (ctx, i) => _TowerCard(
                tower: towers[i],
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TowerDetailScreen(
                        towerId: towers[i].id,
                        name: widget.name,
                      ),
                    ),
                  );
                  _refresh();
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TowerCard extends StatelessWidget {
  final Tower tower;
  final VoidCallback onTap;
  const _TowerCard({required this.tower, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final locked = tower.locked;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: locked ? const Color(0xFFFEF2F2) : Colors.white,
          border: Border.all(
              color: locked
                  ? const Color(0xFFFCA5A5)
                  : const Color(0xFFE5E7EB)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              tower.name != null && tower.name!.isNotEmpty
                  ? '${tower.id}. ${tower.name}'
                  : '塔 ${tower.id}',
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: Color(0xFF1F2937)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                if (tower.noteCount > 0)
                  _chip('笔记 ${tower.noteCount}', const Color(0xFFDBEAFE),
                      const Color(0xFF1E40AF)),
                if (tower.imageCount > 0)
                  _chip('图 ${tower.imageCount}', const Color(0xFFD1FAE5),
                      const Color(0xFF065F46)),
                if (locked)
                  _chip('战斗中', const Color(0xFFDC2626), Colors.white),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(text,
            style: TextStyle(
                fontSize: 11, color: fg, fontWeight: FontWeight.w600)),
      );
}
