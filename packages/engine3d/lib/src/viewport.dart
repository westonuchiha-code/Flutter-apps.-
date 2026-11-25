import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'camera.dart';
import 'renderer.dart';
import 'scene.dart';

/// Shows a scene and lets the user move: drag to look/orbit, pinch or
/// wheel to zoom, WASD/arrow keys to move, and an on-screen joystick on
/// touch screens.
class Viewport3D extends StatefulWidget {
  const Viewport3D({
    super.key,
    required this.scene,
    required this.rig,
    this.options = const RenderOptions(),
    this.onFrame,
    this.showStats = false,
    this.joystick,
  });

  final Scene scene;
  final CameraRig rig;
  final RenderOptions options;

  /// Called every frame with the seconds since the last (animate here).
  final void Function(double dt)? onFrame;
  final bool showStats;

  /// Show the touch joystick (default: on phones).
  final bool? joystick;

  @override
  State<Viewport3D> createState() => _Viewport3DState();
}

class _Viewport3DState extends State<Viewport3D>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _repaint = ValueNotifier<int>(0);
  final _renderer = Renderer();
  Duration _last = Duration.zero;
  double _fps = 0;
  final _focus = FocusNode();

  // Touch state.
  final _looks = <int, Offset>{};
  int? _stickPointer;
  Offset? _stickOrigin;
  Offset _stick = Offset.zero;
  double? _pinchStart;

  bool get _touchUi =>
      widget.joystick ?? (Theme.of(context).platform == TargetPlatform.android);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void didUpdateWidget(Viewport3D old) {
    super.didUpdateWidget(old);
    if (old.options.smoothTextures != widget.options.smoothTextures) {
      _renderer.clearCache();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero
        ? 1 / 60
        : math.min(0.1, (now - _last).inMicroseconds / 1e6);
    _last = now;
    if (dt > 0) {
      _fps = _fps == 0 ? 1 / dt : _fps * 0.95 + (1 / dt) * 0.05;
    }
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    bool down(List<LogicalKeyboardKey> k) => k.any(keys.contains);
    var fwd = 0.0, side = 0.0;
    if (down([LogicalKeyboardKey.keyW, LogicalKeyboardKey.arrowUp])) {
      fwd += 1;
    }
    if (down([LogicalKeyboardKey.keyS, LogicalKeyboardKey.arrowDown])) {
      fwd -= 1;
    }
    if (down([LogicalKeyboardKey.keyD])) {
      side += 1;
    }
    if (down([LogicalKeyboardKey.keyA])) {
      side -= 1;
    }
    if (down([LogicalKeyboardKey.arrowLeft])) {
      widget.rig.drag(-300 * dt, 0);
    }
    if (down([LogicalKeyboardKey.arrowRight])) {
      widget.rig.drag(300 * dt, 0);
    }
    fwd -= _stick.dy;
    side += _stick.dx;
    if (fwd != 0 || side != 0) {
      widget.rig.move(fwd.clamp(-1.0, 1.0), side.clamp(-1.0, 1.0), dt);
    }
    widget.rig.update(dt);
    widget.onFrame?.call(dt);
    _repaint.value++;
  }

  void _down(PointerDownEvent e, Size size) {
    _focus.requestFocus();
    if (_touchUi &&
        e.kind == PointerDeviceKind.touch &&
        _stickPointer == null &&
        e.localPosition.dx < size.width * 0.4 &&
        e.localPosition.dy > size.height * 0.35) {
      _stickPointer = e.pointer;
      _stickOrigin = e.localPosition;
      _stick = Offset.zero;
      setState(() {});
      return;
    }
    _looks[e.pointer] = e.localPosition;
    if (_looks.length == 2) {
      _pinchStart = _spread();
    }
  }

  double _spread() {
    final p = _looks.values.toList();
    return (p[0] - p[1]).distance;
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer == _stickPointer) {
      final d = (e.localPosition - _stickOrigin!) / 56;
      _stick = d.distance > 1 ? d / d.distance : d;
      setState(() {});
      return;
    }
    if (!_looks.containsKey(e.pointer)) {
      return;
    }
    _looks[e.pointer] = e.localPosition;
    if (_looks.length >= 2) {
      final s = _spread();
      if (_pinchStart != null && _pinchStart! > 0) {
        widget.rig.zoom(s / _pinchStart!);
      }
      _pinchStart = s;
    } else {
      widget.rig.drag(e.delta.dx, e.delta.dy);
    }
  }

  void _up(PointerEvent e) {
    if (e.pointer == _stickPointer) {
      _stickPointer = null;
      _stickOrigin = null;
      _stick = Offset.zero;
      setState(() {});
    }
    _looks.remove(e.pointer);
    if (_looks.length < 2) {
      _pinchStart = null;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final size = box.biggest;
      return Focus(
        focusNode: _focus,
        autofocus: true,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => _down(e, size),
          onPointerMove: _move,
          onPointerUp: _up,
          onPointerCancel: _up,
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) {
              widget.rig.zoom(math.exp(-e.scrollDelta.dy / 500));
            }
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _ScenePainter(
                    _renderer,
                    widget.scene,
                    widget.rig,
                    widget.options,
                    _repaint,
                  ),
                ),
              ),
              if (_touchUi)
                Positioned(
                  left: (_stickOrigin?.dx ?? 80) - 48,
                  top: (_stickOrigin?.dy ?? size.height - 90) - 48,
                  child: IgnorePointer(
                    child: _Stick(
                      offset: _stick,
                      active: _stickPointer != null,
                    ),
                  ),
                ),
              if (widget.showStats)
                Positioned(
                  left: 8,
                  top: 6,
                  child: ValueListenableBuilder(
                    valueListenable: _repaint,
                    builder: (context, _, _) {
                      final s = _renderer.stats;
                      return Text(
                        '${_fps.round()} fps · ${s.drawn}/${s.triangles} triangles · ${s.ms.toStringAsFixed(1)} ms · ${s.width}×${s.height}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          shadows: [Shadow(blurRadius: 2)],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _Stick extends StatelessWidget {
  const _Stick({required this.offset, required this.active});
  final Offset offset;
  final bool active;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 96,
    height: 96,
    child: Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: active ? 0.5 : 0.2),
              width: 2,
            ),
          ),
        ),
        Positioned(
          left: 30 + offset.dx * 30,
          top: 30 + offset.dy * 30,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: active ? 0.55 : 0.2),
            ),
          ),
        ),
      ],
    ),
  );
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(
    this.renderer,
    this.scene,
    this.rig,
    this.options,
    Listenable repaint,
  ) : super(repaint: repaint);
  final Renderer renderer;
  final Scene scene;
  final CameraRig rig;
  final RenderOptions options;

  @override
  void paint(Canvas canvas, Size size) =>
      renderer.paint(canvas, size, scene, rig.camera, options);

  @override
  bool shouldRepaint(_ScenePainter old) =>
      old.scene != scene || old.rig != rig || old.options != options;
}
