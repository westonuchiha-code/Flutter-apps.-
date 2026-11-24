import 'dart:math' as math;

import 'package:video_kit/video_kit.dart';

import 'project.dart';

const _bayer8 = [
  0, 32, 8, 40, 2, 34, 10, 42, 48, 16, 56, 24, 50, 18, 58, 26, //
  12, 44, 4, 36, 14, 46, 6, 38, 60, 28, 52, 20, 62, 30, 54, 22,
  3, 35, 11, 43, 1, 33, 9, 41, 51, 19, 59, 27, 49, 17, 57, 25,
  15, 47, 7, 39, 13, 45, 5, 37, 63, 31, 55, 23, 61, 29, 53, 21,
];

double _hash(int a, int b) {
  var h = (a * 374761393 + b * 668265263) & 0x7fffffff;
  h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff;
  return (h & 0xffff) / 65536;
}

int _dim(int c, double k) =>
    0xFF000000 |
    ((((c >> 16) & 255) * k).round().clamp(0, 255) << 16) |
    ((((c >> 8) & 255) * k).round().clamp(0, 255) << 8) |
    ((c & 255) * k).round().clamp(0, 255);

/// Mixes the end of the previous scene ([from]) into the new one ([to]) at
/// progress [p] (0..1). [from] must have [to]'s size. [time] drives noise.
VideoFrame applyTransition(
  Transition kind,
  VideoFrame from,
  VideoFrame to,
  double p,
  double time,
) {
  final w = to.width, h = to.height;
  final out = VideoFrame(w, h);
  final o = out.pixels, a = from.pixels, b = to.pixels;
  final frame = (time * 30).floor();
  switch (kind) {
    case Transition.cut:
      return to;
    case Transition.dither:
      // Ordered dither: new pixels appear in the classic Bayer pattern.
      final k = p * 64;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final i = y * w + x;
          o[i] = _bayer8[(y & 7) * 8 + (x & 7)] < k ? b[i] : a[i];
        }
      }
    case Transition.vhs:
      // The picture rolls (lost vertical hold) with a black blanking bar
      // and tracking noise, then settles on the new scene.
      final src = p < 0.5 ? a : b;
      final q = p < 0.5 ? p * 2 : (1 - p) * 2;
      final roll = (q * q * h).round();
      final bar = math.max(2, h ~/ 12);
      for (var y = 0; y < h; y++) {
        final sy = (y + roll) % h;
        final inBar = ((y + roll) % h) >= h - bar && roll > 0;
        final noisyRow = _hash(y, frame) < 0.15 * q;
        final shift = noisyRow
            ? ((_hash(frame, y) - 0.5) * w * 0.15 * q).round()
            : 0;
        for (var x = 0; x < w; x++) {
          if (inBar) {
            o[y * w + x] = 0xFF000000;
            continue;
          }
          var c = src[sy * w + ((x + shift) % w + w) % w];
          if (noisyRow && _hash(x ~/ 3, y + frame * 7) < 0.2) {
            c = 0xFFE0E0E0;
          }
          o[y * w + x] = c;
        }
      }
    case Transition.sync:
      // Horizontal hold goes: lines tear sideways and the picture darkens;
      // it comes back on the new scene.
      final src = p < 0.5 ? a : b;
      final q = math.sin(p * math.pi);
      for (var y = 0; y < h; y++) {
        final tear =
            (q * w * 0.45 * math.sin(y * 0.045 + time * 25) +
                    q * w * 0.25 * math.sin(y * 0.011 - time * 7))
                .round();
        for (var x = 0; x < w; x++) {
          final c = src[y * w + ((x + tear) % w + w) % w];
          o[y * w + x] = _dim(c, 1 - 0.6 * q);
        }
      }
    case Transition.teletext:
      // A Teletext page change: the screen clears, then the page arrives
      // one character row (of 25) at a time.
      const rows = 25;
      for (var y = 0; y < h; y++) {
        final row = y * rows ~/ h;
        for (var x = 0; x < w; x++) {
          final i = y * w + x;
          if (p < 0.15) {
            o[i] = a[i];
          } else {
            o[i] = row < (p - 0.15) / 0.85 * rows ? b[i] : 0xFF000000;
          }
        }
      }
    case Transition.mosh:
      // Blocks of the old picture slide along before snapping to the new
      // one, like a P-frame applied to the wrong key frame.
      final bs = math.max(8, w ~/ 40);
      final drift = p * bs * 3;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final bx = x ~/ bs, by = y ~/ bs;
          final i = y * w + x;
          if (p * 1.2 > _hash(bx, by) + 0.1) {
            o[i] = b[i];
          } else {
            final dx = ((_hash(by, bx + 7) - 0.5) * 2 * drift).round();
            final dy = ((_hash(bx + 3, by) - 0.5) * 2 * drift).round();
            final sx = (x - dx).clamp(0, w - 1), sy = (y - dy).clamp(0, h - 1);
            // New picture's colours bleed into the dragged old blocks.
            o[i] = p > 0.4 ? b[sy * w + sx] : a[sy * w + sx];
          }
        }
      }
  }
  return out;
}
