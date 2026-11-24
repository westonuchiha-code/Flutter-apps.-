// Computers and consoles: each reproduces the real limit of its video chip.
import 'dart:math' as math;
import 'dart:typed_data';

import '../effect.dart';
import '../frame.dart';

int _dist(int a, int b) {
  final dr = ((a >> 16) & 255) - ((b >> 16) & 255);
  final dg = ((a >> 8) & 255) - ((b >> 8) & 255);
  final db = (a & 255) - (b & 255);
  return 3 * dr * dr + 4 * dg * dg + 2 * db * db;
}

int _nearest(int c, List<int> pal) {
  var best = pal.first, bd = 1 << 62;
  for (final p in pal) {
    final d = _dist(c, p);
    if (d < bd) {
      bd = d;
      best = p;
    }
  }
  return best;
}

const bayer4 = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];

/// Bayer offset for pixel (x, y) in -0.5..0.5.
double bayer(int x, int y) => bayer4[(y & 3) * 4 + (x & 3)] / 16 - 15 / 32;

int _offset(int c, double t) {
  int ch(int v) => (v + t).round().clamp(0, 255);
  return 0xFF000000 |
      (ch((c >> 16) & 255) << 16) |
      (ch((c >> 8) & 255) << 8) |
      ch(c & 255);
}

// ---------------------------------------------------------------------------

/// ZX Spectrum: 256×192, but colour is set per 8×8 cell: two colours (ink and
/// paper) from one brightness set. Detail and colour fight: "attribute clash".
class ZxSpectrum extends VideoEffect {
  static const _normal = [
    0x000000,
    0x0000D7,
    0xD70000,
    0xD700D7,
    0x00D700,
    0x00D7D7,
    0xD7D700,
    0xD7D7D7,
  ];
  static const _bright = [
    0x000000,
    0x0000FF,
    0xFF0000,
    0xFF00FF,
    0x00FF00,
    0x00FFFF,
    0xFFFF00,
    0xFFFFFF,
  ];
  static final _sets = [
    [for (final c in _normal) 0xFF000000 | c],
    [for (final c in _bright) 0xFF000000 | c],
  ];

  @override
  String get id => 'zx';
  @override
  String get name => 'ZX Spectrum';
  @override
  String get about =>
      '256×192 with only two colours per 8×8 cell (attribute clash).';
  @override
  (int, int) inputSize(int inW, int inH) => (256, 192);
  @override
  List<Knob> get knobs => const [
    Knob('dither', 'Dither', value: 1, choices: ['Off', 'On']),
  ];

  @override
  VideoFrame process(VideoFrame input, double time) {
    final out = VideoFrame(256, 192);
    final dither = knob('dither') >= 0.5;
    final cell = Uint32List(64);
    for (var cy = 0; cy < 24; cy++) {
      for (var cx = 0; cx < 32; cx++) {
        for (var i = 0; i < 64; i++) {
          cell[i] = input.pixels[(cy * 8 + i ~/ 8) * 256 + cx * 8 + i % 8];
        }
        // Best ink/paper pair within one brightness set.
        var bestA = 0, bestB = 0, bestErr = 1 << 62;
        for (final set in _sets) {
          for (var a = 0; a < 8; a++) {
            for (var b = a; b < 8; b++) {
              var err = 0;
              for (final c in cell) {
                err += math.min(_dist(c, set[a]), _dist(c, set[b]));
                if (err >= bestErr) break;
              }
              if (err < bestErr) {
                bestErr = err;
                bestA = set[a];
                bestB = set[b];
              }
            }
          }
        }
        for (var i = 0; i < 64; i++) {
          final x = cx * 8 + i % 8, y = cy * 8 + i ~/ 8;
          final c = dither ? _offset(cell[i], bayer(x, y) * 96) : cell[i];
          out.pixels[y * 256 + x] = _dist(c, bestA) <= _dist(c, bestB)
              ? bestA
              : bestB;
        }
      }
    }
    return out;
  }
}

/// Commodore 64 multicolour bitmap: 160×200 double-wide pixels; each 4×8
/// cell has the shared background plus three colours of its own.
class C64Multicolor extends VideoEffect {
  static const _pepto = [
    0x000000,
    0xFFFFFF,
    0x68372B,
    0x70A4B2,
    0x6F3D86,
    0x588D43,
    0x352879,
    0xB8C76F,
    0x6F4F25,
    0x433900,
    0x9A6759,
    0x444444,
    0x6C6C6C,
    0x9AD284,
    0x6C5EB5,
    0x959595,
  ];
  static final _pal = [for (final c in _pepto) 0xFF000000 | c];

  @override
  String get id => 'c64';
  @override
  String get name => 'Commodore 64';
  @override
  String get about =>
      'Multicolour mode: fat pixels, four colours per 4×8 cell, one shared background.';
  @override
  (int, int) inputSize(int inW, int inH) => (160, 200);
  @override
  List<Knob> get knobs => const [
    Knob('dither', 'Dither', value: 1, choices: ['Off', 'On']),
  ];

  @override
  VideoFrame process(VideoFrame input, double time) {
    final dither = knob('dither') >= 0.5;
    final mapped = Int32List(160 * 200);
    final count = List.filled(16, 0);
    for (var y = 0; y < 200; y++) {
      for (var x = 0; x < 160; x++) {
        var c = input.pixels[y * 160 + x];
        if (dither) c = _offset(c, bayer(x, y) * 48);
        final i = _pal.indexOf(_nearest(c, _pal));
        mapped[y * 160 + x] = i;
        count[i]++;
      }
    }
    var bg = 0;
    for (var i = 1; i < 16; i++) {
      if (count[i] > count[bg]) bg = i;
    }
    final out = VideoFrame(320, 200);
    final cellCount = List.filled(16, 0);
    for (var cy = 0; cy < 25; cy++) {
      for (var cx = 0; cx < 40; cx++) {
        cellCount.fillRange(0, 16, 0);
        for (var y = 0; y < 8; y++) {
          for (var x = 0; x < 4; x++) {
            cellCount[mapped[(cy * 8 + y) * 160 + cx * 4 + x]]++;
          }
        }
        cellCount[bg] = -1;
        final order = List.generate(16, (i) => i)
          ..sort((a, b) => cellCount[b].compareTo(cellCount[a]));
        final allowed = [
          _pal[bg],
          for (final i in order.take(3))
            if (cellCount[i] > 0) _pal[i],
        ];
        for (var y = 0; y < 8; y++) {
          for (var x = 0; x < 4; x++) {
            final px = cx * 4 + x, py = cy * 8 + y;
            final c = _nearest(_pal[mapped[py * 160 + px]], allowed);
            out.pixels[py * 320 + px * 2] = c;
            out.pixels[py * 320 + px * 2 + 1] = c;
          }
        }
      }
    }
    return out;
  }
}

/// The Atari 2600 has no frame buffer: the program "races the beam", setting
/// colours for every scan line. Here each line gets two colours from the NTSC
/// palette, with the 40-block playfield resolution.
class Atari2600 extends VideoEffect {
  static final List<int> palette = () {
    final out = <int>[];
    for (var hue = 0; hue < 16; hue++) {
      for (var lum = 0; lum < 8; lum++) {
        final y = 0.08 + lum / 7 * 0.84;
        if (hue == 0) {
          out.add(rgbClamp(y * 255, y * 255, y * 255));
          continue;
        }
        final a = (hue - 1) / 15 * 2 * math.pi + 1.1;
        final i = 0.25 * math.cos(a), q = 0.25 * math.sin(a);
        out.add(
          rgbClamp(
            (y + 0.956 * i + 0.621 * q) * 255,
            (y - 0.272 * i - 0.647 * q) * 255,
            (y - 1.106 * i + 1.703 * q) * 255,
          ),
        );
      }
    }
    return out;
  }();

  @override
  String get id => 'atari';
  @override
  String get name => 'Atari 2600';
  @override
  String get about =>
      'Racing the beam: two colours per scan line, 40 chunky blocks across.';
  @override
  (int, int) inputSize(int inW, int inH) => (40, 96);
  @override
  List<Knob> get knobs => const [
    Knob('lines', 'Line height', value: 1, choices: ['1', '2']),
  ];

  @override
  VideoFrame process(VideoFrame input, double time) {
    final double2 = knob('lines') >= 0.5;
    final rows = double2 ? 96 : 192;
    final src = double2 ? input : input.resized(40, 192);
    final out = VideoFrame(160, 192);
    for (var row = 0; row < rows; row++) {
      final line = [for (var x = 0; x < 40; x++) src.pixels[row * 40 + x]];
      // Two-colour k-means on the line, snapped to the palette.
      var a = line.reduce((p, c) => lumaOf(c) < lumaOf(p) ? c : p);
      var b = line.reduce((p, c) => lumaOf(c) > lumaOf(p) ? c : p);
      for (var iter = 0; iter < 3; iter++) {
        var ar = 0, ag = 0, ab = 0, an = 0, br = 0, bg = 0, bb = 0, bn = 0;
        for (final c in line) {
          if (_dist(c, a) <= _dist(c, b)) {
            ar += (c >> 16) & 255;
            ag += (c >> 8) & 255;
            ab += c & 255;
            an++;
          } else {
            br += (c >> 16) & 255;
            bg += (c >> 8) & 255;
            bb += c & 255;
            bn++;
          }
        }
        if (an > 0) a = rgbClamp(ar / an, ag / an, ab / an);
        if (bn > 0) b = rgbClamp(br / bn, bg / bn, bb / bn);
      }
      final ca = _nearest(a, palette), cb = _nearest(b, palette);
      for (var x = 0; x < 40; x++) {
        final c = _dist(line[x], ca) <= _dist(line[x], cb) ? ca : cb;
        for (var k = 0; k < 4; k++) {
          for (var r = 0; r < (double2 ? 2 : 1); r++) {
            out.pixels[(row * (double2 ? 2 : 1) + r) * 160 + x * 4 + k] = c;
          }
        }
      }
    }
    return out;
  }
}

/// Game Boy Camera: a 128×112 sensor whose chip sharpened edges in hardware,
/// then four shades with ordered dithering on the green LCD.
class GameBoyCamera extends VideoEffect {
  static const _green = [0xFF0F380F, 0xFF306230, 0xFF8BAC0F, 0xFF9BBC0F];
  static const _grey = [0xFF000000, 0xFF555555, 0xFFAAAAAA, 0xFFFFFFFF];

  @override
  String get id => 'gbcam';
  @override
  String get name => 'Game Boy Camera';
  @override
  String get about =>
      '128×112, edge-boosted by the sensor chip, four dithered shades.';
  @override
  (int, int) inputSize(int inW, int inH) => (128, 112);
  @override
  List<Knob> get knobs => const [
    Knob('edge', 'Edge boost', value: 0.6),
    Knob('contrast', 'Contrast', value: 0.5),
    Knob('screen', 'Screen', value: 0, choices: ['Green', 'Grey']),
  ];

  @override
  VideoFrame process(VideoFrame input, double time) {
    final pal = knob('screen') >= 0.5 ? _grey : _green;
    final edge = knob('edge') * 2;
    final contrast = 0.6 + knob('contrast') * 1.4;
    final l = Int16List(128 * 112);
    for (var i = 0; i < l.length; i++) {
      l[i] = lumaOf(input.pixels[i]);
    }
    final out = VideoFrame(128, 112);
    for (var y = 0; y < 112; y++) {
      for (var x = 0; x < 128; x++) {
        final c = l[y * 128 + x];
        final n =
            (l[y * 128 + math.max(0, x - 1)] +
                l[y * 128 + math.min(127, x + 1)] +
                l[math.max(0, y - 1) * 128 + x] +
                l[math.min(111, y + 1) * 128 + x]) /
            4;
        var v = c + edge * (c - n);
        v = (v - 128) * contrast + 128 + bayer(x, y) * 85;
        out.pixels[y * 128 + x] = pal[(v / 64).floor().clamp(0, 3)];
      }
    }
    return out;
  }
}

/// Early handheld LCD (passive matrix): pixels change slowly, leaving smeared
/// ghosts behind anything that moves.
class HandheldLcd extends VideoEffect {
  static const _green = [0xFF0F380F, 0xFF306230, 0xFF8BAC0F, 0xFF9BBC0F];
  Float32List? _state;

  @override
  String get id => 'lcd';
  @override
  String get name => 'Slow handheld LCD';
  @override
  String get about =>
      '160×144 four-shade LCD whose pixels take ages to change: motion smears.';
  @override
  (int, int) inputSize(int inW, int inH) => (160, 144);
  @override
  List<Knob> get knobs => const [Knob('slow', 'Slowness', value: 0.7)];

  @override
  void reset() => _state = null;

  @override
  VideoFrame process(VideoFrame input, double time) {
    final s = _state ??= Float32List(160 * 144)..fillRange(0, 160 * 144, 128);
    final rate = 0.6 - knob('slow') * 0.55;
    final out = VideoFrame(160, 144);
    for (var i = 0; i < s.length; i++) {
      final target = (lumaOf(input.pixels[i]) / 64).floor().clamp(0, 3) * 85.0;
      s[i] += (target - s[i]) * rate;
      out.pixels[i] = _green[(s[i] / 64).round().clamp(0, 3)];
    }
    return out;
  }
}

/// Teletext / Ceefax: 40×25 character cells of 2×3 block "sixels", 8
/// colours. Changing colour takes up a whole cell (the control code shows as
/// a gap), which gives teletext its broken, stripy look.
class Teletext extends VideoEffect {
  static const _colors = [
    0xFF000000,
    0xFFFF0000,
    0xFF00FF00,
    0xFFFFFF00,
    0xFF0000FF,
    0xFFFF00FF,
    0xFF00FFFF,
    0xFFFFFFFF,
  ];

  @override
  String get id => 'teletext';
  @override
  String get name => 'Teletext';
  @override
  String get about =>
      '40×25 cells of 2×3 blocks, 8 colours; every colour change costs a cell.';
  @override
  (int, int) inputSize(int inW, int inH) => (80, 72);
  @override
  List<Knob> get knobs => const [
    Knob('threshold', 'Block threshold', value: 0.4),
  ];

  @override
  VideoFrame process(VideoFrame input, double time) {
    // Output: cells 12×18 pixels → 480×432 (24 rows used: 72 / 3).
    const cw = 12, ch = 18, cols = 40, rows = 24;
    final out = VideoFrame(cols * cw, rows * ch);
    final thr = 40 + knob('threshold') * 120;
    for (var row = 0; row < rows; row++) {
      var fg = 7; // white at the start of every row
      for (var col = 0; col < cols; col++) {
        // The cell's dominant colour and which sixels light up.
        final counts = List.filled(8, 0);
        final on = List.filled(6, false);
        for (var s = 0; s < 6; s++) {
          final c = input.pixels[(row * 3 + s ~/ 2) * 80 + col * 2 + s % 2];
          if (lumaOf(c) < thr && _saturation(c) < 60) continue;
          on[s] = true;
          counts[_colors.indexOf(_nearest(c, _colors))]++;
        }
        var want = fg, best = 0;
        for (var k = 1; k < 8; k++) {
          if (counts[k] > best) {
            best = counts[k];
            want = k;
          }
        }
        if (best > 0 && want != fg) {
          fg = want; // control code: this cell is spent as a gap
          continue;
        }
        for (var s = 0; s < 6; s++) {
          if (!on[s]) continue;
          final x0 = col * cw + (s % 2) * (cw ~/ 2),
              y0 = row * ch + (s ~/ 2) * (ch ~/ 3);
          for (var y = 0; y < ch ~/ 3; y++) {
            for (var x = 0; x < cw ~/ 2; x++) {
              out.pixels[(y0 + y) * out.width + x0 + x] = _colors[fg];
            }
          }
        }
      }
    }
    return out;
  }

  static int _saturation(int c) {
    final r = (c >> 16) & 255, g = (c >> 8) & 255, b = c & 255;
    return math.max(r, math.max(g, b)) - math.min(r, math.min(g, b));
  }
}

/// Fisher-Price PXL-2000 (1987): a toy camcorder recording to audio
/// cassette. 120×90 grey pixels, low frame rate, heavy smear, black border.
class Pxl2000 extends VideoEffect {
  Float32List? _state;
  VideoFrame? _held;
  double _lastTick = -1;

  @override
  String get id => 'pxl2000';
  @override
  String get name => 'PXL-2000';
  @override
  String get about =>
      'Toy camcorder on audio cassette: 120×90 grey, 15 frames a second, smeary.';
  @override
  (int, int) inputSize(int inW, int inH) => (120, 90);
  @override
  List<Knob> get knobs => const [Knob('smear', 'Smear', value: 0.5)];

  @override
  void reset() {
    _state = null;
    _held = null;
    _lastTick = -1;
  }

  @override
  VideoFrame process(VideoFrame input, double time) {
    // It only manages about 15 frames a second: hold frames in between.
    if (_held != null && time - _lastTick < 1 / 15) return _held!;
    _lastTick = time;
    final s = _state ??= Float32List(120 * 90);
    final keep = 0.2 + knob('smear') * 0.6;
    final rnd = math.Random((time * 1000).round());
    final out = VideoFrame(160, 120);
    for (var y = 0; y < 90; y++) {
      for (var x = 0; x < 120; x++) {
        final i = y * 120 + x;
        final v =
            lumaOf(input.pixels[i]) * 0.75 + 30 + rnd.nextDouble() * 18 - 9;
        s[i] = s[i] * keep + v * (1 - keep);
        out.pixels[(y + 15) * 160 + x + 20] = grey(s[i].round());
      }
    }
    return _held = out;
  }
}
