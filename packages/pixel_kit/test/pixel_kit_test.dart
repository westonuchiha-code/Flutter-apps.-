import 'dart:typed_data';

import 'package:pixel_kit/pixel_kit.dart';
import 'package:test/test.dart';

const red = 0xFFFF0000, blue = 0xFF0000FF;

String show(Canvas c) => [
  for (var y = 0; y < c.h; y++)
    [for (var x = 0; x < c.w; x++) c.get(x, y) == 0 ? '.' : '#'].join(),
].join('\n');

Canvas blank(int w, int h) => Canvas(Uint32List(w * h), w, h);

void main() {
  group('colours', () {
    test('hex round trip and blending', () {
      expect(parseHex('#F80'), 0xFFFF8800);
      expect(parseHex('12345678'), 0x12345678);
      expect(parseHex('nope'), isNull);
      expect(hexOf(0xFFFF8800), '#FF8800');
      expect(blendOver(blue, red), red);
      expect(blendOver(blue, 0), blue);
      final half = blendOver(0xFF000000, 0xFFFFFFFF, 0.5);
      expect(redOf(half), closeTo(128, 1));
    });
  });

  group('drawing', () {
    test('lines join every pixel; mirror draws both sides', () {
      final c = blank(8, 4)..line(0, 0, 7, 3, red);
      expect(c.pixels.where((v) => v != 0).length, 8);
      final m = blank(6, 1)..mirrorX = true;
      m.plot(0, 0, red);
      expect(show(m), '#....#');
    });

    test('rectangles and ellipses', () {
      final r = blank(5, 4)..rect(0, 0, 4, 3, red);
      expect(show(r), '#####\n#...#\n#...#\n#####');
      final e = blank(9, 9)..ellipse(0, 0, 8, 8, red);
      final s = show(e).split('\n');
      expect(s.first.contains('#'), isTrue);
      expect(s[4][0], '#');
      expect(s[4][8], '#');
      expect(s[4][4], '.', reason: 'hollow');
      // Outline is connected: every outline pixel has an 8-neighbour.
      for (var y = 0; y < 9; y++) {
        for (var x = 0; x < 9; x++) {
          if (e.get(x, y) == 0) continue;
          var n = 0;
          for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              if ((dx != 0 || dy != 0) && e.get(x + dx, y + dy) != 0) n++;
            }
          }
          expect(n, greaterThanOrEqualTo(2), reason: 'gap at $x,$y');
        }
      }
      // Symmetric left-right and top-bottom, with a flat top (no 1-pixel nub).
      for (final (w, h) in [(9, 9), (14, 9), (16, 10)]) {
        final o = blank(w, h)..ellipse(0, 0, w - 1, h - 1, red);
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            expect(
              o.get(x, y),
              o.get(w - 1 - x, y),
              reason: '$w×$h mirror x at $x,$y',
            );
            expect(
              o.get(x, y),
              o.get(x, h - 1 - y),
              reason: '$w×$h mirror y at $x,$y',
            );
          }
        }
        expect(
          [for (var x = 0; x < w; x++) o.get(x, 0)].where((v) => v != 0).length,
          greaterThan(1),
        );
      }
      final f = blank(9, 9)..ellipse(0, 0, 8, 8, red, filled: true);
      expect(f.get(4, 4), red);
      expect(f.get(0, 0), 0);
    });

    test('flood fill stays inside walls; global fill replaces everywhere', () {
      final c = blank(6, 3)
        ..line(2, 0, 2, 2, red)
        ..fill(0, 0, blue);
      expect(show(c), '###...\n###...\n###...');
      expect(c.get(4, 1), 0);
      c.fill(5, 0, red, global: true);
      expect(c.get(5, 2), red);
      expect(c.get(0, 0), blue);
    });

    test('a selection mask limits drawing', () {
      final c = Canvas(Uint32List(16), 4, 4, mask: Rect.fromPoints(1, 1, 2, 2))
        ..rect(0, 0, 3, 3, red, filled: true);
      expect(show(c), '....\n.##.\n.##.\n....');
    });

    test('patches flip, rotate and stamp', () {
      final src = Uint32List.fromList([red, 0, 0, blue, 0, 0]); // 3x2
      final p = PixelPatch.copy(src, 3, const Rect(0, 0, 3, 2));
      expect(p.flippedX().pixels.first, 0);
      expect(p.flippedX().pixels[2], red);
      final r = p.rotated();
      expect((r.w, r.h), (2, 3));
      expect(r.pixels[0], blue);
      expect(r.pixels[1], red);
      final dst = Uint32List(9);
      p.stamp(dst, 3, 3, 1, 1);
      expect(dst[4], red);
      expect(dst[7], blue);
    });
  });

  group('sprite', () {
    test('layers flatten with visibility and opacity; merge down', () {
      final s = Sprite.blank(2, 1);
      s.cel(0, 0)[0] = blue;
      s.addLayer('top');
      s.cel(0, 1)[0] = red;
      s.cel(0, 1)[1] = red;
      expect(s.flatten(0), [red, red]);
      s.layers[1].visible = false;
      expect(s.flatten(0), [blue, 0]);
      s.layers[1]
        ..visible = true
        ..opacity = 0.5;
      expect(redOf(s.flatten(0)[0]), closeTo(128, 1));
      s.mergeDown(1);
      expect(s.layers, hasLength(1));
      expect(alphaOf(s.cel(0, 0)[1]), closeTo(128, 1));
    });

    test('frames, resize and JSON round trip', () {
      final s = Sprite.blank(3, 2)..addLayer('ink');
      s.cel(0, 1)[5] = red;
      s.addFrame();
      s.frames[1].durationMs = 250;
      s.cel(1, 0)[0] = blue;
      final back = Sprite.fromJson(s.toJson());
      expect((back.width, back.height), (3, 2));
      expect(back.layers.map((l) => l.name), ['Layer 1', 'ink']);
      expect(back.frames, hasLength(2));
      expect(back.cel(1, 1)[5], red, reason: 'frame copy kept the ink');
      expect(back.cel(1, 0)[0], blue);
      expect(back.frames[1].durationMs, 250);
      final big = s.resized(4, 3);
      expect(big.cel(0, 1)[1 * 4 + 2], red);
      expect(() => Sprite.fromJson({'kind': 'palette'}), throwsFormatException);
    });

    test('PNG export and decode', () {
      final s = Sprite.blank(2, 2);
      s.cel(0, 0).setAll(0, [red, blue, 0, 0xFF00FF00]);
      final png = spriteToPng(s, scale: 3);
      final back = decodePicture(png)!;
      expect((back.width, back.height), (6, 6));
      expect(back.pixels[0], red);
      expect(back.pixels[3], blue);
      expect(alphaOf(back.pixels[6 * 3]), 0);
      expect(back.pixels[35], 0xFF00FF00);
    });
  });

  group('palettes', () {
    test('nearest colour, JSON and GPL', () {
      final p = builtInPalettes.firstWhere(
        (p) => p.name.startsWith('Game Boy (green)'),
      );
      expect(p.colors, hasLength(4));
      expect(p.nearest(0xFF000000), rgb(0x0F380F));
      expect(p.nearest(0), 0);
      final back = Palette.fromJson(p.toJson());
      expect(back.colors, p.colors);
      final gpl = Palette.fromGpl(p.toGpl());
      expect(gpl.name, p.name);
      expect(gpl.colors, p.colors);
      expect(() => Palette.fromGpl('hello'), throwsFormatException);
      for (final b in builtInPalettes) {
        expect(b.colors, isNotEmpty);
        expect(
          b.colors.every((c) => alphaOf(c) == 255),
          isTrue,
          reason: b.name,
        );
      }
    });
  });
}
