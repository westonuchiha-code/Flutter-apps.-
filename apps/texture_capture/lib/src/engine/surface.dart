import 'dart:math' as math;
import 'dart:typed_data';

import 'pic.dart';

/// The picture's large-scale brightness: a coarse grid of average luma
/// (about 16 cells across), lightly blurred.
class LightMap {
  LightMap(Pic p)
    : gx = 16,
      gy = math.max(1, (16 * p.height / p.width).round()) {
    cells = Float64List(gx * gy);
    final n = Int32List(gx * gy);
    for (var y = 0; y < p.height; y++) {
      final cy = y * gy ~/ p.height;
      for (var x = 0; x < p.width; x++) {
        final i = cy * gx + x * gx ~/ p.width;
        cells[i] += lumaOf(p.px[y * p.width + x]);
        n[i]++;
      }
    }
    for (var i = 0; i < cells.length; i++) {
      cells[i] /= math.max(1, n[i]);
    }
    // 3×3 blur so single dark objects count less than lighting.
    final b = Float64List(cells.length);
    for (var y = 0; y < gy; y++) {
      for (var x = 0; x < gx; x++) {
        var s = 0.0, k = 0;
        for (var j = -1; j <= 1; j++) {
          for (var i = -1; i <= 1; i++) {
            final xx = x + i, yy = y + j;
            if (xx < 0 || yy < 0 || xx >= gx || yy >= gy) continue;
            s += cells[yy * gx + xx];
            k++;
          }
        }
        b[y * gx + x] = s / k;
      }
    }
    cells = b;
    mean = cells.reduce((a, b) => a + b) / cells.length;
  }

  final int gx, gy;
  late Float64List cells;
  late double mean;

  /// Brightest part ÷ darkest part (10th and 90th percentiles).
  double get unevenness {
    final s = List<double>.of(cells)..sort();
    final lo = s[(s.length * 0.1).floor()], hi = s[(s.length * 0.9).floor()];
    return (hi + 4) / (lo + 4);
  }

  /// Smooth brightness at a pixel of a [w]×[h] picture.
  double at(int x, int y, int w, int h) {
    final fx = ((x + 0.5) / w * gx - 0.5).clamp(0.0, gx - 1.0);
    final fy = ((y + 0.5) / h * gy - 0.5).clamp(0.0, gy - 1.0);
    final x0 = fx.floor(), y0 = fy.floor();
    final x1 = math.min(x0 + 1, gx - 1), y1 = math.min(y0 + 1, gy - 1);
    final tx = fx - x0, ty = fy - y0;
    final top = cells[y0 * gx + x0] * (1 - tx) + cells[y0 * gx + x1] * tx;
    final bot = cells[y1 * gx + x0] * (1 - tx) + cells[y1 * gx + x1] * tx;
    return top * (1 - ty) + bot * ty;
  }
}

/// Evens out lighting (shadows, light falloff, a bright side) while keeping
/// the surface's own detail. [strength] 0–1.
Pic evenLighting(Pic p, double strength) {
  if (strength <= 0) return p;
  final map = LightMap(p);
  final out = Pic(p.width, p.height);
  for (var y = 0; y < p.height; y++) {
    for (var x = 0; x < p.width; x++) {
      final l = map.at(x, y, p.width, p.height);
      final gain = math
          .pow((map.mean + 2) / (l + 2), strength)
          .toDouble()
          .clamp(0.25, 4.0);
      final c = p.px[y * p.width + x];
      out.px[y * p.width + x] = rgbD(
        rOf(c) * gain,
        gOf(c) * gain,
        bOf(c) * gain,
      );
    }
  }
  return out;
}

/// Makes the picture tile without seams: near each edge it cross-fades to a
/// copy shifted by half (whose edges continue across the wrap). The blend
/// keeps contrast instead of washing it out. [blend] is the fade width as a
/// fraction of the size (0.05–0.45).
Pic makeSeamless(Pic p, double blend) {
  final b = blend.clamp(0.05, 0.45);
  final mean = Float64List(3);
  for (final c in p.px) {
    mean[0] += rOf(c);
    mean[1] += gOf(c);
    mean[2] += bOf(c);
  }
  for (var i = 0; i < 3; i++) {
    mean[i] /= p.px.length;
  }
  double weight(int i, int n) {
    final d = math.min(i + 0.5, n - i - 0.5) / (b * n);
    if (d >= 1) return 1;
    return d * d * (3 - 2 * d);
  }

  int mix(int a, int s, double w) {
    final k = 1 / math.sqrt(w * w + (1 - w) * (1 - w));
    double ch(int va, int vs, double m) =>
        m + (w * (va - m) + (1 - w) * (vs - m)) * k;
    return rgbD(
      ch(rOf(a), rOf(s), mean[0]),
      ch(gOf(a), gOf(s), mean[1]),
      ch(bOf(a), bOf(s), mean[2]),
    );
  }

  final w = p.width, h = p.height;
  final horiz = Pic(w, h);
  for (var x = 0; x < w; x++) {
    final wx = weight(x, w), sx = (x + w ~/ 2) % w;
    for (var y = 0; y < h; y++) {
      horiz.px[y * w + x] = wx >= 1
          ? p.px[y * w + x]
          : mix(p.px[y * w + x], p.px[y * w + sx], wx);
    }
  }
  final out = Pic(w, h);
  for (var y = 0; y < h; y++) {
    final wy = weight(y, h), sy = (y + h ~/ 2) % h;
    for (var x = 0; x < w; x++) {
      out.px[y * w + x] = wy >= 1
          ? horiz.px[y * w + x]
          : mix(horiz.px[y * w + x], horiz.px[sy * w + x], wy);
    }
  }
  return out;
}

double _diff(int a, int b) =>
    ((rOf(a) - rOf(b)).abs() +
        (gOf(a) - gOf(b)).abs() +
        (bOf(a) - bOf(b)).abs()) /
    3;

/// How visible the seams are when tiled: the jump across the wrapped edges
/// compared with the usual step between neighbouring pixels (≈1 = seamless).
double seamScore(Pic p) {
  final w = p.width, h = p.height;
  var inner = 0.0;
  var n = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w - 1; x++) {
      inner += _diff(p.px[y * w + x], p.px[y * w + x + 1]);
      n++;
    }
  }
  for (var y = 0; y < h - 1; y++) {
    for (var x = 0; x < w; x++) {
      inner += _diff(p.px[y * w + x], p.px[(y + 1) * w + x]);
      n++;
    }
  }
  var edge = 0.0;
  for (var y = 0; y < h; y++) {
    edge += _diff(p.px[y * w + w - 1], p.px[y * w]);
  }
  for (var x = 0; x < w; x++) {
    edge += _diff(p.px[(h - 1) * w + x], p.px[x]);
  }
  return (edge / (w + h) + 0.5) / (inner / n + 0.5);
}

/// Mean absolute Laplacian of luma on a centre crop: low = blurry.
double sharpness(Pic p) {
  final s = math.min(256, math.min(p.width, p.height));
  final ox = (p.width - s) ~/ 2, oy = (p.height - s) ~/ 2;
  double l(int x, int y) => lumaOf(p.px[(oy + y) * p.width + ox + x]);
  var sum = 0.0;
  for (var y = 1; y < s - 1; y++) {
    for (var x = 1; x < s - 1; x++) {
      sum +=
          (4 * l(x, y) - l(x - 1, y) - l(x + 1, y) - l(x, y - 1) - l(x, y + 1))
              .abs();
    }
  }
  return sum / ((s - 2) * (s - 2));
}

/// Luma mean and standard deviation, and the share of blown-out pixels.
({double mean, double std, double blown}) lumaStats(Pic p) {
  var s = 0.0, s2 = 0.0;
  var blown = 0;
  for (final c in p.px) {
    final l = lumaOf(c);
    s += l;
    s2 += l * l;
    if (rOf(c) >= 250 && gOf(c) >= 250 && bOf(c) >= 250) blown++;
  }
  final n = p.px.length;
  final mean = s / n;
  return (
    mean: mean,
    std: math.sqrt(math.max(0, s2 / n - mean * mean)),
    blown: blown / n,
  );
}
