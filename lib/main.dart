import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:ota_update/ota_update.dart';
import 'services/prefs.dart';
import 'services/updater.dart';
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

  bool _updateChecked = false;

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

  Future<void> _maybePromptUpdate() async {
    if (_updateChecked) return;
    _updateChecked = true;
    if (!Platform.isAndroid) return; // ota apk install is Android-only
    final info = await Updater.check();
    if (info == null || !mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('发现新版本 ${info.version}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('当前版本 ${info.current}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
              if (info.notes.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(info.notes),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('稍后')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => _UpdateProgressDialog(url: info.apkUrl),
              );
            },
            child: const Text('立即更新'),
          ),
        ],
      ),
    );
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePromptUpdate());
    return _HomeWithBubble(name: _name!);
  }
}

class _UpdateProgressDialog extends StatefulWidget {
  final String url;
  const _UpdateProgressDialog({required this.url});
  @override
  State<_UpdateProgressDialog> createState() => _UpdateProgressDialogState();
}

class _UpdateProgressDialogState extends State<_UpdateProgressDialog> {
  String _status = '准备下载...';
  double? _progress;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    try {
      OtaUpdate()
          .execute(widget.url, destinationFilename: 'info_share_app.apk')
          .listen(
        (OtaEvent e) {
          setState(() {
            switch (e.status) {
              case OtaStatus.DOWNLOADING:
                final p = double.tryParse(e.value ?? '');
                _progress = p != null ? p / 100.0 : null;
                _status = '下载中 ${e.value ?? ''}%';
                break;
              case OtaStatus.INSTALLING:
                _progress = null;
                _status = '准备安装，请在系统弹窗点「安装」';
                break;
              case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
                _failed = true;
                _status = '缺少安装权限：请允许本应用「安装未知应用」后重试';
                break;
              default:
                _failed = true;
                _status = '更新失败：${e.status} ${e.value ?? ''}';
            }
          });
        },
        onError: (e) {
          setState(() {
            _failed = true;
            _status = '更新失败：$e';
          });
        },
      );
    } catch (e) {
      setState(() {
        _failed = true;
        _status = '无法启动更新：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('更新'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(value: _progress),
          const SizedBox(height: 12),
          Text(_status, textAlign: TextAlign.center),
        ],
      ),
      actions: [
        if (_failed)
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭')),
      ],
    );
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

/// Home = tower list.
/// Android: the floating bubble is a real SYSTEM overlay. It auto-starts on
/// launch when permission is granted; if not, a prominent banner offers a
/// one-tap path to grant it. The user never has to manually "start" it.
/// iOS: system overlay is impossible, so an in-app draggable bubble is shown.
class _HomeWithBubble extends StatefulWidget {
  final String name;
  const _HomeWithBubble({required this.name});
  @override
  State<_HomeWithBubble> createState() => _HomeWithBubbleState();
}

class _HomeWithBubbleState extends State<_HomeWithBubble>
    with WidgetsBindingObserver {
  Offset _pos = const Offset(20, 120); // iOS in-app bubble only
  bool _checking = true;
  bool _granted = false;
  bool _active = false;

  bool get _isAndroid => Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _syncOverlay());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from the system permission screen → re-check & auto-start.
    if (state == AppLifecycleState.resumed) _syncOverlay();
  }

  Future<void> _startOverlay() async {
    try {
      await FlutterOverlayWindow.showOverlay(
        enableDrag: true,
        positionGravity: PositionGravity.auto, // snap to nearest side edge
        overlayTitle: '防御塔攻略',
        overlayContent: '点击看最新图文',
        flag: OverlayFlag.defaultFlag,
        height: 60,
        width: 60,
      );
    } catch (_) {}
  }

  Future<void> _syncOverlay() async {
    if (!_isAndroid) {
      if (mounted) setState(() => _checking = false);
      return;
    }
    final granted = await FlutterOverlayWindow.isPermissionGranted();
    bool active = false;
    try {
      active = await FlutterOverlayWindow.isActive();
    } catch (_) {}
    if (granted && !active) {
      await _startOverlay();
      active = true;
    }
    if (!mounted) return;
    setState(() {
      _granted = granted;
      _active = active;
      _checking = false;
    });
  }

  Future<void> _requestPermission() async {
    await FlutterOverlayWindow.requestPermission();
    // The toggle happens on a system screen; the real result is picked up
    // by didChangeAppLifecycleState(resumed) → _syncOverlay().
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        TowerListScreen(name: widget.name),

        // Android: permission gate banner (only when not granted)
        if (_isAndroid && !_checking && !_granted)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Material(
              color: const Color(0xFF7C3AED),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: Row(children: [
                    const Icon(Icons.bubble_chart, color: Colors.white),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        '悬浮球需要「显示在其他应用上层」权限才能用',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF7C3AED),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onPressed: _requestPermission,
                      child: const Text('立即开启'),
                    ),
                  ]),
                ),
              ),
            ),
          ),

        // iOS: in-app draggable bubble (no system overlay possible)
        if (!_isAndroid)
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
                    isAndroid: false,
                    onEnableSystemOverlay: () async {},
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

/// Android system-overlay chat head.
/// Dragging + edge-snap is handled natively by the plugin
/// (enableDrag:true + PositionGravity.auto) — the standard Messenger-style
/// behaviour (drag freely, release → snaps to nearest left/right edge).
/// Tap → the overlay window resizes to full screen so the panel is big and
/// crisp; collapse → back to a small draggable bubble.
class _OverlayBubble extends StatefulWidget {
  const _OverlayBubble();
  @override
  State<_OverlayBubble> createState() => _OverlayBubbleState();
}

class _OverlayBubbleState extends State<_OverlayBubble>
    with WidgetsBindingObserver {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // Rotation: keep the expanded panel filling the (new) screen size.
    if (_expanded) {
      FlutterOverlayWindow.resizeOverlay(
          WindowSize.matchParent, WindowSize.matchParent, false);
    }
  }

  Future<void> _expand() async {
    setState(() => _expanded = true);
    await FlutterOverlayWindow.resizeOverlay(
        WindowSize.matchParent, WindowSize.matchParent, false);
  }

  Future<void> _collapse() async {
    setState(() => _expanded = false);
    // back to a small, still-draggable bubble (native drag + auto edge snap)
    await FlutterOverlayWindow.resizeOverlay(60, 60, true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_expanded) {
      // Native drag moves the window; we only need a tap target here.
      return Material(
        color: Colors.transparent,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
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

    // Full-screen window → MediaQuery == real screen. Use almost the whole
    // screen so images/text are as large and clear as possible.
    final mq = MediaQuery.of(context);
    final landscape = mq.size.width > mq.size.height;
    final cardW = mq.size.width * (landscape ? 0.82 : 0.98);
    final cardH = mq.size.height * 0.92;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _collapse,
              child: Container(color: Colors.black54),
            ),
          ),
          Center(
            child: SizedBox(
              width: cardW,
              height: cardH,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 18,
                        offset: const Offset(0, 6)),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Container(
                      color: const Color(0xFF1E2A47),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Row(children: [
                        const Icon(Icons.shield,
                            color: Colors.white, size: 16),
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
                            child: Icon(Icons.remove,
                                color: Colors.white, size: 20),
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => FlutterOverlayWindow.closeOverlay(),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.close,
                                color: Colors.white, size: 20),
                          ),
                        ),
                      ]),
                    ),
                    const Expanded(child: RecentFeed(compact: true)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
