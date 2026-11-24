import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pixel_kit/pixel_kit.dart' as pk;

import 'pic.dart';

/// How a colour is stored.
enum ColorBits {
  /// 5 bits per channel (PS1, N64 RGBA16 / palettes).
  rgb555,

  /// 5-6-5 (GameCube, Dreamcast).
  rgb565,

  /// Full 8 bits per channel.
  rgb888,
}

int _expand5(int v) => (v << 3) | (v >> 2);
int _expand6(int v) => (v << 2) | (v >> 4);

/// The stored level whose expanded value is nearest [v].
int _level(int v, int max, int Function(int) expand) {
  var k = (v * max + 127) ~/ 255;
  var best = k, bestD = 1 << 30;
  for (final c in [k - 1, k, k + 1]) {
    if (c < 0 || c > max) continue;
    final d = (expand(c) - v).abs();
    if (d < bestD) {
      bestD = d;
      best = c;
    }
  }
  return expand(best);
}

int _q5(int v) => _level(v, 31, _expand5);
int _q6(int v) => _level(v, 63, _expand6);

/// The nearest colour the format can hold (hardware expands 5/6-bit values
/// by repeating the top bits).
int quantizeColor(int c, ColorBits bits) => switch (bits) {
  ColorBits.rgb555 => rgb(_q5(rOf(c)), _q5(gOf(c)), _q5(bOf(c))),
  ColorBits.rgb565 => rgb(_q5(rOf(c)), _q6(gOf(c)), _q5(bOf(c))),
  ColorBits.rgb888 => c | 0xFF000000,
};

enum FormatKind { clut, direct, grey, cmpr, vq }

/// A texture format a console's hardware reads.
class TexFormat {
  const TexFormat(
    this.id,
    this.label,
    this.kind, {
    required this.bitsPerPixel,
    this.colors = 0,
    this.bits = ColorBits.rgb888,
    this.paletteEntryBytes = 0,
    this.fixedBytes = 0,
  });

  final String id, label;
  final FormatKind kind;
  final double bitsPerPixel;

  /// Palette size (CLUT) or grey levels.
  final int colors;
  final ColorBits bits;
  final int paletteEntryBytes;

  /// Extra memory not tied to size (e.g. a VQ codebook).
  final int fixedBytes;

  bool get canDither =>
      kind == FormatKind.clut ||
      kind == FormatKind.grey ||
      (kind == FormatKind.direct && bits != ColorBits.rgb888);

  /// Bytes of video memory for a [w]×[h] texture.
  int bytesFor(int w, int h) =>
      (w * h * bitsPerPixel / 8).ceil() +
      colors * paletteEntryBytes +
      fixedBytes;
}

const clut4ps1 = TexFormat(
  'clut4_15',
  '4-bit CLUT',
  FormatKind.clut,
  bitsPerPixel: 4,
  colors: 16,
  bits: ColorBits.rgb555,
  paletteEntryBytes: 2,
);
const clut8ps1 = TexFormat(
  'clut8_15',
  '8-bit CLUT',
  FormatKind.clut,
  bitsPerPixel: 8,
  colors: 256,
  bits: ColorBits.rgb555,
  paletteEntryBytes: 2,
);
const direct15 = TexFormat(
  'direct15',
  '15-bit direct',
  FormatKind.direct,
  bitsPerPixel: 16,
  bits: ColorBits.rgb555,
);
const ci4 = TexFormat(
  'ci4',
  'CI4',
  FormatKind.clut,
  bitsPerPixel: 4,
  colors: 16,
  bits: ColorBits.rgb555,
  paletteEntryBytes: 2,
);
const ci8 = TexFormat(
  'ci8',
  'CI8',
  FormatKind.clut,
  bitsPerPixel: 8,
  colors: 256,
  bits: ColorBits.rgb555,
  paletteEntryBytes: 2,
);
const rgba16 = TexFormat(
  'rgba16',
  'RGBA16',
  FormatKind.direct,
  bitsPerPixel: 16,
  bits: ColorBits.rgb555,
);
const i4 = TexFormat(
  'i4',
  'I4 (grey)',
  FormatKind.grey,
  bitsPerPixel: 4,
  colors: 16,
);
const clut4ps2 = TexFormat(
  'clut4_32',
  '4-bit CLUT',
  FormatKind.clut,
  bitsPerPixel: 4,
  colors: 16,
  paletteEntryBytes: 4,
);
const clut8ps2 = TexFormat(
  'clut8_32',
  '8-bit CLUT',
  FormatKind.clut,
  bitsPerPixel: 8,
  colors: 256,
  paletteEntryBytes: 4,
);
const rgba32 = TexFormat(
  'rgba32',
  '32-bit',
  FormatKind.direct,
  bitsPerPixel: 32,
);
const cmpr = TexFormat(
  'cmpr',
  'CMPR (S3TC)',
  FormatKind.cmpr,
  bitsPerPixel: 4,
  bits: ColorBits.rgb565,
);
const rgb565 = TexFormat(
  'rgb565',
  'RGB565',
  FormatKind.direct,
  bitsPerPixel: 16,
  bits: ColorBits.rgb565,
);
const ci8gc = TexFormat(
  'ci8_565',
  'C8',
  FormatKind.clut,
  bitsPerPixel: 8,
  colors: 256,
  bits: ColorBits.rgb565,
  paletteEntryBytes: 2,
);
const vq = TexFormat(
  'vq',
  'VQ',
  FormatKind.vq,
  bitsPerPixel: 2,
  bits: ColorBits.rgb565,
  fixedBytes: 2048,
);

class FormatChoice {
  const FormatChoice(this.format, this.sizes, this.defaultSize);
  final TexFormat format;
  final List<int> sizes;
  final int defaultSize;
}

/// A console's texture rules.
class ConsolePreset {
  const ConsolePreset(
    this.id,
    this.name,
    this.about,
    this.formats, {
    required this.smooth,
  });
  final String id, name, about;
  final List<FormatChoice> formats;

  /// Whether the hardware filtered textures (bilinear) or showed raw texels.
  final bool smooth;
}

const consoles = [
  ConsolePreset(
    'ps1',
    'PS1',
    'Textures share 1 MB of VRAM with the screen, in 256×256 pages. Mostly '
        '4-bit or 8-bit CLUTs of 15-bit colours. No filtering: texels stay '
        'sharp (and wobble).',
    [
      FormatChoice(clut4ps1, [32, 64, 128, 256], 128),
      FormatChoice(clut8ps1, [32, 64, 128, 256], 128),
      FormatChoice(direct15, [32, 64, 128, 256], 64),
    ],
    smooth: false,
  ),
  ConsolePreset(
    'n64',
    'N64',
    'Every texture must fit the 4 KB texture memory (TMEM); a palette takes '
        'half of it. That is why N64 textures are tiny and blurred by its '
        '3-point filtering.',
    [
      FormatChoice(ci4, [32, 64], 64),
      FormatChoice(ci8, [32], 32),
      FormatChoice(rgba16, [32], 32),
      FormatChoice(i4, [32, 64], 64),
    ],
    smooth: true,
  ),
  ConsolePreset(
    'ps2',
    'PS2',
    '4 MB of video memory, refilled many times a frame. 4-bit and 8-bit '
        'CLUTs with 32-bit colours were the norm; full colour was costly.',
    [
      FormatChoice(clut4ps2, [64, 128, 256], 128),
      FormatChoice(clut8ps2, [64, 128, 256, 512], 256),
      FormatChoice(rgba32, [64, 128, 256], 128),
    ],
    smooth: true,
  ),
  ConsolePreset(
    'gc',
    'GameCube',
    'CMPR (the same S3TC/DXT1 compression PCs used): every 4×4 block holds '
        'just 2 colours and 2 in between. 1 MB texture cache.',
    [
      FormatChoice(cmpr, [64, 128, 256, 512, 1024], 256),
      FormatChoice(rgb565, [64, 128, 256, 512], 256),
      FormatChoice(ci8gc, [64, 128, 256], 128),
    ],
    smooth: true,
  ),
  ConsolePreset(
    'dc',
    'Dreamcast',
    'VQ compression: the texture is built from a codebook of 256 tiny 2×2 '
        'pieces (2 bits per pixel). 8 MB of video memory.',
    [
      FormatChoice(vq, [64, 128, 256, 512], 256),
      FormatChoice(rgb565, [64, 128, 256, 512], 256),
    ],
    smooth: true,
  ),
];

const _bayer4 = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
double _bayer(int x, int y) => _bayer4[(y & 3) * 4 + (x & 3)] / 16 - 15 / 32;

/// The texture as the console would hold it, decoded back to colours.
Pic applyFormat(Pic p, TexFormat f, {bool dither = false}) => switch (f.kind) {
  FormatKind.direct => _direct(p, f.bits, dither),
  FormatKind.grey => _grey(p, f.colors, dither),
  FormatKind.clut => _clut(p, f.colors, f.bits, dither),
  FormatKind.cmpr => encodeDxt1(p),
  FormatKind.vq => encodeVq(p),
};

Pic _direct(Pic p, ColorBits bits, bool dither) {
  if (bits == ColorBits.rgb888) return p;
  final out = Pic(p.width, p.height);
  // One 5-bit step is about 8 levels.
  for (var y = 0; y < p.height; y++) {
    for (var x = 0; x < p.width; x++) {
      var c = p.px[y * p.width + x];
      if (dither) {
        final t = _bayer(x, y) * 8;
        c = rgbD(rOf(c) + t, gOf(c) + t, bOf(c) + t);
      }
      out.px[y * p.width + x] = quantizeColor(c, bits);
    }
  }
  return out;
}

Pic _grey(Pic p, int levels, bool dither) {
  final out = Pic(p.width, p.height);
  final step = 255 / (levels - 1);
  for (var y = 0; y < p.height; y++) {
    for (var x = 0; x < p.width; x++) {
      var l = lumaOf(p.px[y * p.width + x]);
      if (dither) l += _bayer(x, y) * step;
      final v = ((l / step).round().clamp(0, levels - 1) * step).round();
      out.px[y * p.width + x] = rgb(v, v, v);
    }
  }
  return out;
}

Pic _clut(Pic p, int count, ColorBits bits, bool dither) {
  final palette = <int>{
    for (final c in pk.medianCut(p.px, count)) quantizeColor(c, bits),
  }.toList();
  final out = Pic(p.width, p.height);
  final cache = <int, int>{};
  int nearest(int c) => cache.putIfAbsent(c, () {
    var best = palette.first, bestD = 1 << 62;
    for (final q in palette) {
      final dr = rOf(c) - rOf(q), dg = gOf(c) - gOf(q), db = bOf(c) - bOf(q);
      final d = 2 * dr * dr + 4 * dg * dg + 3 * db * db;
      if (d < bestD) {
        bestD = d;
        best = q;
      }
    }
    return best;
  });
  final strength = count <= 16 ? 24.0 : 12.0;
  for (var y = 0; y < p.height; y++) {
    for (var x = 0; x < p.width; x++) {
      var c = p.px[y * p.width + x];
      if (dither) {
        final t = _bayer(x, y) * strength;
        c = rgbD(rOf(c) + t, gOf(c) + t, bOf(c) + t);
      }
      out.px[y * p.width + x] = nearest(c);
    }
  }
  return out;
}

/// S3TC / DXT1 (GameCube CMPR) in opaque 4-colour mode: per 4×4 block two
/// RGB565 end colours along the block's main colour axis, plus the two
/// colours a third and two thirds between them.
Pic encodeDxt1(Pic p) {
  final out = Pic(p.width, p.height);
  final block = List<int>.filled(16, 0);
  for (var by = 0; by < p.height; by += 4) {
    for (var bx = 0; bx < p.width; bx += 4) {
      var n = 0;
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 4; x++) {
          block[n++] =
              p.px[math.min(by + y, p.height - 1) * p.width +
                  math.min(bx + x, p.width - 1)];
        }
      }
      final colors = _dxtEndpoints(block);
      for (var y = 0; y < 4 && by + y < p.height; y++) {
        for (var x = 0; x < 4 && bx + x < p.width; x++) {
          final c = block[y * 4 + x];
          var best = colors[0], bestD = 1 << 62;
          for (final q in colors) {
            final dr = rOf(c) - rOf(q),
                dg = gOf(c) - gOf(q),
                db = bOf(c) - bOf(q);
            final d = dr * dr + dg * dg + db * db;
            if (d < bestD) {
              bestD = d;
              best = q;
            }
          }
          out.px[(by + y) * p.width + bx + x] = best;
        }
      }
    }
  }
  return out;
}

List<int> _dxtEndpoints(List<int> block) {
  var mr = 0.0, mg = 0.0, mb = 0.0;
  for (final c in block) {
    mr += rOf(c);
    mg += gOf(c);
    mb += bOf(c);
  }
  mr /= 16;
  mg /= 16;
  mb /= 16;
  // Main axis by power iteration on the covariance.
  var crr = 0.0, cgg = 0.0, cbb = 0.0, crg = 0.0, crb = 0.0, cgb = 0.0;
  for (final c in block) {
    final r = rOf(c) - mr, g = gOf(c) - mg, b = bOf(c) - mb;
    crr += r * r;
    cgg += g * g;
    cbb += b * b;
    crg += r * g;
    crb += r * b;
    cgb += g * b;
  }
  var ar = 1.0, ag = 1.0, ab = 1.0;
  for (var i = 0; i < 6; i++) {
    final nr = crr * ar + crg * ag + crb * ab;
    final ng = crg * ar + cgg * ag + cgb * ab;
    final nb = crb * ar + cgb * ag + cbb * ab;
    final len = math.sqrt(nr * nr + ng * ng + nb * nb);
    if (len < 1e-9) break;
    ar = nr / len;
    ag = ng / len;
    ab = nb / len;
  }
  var lo = double.infinity, hi = double.negativeInfinity;
  for (final c in block) {
    final t = (rOf(c) - mr) * ar + (gOf(c) - mg) * ag + (bOf(c) - mb) * ab;
    lo = math.min(lo, t);
    hi = math.max(hi, t);
  }
  final c0 = quantizeColor(
    rgbD(mr + ar * hi, mg + ag * hi, mb + ab * hi),
    ColorBits.rgb565,
  );
  final c1 = quantizeColor(
    rgbD(mr + ar * lo, mg + ag * lo, mb + ab * lo),
    ColorBits.rgb565,
  );
  int mix(int a, int b) => rgb(
    (2 * rOf(a) + rOf(b)) ~/ 3,
    (2 * gOf(a) + gOf(b)) ~/ 3,
    (2 * bOf(a) + bOf(b)) ~/ 3,
  );
  return [c0, c1, mix(c0, c1), mix(c1, c0)];
}

/// Dreamcast VQ: the picture as 2×2 blocks, each replaced by the nearest of
/// 256 codebook blocks (RGB565) learned from the picture (k-means).
Pic encodeVq(Pic p, {int codes = 256, int seed = 1}) {
  final bw = p.width ~/ 2, bh = p.height ~/ 2;
  final nb = bw * bh;
  final data = Float32List(nb * 12);
  for (var by = 0; by < bh; by++) {
    for (var bx = 0; bx < bw; bx++) {
      final o = (by * bw + bx) * 12;
      var k = 0;
      for (var y = 0; y < 2; y++) {
        for (var x = 0; x < 2; x++) {
          final c = p.px[(by * 2 + y) * p.width + bx * 2 + x];
          data[o + k++] = rOf(c).toDouble();
          data[o + k++] = gOf(c).toDouble();
          data[o + k++] = bOf(c).toDouble();
        }
      }
    }
  }
  final rnd = math.Random(seed);
  final k = math.min(codes, nb);
  final book = Float32List(k * 12);
  for (var i = 0; i < k; i++) {
    final s = rnd.nextInt(nb);
    for (var d = 0; d < 12; d++) {
      book[i * 12 + d] = data[s * 12 + d];
    }
  }
  int nearest(int b) {
    var best = 0;
    var bestD = double.infinity;
    final o = b * 12;
    for (var i = 0; i < k; i++) {
      var d = 0.0;
      final q = i * 12;
      for (var j = 0; j < 12; j++) {
        final t = data[o + j] - book[q + j];
        d += t * t;
        if (d >= bestD) break;
      }
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  // Learn the codebook on a sample of blocks.
  final sample = [
    for (var i = 0; i < math.min(nb, 6000); i++)
      nb <= 6000 ? i : rnd.nextInt(nb),
  ];
  final sums = Float64List(k * 12);
  final counts = Int32List(k);
  for (var iter = 0; iter < 8; iter++) {
    sums.fillRange(0, sums.length, 0);
    counts.fillRange(0, k, 0);
    for (final b in sample) {
      final i = nearest(b);
      counts[i]++;
      for (var j = 0; j < 12; j++) {
        sums[i * 12 + j] += data[b * 12 + j];
      }
    }
    for (var i = 0; i < k; i++) {
      if (counts[i] == 0) {
        // Unused code: restart it on a random block.
        final s = sample[rnd.nextInt(sample.length)];
        for (var j = 0; j < 12; j++) {
          book[i * 12 + j] = data[s * 12 + j];
        }
        continue;
      }
      for (var j = 0; j < 12; j++) {
        book[i * 12 + j] = sums[i * 12 + j] / counts[i];
      }
    }
  }
  // Codebook entries are RGB565 pixels.
  final colors = Uint32List(k * 4);
  for (var i = 0; i < k; i++) {
    for (var q = 0; q < 4; q++) {
      final o = i * 12 + q * 3;
      colors[i * 4 + q] = quantizeColor(
        rgbD(book[o], book[o + 1], book[o + 2]),
        ColorBits.rgb565,
      );
    }
  }
  final out = Pic(p.width, p.height);
  for (var by = 0; by < bh; by++) {
    for (var bx = 0; bx < bw; bx++) {
      final i = nearest(by * bw + bx);
      for (var y = 0; y < 2; y++) {
        for (var x = 0; x < 2; x++) {
          out.px[(by * 2 + y) * p.width + bx * 2 + x] =
              colors[i * 4 + y * 2 + x];
        }
      }
    }
  }
  return out;
}

String formatBytes(int b) => b < 1024
    ? '$b B'
    : (b < 1024 * 1024
          ? '${(b / 1024).toStringAsFixed(b % 1024 == 0 ? 0 : 1)} KB'
          : '${(b / 1048576).toStringAsFixed(1)} MB');
