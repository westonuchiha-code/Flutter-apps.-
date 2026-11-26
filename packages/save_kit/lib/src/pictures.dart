/// Pixels for save icons: the Dreamcast and GameCube formats, and our own
/// small pictures for the consoles whose saves never had icons (N64,
/// Saturn, Neo Geo). Ported from the PC's CardPictures.gd.
library;

import 'dart:math' as math;

import 'bytes.dart';
import 'model.dart';

abstract final class CardPictures {
  static const dcSide = 32, gcSide = 32, tile = 16;

  static List<int> argb4444(int v) => [
    (v >> 8 & 15) * 17,
    (v >> 4 & 15) * 17,
    (v & 15) * 17,
    (v >> 12 & 15) * 17,
  ];

  static List<int> rgb5a3(int v) {
    if (v & 0x8000 != 0) {
      return [
        (v >> 10 & 31) * 255 ~/ 31,
        (v >> 5 & 31) * 255 ~/ 31,
        (v & 31) * 255 ~/ 31,
        255,
      ];
    }
    return [
      (v >> 8 & 15) * 17,
      (v >> 4 & 15) * 17,
      (v & 15) * 17,
      (v >> 12 & 7) * 255 ~/ 7,
    ];
  }

  /// Dreamcast: 32×32, a nibble a pixel, high one first; 16 ARGB4444 colours.
  static Pixels dreamcast(List<int> b, int pixelsAt, int paletteAt) {
    final pal = [
      for (var i = 0; i < 16; i++) argb4444(Bytes.u16(b, paletteAt + i * 2)),
    ];
    final img = Pixels(dcSide, dcSide);
    var k = 0;
    for (var i = 0; i < dcSide * dcSide ~/ 2; i++) {
      final v = Bytes.u8(b, pixelsAt + i);
      for (final n in [v >> 4, v & 15]) {
        img.rgba.setRange(k, k + 4, pal[n]);
        k += 4;
      }
    }
    return img;
  }

  /// GameCube: tiles of 8×4 palette numbers (paletteAt >= 0), or of 4×4
  /// RGB5A3 colours.
  static Pixels gamecube(List<int> b, int pixelsAt, int paletteAt) {
    final pal = paletteAt >= 0
        ? [
            for (var i = 0; i < 256; i++)
              rgb5a3(Bytes.be16(b, paletteAt + i * 2)),
          ]
        : const <List<int>>[];
    final img = Pixels(gcSide, gcSide);
    final tileW = paletteAt >= 0 ? 8 : 4;
    var at = pixelsAt;
    for (var ty = 0; ty < gcSide; ty += 4) {
      for (var tx = 0; tx < gcSide; tx += tileW) {
        for (var y = 0; y < 4; y++) {
          for (var x = 0; x < tileW; x++) {
            List<int> col;
            if (paletteAt >= 0) {
              col = pal[Bytes.u8(b, at)];
              at += 1;
            } else {
              col = rgb5a3(Bytes.be16(b, at));
              at += 2;
            }
            final to = ((ty + y) * gcSide + tx + x) * 4;
            img.rgba.setRange(to, to + 4, col);
          }
        }
      }
    }
    return img;
  }

  /// Our own picture for a save with none, tinted by its name so
  /// neighbours differ.
  static Pixels standIn(String system, String name) {
    final img = Pixels(tile, tile);
    final tint = Rgb.hsv((Bytes.hash(name) % 360) / 360, 0.62, 0.95);
    final shell = CardSystems.color(system, 'edge');
    switch (system) {
      case 'N64': // a cartridge
        img.fill(2, 3, 12, 11, shell.argb);
        img.fill(3, 2, 10, 1, shell.argb);
        img.fill(4, 5, 8, 6, tint.argb);
        img.fill(5, 6, 3, 2, tint.lightened(0.5).argb);
        img.fill(5, 12, 6, 1, shell.darkened(0.4).argb);
      case 'SATURN': // a disc
        for (var y = 0; y < tile; y++) {
          for (var x = 0; x < tile; x++) {
            final d = math.sqrt((x - 7.5) * (x - 7.5) + (y - 7.5) * (y - 7.5));
            if (d < 7.2 && d > 1.5) {
              final c = d < 4
                  ? tint
                  : (x + y < 12 ? shell.lightened(0.35) : shell);
              img.fill(x, y, 1, 1, c.argb);
            }
          }
        }
      default: // a card
        img.fill(3, 1, 10, 14, shell.argb);
        img.fill(4, 3, 8, 6, tint.argb);
        img.fill(5, 4, 3, 2, tint.lightened(0.5).argb);
        for (var x = 4; x < 12; x += 2) {
          img.fill(x, 12, 1, 2, shell.darkened(0.5).argb);
        }
    }
    return img;
  }
}
