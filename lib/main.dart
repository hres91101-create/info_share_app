import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' show min;
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services/prefs.dart';
import 'services/updater.dart';
import 'services/diag.dart';
import 'screens/tower_detail_screen.dart';
import 'widgets/overlay_browser.dart';
import 'widgets/zone_map.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Diag.init();
    Diag.log('boot', 'app start'); // first thing — fires even if we crash next
    FlutterError.onError = (d) {
      FlutterError.presentError(d);
      Diag.log('flutter_error', d.exceptionAsString());
    };
    runApp(const InfoShareApp());
  }, (e, st) {
    Diag.log('zone_error', '$e\n$st');
  });
}

/// Separate entry point rendered INSIDE the Android system overlay window.
/// Must be top-level and annotated so the engine can find it.
@pragma('vm:entry-point')
void overlayMain() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Diag.init();
    Diag.log('overlay_main', 'overlay engine start');
    runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _OverlayBubble(),
    ));
  }, (e, st) {
    Diag.log('overlay_zone_error', '$e\n$st');
  });
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

class _GateState extends State<_Gate> with WidgetsBindingObserver {
  String? _name;
  bool _loading = true;

  bool _checking = false;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check whenever the app comes back to the foreground, not only on a
    // cold start — "关掉再重开" often just resumes the existing process.
    if (state == AppLifecycleState.resumed) _maybePromptUpdate();
  }

  Future<void> _load() async {
    final n = await Prefs.getName();
    setState(() {
      _name = n;
      _loading = false;
    });
  }

  Future<void> _maybePromptUpdate() async {
    if (!Platform.isAndroid) return; // ota apk install is Android-only
    if (_checking || _dialogOpen || _name == null || !mounted) return;
    _checking = true;
    final info = await Updater.check();
    _checking = false;
    if (info == null || !mounted || _dialogOpen) return;
    _dialogOpen = true;
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
              const SizedBox(height: 8),
              const Text(
                '点「下载新版」→ 浏览器下载完成后，点通知栏那个 APK 文件即可安装'
                '（首次会要求允许「安装未知应用」）。',
                style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
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
            onPressed: () async {
              Navigator.pop(ctx);
              // Most reliable path: let the system browser/Download Manager
              // fetch the APK, then the user taps the downloaded file to
              // install. No in-app native installer (that was crashing at
              // 100%).
              final ok = await launchUrl(
                Uri.parse(info.apkUrl),
                mode: LaunchMode.externalApplication,
              );
              if (!ok && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('无法打开下载，请手动到 GitHub Releases 下载')));
              }
            },
            child: const Text('下载新版'),
          ),
        ],
      ),
    );
    _dialogOpen = false;
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
    Diag.log('overlay', 'start requested');
    try {
      // Re-showing too soon after a close spawns a half-initialised overlay
      // (the "empty toast, no bubble/functions" bug). Tear any old one down
      // fully and let the plugin's engine settle before re-creating.
      bool active = false;
      try {
        active = await FlutterOverlayWindow.isActive();
      } catch (_) {}
      if (active) {
        await FlutterOverlayWindow.closeOverlay();
        await Future<void>.delayed(const Duration(milliseconds: 600));
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      await FlutterOverlayWindow.showOverlay(
        enableDrag: true,
        alignment: OverlayAlignment.centerRight,
        // none = plugin does NOT auto-reposition; it only follows the finger
        // (enableDrag). We do our own 4-edge snap in Dart (see
        // _OverlayBubbleState: poll position, on release glide to the nearest
        // safe edge). auto/left/right would fight our snap.
        positionGravity: PositionGravity.none,
        overlayTitle: '防御塔攻略',
        overlayContent: '点击看最新图文',
        flag: OverlayFlag.defaultFlag,
        height: 60,
        width: 60,
      );
      Diag.log('overlay', 'showOverlay ok');
    } catch (e) {
      Diag.log('overlay_error', '$e');
    }
  }

  Future<void> _syncOverlay() async {
    if (!_isAndroid) {
      if (mounted) setState(() => _checking = false);
      return;
    }
    // IMPORTANT: never auto-start the overlay on launch/resume. Overlay +
    // foreground-service behaviour varies wildly per OEM (Samsung/Huawei/
    // Xiaomi…) and a failure there must NOT stop the core app from opening.
    // The overlay only starts when the user explicitly taps the button.
    bool granted = false, active = false;
    try {
      granted = await FlutterOverlayWindow.isPermissionGranted();
    } catch (_) {}
    try {
      active = await FlutterOverlayWindow.isActive();
    } catch (_) {}
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

  /// Kill the overlay entirely, even if the bubble is unreachable off-screen.
  Future<void> _closeOverlay() async {
    try {
      await FlutterOverlayWindow.closeOverlay();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _active = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('悬浮球已关闭')));
  }

  Future<void> _enableOverlay() async {
    await _startOverlay();
    if (!mounted) return;
    bool active = false;
    try {
      active = await FlutterOverlayWindow.isActive();
    } catch (_) {}
    setState(() => _active = active);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(active ? '悬浮球已开启' : '悬浮球开启失败（此设备可能不支持）')));
  }

  /// Recover a bubble that got dragged off-screen / lost: tear it down and
  /// re-create it at the plugin's default on-screen position.
  Future<void> _resetOverlay() async {
    // _startOverlay already closes any old overlay + waits for the engine to
    // settle before re-creating, so the re-placed bubble keeps its content.
    await _startOverlay();
    if (!mounted) return;
    setState(() => _active = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('悬浮球已重新放置到屏幕内')));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _MapHome(name: widget.name),

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

        // Android: bubble controls (start when off; recover/close when on).
        // Overlay is opt-in — the app works fully without it on any OEM.
        if (_isAndroid && !_checking && _granted)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: _active
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                                backgroundColor: Colors.white),
                            onPressed: _closeOverlay,
                            icon:
                                const Icon(Icons.cancel_outlined, size: 18),
                            label: const Text('关闭悬浮球'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                                backgroundColor: Colors.white),
                            onPressed: _resetOverlay,
                            icon: const Icon(Icons.my_location, size: 18),
                            label: const Text('重新放置'),
                          ),
                        ],
                      )
                    : SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E2A47),
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: _enableOverlay,
                          icon: const Icon(Icons.bubble_chart),
                          label: const Text('开启悬浮球（浮在其他 app 上）'),
                        ),
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

/// Main-app home: the SAME 3-zone map + hotspots as the overlay, but tapping
/// a tower opens the full TowerDetailScreen (write note / lock / unlock).
class _MapHome extends StatelessWidget {
  final String name;
  const _MapHome({required this.name});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('防御塔攻略'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(name,
                  style: const TextStyle(
                      fontSize: 13, color: Colors.white70)),
            ),
          ),
        ],
      ),
      body: ZoneMapView(
        onTapTower: (id) => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TowerDetailScreen(towerId: id, name: name),
          ),
        ),
      ),
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
            const Expanded(child: OverlayBrowser()),
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
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  // --- 4-edge snap (Dart-side; plugin only follows the finger) ---
  Timer? _poll;
  late final AnimationController _snapCtrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  Offset? _lastPos; // last observed window pos (plugin coords)
  bool _moved = false; // user dragged since last rest
  bool _snapping = false; // our glide animation is running
  bool _busyTick = false;

  // Self-calibrating bounds: we NEVER trust physicalSize / devicePixelRatio
  // (the plugin's coordinate unit is version/device dependent — guessing it
  // is exactly what was flinging the bubble off-screen). Instead we learn the
  // usable range purely from the coordinates the plugin itself reports as the
  // user drags. Snap targets are always inside this observed box, so the
  // bubble can only ever be moved somewhere it has already visibly been.
  double? _minX, _maxX, _minY, _maxY;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(milliseconds: 150), _tick);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _snapCtrl.dispose();
    super.dispose();
  }

  void _observe(Offset c) {
    _minX = _minX == null ? c.dx : min(_minX!, c.dx);
    _maxX = _maxX == null ? c.dx : (c.dx > _maxX! ? c.dx : _maxX!);
    _minY = _minY == null ? c.dy : min(_minY!, c.dy);
    _maxY = _maxY == null ? c.dy : (c.dy > _maxY! ? c.dy : _maxY!);
  }

  Future<void> _tick(Timer _) async {
    if (_expanded || _snapping || _busyTick || _snapCtrl.isAnimating) return;
    _busyTick = true;
    try {
      final p = await FlutterOverlayWindow.getOverlayPosition();
      final cur = Offset((p.x ?? 0).toDouble(), (p.y ?? 0).toDouble());
      _observe(cur);
      if (_lastPos == null) {
        // First sample: no observed range yet → do NOT snap (would be a
        // blind guess and could push it off-screen). Just start tracking.
        _lastPos = cur;
      } else if ((cur - _lastPos!).distance > 2) {
        _moved = true; // still being dragged
        _lastPos = cur;
      } else if (_moved) {
        _moved = false; // released after a drag → glide to nearest edge
        await _snapToNearest(cur);
      }
    } catch (_) {
      _poll?.cancel(); // getOverlayPosition unsupported / overlay gone
    } finally {
      _busyTick = false;
    }
  }

  Future<void> _snapToNearest(Offset cur) async {
    if (_minX == null) return;
    final spanX = _maxX! - _minX!;
    final spanY = _maxY! - _minY!;
    // Not enough drag history to know where the edges are yet — leave it.
    if (spanX < 1 && spanY < 1) {
      _lastPos = cur;
      return;
    }
    // Inset proportional to the observed range (≈8%) so the ball sits well
    // INSIDE the screen, never half-clipped at the very edge. Purely
    // relative → correct on any resolution / pixel density.
    final marginX = spanX * 0.08;
    final marginY = spanY * 0.08;
    final loX = _minX! + marginX, hiX = _maxX! - marginX;
    final loY = _minY! + marginY, hiY = _maxY! - marginY;
    double clampD(double v, double lo, double hi) =>
        hi <= lo ? (lo + hi) / 2 : v.clamp(lo, hi);
    final dL = cur.dx - _minX!;
    final dR = _maxX! - cur.dx;
    final dT = cur.dy - _minY!;
    final dB = _maxY! - cur.dy;
    final nearest = [dL, dR, dT, dB].reduce(min);
    double tx = clampD(cur.dx, loX, hiX);
    double ty = clampD(cur.dy, loY, hiY);
    if (nearest == dL) {
      tx = loX;
    } else if (nearest == dR) {
      tx = hiX;
    } else if (nearest == dT) {
      ty = loY;
    } else {
      ty = hiY;
    }
    // Hard safety: never leave the box the bubble has actually occupied.
    tx = tx.clamp(_minX!, _maxX!);
    ty = ty.clamp(_minY!, _maxY!);
    final to = Offset(tx, ty);
    if ((to - cur).distance < 1) {
      _lastPos = to;
      return;
    }
    _snapping = true;
    final curve =
        CurvedAnimation(parent: _snapCtrl, curve: Curves.easeOutCubic);
    void onTick() {
      final pos = Offset.lerp(cur, to, curve.value)!;
      FlutterOverlayWindow.moveOverlay(OverlayPosition(pos.dx, pos.dy));
    }

    _snapCtrl
      ..reset()
      ..addListener(onTick);
    try {
      await _snapCtrl.forward();
    } catch (_) {}
    _snapCtrl.removeListener(onTick);
    _snapping = false;
    _lastPos = to;
  }

  /// Cover the whole device screen AND sit at the screen origin.
  Future<void> _fillScreen() async {
    await FlutterOverlayWindow.resizeOverlay(
        WindowSize.matchParent, WindowSize.matchParent, false);
    try {
      await FlutterOverlayWindow.moveOverlay(OverlayPosition(0.0, 0.0));
    } catch (_) {}
  }

  Future<void> _expand() async {
    setState(() => _expanded = true);
    await _fillScreen();
    try {
      await FlutterOverlayWindow.updateFlag(OverlayFlag.focusPointer);
    } catch (_) {}
  }

  Future<void> _collapse() async {
    setState(() => _expanded = false);
    try {
      await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
    } catch (_) {}
    await FlutterOverlayWindow.resizeOverlay(60, 60, true);
    // Force a re-dock on the next poll tick so it returns to a safe edge.
    _lastPos = null;
    _moved = false;
  }

  @override
  Widget build(BuildContext context) {
    if (!_expanded) {
      // Native drag moves the window; we only need a tap target here.
      return Material(
        color: Colors.transparent,
        child: GestureDetector(
          // NOTE: no HitTestBehavior.opaque — opaque made Flutter's gesture
          // arena swallow the touches the plugin's native drag needs, so the
          // bubble couldn't be moved. deferToChild lets native drag work.
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
    final cardW = mq.size.width * (landscape ? 0.9 : 1.0);
    final cardH = mq.size.height * (landscape ? 0.96 : 0.97);

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
            child: SafeArea(
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
                        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                        child: Row(children: [
                          const Icon(Icons.shield,
                              color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text('最新动态',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold)),
                          ),
                          // Big tap targets — the old ones were tiny and the
                          // user kept hitting the screen-edge system gesture
                          // instead of ✕.
                          InkWell(
                            onTap: _collapse,
                            borderRadius: BorderRadius.circular(24),
                            child: const SizedBox(
                              width: 48,
                              height: 48,
                              child: Icon(Icons.remove,
                                  color: Colors.white, size: 26),
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () => FlutterOverlayWindow.closeOverlay(),
                            borderRadius: BorderRadius.circular(24),
                            child: const SizedBox(
                              width: 48,
                              height: 48,
                              child: Icon(Icons.close,
                                  color: Colors.white, size: 28),
                            ),
                          ),
                        ]),
                      ),
                      const Expanded(child: OverlayBrowser()),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
