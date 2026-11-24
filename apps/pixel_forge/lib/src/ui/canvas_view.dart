import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pixel_kit/pixel_kit.dart' as px;

import '../editor.dart';

/// The drawing area: one finger draws, two fingers pan and zoom; mouse
/// wheel zooms, right or middle drag pans.
class CanvasView extends StatefulWidget {
  const CanvasView({super.key, required this.editor});

  final Editor editor;

  @override
  State<CanvasView> createState() => CanvasViewState();
}

class CanvasViewState extends State<CanvasView> {
  double _scale = 0;
  Offset _offset = Offset.zero;
  Size _size = Size.zero;
  ui.Image? _image;
  int _imageVersion = -1;
  bool _building = false;

  final _pointers = <int, Offset>{};
  bool _drawing = false;
  bool _panning = false;
  double _startDist = 0, _startScale = 1;
  Offset _startFocal = Offset.zero, _startOffset = Offset.zero;

  Editor get e => widget.editor;

  @override
  void initState() {
    super.initState();
    e.addListener(_onEditor);
  }

  @override
  void didUpdateWidget(CanvasView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editor != e) {
      oldWidget.editor.removeListener(_onEditor);
      e.addListener(_onEditor);
    }
  }

  @override
  void dispose() {
    e.removeListener(_onEditor);
    _image?.dispose();
    super.dispose();
  }

  int _spriteW = 0, _spriteH = 0;

  void _onEditor() {
    if (e.sprite.width != _spriteW || e.sprite.height != _spriteH) {
      _scale = 0; // new size: fit again
    }
    _rebuildImage();
    setState(() {});
  }

  /// Zooms so the whole sprite fits.
  void fit() {
    setState(() => _scale = 0);
  }

  void _rebuildImage() {
    if (_building || _imageVersion == e.version) return;
    _building = true;
    final version = e.version;
    final s = e.sprite;
    final pixels = e.onionSkin && s.frames.length > 1
        ? onionComposite(s, e.frame)
        : s.flatten(e.frame);
    // ARGB words in little-endian memory are B,G,R,A bytes.
    ui.decodeImageFromPixels(
      pixels.buffer.asUint8List(),
      s.width,
      s.height,
      ui.PixelFormat.bgra8888,
      (img) {
        if (!mounted) {
          img.dispose();
          return;
        }
        _building = false;
        setState(() {
          _image?.dispose();
          _image = img;
          _imageVersion = version;
        });
        if (_imageVersion != e.version) _rebuildImage();
      },
    );
  }

  void _fitIfNeeded(Size size) {
    _size = size;
    if (_scale > 0 || size.isEmpty) return;
    final s = e.sprite;
    _spriteW = s.width;
    _spriteH = s.height;
    final fit = math.min(size.width / s.width, size.height / s.height) * 0.92;
    _scale = fit >= 1 ? fit.floorToDouble() : fit;
    _offset = Offset(
      (size.width - s.width * _scale) / 2,
      (size.height - s.height * _scale) / 2,
    );
  }

  (int, int) _toPixel(Offset p) {
    final q = (p - _offset) / _scale;
    return (q.dx.floor(), q.dy.floor());
  }

  void _zoomAt(Offset focal, double newScale) {
    final s = newScale.clamp(0.5, 80.0);
    final spritePoint = (focal - _offset) / _scale;
    setState(() {
      _scale = s;
      _offset = focal - spritePoint * s;
    });
  }

  void _down(PointerDownEvent ev) {
    _pointers[ev.pointer] = ev.localPosition;
    final mousePan =
        ev.kind == PointerDeviceKind.mouse &&
        (ev.buttons & (kSecondaryMouseButton | kMiddleMouseButton)) != 0;
    if (mousePan) {
      _panning = true;
      _startFocal = ev.localPosition;
      _startOffset = _offset;
      return;
    }
    if (_pointers.length == 1) {
      final (x, y) = _toPixel(ev.localPosition);
      _drawing = true;
      e.strokeStart(x, y);
    } else if (_pointers.length == 2) {
      if (_drawing) {
        e.strokeCancel();
        _drawing = false;
      }
      final pts = _pointers.values.toList();
      _startDist = (pts[0] - pts[1]).distance;
      _startFocal = (pts[0] + pts[1]) / 2;
      _startScale = _scale;
      _startOffset = _offset;
    }
  }

  void _move(PointerMoveEvent ev) {
    _pointers[ev.pointer] = ev.localPosition;
    if (_panning) {
      setState(() => _offset = _startOffset + (ev.localPosition - _startFocal));
      return;
    }
    if (_pointers.length >= 2) {
      final pts = _pointers.values.toList();
      final dist = (pts[0] - pts[1]).distance;
      final focal = (pts[0] + pts[1]) / 2;
      final s = (_startScale * (dist / math.max(1, _startDist))).clamp(
        0.5,
        80.0,
      );
      final spritePoint = (_startFocal - _startOffset) / _startScale;
      setState(() {
        _scale = s;
        _offset = focal - spritePoint * s;
      });
      return;
    }
    if (_drawing) {
      final (x, y) = _toPixel(ev.localPosition);
      e.strokeMove(x, y);
    }
  }

  void _up(PointerEvent ev) {
    _pointers.remove(ev.pointer);
    if (_panning && _pointers.isEmpty) _panning = false;
    if (_drawing && _pointers.isEmpty) {
      _drawing = false;
      e.strokeEnd();
    }
  }

  void _signal(PointerSignalEvent ev) {
    if (ev is PointerScrollEvent) {
      final factor = ev.scrollDelta.dy > 0 ? 1 / 1.25 : 1.25;
      _zoomAt(ev.localPosition, _scale * factor);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_imageVersion != e.version) _rebuildImage();
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, box) {
        _fitIfNeeded(Size(box.maxWidth, box.maxHeight));
        return Listener(
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _up,
          onPointerCancel: _up,
          onPointerSignal: _signal,
          child: ClipRect(
            child: CustomPaint(
              size: Size.infinite,
              painter: _CanvasPainter(
                image: _image,
                w: e.sprite.width,
                h: e.sprite.height,
                scale: _scale,
                offset: _offset,
                selection: e.selection,
                background: scheme.surfaceContainerLowest,
                grid: scheme.outline.withValues(alpha: 0.25),
                select: scheme.primary,
                version: e.version ^ _imageVersion,
              ),
            ),
          ),
        );
      },
    );
  }

  /// For tests: the screen point of a sprite pixel's centre.
  Offset pixelCenter(int x, int y) =>
      _offset + Offset((x + 0.5) * _scale, (y + 0.5) * _scale);
  Size get viewSize => _size;
}

class _CanvasPainter extends CustomPainter {
  _CanvasPainter({
    required this.image,
    required this.w,
    required this.h,
    required this.scale,
    required this.offset,
    required this.selection,
    required this.background,
    required this.grid,
    required this.select,
    required this.version,
  });

  final ui.Image? image;
  final int w, h;
  final double scale;
  final Offset offset;
  final px.Rect? selection;
  final Color background, grid, select;
  final int version;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final area = offset & Size(w * scale, h * scale);
    // Checkerboard shows transparency; its squares follow the pixel grid
    // (one pixel, or a few when zoomed out so squares stay >= 10 px).
    final cell = scale * math.max(1, (10 / scale).ceil());
    final light = Paint()..color = const Color(0xFFDDDDDD);
    final dark = Paint()..color = const Color(0xFFBBBBBB);
    canvas.save();
    canvas.clipRect(area);
    canvas.drawRect(area, light);
    for (var y = 0; y * cell < area.height; y++) {
      for (var x = (y.isOdd ? 1 : 0); x * cell < area.width; x += 2) {
        canvas.drawRect(
          Rect.fromLTWH(area.left + x * cell, area.top + y * cell, cell, cell),
          dark,
        );
      }
    }
    final img = image;
    if (img != null) {
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        area,
        Paint()..filterQuality = FilterQuality.none,
      );
    }
    if (scale >= 8) {
      final gp = Paint()
        ..color = grid
        ..strokeWidth = 1;
      for (var x = 1; x < w; x++) {
        final sx = area.left + x * scale;
        canvas.drawLine(Offset(sx, area.top), Offset(sx, area.bottom), gp);
      }
      for (var y = 1; y < h; y++) {
        final sy = area.top + y * scale;
        canvas.drawLine(Offset(area.left, sy), Offset(area.right, sy), gp);
      }
    }
    canvas.restore();
    canvas.drawRect(
      area,
      Paint()
        ..color = grid
        ..style = PaintingStyle.stroke,
    );
    final s = selection;
    if (s != null) {
      final r = Rect.fromLTWH(
        offset.dx + s.left * scale,
        offset.dy + s.top * scale,
        s.width * scale,
        s.height * scale,
      );
      canvas.drawRect(
        r,
        Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      canvas.drawRect(
        r,
        Paint()
          ..color = select
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_CanvasPainter old) =>
      old.image != image ||
      old.scale != scale ||
      old.offset != offset ||
      old.selection != selection ||
      old.version != version;
}

/// The current frame over faint copies of its neighbours: the previous
/// frame tinted red and the next tinted blue (like other animation tools).
Uint32List onionComposite(px.Sprite s, int frame) {
  final out = Uint32List(s.pixelCount);
  final n = s.frames.length;
  void ghost(int f, int tint) {
    final p = s.flatten(f);
    for (var i = 0; i < p.length; i++) {
      final c = p[i];
      if (px.alphaOf(c) == 0) continue;
      final mixed = px.blendOver(c | 0xFF000000, tint, 0.5);
      out[i] = px.blendOver(out[i], (mixed & 0x00FFFFFF) | 0x55000000);
    }
  }

  if (frame > 0) ghost(frame - 1, 0xFFFF3030);
  if (frame < n - 1) ghost(frame + 1, 0xFF3080FF);
  final cur = s.flatten(frame);
  for (var i = 0; i < cur.length; i++) {
    if (cur[i] != 0) out[i] = px.blendOver(out[i], cur[i]);
  }
  return out;
}
