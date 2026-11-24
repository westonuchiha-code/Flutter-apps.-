import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

/// Shows a frame on a pretend CRT: aperture-grille stripes, scan lines,
/// phosphor glow and a darker edge. Drawn on the GPU, so it costs nothing
/// on the processing side.
class ScreenView extends StatefulWidget {
  const ScreenView({super.key, required this.image, required this.crt});

  final ui.Image? image;
  final bool crt;

  @override
  State<ScreenView> createState() => _ScreenViewState();
}

class _ScreenViewState extends State<ScreenView> {
  static ui.Image? _mask;

  @override
  void initState() {
    super.initState();
    if (_mask == null) unawaited(_makeMask());
  }

  /// 3×3 tile: R, G, B stripes; the third row darker (scan line gap).
  Future<void> _makeMask() async {
    const tints = [
      [255, 140, 140],
      [140, 255, 140],
      [140, 140, 255],
    ];
    final px = Uint8List(3 * 3 * 4);
    for (var y = 0; y < 3; y++) {
      for (var x = 0; x < 3; x++) {
        final dim = y == 2 ? 0.55 : 1.0;
        final o = (y * 3 + x) * 4;
        px[o] = (tints[x][0] * dim).round();
        px[o + 1] = (tints[x][1] * dim).round();
        px[o + 2] = (tints[x][2] * dim).round();
        px[o + 3] = 255;
      }
    }
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(px, 3, 3, ui.PixelFormat.rgba8888, c.complete);
    final m = await c.future;
    if (mounted) setState(() => _mask = m);
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.infinite,
    painter: _ScreenPainter(widget.image, widget.crt ? _mask : null),
  );
}

class _ScreenPainter extends CustomPainter {
  _ScreenPainter(this.image, this.mask);
  final ui.Image? image;
  final ui.Image? mask;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    final img = image;
    if (img == null) return;
    final scale = (size.width / img.width < size.height / img.height
        ? size.width / img.width
        : size.height / img.height);
    final w = img.width * scale, h = img.height * scale;
    final dst = Rect.fromLTWH(
      (size.width - w) / 2,
      (size.height - h) / 2,
      w,
      h,
    );
    final src = Rect.fromLTWH(
      0,
      0,
      img.width.toDouble(),
      img.height.toDouble(),
    );
    final m = mask;
    if (m == null) {
      canvas.drawImageRect(
        img,
        src,
        dst,
        Paint()..filterQuality = FilterQuality.none,
      );
      return;
    }
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(dst, Radius.circular(dst.shortestSide * 0.04)),
    );
    // Slightly soft, like a real tube.
    canvas.drawImageRect(
      img,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.low,
    );
    // Mask and scan lines.
    canvas.drawRect(
      dst,
      Paint()
        ..blendMode = BlendMode.multiply
        ..shader = ImageShader(
          m,
          TileMode.repeated,
          TileMode.repeated,
          Matrix4.identity().storage,
        ),
    );
    // Phosphor glow: a blurred copy added on top.
    canvas.saveLayer(dst, Paint()..blendMode = BlendMode.plus);
    canvas.drawImageRect(
      img,
      src,
      dst,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: scale * 1.2,
          sigmaY: scale * 1.2,
        )
        ..color = const Color(0x55FFFFFF),
    );
    canvas.restore();
    // Darker towards the edges.
    canvas.drawRect(
      dst,
      Paint()
        ..shader = RadialGradient(
          colors: const [Color(0x00000000), Color(0x99000000)],
          stops: const [0.65, 1.0],
        ).createShader(dst),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScreenPainter old) =>
      old.image != image || old.mask != mask;
}
