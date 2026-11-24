import 'dart:math' as math;
import 'dart:typed_data';

import 'package:photo_quilt/src/work.dart';

/// A made-up landscape: sunset sky, sun, two hills, a lake.
Picture landscape({int w = 480, int h = 320}) {
  final px = Uint32List(w * h);
  int rgb(double r, double g, double b) =>
      0xFF000000 |
      (r.round().clamp(0, 255) << 16) |
      (g.round().clamp(0, 255) << 8) |
      b.round().clamp(0, 255);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final t = y / h;
      var c = rgb(40 + 215 * t, 60 + 110 * t, 140 - 60 * t); // sky
      final sx = x - w * 0.7, sy = y - h * 0.42;
      if (sx * sx + sy * sy < (h * 0.12) * (h * 0.12)) {
        c = rgb(255, 210, 90); // sun
      }
      final hill1 = h * 0.55 + math.sin(x / w * math.pi * 1.3) * h * -0.12;
      final hill2 = h * 0.62 + math.cos(x / w * math.pi * 2.1) * h * 0.05;
      if (y > hill1) {
        c = rgb(60, 110, 70);
      }
      if (y > hill2) {
        c = rgb(40, 85, 55);
      }
      if (y > h * 0.8) {
        c = rgb(50, 90 + (x % 37 < 3 ? 40 : 0), 150); // lake
      }
      px[y * w + x] = c;
    }
  }
  return (width: w, height: h, pixels: px);
}
