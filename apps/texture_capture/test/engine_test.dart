import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:texture_capture/src/engine/formats.dart';
import 'package:texture_capture/src/engine/pic.dart';
import 'package:texture_capture/src/engine/pipeline.dart';
import 'package:texture_capture/src/engine/surface.dart';
import 'package:texture_capture/src/engine/warp.dart';

/// A bumpy, colourful, non-tiling test surface.
Pic noise(int w, int h, {int seed = 3, int grain = 40}) {
  final r = math.Random(seed);
  final p = Pic(w, h);
  for (var i = 0; i < p.px.length; i++) {
    final x = i % w, y = i ~/ w;
    final v =
        120 + 60 * math.sin(x / 7.0) * math.cos(y / 11.0) + r.nextInt(grain);
    p.px[i] = rgbD(v, v * 0.8 + x * 0.1, v * 0.6 + y * 0.1);
  }
  return p;
}

List<Pt> full(Pic p) => [
  (x: 0, y: 0),
  (x: p.width.toDouble(), y: 0),
  (x: p.width.toDouble(), y: p.height.toDouble()),
  (x: 0, y: p.height.toDouble()),
];

void main() {
  test('homography maps the square onto the quad', () {
    const q = <Pt>[
      (x: 10, y: 20),
      (x: 200, y: 5),
      (x: 220, y: 180),
      (x: 0, y: 150),
    ];
    final h = Homography.squareToQuad(q);
    for (final (u, v, i) in [
      (0.0, 0.0, 0),
      (1.0, 0.0, 1),
      (1.0, 1.0, 2),
      (0.0, 1.0, 3),
    ]) {
      final p = h.map(u, v);
      expect(p.x, closeTo(q[i].x, 1e-6));
      expect(p.y, closeTo(q[i].y, 1e-6));
    }
  });

  test('flattening undoes a perspective view', () {
    // A checkerboard of 8 squares across, seen in perspective.
    const n = 8;
    int board(double u, double v) =>
        ((u * n).floor() + (v * n).floor()).isEven ? 0xFFFFFFFF : 0xFF000000;
    const q = <Pt>[
      (x: 60, y: 30),
      (x: 260, y: 40),
      (x: 300, y: 230),
      (x: 20, y: 210),
    ];
    // Render it by inverting the mapping numerically: for each photo pixel
    // find (u, v) with a fine search over the homography.
    final h = Homography.squareToQuad(q);
    final photo = Pic(320, 260);
    photo.px.fillRange(0, photo.px.length, 0xFF808080);
    const steps = 800;
    for (var j = 0; j < steps; j++) {
      for (var i = 0; i < steps; i++) {
        final u = (i + 0.5) / steps, v = (j + 0.5) / steps;
        final p = h.map(u, v);
        photo.px[p.y.floor() * 320 + p.x.floor()] = board(u, v);
      }
    }
    final flat = warp(photo, q, 64, 64);
    var wrong = 0;
    for (var y = 0; y < 64; y++) {
      for (var x = 0; x < 64; x++) {
        // Skip pixels on square borders (blended).
        if (x % 8 == 0 || x % 8 == 7 || y % 8 == 0 || y % 8 == 7) continue;
        final want = board((x + 0.5) / 64, (y + 0.5) / 64) == 0xFFFFFFFF;
        if ((lumaOf(flat.at(x, y)) > 128) != want) wrong++;
      }
    }
    expect(wrong, 0);
  });

  test('even lighting removes a light gradient but keeps detail', () {
    final base = noise(256, 256);
    final lit = Pic(256, 256);
    for (var i = 0; i < lit.px.length; i++) {
      final g = 0.35 + 0.65 * (i % 256) / 255; // dark left, bright right
      final c = base.px[i];
      lit.px[i] = rgbD(rOf(c) * g, gOf(c) * g, bOf(c) * g);
    }
    expect(LightMap(lit).unevenness, greaterThan(2));
    final fixed = evenLighting(lit, 1);
    expect(LightMap(fixed).unevenness, lessThan(1.25));
    expect(lumaStats(fixed).std, greaterThan(lumaStats(base).std * 0.6));
  });

  test('make seamless removes the seams', () {
    final p = noise(128, 128, grain: 6);
    expect(seamScore(p), greaterThan(2.5));
    final s = makeSeamless(p, 0.2);
    expect(seamScore(s), lessThan(1.5));
    // Contrast is kept (no washed-out blend).
    expect(lumaStats(s).std, greaterThan(lumaStats(p).std * 0.8));
    // Shrinking keeps it seamless.
    expect(seamScore(resizeTile(s, 32, 32)), lessThan(1.5));
  });

  test('console formats stay within the hardware limits', () {
    final master = makeSeamless(noise(256, 256), 0.2);
    for (final console in consoles) {
      for (final f in console.formats) {
        for (final dither in [false, true]) {
          final out = buildConsole(
            master,
            f.format,
            f.defaultSize,
            dither: dither,
          );
          final why = '${console.name} ${f.format.label} dither=$dither';
          expect(out.width, f.defaultSize, reason: why);
          final colors = out.px.toSet();
          switch (f.format.kind) {
            case FormatKind.clut:
            case FormatKind.grey:
              expect(
                colors.length,
                lessThanOrEqualTo(f.format.colors),
                reason: why,
              );
            case FormatKind.cmpr:
              _blocks(
                out,
                4,
                (b) =>
                    expect(b.toSet().length, lessThanOrEqualTo(4), reason: why),
              );
            case FormatKind.vq:
              final blocks = <String>{};
              _blocks(out, 2, (b) => blocks.add(b.join(',')));
              expect(blocks.length, lessThanOrEqualTo(256), reason: why);
            case FormatKind.direct:
              break;
          }
          // CMPR's in-between colours are interpolated by the hardware.
          if (f.format.bits != ColorBits.rgb888 &&
              f.format.kind != FormatKind.cmpr) {
            for (final c in colors) {
              expect(quantizeColor(c, f.format.bits), c, reason: why);
            }
          }
          // N64: the texture (and palette) must fit 4 KB of TMEM.
          if (console.id == 'n64') {
            for (final s in f.sizes) {
              expect(
                f.format.bytesFor(s, s),
                lessThanOrEqualTo(4096),
                reason: why,
              );
            }
          }
        }
      }
    }
  });

  test('compressed formats still look like the picture', () {
    final master = noise(128, 128);
    double err(Pic a) {
      var e = 0.0;
      for (var i = 0; i < a.px.length; i++) {
        e += (lumaOf(a.px[i]) - lumaOf(master.px[i])).abs();
      }
      return e / a.px.length;
    }

    expect(err(encodeDxt1(master)), lessThan(12));
    expect(err(encodeVq(master)), lessThan(16));
  });

  test('photo checks', () {
    final good = noise(1200, 1200);
    final s = MasterSettings(corners: full(good), size: 1024);
    final r = buildMaster(good, s);
    expect(r.advice.where((a) => a.serious), isEmpty);

    // Small, dark and blurry.
    final dark = Pic(200, 200);
    for (var i = 0; i < dark.px.length; i++) {
      dark.px[i] = rgb(20, 20, 22);
    }
    final bad = buildMaster(
      dark,
      MasterSettings(corners: full(dark), size: 1024),
    );
    final titles = bad.advice.map((a) => a.title).toList();
    expect(titles, containsAll(['Soft at 1024', 'Too dark', 'Very plain']));

    // Steep angle.
    final steep = checkPhoto(
      good,
      MasterSettings(
        corners: const [
          (x: 400, y: 0),
          (x: 800, y: 0),
          (x: 1200, y: 1200),
          (x: 0, y: 1200),
        ],
        size: 512,
      ),
      good,
      good,
    );
    expect(steep.map((a) => a.title), contains('Steep angle'));
  });

  test('memory sizes', () {
    expect(clut4ps1.bytesFor(128, 128), 8192 + 32);
    expect(cmpr.bytesFor(256, 256), 32768);
    expect(vq.bytesFor(256, 256), 16384 + 2048);
    expect(formatBytes(8224), '8.0 KB');
  });
}

void _blocks(Pic p, int n, void Function(List<int>) f) {
  for (var by = 0; by < p.height; by += n) {
    for (var bx = 0; bx < p.width; bx += n) {
      f([
        for (var y = 0; y < n; y++)
          for (var x = 0; x < n; x++) p.at(bx + x, by + y),
      ]);
    }
  }
}
