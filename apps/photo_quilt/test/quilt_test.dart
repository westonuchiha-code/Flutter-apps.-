import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_quilt/src/quilt.dart';

const red = 0xFFE03C31,
    blue = 0xFF2F6FD6,
    white = 0xFFF5F5F0,
    black = 0xFF1A1A1A;
const palette = [red, blue, white, black];

/// [cols]×[rows] patches of 16 px each, painted by [paint](x, y).
({int w, int h, Uint32List px}) photo(
  int cols,
  int rows,
  int Function(int x, int y) paint,
) {
  final w = cols * 16, h = rows * 16;
  return (
    w: w,
    h: h,
    px: Uint32List.fromList([
      for (var y = 0; y < h; y++)
        for (var x = 0; x < w; x++) paint(x, y),
    ]),
  );
}

void main() {
  test('flat areas become plain patches in the nearest palette colour', () {
    final p = photo(4, 2, (x, y) => x < 32 ? 0xFFD04030 : 0xFF3070D0);
    final q = makeQuilt(
      p.w,
      p.h,
      p.px,
      const QuiltSettings(columns: 4, palette: palette),
    );
    expect(q.rows, 2);
    expect(q.at(0, 0).block, Block.plain);
    expect(q.at(0, 0).colors, [red]);
    expect(q.at(3, 1).colors, [blue]);
  });

  test('a diagonal edge becomes a half-square triangle', () {
    final p = photo(1, 1, (x, y) => x >= y ? white : black);
    final q = makeQuilt(
      p.w,
      p.h,
      p.px,
      const QuiltSettings(columns: 1, palette: palette),
    );
    expect(q.at(0, 0).block, Block.hstDown);
    expect(q.at(0, 0).colors, [white, black]);
  });

  test('detail decides whether subtle shading becomes a busier block', () {
    const darkRed = 0xFFB03028;
    const pal = [red, darkRed, blue, white, black];
    final p = photo(1, 1, (x, y) => (x < 8) == (y < 8) ? red : darkRed);
    final busy = makeQuilt(
      p.w,
      p.h,
      p.px,
      const QuiltSettings(columns: 1, palette: pal, detail: 1),
    );
    final calm = makeQuilt(
      p.w,
      p.h,
      p.px,
      const QuiltSettings(columns: 1, palette: pal, detail: 0),
    );
    expect(busy.at(0, 0).block, Block.fourPatch);
    expect(calm.at(0, 0).block, Block.plain);
  });

  test('rendering: size, seams, only palette colours (and their shades)', () {
    final p = photo(3, 2, (x, y) => x > y ? red : blue);
    const s = QuiltSettings(
      columns: 3,
      palette: palette,
      seam: 2,
      patchSize: 20,
      texture: false,
      stitches: false,
    );
    final q = makeQuilt(p.w, p.h, p.px, s);
    final img = renderQuilt(q, s);
    expect(img.width, 3 * 20 + 2);
    expect(img.height, 2 * 20 + 2);
    expect(img.pixels[0], s.seamColor);
    expect(img.pixels.toSet().difference({...palette, s.seamColor}), isEmpty);
  });
}
