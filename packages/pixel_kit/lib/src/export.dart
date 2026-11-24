import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'codec.dart';
import 'color.dart';
import 'sprite.dart';

/// All frames side by side in a grid ([columns] wide; 0 = one row).
({Uint32List pixels, int width, int height}) spriteSheet(
  Sprite s, {
  int columns = 0,
}) {
  final n = s.frames.length;
  final cols = columns <= 0 ? n : columns.clamp(1, n);
  final rows = (n / cols).ceil();
  final w = cols * s.width, h = rows * s.height;
  final out = Uint32List(w * h);
  for (var f = 0; f < n; f++) {
    final px = s.flatten(f);
    final ox = (f % cols) * s.width, oy = (f ~/ cols) * s.height;
    for (var y = 0; y < s.height; y++) {
      out.setRange(
        (oy + y) * w + ox,
        (oy + y) * w + ox + s.width,
        px,
        y * s.width,
      );
    }
  }
  return (pixels: out, width: w, height: h);
}

Uint8List spriteSheetPng(Sprite s, {int columns = 0, int scale = 1}) {
  final sheet = spriteSheet(s, columns: columns);
  return img.encodePng(
    toImage(sheet.pixels, sheet.width, sheet.height, scale: scale),
  );
}

/// Animated GIF of every frame with its own timing. Colours are written
/// exactly (GIFs hold 256 colours per frame; extra colours fall back to the
/// nearest one kept). Transparent pixels stay transparent.
Uint8List spriteToGif(Sprite s, {int scale = 1}) {
  final enc = img.GifEncoder(repeat: 0, dither: img.DitherKernel.none);
  final w = s.width * scale, h = s.height * scale;
  for (var f = 0; f < s.frames.length; f++) {
    final px = s.flatten(f);
    // Build an exact palette: index 0 is transparent.
    final index = <int, int>{};
    final colors = <int>[0];
    for (final c in px) {
      if (alphaOf(c) < 128) continue;
      final o = c | 0xFF000000;
      if (!index.containsKey(o) && colors.length < 256) {
        index[o] = colors.length;
        colors.add(o);
      }
    }
    int indexOf(int c) {
      if (alphaOf(c) < 128) return 0;
      final o = c | 0xFF000000;
      final i = index[o];
      if (i != null) return i;
      var best = 1, bestD = 1 << 62;
      for (var k = 1; k < colors.length; k++) {
        final d = colorDistance(o, colors[k]);
        if (d < bestD) {
          bestD = d;
          best = k;
        }
      }
      return best;
    }

    final frame = img.Image(
      width: w,
      height: h,
      numChannels: 4,
      withPalette: true,
      paletteFormat: img.Format.uint8,
    );
    final pal = frame.palette!;
    for (var i = 0; i < colors.length; i++) {
      final c = colors[i];
      pal.setRgba(i, redOf(c), greenOf(c), blueOf(c), i == 0 ? 0 : 255);
    }
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        frame.getPixel(x, y).index = indexOf(
          px[(y ~/ scale) * s.width + (x ~/ scale)],
        );
      }
    }
    enc.addFrame(
      frame,
      duration: (s.frames[f].durationMs / 10).round().clamp(2, 6000),
    );
  }
  return enc.finish()!;
}
