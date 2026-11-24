import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../controller.dart';
import '../engine/warp.dart';

/// The photo with four draggable corners. While dragging, a magnifier shows
/// the corner up close.
class CornerEditor extends StatefulWidget {
  const CornerEditor({super.key, required this.controller});
  final TextureController controller;

  @override
  State<CornerEditor> createState() => _CornerEditorState();
}

class _CornerEditorState extends State<CornerEditor> {
  int? _active;

  static const _margin = 28.0;

  ({double scale, Offset origin}) _fit(Size size, ui.Image img) {
    final scale = math.min(
      (size.width - 2 * _margin) / img.width,
      (size.height - 2 * _margin) / img.height,
    );
    final origin = Offset(
      (size.width - img.width * scale) / 2,
      (size.height - img.height * scale) / 2,
    );
    return (scale: scale, origin: origin);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final img = c.photoImage, s = c.settings;
    if (img == null || s == null) return const SizedBox.expand();
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final fit = _fit(size, img);
        Offset toScreen(Pt p) => fit.origin + Offset(p.x, p.y) * fit.scale;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) {
            var best = -1;
            var bestD = 56.0;
            for (var i = 0; i < 4; i++) {
              final dd = (toScreen(s.corners[i]) - d.localPosition).distance;
              if (dd < bestD) {
                bestD = dd;
                best = i;
              }
            }
            setState(() => _active = best < 0 ? null : best);
          },
          onPanUpdate: (d) {
            final i = _active;
            if (i == null) return;
            final p = c.settings!.corners[i];
            c.moveCorner(i, (
              x: p.x + d.delta.dx / fit.scale,
              y: p.y + d.delta.dy / fit.scale,
            ));
          },
          onPanEnd: (_) => _end(),
          onPanCancel: _end,
          child: CustomPaint(
            size: size,
            painter: _CornerPainter(
              img,
              [for (final p in c.settings!.corners) toScreen(p)],
              fit.origin,
              fit.scale,
              _active,
              Theme.of(context).colorScheme.primary,
            ),
          ),
        );
      },
    );
  }

  void _end() {
    if (_active == null) return;
    setState(() => _active = null);
    widget.controller.rebuild();
  }
}

class _CornerPainter extends CustomPainter {
  _CornerPainter(
    this.img,
    this.quad,
    this.origin,
    this.scale,
    this.active,
    this.accent,
  );
  final ui.Image img;
  final List<Offset> quad;
  final Offset origin;
  final double scale;
  final int? active;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final dst = origin & Size(img.width * scale, img.height * scale);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
    final quadPath = Path()..addPolygon(quad, true);
    // Dim everything outside the surface.
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(dst)
        ..addPath(quadPath, Offset.zero),
      Paint()..color = const Color(0x99000000),
    );
    // Perspective grid: shows how the surface will be flattened.
    final h = Homography.squareToQuad([
      for (final q in quad) (x: q.dx, y: q.dy),
    ]);
    Offset at(double u, double v) {
      final p = h.map(u, v);
      return Offset(p.x, p.y);
    }

    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    for (var k = 1; k < 4; k++) {
      canvas.drawLine(at(k / 4, 0), at(k / 4, 1), grid);
      canvas.drawLine(at(0, k / 4), at(1, k / 4), grid);
    }
    canvas.drawPath(
      quadPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = accent,
    );
    // Top edge marker: the texture's top.
    canvas.drawLine(
      quad[0],
      quad[1],
      Paint()
        ..strokeWidth = 4
        ..color = accent,
    );
    for (var i = 0; i < 4; i++) {
      canvas.drawCircle(
        quad[i],
        i == active ? 14 : 11,
        Paint()..color = Colors.black54,
      );
      canvas.drawCircle(
        quad[i],
        i == active ? 14 : 11,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = i == 0 ? Colors.white : accent,
      );
    }
    final a = active;
    if (a != null) _loupe(canvas, size, quad[a]);
  }

  void _loupe(Canvas canvas, Size size, Offset p) {
    const r = 64.0, zoom = 4.0;
    final centre = Offset(
      p.dx < size.width / 2 ? size.width - r - 12 : r + 12,
      r + 12,
    );
    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: centre, radius: r)),
    );
    canvas.drawColor(Colors.black, BlendMode.src);
    // Image pixels around the corner.
    final ip = (p - origin) / scale;
    final half = r / (scale * zoom);
    canvas.drawImageRect(
      img,
      Rect.fromCenter(center: ip, width: half * 2, height: half * 2),
      Rect.fromCircle(center: centre, radius: r),
      Paint()..filterQuality = FilterQuality.none,
    );
    final cross = Paint()
      ..color = accent
      ..strokeWidth = 1.5;
    canvas.drawLine(
      centre - const Offset(r, 0),
      centre + const Offset(r, 0),
      cross,
    );
    canvas.drawLine(
      centre - const Offset(0, r),
      centre + const Offset(0, r),
      cross,
    );
    canvas.restore();
    canvas.drawCircle(
      centre,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_CornerPainter old) =>
      old.img != img ||
      old.active != active ||
      old.scale != scale ||
      old.origin != origin ||
      !_same(old.quad, quad);

  static bool _same(List<Offset> a, List<Offset> b) {
    for (var i = 0; i < 4; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// A texture on its own or repeated 3×3, with sharp or filtered texels.
class TexturePreview extends StatelessWidget {
  const TexturePreview({
    super.key,
    required this.image,
    required this.tiled,
    required this.smooth,
    this.busy = false,
    this.label,
  });

  final ui.Image? image;
  final bool tiled, smooth, busy;
  final String? label;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: CustomPaint(painter: _TexturePainter(image, tiled, smooth)),
      ),
      if (label != null)
        Positioned(
          left: 8,
          bottom: 6,
          child: Text(
            label!,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      if (busy || image == null)
        const Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: LinearProgressIndicator(),
        ),
    ],
  );
}

class _TexturePainter extends CustomPainter {
  _TexturePainter(this.image, this.tiled, this.smooth);
  final ui.Image? image;
  final bool tiled, smooth;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF101010),
    );
    final img = image;
    if (img == null) return;
    final n = tiled ? 3 : 1;
    final side = (math.min(size.width, size.height) - 16) / n;
    final left = (size.width - side * n) / 2,
        top = (size.height - side * n) / 2;
    // A repeating shader wraps filtering across tile edges, like hardware.
    final m = Matrix4.identity()
      ..translateByDouble(left, top, 0, 1)
      ..scaleByDouble(side / img.width, side / img.height, 1, 1);
    canvas.drawRect(
      Rect.fromLTWH(left, top, side * n, side * n),
      Paint()
        ..shader = ImageShader(
          img,
          TileMode.repeated,
          TileMode.repeated,
          m.storage,
          filterQuality: smooth ? FilterQuality.low : FilterQuality.none,
        ),
    );
  }

  @override
  bool shouldRepaint(_TexturePainter old) =>
      old.image != image || old.tiled != tiled || old.smooth != smooth;
}
