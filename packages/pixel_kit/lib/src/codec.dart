import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'color.dart';
import 'sprite.dart';

/// ARGB pixels → an `image` package image.
img.Image toImage(Uint32List argbPixels, int w, int h, {int scale = 1}) {
  final out = img.Image(width: w * scale, height: h * scale, numChannels: 4);
  for (var y = 0; y < h * scale; y++) {
    for (var x = 0; x < w * scale; x++) {
      final c = argbPixels[(y ~/ scale) * w + (x ~/ scale)];
      out.setPixelRgba(x, y, redOf(c), greenOf(c), blueOf(c), alphaOf(c));
    }
  }
  return out;
}

/// PNG of one frame (all visible layers), optionally scaled up (nearest).
Uint8List spriteToPng(Sprite s, {int frame = 0, int scale = 1}) =>
    img.encodePng(toImage(s.flatten(frame), s.width, s.height, scale: scale));

/// Decodes PNG/JPEG/GIF/BMP/WebP bytes to ARGB pixels.
({int width, int height, Uint32List pixels})? decodePicture(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) return null;
  final rgba = image.convert(numChannels: 4);
  final out = Uint32List(rgba.width * rgba.height);
  for (final p in rgba) {
    out[p.y * rgba.width + p.x] = argb(
      p.a.toInt(),
      p.r.toInt(),
      p.g.toInt(),
      p.b.toInt(),
    );
  }
  return (width: rgba.width, height: rgba.height, pixels: out);
}
