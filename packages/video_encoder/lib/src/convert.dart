import 'dart:typed_data';

/// ARGB → I420 (planar Y, then U and V at half size), BT.601 limited range:
/// what hardware H.264 encoders expect.
Uint8List argbToI420(Uint32List argb, int width, int height) {
  final ySize = width * height, cw = width ~/ 2, ch = height ~/ 2;
  final out = Uint8List(ySize + 2 * cw * ch);
  for (var i = 0; i < ySize; i++) {
    final c = argb[i];
    final r = (c >> 16) & 255, g = (c >> 8) & 255, b = c & 255;
    out[i] = ((66 * r + 129 * g + 25 * b + 128) >> 8) + 16;
  }
  final uo = ySize, vo = ySize + cw * ch;
  for (var y = 0; y < ch; y++) {
    for (var x = 0; x < cw; x++) {
      var r = 0, g = 0, b = 0;
      for (var dy = 0; dy < 2; dy++) {
        for (var dx = 0; dx < 2; dx++) {
          final c = argb[(y * 2 + dy) * width + x * 2 + dx];
          r += (c >> 16) & 255;
          g += (c >> 8) & 255;
          b += c & 255;
        }
      }
      r >>= 2;
      g >>= 2;
      b >>= 2;
      out[uo + y * cw + x] = ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128;
      out[vo + y * cw + x] = ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128;
    }
  }
  return out;
}

/// Scales ARGB pixels up by whole steps with no smoothing (pixel art stays
/// sharp), centred on a [width]×[height] black canvas. The scale is the
/// largest whole number that fits (at least 1; bigger pictures are cropped).
Uint32List upscaleNearest(
  Uint32List src,
  int sw,
  int sh,
  int width,
  int height,
) {
  var k = width ~/ sw < height ~/ sh ? width ~/ sw : height ~/ sh;
  if (k < 1) k = 1;
  final out = Uint32List(width * height)
    ..fillRange(0, width * height, 0xFF000000);
  final ox = (width - sw * k) ~/ 2, oy = (height - sh * k) ~/ 2;
  for (var y = 0; y < height; y++) {
    final sy = (y - oy) ~/ k;
    if (y < oy || sy >= sh) continue;
    final row = sy * sw;
    for (var x = 0; x < width; x++) {
      final sx = (x - ox) ~/ k;
      if (x < ox || sx >= sw) continue;
      out[y * width + x] = src[row + sx] | 0xFF000000;
    }
  }
  return out;
}
