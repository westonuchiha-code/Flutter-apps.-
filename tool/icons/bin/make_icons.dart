// Draws every app's launcher icon as 16×16 pixel art with pixel_kit (the
// engine of Pixel Forge) and installs it:
//   apps/<app>/icon/icon.pixel_sprite.json   the Pixel Forge sprite (edit it there)
//   apps/<app>/icon/icon.png                 16×16, and icon_256.png (preview)
//   android/app/src/main/res/mipmap-*/ic_launcher.png         older Androids
//   android/.../mipmap-anydpi-v26/ic_launcher.xml + foreground  adaptive icon
//   windows/runner/resources/app_icon.ico    16, 32, 48, 256
// Run from the repo root:  dart run tool/icons/bin/make_icons.dart [app ...]
// A new app needs an entry in `icons` below (CLAUDE.md: every app gets one).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pixel_kit/pixel_kit.dart';

const k = 0xFF16161D; // outline
const w = 0xFFF4F4F4;

/// Tile colour and the glyph, drawn on a 16×16 canvas (keep to 2..13).
typedef Art = (int tile, void Function(Canvas c) glyph);

final icons = <String, Art>{
  'ambience_machine': (
    0xFF3B2A6B,
    (c) {
      // A crescent moon and stars.
      c.ellipse(3, 3, 12, 12, 0xFFF4D35E, filled: true);
      c.ellipse(6, 2, 14, 10, 0, filled: true);
      for (final (x, y) in [(11, 11), (12, 4), (9, 7)]) {
        c.plot(x, y, w);
      }
      c.plot(4, 11, 0xFFC9A227);
      c.plot(5, 12, 0xFFC9A227);
    },
  ),
  'chip_cam': (
    0xFF1F7A7A,
    (c) {
      // A chunky retro camera with a red light.
      c.rect(2, 5, 13, 12, 0xFF3A3A48, filled: true);
      c.rect(4, 3, 7, 5, 0xFF3A3A48, filled: true);
      c.rect(2, 7, 13, 7, 0xFF8A8A9A, filled: true);
      c.ellipse(5, 6, 10, 11, 0xFF101018, filled: true);
      c.ellipse(6, 7, 9, 10, 0xFF4A9AE0, filled: true);
      c.plot(7, 8, w);
      c.plot(12, 6, 0xFFE04A4A);
    },
  ),
  'controller_lab': (
    0xFF1E4664,
    (c) {
      // A Wii U Pro (sticks high, d-pad and buttons below) with one
      // button lit up in the test's blue.
      grid(
        c,
        2,
        2,
        [
          '..gg....gg..',
          '.wwwwwwwwww.',
          'wwkwwwwwwkww',
          'wkokwwwwkokw',
          'wwkwwppwwkww',
          'wwwwwwwwwwww',
          'wwwwdwwwbwww',
          'wwwdddwbwcww',
          'wwwwdwwwbwww',
          'wwww....wwww',
          '.ww......ww.',
        ],
        {
          'w': 0xFFF1F1F3,
          'g': 0xFFB9BAC2,
          'k': 0xFF2A2B31,
          'o': 0xFF8A8B94,
          'p': 0xFF8A8B94,
          'd': 0xFF3A3B42,
          'b': 0xFF3A3B42,
          'c': 0xFF29B6F6,
        },
      );
    },
  ),
  'crt_tv': (
    0xFF2F6B3A,
    (c) {
      // A wood-grain CRT set with rabbit ears, showing colour bars.
      c.line(7, 4, 5, 2, 0xFFC8CCD4);
      c.line(8, 4, 10, 2, 0xFFC8CCD4);
      c.rect(2, 5, 13, 13, 0xFF9A6234, filled: true);
      c.line(2, 13, 13, 13, 0xFF6E4222);
      c.rect(3, 6, 10, 12, 0xFF22222C, filled: true);
      const bars = [
        0xFFE8E8E8,
        0xFFE8D820,
        0xFF20D0E0,
        0xFF30C040,
        0xFFD040C8,
        0xFFE03830,
      ];
      for (var i = 0; i < bars.length; i++) {
        c.line(4 + i, 7, 4 + i, 10, bars[i]);
      }
      c.line(4, 11, 9, 11, 0xFF2840C8);
      c.plot(11, 7, 0xFFE8D8A0);
      c.plot(12, 7, 0xFFE8D8A0);
      for (final y in [9, 11]) {
        c.line(11, y, 12, y, 0xFF5A3418);
      }
    },
  ),
  'dev_dashboard': (
    0xFF2E3A4E,
    (c) {
      // A screen with a bar chart and a green tick.
      c.rect(2, 3, 13, 11, 0xFFD8DEE8, filled: true);
      c.rect(3, 4, 12, 10, 0xFF101826, filled: true);
      c.rect(4, 8, 5, 9, 0xFF4EC06A, filled: true);
      c.rect(7, 6, 8, 9, 0xFFF2B51C, filled: true);
      c.rect(10, 5, 11, 9, 0xFF4A9AE0, filled: true);
      c.rect(6, 12, 9, 13, 0xFFD8DEE8, filled: true);
    },
  ),
  'field_recorder': (
    0xFFB83A3A,
    (c) {
      // A microphone on a stand.
      c.ellipse(5, 2, 10, 9, 0xFFC8CCD4, filled: true);
      c.line(6, 4, 9, 4, 0xFF8A8E98);
      c.line(6, 6, 9, 6, 0xFF8A8E98);
      c.line(4, 7, 4, 9, w);
      c.line(11, 7, 11, 9, w);
      c.line(5, 10, 10, 10, w);
      c.line(7, 11, 8, 11, w);
      c.rect(5, 12, 10, 13, w, filled: true);
    },
  ),
  'lab3d': (
    0xFF2F6B3A,
    (c) {
      // An isometric cube: light top, mid left, dark right.
      grid(
        c,
        2,
        2,
        const [
          '.....TT.....',
          '...TTTTTT...',
          '.TTTTTTTTTT.',
          'LLTTTTTTTTRR',
          'LLLLTTTTRRRR',
          'LLLLLLRRRRRR',
          'LLLLLLRRRRRR',
          'LLLLLLRRRRRR',
          'LLLLLLRRRRRR',
          '.LLLLLRRRRR.',
          '...LLLRRR...',
          '.....LR.....',
        ],
        const {'T': 0xFFB8F0A0, 'L': 0xFF6ABF5A, 'R': 0xFF3E8A3A},
      );
    },
  ),
  'lofi_video': (
    0xFFD9822B,
    (c) {
      // A film clapperboard.
      c.rect(2, 7, 13, 13, 0xFF22222C, filled: true);
      c.rect(2, 4, 13, 6, w, filled: true);
      for (var x = 3; x <= 12; x += 3) {
        c.line(x, 4, x + 1, 6, 0xFF22222C);
      }
      c.line(4, 9, 11, 9, 0xFF6A6A78);
      c.line(4, 11, 9, 11, 0xFF6A6A78);
    },
  ),
  'optical_theremin': (
    0xFF2B3D8C,
    (c) {
      // A light bulb sending out a sound wave.
      c.ellipse(2, 2, 9, 9, 0xFFFFE680, filled: true);
      c.rect(4, 10, 7, 12, 0xFFB8BCC8, filled: true);
      c.plot(5, 4, w);
      c.plot(4, 5, w);
      for (final (x, y) in [
        (10, 7),
        (11, 6),
        (12, 7),
        (13, 8),
        (11, 8),
        (12, 9),
      ]) {
        c.plot(x, y, 0xFF80E0FF);
      }
    },
  ),
  'photo_quilt': (
    0xFFC94C7C,
    (c) {
      // Four patches with stitches.
      c.rect(2, 2, 7, 7, 0xFFF2D06A, filled: true);
      c.rect(8, 2, 13, 7, 0xFF5AB0D8, filled: true);
      c.rect(2, 8, 7, 13, 0xFF6AC07A, filled: true);
      c.rect(8, 8, 13, 13, 0xFFF29A6A, filled: true);
      for (var i = 2; i <= 13; i += 2) {
        c.plot(i, 7, w);
        c.plot(7, i, w);
      }
    },
  ),
  'pixel_forge': (
    0xFFE0A82E,
    (c) {
      // A pencil drawing a row of coloured pixels.
      grid(
        c,
        2,
        2,
        const [
          '.........EE.',
          '........EEEE',
          '.......RREEE',
          '......RRRRE.',
          '.....RRRRR..',
          '....RRRRR...',
          '...WRRRR....',
          '..WWWRR.....',
          '..WWWW......',
          '.DWW........',
          '............',
          'BB.GG.PP....',
        ],
        const {
          'E': 0xFFF0A0B0,
          'R': 0xFFD84A3A,
          'W': 0xFFF0D0A0,
          'D': 0xFF22222C,
          'B': 0xFF4A9AE0,
          'G': 0xFF4EC06A,
          'P': 0xFFB050C0,
        },
      );
    },
  ),
  'pokeville_app': (
    0xFF5AA84A,
    (c) {
      // Two little houses (the "ville") and a red-and-white ball.
      for (final x in [0, 10]) {
        c.rect(x + 1, 4, x + 5, 8, 0xFFF2E6C8, filled: true);
        c.line(x, 3, x + 6, 3, 0xFFC0603A);
        c.line(x + 1, 2, x + 5, 2, 0xFFC0603A);
        c.line(x + 2, 1, x + 4, 1, 0xFFC0603A);
        c.rect(x + 3, 6, x + 3, 8, 0xFF6A4A3A, filled: true);
      }
      c.ellipse(4, 7, 11, 14, 0xFF22222C, filled: true);
      c.ellipse(5, 8, 10, 13, 0xFFE8ECF4, filled: true);
      for (var y = 8; y <= 10; y++) {
        for (var x = 5; x <= 10; x++) {
          if (c.pixels[y * c.w + x] == 0xFFE8ECF4) {
            c.plot(x, y, 0xFFE5483C);
          }
        }
      }
      c.line(5, 10, 10, 10, 0xFF22222C);
      c.rect(7, 9, 8, 11, 0xFF22222C, filled: true);
      c.plot(7, 10, 0xFFE8ECF4);
    },
  ),
  'puppet_stage': (
    0xFF7A1F2A,
    (c) {
      // Stage curtains and a little figure.
      c.rect(2, 2, 13, 3, 0xFFD8B04A, filled: true);
      c.rect(2, 4, 4, 13, 0xFFC0303A, filled: true);
      c.rect(11, 4, 13, 13, 0xFFC0303A, filled: true);
      c.rect(7, 6, 8, 7, 0xFFF0C8A8, filled: true);
      c.rect(6, 8, 9, 10, 0xFF4A7AD0, filled: true);
      c.rect(6, 11, 6, 12, 0xFF2E3440, filled: true);
      c.rect(9, 11, 9, 12, 0xFF2E3440, filled: true);
      c.line(5, 13, 10, 13, 0xFF8A5A30);
    },
  ),
  'sa_companion': (
    0xFFE07A30,
    (c) {
      // A palm tree in front of a setting sun.
      c.ellipse(5, 3, 12, 10, 0xFFFFD25A, filled: true);
      c.rect(4, 10, 13, 13, 0xFF3A2A50, filled: true);
      c.line(6, 5, 7, 12, 0xFF6A4020);
      c.line(7, 5, 8, 12, 0xFF6A4020);
      c.line(3, 5, 6, 3, 0xFF2E8A3A);
      c.line(6, 3, 10, 5, 0xFF2E8A3A);
      c.line(6, 4, 3, 7, 0xFF2E8A3A);
      c.line(7, 4, 11, 7, 0xFF2E8A3A);
    },
  ),
  'sample_pad': (
    0xFF1E2A50,
    (c) {
      // A 4×4 grid of lit pads.
      const cols = [0xFFE04A6A, 0xFF4ED0E0, 0xFFF2B51C, 0xFF7AE05A];
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 4; x++) {
          final col = (x + y) % 3 == 0 ? cols[(x + 2 * y) % 4] : 0xFF5A6490;
          c.rect(2 + x * 3, 2 + y * 3, 3 + x * 3, 3 + y * 3, col, filled: true);
        }
      }
    },
  ),
  'save_manager': (
    0xFF3B2E9E,
    (c) {
      // A memory card with a rainbow label (the PC menu's paint) and gold contacts.
      c.rect(3, 1, 12, 14, 0xFF16161E, filled: true);
      c.rect(4, 2, 11, 13, 0xFF3A3C4C, filled: true);
      c.line(12, 2, 12, 13, 0xFF56586C);
      const paint = [
        0xFFE5483C,
        0xFFF2B51C,
        0xFF3BB54A,
        0xFF4A7AE0,
        0xFFB04AE0,
      ];
      for (var i = 0; i < 5; i++) {
        c.line(5, 3 + i, 10, 3 + i, paint[i]);
      }
      c.rect(5, 9, 10, 10, 0xFFE8ECF4, filled: true);
      for (var x = 5; x <= 10; x += 2) {
        c.plot(x, 12, 0xFFE0B040);
      }
    },
  ),
  'scan_ranch': (
    0xFF3E7A2E,
    (c) {
      // A barcode with horns and eyes: a monster to raise.
      c.rect(3, 5, 12, 13, w, filled: true);
      for (final x in [4, 5, 7, 9, 10]) {
        c.line(x, 9, x, 12, 0xFF22222C);
      }
      c.plot(5, 6, 0xFF22222C);
      c.plot(10, 6, 0xFF22222C);
      c.line(6, 7, 9, 7, 0xFFE05A6A);
      c.line(3, 2, 4, 4, 0xFFF2D06A);
      c.line(12, 2, 11, 4, 0xFFF2D06A);
    },
  ),
  'sound_lab': (
    0xFF1A7A8C,
    (c) {
      // A flask with a sine wave inside.
      c.rect(6, 2, 9, 5, 0xFFD8E8F0, filled: true);
      c.ellipse(3, 5, 12, 13, 0xFFD8E8F0, filled: true);
      c.ellipse(4, 8, 11, 12, 0xFF5AE0B0, filled: true);
      for (final (x, y) in [
        (4, 9),
        (5, 8),
        (6, 8),
        (7, 9),
        (8, 10),
        (9, 10),
        (10, 9),
        (11, 8),
      ]) {
        c.plot(x, y, w);
      }
    },
  ),
  'speech_chip_lab': (
    0xFF6A3AA0,
    (c) {
      // A speech bubble holding a chip.
      c.rect(2, 2, 13, 10, w, filled: true);
      c.line(4, 11, 4, 13, w);
      c.plot(5, 11, w);
      c.rect(5, 4, 10, 8, 0xFF2E3440, filled: true);
      for (var x = 5; x <= 10; x += 2) {
        c.plot(x, 3, 0xFFB8BCC8);
        c.plot(x, 9, 0xFFB8BCC8);
      }
      c.plot(6, 5, 0xFFF2B51C);
    },
  ),
  'sprite_pet': (
    0xFF4A90D0,
    (c) {
      // A happy slime.
      c.ellipse(2, 4, 13, 14, 0xFF6AE07A, filled: true);
      c.rect(2, 11, 13, 13, 0xFF6AE07A, filled: true);
      c.plot(5, 8, 0xFF22222C);
      c.plot(10, 8, 0xFF22222C);
      c.line(6, 10, 9, 10, 0xFF22222C);
      c.plot(4, 6, w);
      c.plot(5, 5, w);
      c.line(2, 13, 13, 13, 0xFF3EA04A);
    },
  ),
  'starter_app': (
    0xFF5A5F6E,
    (c) {
      // A star.
      c.rect(7, 2, 8, 13, 0xFFF2D06A, filled: true);
      c.rect(2, 6, 13, 7, 0xFFF2D06A, filled: true);
      c.rect(4, 5, 11, 10, 0xFFF2D06A, filled: true);
      c.line(4, 13, 6, 10, 0xFFF2D06A);
      c.line(11, 13, 9, 10, 0xFFF2D06A);
    },
  ),
  'texture_capture': (
    0xFF7A4A2E,
    (c) {
      // Bricks inside a camera viewfinder.
      for (var y = 4; y <= 11; y += 2) {
        c.rect(4, y, 11, y, 0xFFC0603A, filled: true);
        c.plot(y % 4 == 0 ? 6 : 8, y, 0xFFE0C0A0);
        c.line(4, y + 1, 11, y + 1, 0xFFE0C0A0);
      }
      for (final (x, y, dx, dy) in [
        (2, 2, 1, 1),
        (13, 2, -1, 1),
        (2, 13, 1, -1),
        (13, 13, -1, -1),
      ]) {
        c.line(x, y, x + 2 * dx, y, w);
        c.line(x, y, x, y + 2 * dy, w);
      }
    },
  ),
  'touch_synth': (
    0xFFB0307A,
    (c) {
      // Piano keys.
      c.rect(2, 4, 13, 13, w, filled: true);
      for (final x in [4, 7, 10, 13]) {
        c.line(x, 4, x, 13, 0xFF9A9AA8);
      }
      for (final x in [3, 6, 9, 12]) {
        c.rect(x, 4, x + 1, 9, 0xFF22222C, filled: true);
      }
      c.line(13, 4, 13, 13, w);
    },
  ),
  'vista': (
    0xFF3A8AD8,
    (c) {
      // Mountains with snow and a sun.
      c.ellipse(9, 2, 12, 5, 0xFFFFE680, filled: true);
      for (var i = 0; i < 6; i++) {
        c.line(6 - i, 5 + i, 6 + i, 5 + i, 0xFF5A6A80);
      }
      for (var i = 0; i < 4; i++) {
        c.line(10 - i, 8 + i, 10 + i, 8 + i, 0xFF3E8A4A);
      }
      c.line(6, 5, 6, 5, w);
      c.line(5, 6, 7, 6, w);
      c.rect(2, 12, 13, 13, 0xFF3E8A4A, filled: true);
    },
  ),
  'waveform_painter': (
    0xFF7AA02E,
    (c) {
      // A brush painting a wave.
      for (final (x, y) in [
        (2, 9),
        (3, 8),
        (4, 7),
        (5, 7),
        (6, 8),
        (7, 9),
        (8, 10),
        (9, 10),
        (10, 9),
      ]) {
        c.rect(x, y, x, y + 1, 0xFFF0E050, filled: true);
      }
      c.line(10, 8, 13, 2, 0xFF8A5A30);
      c.line(11, 8, 13, 4, 0xFF8A5A30);
      c.rect(10, 8, 11, 9, 0xFFC8CCD4, filled: true);
      c.plot(10, 10, 0xFFF0E050);
    },
  ),
  'xmb_frontend': (
    0xFF1F55B5,
    (c) {
      // A gamepad (and the XMB's blue).
      c.rect(2, 6, 13, 11, 0xFFE8ECF4, filled: true);
      c.rect(3, 12, 5, 13, 0xFFE8ECF4, filled: true);
      c.rect(10, 12, 12, 13, 0xFFE8ECF4, filled: true);
      c.line(4, 8, 6, 8, 0xFF22222C);
      c.line(5, 7, 5, 9, 0xFF22222C);
      c.plot(10, 7, 0xFF3BB54A);
      c.plot(11, 8, 0xFFE5483C);
      c.plot(9, 8, 0xFF4A7AE0);
      c.plot(10, 9, 0xFFF2B51C);
      c.line(4, 4, 11, 4, 0xFF8AB8F0);
    },
  ),
};

/// Plots [rows] (one character per pixel, '.' = nothing) at [x0], [y0].
void grid(Canvas c, int x0, int y0, List<String> rows, Map<String, int> pal) {
  for (var y = 0; y < rows.length; y++) {
    for (var x = 0; x < rows[y].length; x++) {
      final col = pal[rows[y][x]];
      if (col != null) c.plot(x0 + x, y0 + y, col);
    }
  }
}

int _shade(int c, double f) {
  int ch(int v) => (v * f).round().clamp(0, 255);
  return 0xFF000000 |
      (ch(redOf(c)) << 16) |
      (ch(greenOf(c)) << 8) |
      ch(blueOf(c));
}

/// The icon as a Pixel Forge sprite: layer 1 the tile, layer 2 the glyph
/// with its outline.
Sprite build(Art art) {
  final (tile, glyph) = art;
  final s = Sprite.blank(16, 16);
  final t = Canvas(s.frames.first.cels.first, 16, 16);
  t.rect(0, 0, 15, 15, _shade(tile, 0.55), filled: true);
  t.rect(1, 1, 14, 14, tile, filled: true);
  t.line(1, 1, 14, 1, _shade(tile, 1.3));
  t.line(1, 1, 1, 14, _shade(tile, 1.15));
  for (final (x, y) in [(0, 0), (15, 0), (0, 15), (15, 15)]) {
    t.plot(x, y, 0);
  }
  s.layers.first.name = 'Tile';
  s.addLayer('Picture');
  final g = Uint32List(256);
  glyph(Canvas(g, 16, 16));
  // A dark outline round the picture (16-bit style).
  final out = Uint32List.fromList(g);
  for (var y = 0; y < 16; y++) {
    for (var x = 0; x < 16; x++) {
      if (alphaOf(g[y * 16 + x]) > 0) continue;
      var edge = false;
      for (final (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final nx = x + dx, ny = y + dy;
        if (nx >= 0 &&
            ny >= 0 &&
            nx < 16 &&
            ny < 16 &&
            alphaOf(g[ny * 16 + nx]) > 0) {
          edge = true;
        }
      }
      if (edge && x > 0 && y > 0 && x < 15 && y < 15) out[y * 16 + x] = k;
    }
  }
  s.frames.first.cels[1].setAll(0, out);
  return s;
}

img.Image _scaled(Uint32List px, int scale, {int canvas = 0}) {
  final size = 16 * scale;
  final c = canvas == 0 ? size : canvas;
  final out = img.Image(width: c, height: c, numChannels: 4);
  final o = (c - size) ~/ 2;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final v = px[(y ~/ scale) * 16 + (x ~/ scale)];
      out.setPixelRgba(
        o + x,
        o + y,
        redOf(v),
        greenOf(v),
        blueOf(v),
        alphaOf(v),
      );
    }
  }
  return out;
}

void _write(String path, List<int> bytes) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);
}

void install(String app, Sprite s, int tile) {
  final dir = 'apps/$app';
  final px = s.flatten(0);
  _write(
    '$dir/icon/icon.pixel_sprite.json',
    utf8.encode(const JsonEncoder.withIndent(' ').convert(s.toJson())),
  );
  _write('$dir/icon/icon.png', img.encodePng(_scaled(px, 1)));
  _write('$dir/icon/icon_256.png', img.encodePng(_scaled(px, 16)));
  final res = '$dir/android/app/src/main/res';
  if (Directory(res).existsSync()) {
    // Older Androids: the whole tile (48/72/96/144/192 px, nearest-neighbour).
    for (final (d, size, scale) in [
      ('mdpi', 48, 3), ('hdpi', 72, 4), ('xhdpi', 96, 6), //
      ('xxhdpi', 144, 9), ('xxxhdpi', 192, 12),
    ]) {
      _write(
        '$res/mipmap-$d/ic_launcher.png',
        img.encodePng(_scaled(px, scale, canvas: size)),
      );
      // Adaptive icon (Android 8+): the tile fills the 66 dp safe zone of
      // a 108 dp layer, over the tile's colour.
      final (fg, fs) = switch (d) {
        'mdpi' => (108, 4),
        'hdpi' => (162, 6),
        'xhdpi' => (216, 8),
        'xxhdpi' => (324, 12),
        _ => (432, 16),
      };
      _write(
        '$res/mipmap-$d/ic_launcher_foreground.png',
        img.encodePng(_scaled(px, fs, canvas: fg)),
      );
    }
    _write(
      '$res/mipmap-anydpi-v26/ic_launcher.xml',
      utf8.encode('''<?xml version="1.0" encoding="utf-8"?>
<!-- Made by tool/icons (pixel_kit). -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
'''),
    );
    final hex = (tile & 0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0')
        .toUpperCase();
    _write(
      '$res/values/ic_launcher_background.xml',
      utf8.encode('''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#FF$hex</color>
</resources>
'''),
    );
  }
  final win = '$dir/windows/runner/resources';
  if (Directory(win).existsSync()) {
    _write(
      '$win/app_icon.ico',
      img.IcoEncoder().encodeImages([
        for (final sc in [1, 2, 3, 16]) _scaled(px, sc),
      ]),
    );
  }
}

void main(List<String> args) {
  final apps = [
    for (final d in Directory('apps').listSync().whereType<Directory>())
      if (File('${d.path}/pubspec.yaml').existsSync()) d.uri.pathSegments[1],
  ]..sort();
  final missing = [
    for (final a in apps)
      if (!icons.containsKey(a)) a,
  ];
  if (missing.isNotEmpty) {
    stderr.writeln(
      'No icon drawn yet for: ${missing.join(', ')} '
      '(add them to tool/icons/bin/make_icons.dart)',
    );
    exitCode = 1;
  }
  final want = args.isEmpty ? apps : args;
  // A contact sheet of every icon, 4× size.
  final sheet = img.Image(
    width: 8 * 80,
    height: ((want.length + 7) ~/ 8) * 80,
    numChannels: 4,
  );
  img.fill(sheet, color: img.ColorRgba8(40, 40, 48, 255));
  var i = 0;
  for (final app in want) {
    final art = icons[app];
    if (art == null) continue;
    final s = build(art);
    install(app, s, art.$1);
    img.compositeImage(
      sheet,
      _scaled(s.flatten(0), 4),
      dstX: (i % 8) * 80 + 8,
      dstY: (i ~/ 8) * 80 + 8,
    );
    i++;
    stdout.writeln('icon: $app');
  }
  _write('tool/icons/all_icons.png', img.encodePng(sheet));
}
