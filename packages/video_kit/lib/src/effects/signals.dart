// Analog signals and tape: each one reproduces how the signal itself carried
// (and damaged) the picture.
import 'dart:math' as math;
import 'dart:typed_data';

import '../effect.dart';
import '../frame.dart';

/// Moving average of [src] (length n) with window [w], centred.
void _box(Float32List src, Float32List dst, int w) {
  final n = src.length;
  if (w <= 1) {
    dst.setAll(0, src);
    return;
  }
  final half = w ~/ 2;
  var sum = 0.0;
  for (var i = -half; i < w - half; i++) {
    sum += src[i.clamp(0, n - 1)];
  }
  for (var i = 0; i < n; i++) {
    dst[i] = sum / w;
    sum +=
        src[(i + w - half).clamp(0, n - 1)] - src[(i - half).clamp(0, n - 1)];
  }
}

// YIQ (NTSC colour space).
double _y(int c) =>
    (0.299 * ((c >> 16) & 255) + 0.587 * ((c >> 8) & 255) + 0.114 * (c & 255)) /
    255;
double _i(int c) =>
    (0.596 * ((c >> 16) & 255) - 0.274 * ((c >> 8) & 255) - 0.322 * (c & 255)) /
    255;
double _q(int c) =>
    (0.211 * ((c >> 16) & 255) - 0.523 * ((c >> 8) & 255) + 0.312 * (c & 255)) /
    255;
int _yiq(double y, double i, double q) => rgbClamp(
  (y + 0.956 * i + 0.621 * q) * 255,
  (y - 0.272 * i - 0.647 * q) * 255,
  (y - 1.106 * i + 1.703 * q) * 255,
);

/// Decodes one composite line ([s], 4 samples per colour cycle, starting at
/// [phase]) into [out] RGB. [prev] enables the 2-line comb filter.
void _decodeLine(
  Float32List s,
  double phase,
  Uint32List out,
  int outOffset, {
  Float32List? prev,
  int iWidth = 8,
  int qWidth = 14,
}) {
  final n = s.length;
  final yl = Float32List(n),
      c = Float32List(n),
      ii = Float32List(n),
      qq = Float32List(n);
  if (prev != null) {
    // Chroma flips sign line to line, so averaging two lines cancels it.
    for (var k = 0; k < n; k++) {
      yl[k] = (s[k] + prev[k]) / 2;
    }
  } else {
    _box(s, yl, 4); // notch: one whole colour cycle averages chroma away
  }
  for (var k = 0; k < n; k++) {
    c[k] = s[k] - yl[k];
    final t = k * math.pi / 2 + phase;
    ii[k] = 2 * c[k] * math.cos(t);
    qq[k] = 2 * c[k] * math.sin(t);
  }
  final fi = Float32List(n), fq = Float32List(n);
  _box(ii, fi, iWidth);
  _box(qq, fq, qWidth);
  for (var k = 0; k < n; k++) {
    out[outOffset + k] = _yiq(yl[k], fi[k], fq[k]);
  }
}

/// NTSC composite video: brightness and colour share one wire; colour rides
/// on a 3.58 MHz subcarrier whose phase flips every line and every frame.
/// Encoding and decoding it for real gives dot crawl, colour bleeding and
/// rainbows on fine detail.
class NtscComposite extends VideoEffect {
  int _frame = 0;
  Float32List? _prevLine;

  @override
  String get id => 'ntsc';
  @override
  String get name => 'NTSC composite';
  @override
  String get about =>
      'Colour on a 3.58 MHz subcarrier: dot crawl, colour bleed and rainbows.';
  @override
  (int, int) inputSize(int inW, int inH) => (640, 240);
  @override
  List<Knob> get knobs => const [
    Knob('noise', 'Signal noise', value: 0.15),
    Knob('bleed', 'Colour bleed', value: 0.4),
    Knob('comb', 'Comb filter (better TV)', value: 0, choices: ['Off', 'On']),
  ];

  @override
  void reset() {
    _frame = 0;
    _prevLine = null;
  }

  @override
  VideoFrame process(VideoFrame input, double time) {
    const w = 640, h = 240;
    final out = VideoFrame(w, h * 2);
    final noise = knob('noise') * 0.12;
    final bleed = knob('bleed');
    final comb = knob('comb') >= 0.5;
    final iw = (4 + bleed * 16).round(), qw = (8 + bleed * 28).round();
    final rnd = math.Random(_frame);
    final s = Float32List(w),
        ib = Float32List(w),
        qb = Float32List(w),
        ii = Float32List(w),
        qq = Float32List(w);
    final line = Uint32List(w);
    _prevLine = null;
    for (var y = 0; y < h; y++) {
      final phase = ((y + _frame) & 1) * math.pi;
      for (var x = 0; x < w; x++) {
        final c = input.pixels[y * w + x];
        ii[x] = _i(c);
        qq[x] = _q(c);
      }
      // The encoder band-limits colour (I wider than Q).
      _box(ii, ib, 6);
      _box(qq, qb, 16);
      for (var x = 0; x < w; x++) {
        final t = x * math.pi / 2 + phase;
        s[x] =
            _y(input.pixels[y * w + x]) +
            ib[x] * math.cos(t) +
            qb[x] * math.sin(t) +
            (rnd.nextDouble() - 0.5) * noise;
      }
      _decodeLine(
        s,
        phase,
        line,
        0,
        prev: comb ? _prevLine : null,
        iWidth: iw,
        qWidth: qw,
      );
      _prevLine = Float32List.fromList(s);
      out.pixels.setRange(y * 2 * w, y * 2 * w + w, line);
      out.pixels.setRange((y * 2 + 1) * w, (y * 2 + 1) * w + w, line);
    }
    _frame++;
    return out;
  }
}

/// Colour made from black-and-white pixels: on a composite monitor, fine
/// on/off patterns become colours. IBM CGA's composite mode picks one of 16
/// four-pixel patterns per colour; the Apple II hi-res screen gets green,
/// violet, orange and blue fringes the same way.
class ArtifactColor extends VideoEffect {
  List<int>? _cgaColors;

  @override
  String get id => 'artifact';
  @override
  String get name => 'Artifact colour (CGA / Apple II)';
  @override
  String get about =>
      'Black-and-white pixel patterns that a TV decodes into colour.';
  @override
  (int, int) inputSize(int inW, int inH) =>
      knob('machine') >= 0.5 ? (140, 192) : (160, 200);
  @override
  List<Knob> get knobs => const [
    Knob('machine', 'Machine', value: 0, choices: ['IBM CGA', 'Apple II']),
  ];

  /// Decoded colour of each 4-sample pattern (as seen in a long run of it).
  List<int> _patternColors(double phase) {
    final colors = <int>[];
    for (var p = 0; p < 16; p++) {
      final s = Float32List(64);
      for (var k = 0; k < 64; k++) {
        s[k] = ((p >> (3 - k % 4)) & 1).toDouble();
      }
      final out = Uint32List(64);
      _decodeLine(s, phase, out, 0, iWidth: 8, qWidth: 8);
      colors.add(out[32]);
    }
    return colors;
  }

  int _dist(int a, int b) {
    final dr = ((a >> 16) & 255) - ((b >> 16) & 255);
    final dg = ((a >> 8) & 255) - ((b >> 8) & 255);
    final db = (a & 255) - (b & 255);
    return 3 * dr * dr + 4 * dg * dg + 2 * db * db;
  }

  @override
  VideoFrame process(VideoFrame input, double time) {
    final apple = knob('machine') >= 0.5;
    final cells = input.width, rows = input.height;
    final w = cells * 4;
    final colors = _cgaColors ??= _patternColors(0);
    final out = VideoFrame(w, rows * 2);
    final s = Float32List(w);
    final line = Uint32List(w);
    for (var y = 0; y < rows; y++) {
      if (!apple) {
        for (var cx = 0; cx < cells; cx++) {
          final want = input.pixels[y * cells + cx];
          var best = 0, bd = 1 << 62;
          for (var p = 0; p < 16; p++) {
            final d = _dist(want, colors[p]);
            if (d < bd) {
              bd = d;
              best = p;
            }
          }
          for (var k = 0; k < 4; k++) {
            s[cx * 4 + k] = ((best >> (3 - k)) & 1).toDouble();
          }
        }
      } else {
        // Apple II: pairs of hi-res pixels; each group of 4 pairs has a
        // palette bit that delays its dots by one, swapping
        // violet/green for blue/orange.
        for (var g = 0; g < cells ~/ 4; g++) {
          var bestErr = 1 << 62;
          var bestBits = 0;
          for (var shift = 0; shift < 2; shift++) {
            var err = 0, bits = 0;
            for (var k = 0; k < 4; k++) {
              final want = input.pixels[y * cells + g * 4 + k];
              var bp = 0, bd = 1 << 62;
              for (final p in const [0, 0x5, 0xA, 0xF]) {
                final pat = shift == 1 ? ((p >> 1) | ((p & 1) << 3)) : p;
                final d = _dist(want, colors[pat]);
                if (d < bd) {
                  bd = d;
                  bp = pat;
                }
              }
              err += bd;
              bits |= bp << (k * 4);
            }
            if (err < bestErr) {
              bestErr = err;
              bestBits = bits;
            }
          }
          for (var k = 0; k < 4; k++) {
            final p = (bestBits >> (k * 4)) & 15;
            for (var b = 0; b < 4; b++) {
              s[(g * 4 + k) * 4 + b] = ((p >> (3 - b)) & 1).toDouble();
            }
          }
        }
      }
      _decodeLine(s, 0, line, 0, iWidth: 6, qWidth: 8);
      out.pixels.setRange(y * 2 * w, y * 2 * w + w, line);
      out.pixels.setRange((y * 2 + 1) * w, (y * 2 + 1) * w + w, line);
    }
    return out;
  }
}

/// VHS tape: blurry colour shifted to the right, edge halos from the
/// player's sharpening, tape noise, dropouts, tracking errors and the
/// head-switching tear at the bottom.
class Vhs extends VideoEffect {
  @override
  String get id => 'vhs';
  @override
  String get name => 'VHS';
  @override
  String get about =>
      'Smeared, shifted colour, halos, tracking errors, dropouts and head switching.';
  @override
  (int, int) inputSize(int inW, int inH) => byWidth(inW, inH, 320);
  @override
  List<Knob> get knobs => const [
    Knob('tracking', 'Tracking error', value: 0.3),
    Knob('wear', 'Tape wear', value: 0.3),
    Knob('bleed', 'Colour smear', value: 0.6),
  ];

  @override
  VideoFrame process(VideoFrame input, double time) {
    final w = input.width, h = input.height;
    final out = VideoFrame(w, h);
    final rnd = math.Random((time * 30).floor());
    final wear = knob('wear'), tracking = knob('tracking');
    final cw = (6 + knob('bleed') * 30).round();
    final y = Float32List(w),
        yb = Float32List(w),
        i = Float32List(w),
        q = Float32List(w);
    final ib = Float32List(w), qb = Float32List(w);
    Float32List? prevI, prevQ;
    // A tracking band drifts down the picture.
    final bandCentre = (time * 0.15 % 1.3 - 0.15) * h;
    final bandHalf = 4 + tracking * h * 0.12;
    for (var row = 0; row < h; row++) {
      for (var x = 0; x < w; x++) {
        final c = input.pixels[row * w + x];
        y[x] = _y(c);
        i[x] = _i(c);
        q[x] = _q(c);
      }
      // Luma: soft, then the player's sharpening adds halos.
      _box(y, yb, 3);
      final halo = Float32List(w);
      _box(yb, halo, 9);
      // Chroma: very low bandwidth and late (shifted right).
      _box(i, ib, cw);
      _box(q, qb, cw);
      final shift = 3;
      final inBand = (row - bandCentre).abs() < bandHalf && tracking > 0.02;
      final headSwitch = row >= h - 6;
      final offset = inBand
          ? (rnd.nextDouble() * 2 - 1) * tracking * 24
          : headSwitch
          ? (row - (h - 6)) * 3.0 + rnd.nextDouble() * 4
          : (rnd.nextDouble() - 0.5) * 0.8;
      for (var x = 0; x < w; x++) {
        final sx = (x - offset).round().clamp(0, w - 1);
        var yy =
            yb[sx] +
            (yb[sx] - halo[sx]) * 0.7 +
            (rnd.nextDouble() - 0.5) * (0.03 + wear * 0.08);
        if (inBand) yy += (rnd.nextDouble() - 0.5) * tracking * 0.6;
        final cx = (sx - shift).clamp(0, w - 1);
        // Chroma has half the vertical resolution too.
        var ci = ib[cx], cq = qb[cx];
        if (prevI != null) {
          ci = (ci + prevI[cx]) / 2;
          cq = (cq + prevQ![cx]) / 2;
        }
        out.pixels[row * w + x] = _yiq(yy, ci * 0.85, cq * 0.85);
      }
      prevI = Float32List.fromList(ib);
      prevQ = Float32List.fromList(qb);
    }
    // Dropouts: oxide missing from the tape flashes as white streaks.
    final drops = (wear * 12 * rnd.nextDouble()).round();
    for (var d = 0; d < drops; d++) {
      final row = rnd.nextInt(h),
          x0 = rnd.nextInt(w),
          len = 8 + rnd.nextInt(40);
      for (var x = x0; x < math.min(w, x0 + len); x++) {
        out.pixels[row * w + x] = grey(200 + rnd.nextInt(55));
      }
    }
    return out;
  }
}

/// Over-the-air TV with a poor antenna: echoes off buildings arrive late as
/// a ghost to the right, snow, weak colour and jittery lines.
class BadAntenna extends VideoEffect {
  @override
  String get id => 'antenna';
  @override
  String get name => 'Bad antenna';
  @override
  String get about =>
      'Ghost echoes from reflected signals, snow and fading colour.';
  @override
  (int, int) inputSize(int inW, int inH) => byWidth(inW, inH, 320);
  @override
  List<Knob> get knobs => const [
    Knob('signal', 'Signal strength', value: 0.5),
    Knob('ghost', 'Ghost distance', value: 0.4),
  ];

  @override
  VideoFrame process(VideoFrame input, double time) {
    final w = input.width, h = input.height;
    final out = VideoFrame(w, h);
    final rnd = math.Random((time * 60).floor());
    final weak = 1 - knob('signal');
    final d = (6 + knob('ghost') * 40).round();
    final ghostGain = 0.25 + weak * 0.3;
    final snow = weak * weak * 1.2;
    final sat = 1 - weak * 0.9;
    for (var row = 0; row < h; row++) {
      final jitter = ((rnd.nextDouble() - 0.5) * weak * 6).round();
      for (var x = 0; x < w; x++) {
        final sx = (x + jitter).clamp(0, w - 1);
        final c = input.pixels[row * w + sx];
        final g = input.pixels[row * w + (sx - d).clamp(0, w - 1)];
        var yy = _y(c) + ghostGain * (_y(g) - 0.3);
        yy = yy * (1 - snow * 0.5) + snow * rnd.nextDouble();
        out.pixels[row * w + x] = _yiq(yy, _i(c) * sat, _q(c) * sat);
      }
    }
    return out;
  }
}

/// A TV that has lost sync: with the vertical hold off the picture rolls
/// (the black bar is the blanking interval); with the horizontal hold off it
/// tears into diagonal bands.
class SyncLoss extends VideoEffect {
  @override
  String get id => 'sync';
  @override
  String get name => 'Lost sync';
  @override
  String get about =>
      'Vertical roll with the blanking bar, horizontal tearing into diagonals.';
  @override
  (int, int) inputSize(int inW, int inH) => byWidth(inW, inH, 320);
  @override
  List<Knob> get knobs => const [
    Knob('roll', 'Vertical roll', value: 0.3),
    Knob('hold', 'Horizontal hold', value: 0.2),
  ];

  @override
  VideoFrame process(VideoFrame input, double time) {
    final w = input.width, h = input.height;
    final vbi = (h * 0.08).round();
    final total = h + vbi;
    final out = VideoFrame(w, h);
    final roll = (time * knob('roll') * total * 0.8).floor();
    final hold = knob('hold');
    for (var row = 0; row < h; row++) {
      final src = (row + roll) % total;
      // Horizontal hold off: each line starts a little later than the last.
      final skew = (hold * hold * src * 7 + time * hold * 40).floor() % w;
      for (var x = 0; x < w; x++) {
        if (src >= h) {
          // Blanking interval: black, with the darker sync pulse.
          out.pixels[row * w + x] = x < w * 0.08 ? 0xFF050505 : 0xFF141414;
          continue;
        }
        final sx = (x + skew) % w;
        // The sync pulse shows up as a dark band where the line wraps.
        out.pixels[row * w + x] = (hold > 0.02 && sx < w * 0.06)
            ? 0xFF080808
            : input.pixels[src * w + sx];
      }
    }
    return out;
  }
}

/// Interlaced video: odd and even lines are filmed a moment apart, so
/// anything moving gets combed edges.
class Interlace extends VideoEffect {
  final _history = <VideoFrame>[];

  @override
  String get id => 'interlace';
  @override
  String get name => 'Interlace';
  @override
  String get about =>
      'Odd and even lines from different moments: combing on motion.';
  @override
  (int, int) inputSize(int inW, int inH) => byWidth(inW, inH, 320);
  @override
  List<Knob> get knobs => const [
    Knob('gap', 'Field gap (frames)', min: 1, max: 6, value: 2),
  ];

  @override
  void reset() => _history.clear();

  @override
  VideoFrame process(VideoFrame input, double time) {
    _history.add(input);
    final gap = knob('gap').round().clamp(1, 6);
    while (_history.length > gap + 1) {
      _history.removeAt(0);
    }
    final old = _history.first;
    final out = input.copy();
    for (var row = 1; row < input.height; row += 2) {
      out.pixels.setRange(
        row * input.width,
        (row + 1) * input.width,
        old.pixels,
        row * input.width,
      );
    }
    return out;
  }
}
