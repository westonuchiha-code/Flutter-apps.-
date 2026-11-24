// Digital video faults.
import 'dart:math' as math;
import 'dart:typed_data';

import '../effect.dart';
import '../frame.dart';

final Float64List _cos = () {
  final t = Float64List(64);
  for (var x = 0; x < 8; x++) {
    for (var u = 0; u < 8; u++) {
      t[x * 8 + u] =
          math.cos((2 * x + 1) * u * math.pi / 16) *
          (u == 0 ? math.sqrt1_2 : 1);
    }
  }
  return t;
}();

/// The JPEG luma quantisation table (quality 50).
const _quant = [
  16, 11, 10, 16, 24, 40, 51, 61, 12, 12, 14, 19, 26, 58, 60, 55, //
  14, 13, 16, 24, 40, 57, 69, 56, 14, 17, 22, 29, 51, 87, 80, 62,
  18, 22, 37, 56, 68, 109, 103, 77, 24, 35, 55, 64, 81, 104, 113, 92,
  49, 64, 78, 87, 103, 121, 120, 101, 72, 92, 95, 98, 112, 100, 103, 99,
];

/// 8×8 DCT, quantise with [scale] × the JPEG table, inverse DCT, in place.
void _jpegBlock(Float64List b, double scale) {
  final tmp = Float64List(64), coef = Float64List(64);
  // Forward: rows then columns.
  for (var y = 0; y < 8; y++) {
    for (var u = 0; u < 8; u++) {
      var s = 0.0;
      for (var x = 0; x < 8; x++) {
        s += b[y * 8 + x] * _cos[x * 8 + u];
      }
      tmp[y * 8 + u] = s / 2;
    }
  }
  for (var u = 0; u < 8; u++) {
    for (var v = 0; v < 8; v++) {
      var s = 0.0;
      for (var y = 0; y < 8; y++) {
        s += tmp[y * 8 + u] * _cos[y * 8 + v];
      }
      final q = math.max(1.0, _quant[v * 8 + u] * scale);
      coef[v * 8 + u] = (s / 2 / q).roundToDouble() * q;
    }
  }
  // Inverse.
  for (var v = 0; v < 8; v++) {
    for (var x = 0; x < 8; x++) {
      var s = 0.0;
      for (var u = 0; u < 8; u++) {
        s += coef[v * 8 + u] * _cos[x * 8 + u];
      }
      tmp[v * 8 + x] = s / 2;
    }
  }
  for (var x = 0; x < 8; x++) {
    for (var y = 0; y < 8; y++) {
      var s = 0.0;
      for (var v = 0; v < 8; v++) {
        s += tmp[v * 8 + x] * _cos[y * 8 + v];
      }
      b[y * 8 + x] = s / 2;
    }
  }
}

/// Over-compressed JPEG/MPEG: the picture is cut into 8×8 blocks, fine
/// detail thrown away and colour stored at half size, so blocks, ringing and
/// colour smudges appear.
class JpegBlocks extends VideoEffect {
  @override
  String get id => 'jpeg';
  @override
  String get name => 'JPEG / MPEG blocks';
  @override
  String get about =>
      '8×8 blocks with fine detail thrown away and half-size colour.';
  @override
  (int, int) inputSize(int inW, int inH) {
    final (w, h) = byWidth(inW, inH, 320);
    return (w ~/ 16 * 16, h ~/ 16 * 16);
  }

  @override
  List<Knob> get knobs => const [Knob('crush', 'Compression', value: 0.6)];

  @override
  VideoFrame process(VideoFrame input, double time) {
    final w = input.width, h = input.height;
    final scale = 0.5 + knob('crush') * knob('crush') * 12;
    final y = Float64List(w * h),
        cb = Float64List((w ~/ 2) * (h ~/ 2)),
        cr = Float64List((w ~/ 2) * (h ~/ 2));
    for (var py = 0; py < h; py++) {
      for (var px = 0; px < w; px++) {
        final c = input.pixels[py * w + px];
        final r = (c >> 16) & 255, g = (c >> 8) & 255, b = c & 255;
        y[py * w + px] = 0.299 * r + 0.587 * g + 0.114 * b - 128;
        if (px.isEven && py.isEven) {
          // 4:2:0 colour (one sample per 2×2 pixels).
          final ci = (py ~/ 2) * (w ~/ 2) + px ~/ 2;
          cb[ci] = -0.1687 * r - 0.3313 * g + 0.5 * b;
          cr[ci] = 0.5 * r - 0.4187 * g - 0.0813 * b;
        }
      }
    }
    void blocks(Float64List plane, int pw, int ph, double s) {
      final b = Float64List(64);
      for (var by = 0; by + 8 <= ph; by += 8) {
        for (var bx = 0; bx + 8 <= pw; bx += 8) {
          for (var k = 0; k < 64; k++) {
            b[k] = plane[(by + k ~/ 8) * pw + bx + k % 8];
          }
          _jpegBlock(b, s);
          for (var k = 0; k < 64; k++) {
            plane[(by + k ~/ 8) * pw + bx + k % 8] = b[k];
          }
        }
      }
    }

    blocks(y, w, h, scale);
    blocks(cb, w ~/ 2, h ~/ 2, scale * 1.6);
    blocks(cr, w ~/ 2, h ~/ 2, scale * 1.6);
    final out = VideoFrame(w, h);
    for (var py = 0; py < h; py++) {
      for (var px = 0; px < w; px++) {
        final yy = y[py * w + px] + 128;
        final ci = (py ~/ 2) * (w ~/ 2) + px ~/ 2;
        out.pixels[py * w + px] = rgbClamp(
          yy + 1.402 * cr[ci],
          yy - 0.344 * cb[ci] - 0.714 * cr[ci],
          yy + 1.772 * cb[ci],
        );
      }
    }
    return out;
  }
}

/// Datamosh: compressed video stores mostly "move these blocks" instructions
/// between key frames. Remove the key frames and the movement gets applied
/// to the wrong picture: the old image smears and melts along new motion.
class Datamosh extends VideoEffect {
  VideoFrame? _prevIn, _prevOut;
  double _lastKey = 0;

  @override
  String get id => 'datamosh';
  @override
  String get name => 'Datamosh';
  @override
  String get about =>
      'Key frames removed: block motion drags the old picture along.';
  @override
  (int, int) inputSize(int inW, int inH) {
    final (w, h) = byWidth(inW, inH, 192);
    return (w ~/ 8 * 8, h ~/ 8 * 8);
  }

  @override
  List<Knob> get knobs => const [
    Knob('key', 'New key frame every (s, 0 = never)', max: 10, value: 0),
    Knob('leak', 'Leak of the real picture', value: 0.05),
  ];

  @override
  void reset() {
    _prevIn = null;
    _prevOut = null;
    _lastKey = 0;
  }

  /// Requests a fresh key frame now.
  void keyFrame() => _prevOut = null;

  @override
  VideoFrame process(VideoFrame input, double time) {
    final key = knob('key');
    if (_prevOut == null ||
        _prevIn == null ||
        (key > 0 && time - _lastKey > key)) {
      _lastKey = time;
      _prevIn = input;
      return _prevOut = input;
    }
    final w = input.width, h = input.height;
    final prevIn = _prevIn!, prevOut = _prevOut!;
    final out = VideoFrame(w, h);
    const bs = 8, range = 6;
    int lum(VideoFrame f, int x, int y) =>
        lumaOf(f.pixels[y.clamp(0, h - 1) * w + x.clamp(0, w - 1)]);
    for (var by = 0; by < h; by += bs) {
      for (var bx = 0; bx < w; bx += bs) {
        // Motion search: where did this block come from in the last frame?
        var best = 1 << 30, mx = 0, my = 0;
        for (var dy = -range; dy <= range; dy += 2) {
          for (var dx = -range; dx <= range; dx += 2) {
            var sad = 0;
            for (var y = 0; y < bs && sad < best; y += 2) {
              for (var x = 0; x < bs; x += 2) {
                sad +=
                    (lum(input, bx + x, by + y) -
                            lum(prevIn, bx + x + dx, by + y + dy))
                        .abs();
              }
            }
            if (sad < best) {
              best = sad;
              mx = dx;
              my = dy;
            }
          }
        }
        // Apply that motion to the *moshed* picture, not the real one.
        for (var y = 0; y < bs; y++) {
          for (var x = 0; x < bs; x++) {
            final sx = (bx + x + mx).clamp(0, w - 1),
                sy = (by + y + my).clamp(0, h - 1);
            out.pixels[(by + y) * w + bx + x] = prevOut.pixels[sy * w + sx];
          }
        }
      }
    }
    // A little of the real picture leaks through (like residual data).
    final leak = knob('leak');
    if (leak > 0) {
      for (var i = 0; i < out.pixels.length; i++) {
        final a = out.pixels[i], b = input.pixels[i];
        int m(int s) =>
            ((((a >> s) & 255) * (1 - leak)) + (((b >> s) & 255) * leak))
                .round();
        out.pixels[i] = 0xFF000000 | (m(16) << 16) | (m(8) << 8) | m(0);
      }
    }
    _prevIn = input;
    return _prevOut = out;
  }
}
