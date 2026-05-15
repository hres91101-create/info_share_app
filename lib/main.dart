import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'services/prefs.dart';
import 'services/api.dart';
import 'screens/tower_list_screen.dart';

void main() {
  runApp(const InfoShareApp());
}

/// Separate entry point rendered INSIDE the Android system overlay window.
/// Must be top-level and annotated so the engine can find it.
@pragma('vm:entry-point')
void overlayMain() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: _OverlayBubble(),
  ));
}

class InfoShareApp extends StatelessWidget {
  const InfoShareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '防御塔攻略',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1E2A47),
      ),
      home: const _Gate(),
    );
  }
}

/// Ensures a display name exists before entering the app.
class _Gate extends StatefulWidget {
  const _Gate();
  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  String? _name;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final n = await Prefs.getName();
    setState(() {
      _name = n;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }
    if (_name == null) {
      return _NameSetup(onDone: (n) => setState(() => _name = n));
    }
    return _HomeWithBubble(name: _name!);
  }
}

class _NameSetup extends StatefulWidget {
  final void Function(String) onDone;
  const _NameSetup({required this.onDone});
  @override
  State<_NameSetup> createState() => _NameSetupState();
}

class _NameSetupState extends State<_NameSetup> {
  late final TextEditingController _ctrl =
      TextEditingController(text: Prefs.randomName());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设定名字')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('系统给你一个随机名字，可改成你自己的。'),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              maxLength: 50,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(), labelText: '你的名字'),
            ),
            const SizedBox(height: 8),
            Row(children: [
              OutlinedButton(
                onPressed: () =>
                    setState(() => _ctrl.text = Prefs.randomName()),
                child: const Text('换一个'),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: () async {
                  final n = _ctrl.text.trim();
                  if (n.isEmpty) return;
                  await Prefs.setName(n);
                  widget.onDone(n);
                },
                child: const Text('保存'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Home = tower list, with an in-app draggable floating button on top.
/// On Android this same button can spawn a true system overlay that
/// floats over OTHER apps. On iOS the system overlay is impossible, so
/// the floating button only lives inside this app.
class _HomeWithBubble extends StatefulWidget {
  final String name;
  const _HomeWithBubble({required this.name});
  @override
  State<_HomeWithBubble> createState() => _HomeWithBubbleState();
}

class _HomeWithBubbleState extends State<_HomeWithBubble> {
  Offset _pos = const Offset(20, 120);

  Future<void> _enableSystemOverlay() async {
    final granted = await FlutterOverlayWindow.isPermissionGranted();
    if (!granted) {
      final ok = await FlutterOverlayWindow.requestPermission();
      if (ok != true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('需要「显示在其他应用上层」权限')));
        return;
      }
    }
    await FlutterOverlayWindow.showOverlay(
      enableDrag: true,
      overlayTitle: '防御塔攻略',
      overlayContent: '点击展开',
      flag: OverlayFlag.defaultFlag,
      height: 180,
      width: 180,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('悬浮按钮已开启，可切到其他 app')));
  }

  @override
  Widget build(BuildContext context) {
    final isAndroid = Platform.isAndroid;
    return Stack(
      children: [
        TowerListScreen(name: widget.name),
        Positioned(
          left: _pos.dx,
          top: _pos.dy,
          child: GestureDetector(
            onPanUpdate: (d) => setState(() => _pos += d.delta),
            onTap: () {
              showModalBottomSheet(
                context: context,
                builder: (_) => _QuickPanel(
                  name: widget.name,
                  isAndroid: isAndroid,
                  onEnableSystemOverlay: _enableSystemOverlay,
                ),
              );
            },
            child: const _Bubble(),
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFF1E2A47),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: const Icon(Icons.shield, color: Colors.white),
    );
  }
}

class _QuickPanel extends StatelessWidget {
  final String name;
  final bool isAndroid;
  final Future<void> Function() onEnableSystemOverlay;
  const _QuickPanel({
    required this.name,
    required this.isAndroid,
    required this.onEnableSystemOverlay,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('快捷面板 · $name',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            FutureBuilder(
              future: Api.fetchTowers(),
              builder: (ctx, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final locked = (snap.data as List<Tower>)
                    .where((t) => t.locked)
                    .toList();
                if (locked.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('目前没有塔被锁定'),
                  );
                }
                return Column(
                  children: locked
                      .map((t) => ListTile(
                            dense: true,
                            leading: const Text('🔥'),
                            title: Text('塔 ${t.id}'),
                            subtitle: Text('${t.lockBy} 进攻中'),
                          ))
                      .toList(),
                );
              },
            ),
            if (isAndroid) ...[
              const Divider(),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  onEnableSystemOverlay();
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('开启系统悬浮按钮（浮在其他 app 上）'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Content shown inside the Android system overlay window.
class _OverlayBubble extends StatelessWidget {
  const _OverlayBubble();
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: () async {
          // Tapping the system bubble pops a tiny live summary in-overlay.
          await FlutterOverlayWindow.shareData('open');
        },
        child: Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: Color(0xFF1E2A47),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.shield, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
