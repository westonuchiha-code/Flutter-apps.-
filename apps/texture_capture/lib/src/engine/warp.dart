import 'dart:math' as math;
import 'dart:typed_data';

import 'pic.dart';

typedef Pt = ({double x, double y});

/// Maps the unit square onto a quad: (0,0)→p0, (1,0)→p1, (1,1)→p2,
/// (0,1)→p3 (Heckbert's square-to-quad projective mapping).
class Homography {
  Homography._(this.a, this.b, this.c, this.d, this.e, this.f, this.g, this.h);

  factory Homography.squareToQuad(List<Pt> q) {
    final (x0, y0) = (q[0].x, q[0].y);
    final (x1, y1) = (q[1].x, q[1].y);
    final (x2, y2) = (q[2].x, q[2].y);
    final (x3, y3) = (q[3].x, q[3].y);
    final dx3 = x0 - x1 + x2 - x3, dy3 = y0 - y1 + y2 - y3;
    if (dx3.abs() < 1e-9 && dy3.abs() < 1e-9) {
      return Homography._(x1 - x0, x3 - x0, x0, y1 - y0, y3 - y0, y0, 0, 0);
    }
    final dx1 = x1 - x2, dx2 = x3 - x2, dy1 = y1 - y2, dy2 = y3 - y2;
    final den = dx1 * dy2 - dx2 * dy1;
    final g = den == 0 ? 0.0 : (dx3 * dy2 - dx2 * dy3) / den;
    final h = den == 0 ? 0.0 : (dx1 * dy3 - dx3 * dy1) / den;
    return Homography._(
      x1 - x0 + g * x1,
      x3 - x0 + h * x3,
      x0,
      y1 - y0 + g * y1,
      y3 - y0 + h * y3,
      y0,
      g,
      h,
    );
  }

  final double a, b, c, d, e, f, g, h;

  Pt map(double u, double v) {
    final w = g * u + h * v + 1;
    return (x: (a * u + b * v + c) / w, y: (d * u + e * v + f) / w);
  }
}

double _dist(Pt a, Pt b) =>
    math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

/// Average side length of the quad, in source pixels.
double quadSide(List<Pt> q) =>
    (_dist(q[0], q[1]) +
        _dist(q[1], q[2]) +
        _dist(q[2], q[3]) +
        _dist(q[3], q[0])) /
    4;

/// How much longer the longer of each pair of opposite sides is (1 = shot
/// straight on).
double quadSkew(List<Pt> q) {
  double r(double a, double b) =>
      math.max(a, b) / math.max(1e-9, math.min(a, b));
  return math.max(
    r(_dist(q[0], q[1]), _dist(q[3], q[2])),
    r(_dist(q[0], q[3]), _dist(q[1], q[2])),
  );
}

/// Flattens the quad [q] (in [src] pixel coordinates; corners of pixels at
/// whole numbers) into a [w]×[h] picture.
Pic warp(Pic src, List<Pt> q, int w, int h) {
  final hm = Homography.squareToQuad(q);
  final out = Pic(w, h);
  // Supersample when the surface is bigger in the photo than the output.
  final s = math.max(1, math.min(3, (quadSide(q) / math.max(w, h)).ceil()));
  final rgbOut = Float64List(3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var r = 0.0, g = 0.0, b = 0.0;
      for (var j = 0; j < s; j++) {
        for (var i = 0; i < s; i++) {
          final p = hm.map((x + (i + 0.5) / s) / w, (y + (j + 0.5) / s) / h);
          sampleBilinear(src, p.x - 0.5, p.y - 0.5, rgbOut);
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
