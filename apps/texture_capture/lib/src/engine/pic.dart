import 'dart:math' as math;
import 'dart:typed_data';

/// A picture: ARGB pixels (0xAARRGGBB), row-major.
class Pic {
  Pic(this.width, this.height, [Uint32List? px])
    : px = px ?? Uint32List(width * height);

  final int width, height;
  final Uint32List px;

  int at(int x, int y) => px[y * width + x];

  /// BGRA bytes for `decodeImageFromPixels` (ARGB words are B, G, R, A in
  /// little-endian memory).
  Uint8List get bgraBytes =>
      px.buffer.asUint8List(px.offsetInBytes, px.lengthInBytes);
}

int rOf(int c) => (c >> 16) & 255;
int gOf(int c) => (c >> 8) & 255;
int bOf(int c) => c & 255;
int rgb(int r, int g, int b) => 0xFF000000 | (r << 16) | (g << 8) | b;

int clamp255(double v) => v <= 0 ? 0 : (v >= 255 ? 255 : v.round());
int rgbD(double r, double g, double b) =>
    rgb(clamp255(r), clamp255(g), clamp255(b));

double lumaOf(int c) => 0.299 * rOf(c) + 0.587 * gOf(c) + 0.114 * bOf(c);

/// Resizes a texture, treating it as tiling (samples wrap around the edges
/// so seamless textures stay seamless). Exact box averaging when shrinking
/// by a whole factor (powers of two), bilinear otherwise.
Pic resizeTile(Pic p, int w, int h) {
  if (w == p.width && h == p.height) return p;
  final out = Pic(w, h);
  if (p.width % w == 0 && p.height % h == 0) {
    final fx = p.width ~/ w, fy = p.height ~/ h, n = fx * fy;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var r = 0, g = 0, b = 0;
        for (var yy = y * fy; yy < (y + 1) * fy; yy++) {
          final row = yy * p.width;
          for (var xx = x * fx; xx < (x + 1) * fx; xx++) {
            final c = p.px[row + xx];
            r += (c >> 16) & 255;
            g += (c >> 8) & 255;
            b += c & 255;
          }
        }
        out.px[y * w + x] = rgb(
          (r + n ~/ 2) ~/ n,
          (g + n ~/ 2) ~/ n,
          (b + n ~/ 2) ~/ n,
        );
      }
    }
    return out;
  }
  // Supersample when shrinking by an odd factor.
  final s = math.max(1, math.min(6, (p.width / w).ceil()));
  final rgbOut = Float64List(3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var r = 0.0, g = 0.0, b = 0.0;
      for (var j = 0; j < s; j++) {
        for (var i = 0; i < s; i++) {
          final sx = (x + (i + 0.5) / s) * p.width / w - 0.5;
          final sy = (y + (j + 0.5) / s) * p.height / h - 0.5;
          sampleBilinear(p, sx, sy, rgbOut, wrap: true);
          r += rgbOut[0];
          g += rgbOut[1];
          b += rgbOut[2];
        }
      }
      final n = s * s;
      out.px[y * w + x] = rgbD(r / n, g / n, b / n);
    }
  }
  return out;
}

/// Bilinear sample at pixel-centre coordinates (pixel i's centre is i).
void sampleBilinear(
  Pic p,
  double x,
  double y,
  Float64List out, {
  bool wrap = false,
}) {
  final w = p.width, h = p.height;
  var x0 = x.floor(), y0 = y.floor();
  final fx = x - x0, fy = y - y0;
  var x1 = x0 + 1, y1 = y0 + 1;
  if (wrap) {
    x0 %= w;
    x1 %= w;
    y0 %= h;
    y1 %= h;
  } else {
    x0 = x0.clamp(0, w - 1);
    x1 = x1.clamp(0, w - 1);
    y0 = y0.clamp(0, h - 1);
    y1 = y1.clamp(0, h - 1);
  }
  final a = p.px[y0 * w + x0], b = p.px[y0 * w + x1];
  final c = p.px[y1 * w + x0], d = p.px[y1 * w + x1];
  final wa = (1 - fx) * (1 - fy), wb = fx * (1 - fy);
  final wc = (1 - fx) * fy, wd = fx * fy;
  out[0] = rOf(a) * wa + rOf(b) * wb + rOf(c) * wc + rOf(d) * wd;
  out[1] = gOf(a) * wa + gOf(b) * wb + gOf(c) * wc + gOf(d) * wd;
  out[2] = bOf(a) * wa + bOf(b) * wb + bOf(c) * wc + bOf(d) * wd;
}

/// Largest power of two ≤ [v] (at least 1).
int pow2Floor(num v) {
  var p = 1;
  while (p * 2 <= v) {
    p *= 2;
  }
  return p;
}
