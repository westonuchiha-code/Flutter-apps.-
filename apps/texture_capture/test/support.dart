import 'dart:math' as math;

import 'package:texture_capture/src/engine/pic.dart';
import 'package:texture_capture/src/engine/warp.dart';

/// A brick wall texture (does not tile on its own).
Pic bricks(int size, {int seed = 5}) {
  final r = math.Random(seed);
  final p = Pic(size, size);
  final bh = size / 10, bw = size / 4.3;
  final shade = <int, double>{};
  for (var y = 0; y < size; y++) {
    final row = (y / bh).floor();
    final off = row.isOdd ? bw / 2 : 0;
    for (var x = 0; x < size; x++) {
      final col = ((x + off) / bw).floor();
      final inX = (x + off) % bw, inY = y % bh;
      final mortar = inX < size / 110 || inY < size / 110;
      final n = r.nextInt(22) - 11;
      if (mortar) {
        p.px[y * size + x] = rgbD(150.0 + n, 145.0 + n, 135.0 + n);
      } else {
        final s = shade.putIfAbsent(
          row * 100 + col,
          () => 0.8 + r.nextDouble() * 0.35,
        );
        p.px[y * size + x] = rgbD(165 * s + n, 78 * s + n, 58 * s + n);
      }
    }
  }
  return p;
}

/// [tex] photographed at an angle with light falling off to one side, on a
/// grey background. Returns the photo and where the texture's corners are.
({Pic photo, List<Pt> corners}) photoOf(Pic tex, {int w = 1200, int h = 900}) {
  const corners = <Pt>[
    (x: 260, y: 120),
    (x: 1010, y: 70),
    (x: 1080, y: 840),
    (x: 170, y: 760),
  ];
  final m = Homography.squareToQuad(corners);
  // Invert the 3×3 projective matrix.
  final a = [
    [m.a, m.b, m.c],
    [m.d, m.e, m.f],
    [m.g, m.h, 1.0],
  ];
  final det =
      a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1]) -
      a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0]) +
      a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0]);
  double co(int r, int c) {
    final rows = [0, 1, 2]..remove(r);
    final cols = [0, 1, 2]..remove(c);
    final v =
        a[rows[0]][cols[0]] * a[rows[1]][cols[1]] -
        a[rows[0]][cols[1]] * a[rows[1]][cols[0]];
    return ((r + c).isEven ? v : -v) / det;
  }

  final inv = [
    for (var r = 0; r < 3; r++) [for (var c = 0; c < 3; c++) co(c, r)],
  ];
  final photo = Pic(w, h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final px = x + 0.5, py = y + 0.5;
      final ww = inv[2][0] * px + inv[2][1] * py + inv[2][2];
      final u = (inv[0][0] * px + inv[0][1] * py + inv[0][2]) / ww;
      final v = (inv[1][0] * px + inv[1][1] * py + inv[1][2]) / ww;
      final light = 0.45 + 0.75 * x / w;
      int c;
      if (u >= 0 && u < 1 && v >= 0 && v < 1) {
        c = tex
            .px[(v * tex.height).floor() * tex.width + (u * tex.width).floor()];
      } else {
        c = rgb(90, 95, 100);
      }
      photo.px[y * w + x] = rgbD(
        rOf(c) * light,
        gOf(c) * light,
        bOf(c) * light,
      );
    }
  }
  return (photo: photo, corners: corners);
}
