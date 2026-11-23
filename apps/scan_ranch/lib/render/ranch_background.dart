// Pixel-art ranch scenery, generated at low resolution and drawn scaled up
// with nearest-neighbour filtering (crisp pixels, matching the sprites).
import 'dart:math' as math;
import 'dart:typed_data';

import '../model/genome.dart';

/// Fraction of the height where the grass begins (matches the simulation).
const groundTopFraction = 0.3;

/// Builds RGBA pixels for a [w]×[h] ranch background.
Uint8List ranchBackground(int w, int h, {int seed = 7}) {
  final px = Uint32List(w * h); // 0xAARRGGBB
  final r = SeededRandom(seed);
  final ground = (h * groundTopFraction).round();

  int mix(int a, int b, double t) {
    int ch(int s) =>
        (((a >> s) & 0xFF) * (1 - t) + ((b >> s) & 0xFF) * t).round();
    return 0xFF000000 | ch(16) << 16 | ch(8) << 8 | ch(0);
  }

  // Ordered dithering matrix for smooth pixel gradients.
  const bayer = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
  bool dither(int x, int y, double t) => t * 16 > bayer[(y & 3) * 4 + (x & 3)];

  void set(int x, int y, int c) {
    if (x >= 0 && y >= 0 && x < w && y < h) px[y * w + x] = c;
  }

  // Sky: banded gradient with dithered transitions.
  const skyTop = 0xFF120C24, skyBottom = 0xFF6B2347;
  for (var y = 0; y < ground; y++) {
    final t = y / ground;
    final band = (t * 5).floor() / 5;
    final next = math.min(1.0, band + 0.2);
    for (var x = 0; x < w; x++) {
      final local = (t - band) * 5;
      px[y * w + x] = mix(skyTop, skyBottom, dither(x, y, local) ? next : band);
    }
  }

  // Clouds.
  for (var i = 0; i < 3 + w ~/ 80; i++) {
    final cx = r.nextInt(w), cy = 4 + r.nextInt(math.max(1, ground ~/ 3));
    final len = 10 + r.nextInt(14);
    for (var k = 0; k < 4; k++) {
      final ox = cx + k * len ~/ 4 - len ~/ 2;
      final rad = 3 + r.nextInt(3);
      for (var y = -rad; y <= rad; y++) {
        for (var x = -rad * 2; x <= rad * 2; x++) {
          if (x * x / 4 + y * y <= rad * rad && y <= rad ~/ 2) {
            set(ox + x, cy + y, y > rad ~/ 4 ? 0xFF2A1A3A : 0xFF3A2348);
          }
        }
      }
    }
  }

  // Distant hills (two layers).
  for (final (base, amp, color, freq) in [
    (ground - 10, 6.0, 0xFF241A33, 0.05),
    (ground - 4, 4.0, 0xFF1B1527, 0.09),
  ]) {
    final phase = r.range(0, 6);
    for (var x = 0; x < w; x++) {
      final top = base - (math.sin(x * freq + phase) * amp + amp).round();
      for (var y = top; y < ground; y++) {
        set(x, y, y == top ? mix(color, 0xFFFF6A5A, 0.25) : color);
      }
    }
  }

  // Grass with dithered depth shading.
  const grassFar = 0xFF2B3A26, grassNear = 0xFF23311F, grassDark = 0xFF172113;
  for (var y = ground; y < h; y++) {
    final t = (y - ground) / (h - ground);
    for (var x = 0; x < w; x++) {
      px[y * w + x] = dither(x, y, t) ? grassNear : grassFar;
    }
  }
  // Grass tufts and flowers.
  final tufts = w * h ~/ 90;
  for (var i = 0; i < tufts; i++) {
    final x = r.nextInt(w),
        y = ground + 2 + r.nextInt(math.max(1, h - ground - 2));
    set(x, y, grassDark);
    set(x + 1, y - 1, grassDark);
    set(x + 2, y, grassDark);
  }
  const flowers = [0xFF5A5450, 0xFF4A4440, 0xFF6A3A3A, 0xFF3A4A5A];
  for (var i = 0; i < w * h ~/ 600; i++) {
    final x = r.nextInt(w),
        y = ground + 4 + r.nextInt(math.max(1, h - ground - 4));
    final c = flowers[r.nextInt(flowers.length)];
    set(x, y - 1, c);
    set(x - 1, y, c);
    set(x + 1, y, c);
    set(x, y + 1, c);
    set(x, y, 0xFF2A2522);
  }

  // Wooden fence along the horizon.
  const wood = 0xFF4A3426, woodDark = 0xFF2A1C14;
  for (var x = 0; x < w; x++) {
    for (final ry in [ground - 5, ground - 2]) {
      set(x, ry, wood);
      set(x, ry + 1, woodDark);
    }
    if (x % 14 == 3) {
      for (var y = ground - 8; y <= ground + 1; y++) {
        set(x, y, woodDark);
        set(x + 1, y, wood);
        set(x + 2, y, woodDark);
      }
    }
  }

  // A tree at one side.
  final treeX = (w * 0.86).round(), treeY = ground + 1;
  for (var y = treeY - 10; y <= treeY + 2; y++) {
    set(treeX, y, 0xFF2A1C14);
    set(treeX + 1, y, 0xFF1A120C);
  }
  for (var y = -9; y <= 7; y++) {
    for (var x = -9; x <= 9; x++) {
      if (x * x + y * y * 1.4 <= 80) {
        final shade = x + y > 4
            ? 0xFF121A12
            : (x + y < -6 ? 0xFF2A3A24 : 0xFF1C281A);
        set(treeX + x, treeY - 16 + y, shade);
      }
    }
  }

  final out = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    final c = px[i];
    out[i * 4] = (c >> 16) & 0xFF;
    out[i * 4 + 1] = (c >> 8) & 0xFF;
    out[i * 4 + 2] = c & 0xFF;
    out[i * 4 + 3] = 255;
  }
  return out;
}
