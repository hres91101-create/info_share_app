import 'dart:io' show Platform;
import 'dart:ui' as ui;
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
      enableDrag: false, // we do our own drag + edge-snap inside the overlay
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

/// Android system-overlay chat head (Messenger-style):
/// - collapsed: small bubble, custom drag that glides + snaps to the nearest
///   screen edge, never stuck off-screen
/// - expanded: the overlay window becomes full-screen so the panel lays out
///   responsively (portrait/landscape) and is never clipped in a corner
class _OverlayBubble extends StatefulWidget {
  const _OverlayBubble();
  @override
  State<_OverlayBubble> createState() => _OverlayBubbleState();
}

class _OverlayBubbleState extends State<_OverlayBubble>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  bool _expanded = false;

  // Bubble window position in physical pixels (raw window-manager coords).
  double _bx = 0;
  double _by = 0;
  bool _posInited = false;

  late final AnimationController _snap = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPos();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _snap.dispose();
    super.dispose();
  }

  ui.FlutterView get _view =>
      WidgetsBinding.instance.platformDispatcher.views.first;
  double get _dpr => _view.devicePixelRatio;
  Size get _screenPx => _view.physicalSize;
  double get _bubblePx => 64 * _dpr;

  Future<void> _initPos() async {
    try {
      final p = await FlutterOverlayWindow.getOverlayPosition();
      _bx = (p.x ?? 0).toDouble();
      _by = (p.y ?? 0).toDouble();
    } catch (_) {
      _bx = _screenPx.width - _bubblePx;
      _by = _screenPx.height * 0.35;
    }
    _posInited = true;
  }

  @override
  void didChangeMetrics() {
    // Rotation / screen size change: keep full-screen panel correct,
    // and keep the collapsed bubble on-screen.
    if (_expanded) {
      FlutterOverlayWindow.resizeOverlay(
          WindowSize.matchParent, WindowSize.matchParent, false);
    } else if (_posInited) {
      _clampPos();
      FlutterOverlayWindow.moveOverlay(OverlayPosition(_bx, _by));
    }
  }

  void _clampPos() {
    final s = _screenPx;
    _bx = _bx.clamp(0.0, (s.width - _bubblePx).clamp(0.0, s.width));
    _by = _by.clamp(0.0, (s.height - _bubblePx).clamp(0.0, s.height));
  }

  Future<void> _expand() async {
    setState(() => _expanded = true);
    await FlutterOverlayWindow.resizeOverlay(
        WindowSize.matchParent, WindowSize.matchParent, false);
  }

  Future<void> _collapse() async {
    setState(() => _expanded = false);
    await FlutterOverlayWindow.resizeOverlay(64, 64, false);
    _clampPos();
    await FlutterOverlayWindow.moveOverlay(OverlayPosition(_bx, _by));
    _snapToEdge();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_snap.isAnimating) _snap.stop();
    _bx += d.delta.dx * _dpr;
    _by += d.delta.dy * _dpr;
    _clampPos();
    FlutterOverlayWindow.moveOverlay(OverlayPosition(_bx, _by));
  }

  void _snapToEdge() {
    final s = _screenPx;
    final centerX = _bx + _bubblePx / 2;
    final targetX = centerX < s.width / 2 ? 0.0 : s.width - _bubblePx;
    final fromX = _bx;
    final fromY = _by;
    final targetY = fromY.clamp(0.0, (s.height - _bubblePx).clamp(0.0, s.height));
    final anim = CurvedAnimation(parent: _snap, curve: Curves.easeOutCubic);
    void tick() {
      final t = anim.value;
      _bx = fromX + (targetX - fromX) * t;
      _by = fromY + (targetY - fromY) * t;
      FlutterOverlayWindow.moveOverlay(OverlayPosition(_bx, _by));
    }

    _snap
      ..removeListener(tick)
      ..reset()
      ..addListener(tick);
    _snap.forward();
  }

  @override
  Widget build(BuildContext context) {
    if (!_expanded) {
      return Material(
        color: Colors.transparent,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _expand,
          onPanUpdate: _onDragUpdate,
          onPanEnd: (_) => _snapToEdge(),
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

    // Full-screen window now → MediaQuery == real screen, lay out responsively.
    final mq = MediaQuery.of(context);
    final landscape = mq.size.width > mq.size.height;
    final cardW = (mq.size.width * (landscape ? 0.62 : 0.94))
        .clamp(280.0, 560.0);
    final cardH = mq.size.height * (landscape ? 0.88 : 0.7);

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
              width: cardW.toDouble(),
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
                          horizontal: 12, vertical: 8),
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
                                color: Colors.white, size: 18),
                          ),
                        ),
                        InkWell(
                          onTap: () => FlutterOverlayWindow.closeOverlay(),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.close,
                                color: Colors.white, size: 18),
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
