import 'dart:typed_data';

export 'package:pixel_kit/pixel_kit.dart'
    show argb, alphaOf, redOf, greenOf, blueOf;

/// A picture: ARGB pixels (0xAARRGGBB), row-major.
class VideoFrame {
  VideoFrame(this.width, this.height, [Uint32List? pixels])
    : pixels = pixels ?? Uint32List(width * height);

  final int width, height;
  final Uint32List pixels;

  int at(int x, int y) => pixels[y * width + x];

  /// Area-averaged resize (used to bring the camera to each machine's
  /// resolution).
  VideoFrame resized(int w, int h) {
    if (w == width && h == height) return this;
    final out = VideoFrame(w, h);
    for (var ty = 0; ty < h; ty++) {
      final y0 = ty * height ~/ h;
      var y1 = (ty + 1) * height ~/ h;
      if (y1 <= y0) y1 = y0 + 1;
      for (var tx = 0; tx < w; tx++) {
        final x0 = tx * width ~/ w;
        var x1 = (tx + 1) * width ~/ w;
        if (x1 <= x0) x1 = x0 + 1;
        var r = 0, g = 0, b = 0, n = 0;
        for (var y = y0; y < y1; y++) {
          for (var x = x0; x < x1; x++) {
            final c = pixels[y * width + x];
            r += (c >> 16) & 255;
            g += (c >> 8) & 255;
            b += c & 255;
            n++;
          }
        }
        out.pixels[ty * w + tx] =
            0xFF000000 | ((r ~/ n) << 16) | ((g ~/ n) << 8) | (b ~/ n);
      }
    }
    return out;
  }

  /// Rotated by quarter turns clockwise (camera sensors are sideways).
  VideoFrame rotated(int quarterTurns) {
    final q = quarterTurns % 4;
    if (q == 0) return this;
    final w = q.isOdd ? height : width, h = q.isOdd ? width : height;
    final out = VideoFrame(w, h);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final (nx, ny) = switch (q) {
          1 => (height - 1 - y, x),
          2 => (width - 1 - x, height - 1 - y),
          _ => (y, width - 1 - x),
        };
        out.pixels[ny * w + nx] = pixels[y * width + x];
      }
    }
    return out;
  }

  VideoFrame mirrored() {
    final out = VideoFrame(width, height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        out.pixels[y * width + x] = pixels[y * width + width - 1 - x];
      }
    }
    return out;
  }

  VideoFrame copy() => VideoFrame(width, height, Uint32List.fromList(pixels));

  /// BGRA bytes (what Flutter's `decodeImageFromPixels` wants): ARGB words
  /// are already B, G, R, A in little-endian memory.
  Uint8List get bgraBytes =>
      pixels.buffer.asUint8List(pixels.offsetInBytes, pixels.lengthInBytes);

  /// From BGRA bytes (e.g. a desktop webcam frame).
  factory VideoFrame.fromBgra(Uint8List bgra, int width, int height) {
    final copy = Uint8List.fromList(bgra.sublist(0, width * height * 4));
    final px = copy.buffer.asUint32List();
    for (var i = 0; i < px.length; i++) {
      px[i] |= 0xFF000000;
    }
    return VideoFrame(width, height, px);
  }

  /// From an 8-bit grey image.
  factory VideoFrame.fromLuma(Uint8List luma, int width, int height) {
    final f = VideoFrame(width, height);
    for (var i = 0; i < width * height; i++) {
      final v = luma[i];
      f.pixels[i] = 0xFF000000 | (v << 16) | (v << 8) | v;
    }
    return f;
  }
}

/// Converts a camera YUV 4:2:0 image (three planes, Android) to ARGB,
/// shrinking by [step] (sampling every step-th pixel) on the way.
VideoFrame yuv420ToFrame({
  required int width,
  required int height,
  required Uint8List y,
  required Uint8List u,
  required Uint8List v,
  required int yRowStride,
  required int uvRowStride,
  required int uvPixelStride,
  int step = 1,
}) {
  final w = width ~/ step, h = height ~/ step;
  final out = VideoFrame(w, h);
  int clamp(int x) => x < 0 ? 0 : (x > 255 ? 255 : x);
  for (var ty = 0; ty < h; ty++) {
    final sy = ty * step;
    for (var tx = 0; tx < w; tx++) {
      final sx = tx * step;
      final yy = y[sy * yRowStride + sx];
      final uvIndex = (sy >> 1) * uvRowStride + (sx >> 1) * uvPixelStride;
      final cu = (uvIndex < u.length ? u[uvIndex] : 128) - 128;
      final cv = (uvIndex < v.length ? v[uvIndex] : 128) - 128;
      // BT.601 (full range, as Android cameras deliver).
      final r = clamp(yy + ((359 * cv) >> 8));
      final g = clamp(yy - ((88 * cu + 183 * cv) >> 8));
      final b = clamp(yy + ((454 * cu) >> 8));
      out.pixels[ty * w + tx] = 0xFF000000 | (r << 16) | (g << 8) | b;
    }
  }
  return out;
}

int lumaOf(int c) =>
    (77 * ((c >> 16) & 255) + 150 * ((c >> 8) & 255) + 29 * (c & 255)) >> 8;

int grey(int v) {
  final x = v < 0 ? 0 : (v > 255 ? 255 : v);
  return 0xFF000000 | (x << 16) | (x << 8) | x;
}

int rgbClamp(double r, double g, double b) {
  int c(double v) => v <= 0 ? 0 : (v >= 255 ? 255 : v.round());
  return 0xFF000000 | (c(r) << 16) | (c(g) << 8) | c(b);
}
