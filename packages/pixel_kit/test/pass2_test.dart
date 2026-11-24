import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pixel_kit/pixel_kit.dart';
import 'package:test/test.dart';

const red = 0xFFFF0000, blue = 0xFF0000FF, green = 0xFF00FF00;

void main() {
  test('median cut finds the main colours of a picture', () {
    final px = Uint32List.fromList([
      ...List.filled(60, red),
      ...List.filled(40, blue),
      0,
      0,
    ]);
    final colors = medianCut(px, 2);
    expect(colors, unorderedEquals([red, blue]));
    expect(medianCut(Uint32List(4), 4), isEmpty, reason: 'all transparent');
    final p = paletteFromPixels(px, 8);
    expect(p.colors.length, lessThanOrEqualTo(8));
  });

  test('snapping to a palette, with and without dither', () {
    final pal = Palette('bw', [0xFF000000, 0xFFFFFFFF]);
    final grey = Uint32List(64)..fillRange(0, 64, 0xFF808080);
    final flat = reduceToPalette(grey, 8, pal);
    expect(flat.toSet().length, 1, reason: 'no dither: one flat colour');
    final dithered = reduceToPalette(grey, 8, pal, dither: true, strength: 255);
    expect(dithered.toSet(), {
      0xFF000000,
      0xFFFFFFFF,
    }, reason: 'ordered dither mixes both');
    expect(reduceToPalette(Uint32List(1), 1, pal), [
      0,
    ], reason: 'transparent stays transparent');
  });

  test('pictures shrink to fit, keeping their shape', () {
    final pic = (
      width: 100,
      height: 50,
      pixels: Uint32List(5000)..fillRange(0, 5000, red),
    );
    final f = fitPicture(pic, 32, 32);
    expect((f.width, f.height), (32, 16));
    expect(f.pixels.every((v) => v == red), isTrue);
    final small = fitPicture(
      (width: 4, height: 4, pixels: Uint32List(16)),
      32,
      32,
    );
    expect(small.width, 4, reason: 'never enlarged');
  });

  test('tile sets drop duplicates; maps render, fill and round trip', () {
    // 4x2 picture of two 2x2 tiles: red, then red again.
    final px = Uint32List(8)..fillRange(0, 8, red);
    final set = TileSet.cut(px, 4, 2, 2);
    expect(set.length, 2, reason: 'empty tile + one red tile');
    expect(TileSet.cut(px, 4, 2, 2, keepDuplicates: true).length, 3);
    final map = TileMap(3, 2, set)..set(0, 0, 1);
    map.fill(1, 1, 1);
    expect(
      map.cells.where((c) => c == 1).length,
      6,
      reason: 'fill spread over empty cells',
    );
    map.set(2, 1, 0);
    final pixels = map.render();
    expect(pixels.length, 6 * 4);
    expect(pixels[0], red);
    expect(pixels[3 * 6 + 5], 0);
    final back = TileMap.fromJson(map.toJson());
    expect(back.cells, map.cells);
    expect(back.tileSet.tiles[1], set.tiles[1]);
    expect(() => TileMap.fromJson({'kind': 'palette'}), throwsFormatException);
  });

  test('sprite sheets lay frames out in a grid', () {
    final s = Sprite.blank(2, 2);
    s.cel(0, 0)[0] = red;
    s.addFrame(copy: false);
    s.cel(1, 0)[0] = blue;
    s.addFrame(copy: false);
    s.cel(2, 0)[0] = green;
    final row = spriteSheet(s);
    expect((row.width, row.height), (6, 2));
    expect([row.pixels[0], row.pixels[2], row.pixels[4]], [red, blue, green]);
    final grid = spriteSheet(s, columns: 2);
    expect((grid.width, grid.height), (4, 4));
    expect(grid.pixels[2 * 4], green);
  });

  test('GIFs keep exact colours, frame timing and transparency', () {
    final s = Sprite.blank(3, 2);
    s.cel(0, 0).setAll(0, [red, blue, 0, 0x11223344 | 0xFF000000, green, red]);
    s.frames[0].durationMs = 200;
    s.addFrame(copy: false);
    s.cel(1, 0)[0] = blue;
    s.frames[1].durationMs = 50;
    final gif = spriteToGif(s, scale: 2);
    final anim = img.decodeGif(gif)!;
    expect(anim.numFrames, 2);
    expect((anim.width, anim.height), (6, 4));
    int at(img.Image f, int x, int y) {
      final p = f.getPixel(x, y);
      return argb(p.a.toInt(), p.r.toInt(), p.g.toInt(), p.b.toInt());
    }

    final f0 = anim.frames[0];
    expect(at(f0, 0, 0), red);
    expect(at(f0, 2, 0), blue);
    expect(at(f0, 0, 2), 0xFF223344);
    expect(alphaOf(at(f0, 4, 0)), 0);
    expect(f0.frameDuration, 200);
    expect(anim.frames[1].frameDuration, 50);
    expect(at(anim.frames[1], 0, 0), blue);
  });
}
