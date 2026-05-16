import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'services/prefs.dart';
import 'screens/tower_list_screen.dart';
import 'widgets/recent_feed.dart';

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
      overlayContent: '点击展开看最新图文',
      flag: OverlayFlag.defaultFlag,
      height: 64,
      width: 64,
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

/// In-app expandable panel (iOS uses this since system overlay is impossible).
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
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Row(children: [
                const Icon(Icons.shield, size: 18),
                const SizedBox(width: 6),
                Text('最新动态 · $name',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ]),
            ),
            const Expanded(child: RecentFeed(compact: true)),
            if (isAndroid)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      onEnableSystemOverlay();
                    },
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('开启悬浮球（浮在其他 app 上）'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Android system-overlay chat head: collapsed bubble that expands into a
/// panel showing the latest site images + text, then collapses back.
/// The overlay window itself is resized between the two states.
class _OverlayBubble extends StatefulWidget {
  const _OverlayBubble();
  @override
  State<_OverlayBubble> createState() => _OverlayBubbleState();
}

class _OverlayBubbleState extends State<_OverlayBubble> {
  bool _expanded = false;

  Future<void> _expand() async {
    setState(() => _expanded = true);
    await FlutterOverlayWindow.resizeOverlay(330, 480, false);
  }

  Future<void> _collapse() async {
    setState(() => _expanded = false);
    await FlutterOverlayWindow.resizeOverlay(64, 64, true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_expanded) {
      return Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: _expand,
          child: Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFF1E2A47),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2)),
                ],
              ),
              child: const Icon(Icons.shield, color: Colors.white),
            ),
          ),
        ),
      );
    }
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 14,
                offset: const Offset(0, 4)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              color: const Color(0xFF1E2A47),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                const Icon(Icons.shield, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('最新动态',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold)),
                ),
                InkWell(
                  onTap: _collapse,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.remove, color: Colors.white, size: 18),
                  ),
                ),
                InkWell(
                  onTap: () => FlutterOverlayWindow.closeOverlay(),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, color: Colors.white, size: 18),
                  ),
                ),
              ]),
            ),
            const Expanded(child: RecentFeed(compact: true)),
          ],
        ),
      ),
    );
  }
}
