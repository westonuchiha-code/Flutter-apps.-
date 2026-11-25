import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// A texture from ARGB pixels.
Future<ui.Image> imageFromArgb(Uint32List argb, int width, int height) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    argb.buffer.asUint8List(argb.offsetInBytes, argb.lengthInBytes),
    width,
    height,
    ui.PixelFormat.bgra8888,
    c.complete,
  );
  return c.future;
}

/// A texture from PNG/JPEG/GIF/WebP bytes.
Future<ui.Image> imageFromBytes(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

/// A [cells]×[cells] checkerboard, [size] pixels square.
Future<ui.Image> checkerTexture(int a, int b, {int size = 32, int cells = 2}) {
  final px = Uint32List(size * size);
  final cell = size ~/ cells;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      px[y * size + x] = ((x ~/ cell) + (y ~/ cell)).isEven ? a : b;
    }
  }
  return imageFromArgb(px, size, size);
}

/// Bricks, [size] pixels square (a handy wall texture).
Future<ui.Image> brickTexture({
  int brick = 0xFF9A4A3A,
  int mortar = 0xFFB8AFA0,
  int size = 32,
}) {
  final px = Uint32List(size * size);
  final bh = size ~/ 4, bw = size ~/ 2;
  for (var y = 0; y < size; y++) {
    final row = y ~/ bh;
    final off = row.isOdd ? bw ~/ 2 : 0;
    for (var x = 0; x < size; x++) {
      final m = y % bh == 0 || (x + off) % bw == 0;
      final shade = ((x * 7 + y * 13 + row * 5) % 9) - 4;
      int tweak(int c) {
        int ch(int v) => (v + shade * 3).clamp(0, 255);
        return 0xFF000000 |
            (ch((c >> 16) & 255) << 16) |
            (ch((c >> 8) & 255) << 8) |
            ch(c & 255);
      }

      px[y * size + x] = m ? mortar : tweak(brick);
    }
  }
  return imageFromArgb(px, size, size);
}
