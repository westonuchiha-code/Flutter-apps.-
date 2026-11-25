/// Small DSP kit for rendering music offline (mono buffers, 44.1 kHz).
library;

import 'dart:math' as math;
import 'dart:typed_data';

const sr = 44100.0;
const tau = math.pi * 2;

/// A seeded random source (every render is the same).
class Rng {
  Rng(int seed) : _r = math.Random(seed);
  final math.Random _r;
  double get next => _r.nextDouble();
  double get noise => _r.nextDouble() * 2 - 1;
  int pick(int n) => _r.nextInt(n);
}

Float32List buf(double seconds) => Float32List((seconds * sr).ceil());

/// Adds [src] into [dst] at [at] seconds, times [gain].
void mixInto(Float32List dst, Float32List src, double at, [double gain = 1]) {
  final o = (at * sr).round();
  for (var i = 0; i < src.length; i++) {
    final j = o + i;
    if (j < 0) continue;
    if (j >= dst.length) break;
    dst[j] += src[i] * gain;
  }
}

/// RBJ biquad (one channel).
class Biquad {
  double b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0;
  double _x1 = 0, _x2 = 0, _y1 = 0, _y2 = 0;

  Biquad.lowPass(double f, [double q = 0.707]) {
    _set(f, q, 0);
  }
  Biquad.highPass(double f, [double q = 0.707]) {
    _set(f, q, 1);
  }
  Biquad.bandPass(double f, [double q = 1]) {
    _set(f, q, 2);
  }
  Biquad.peak(double f, double db, [double q = 1]) {
    final a = math.pow(10, db / 40).toDouble();
    final w = tau * f / sr, al = math.sin(w) / (2 * q), c = math.cos(w);
    final a0 = 1 + al / a;
    b0 = (1 + al * a) / a0;
    b1 = -2 * c / a0;
    b2 = (1 - al * a) / a0;
    a1 = -2 * c / a0;
    a2 = (1 - al / a) / a0;
  }

  void _set(double f, double q, int type) {
    final w = tau * f.clamp(10, sr * 0.45) / sr;
    final al = math.sin(w) / (2 * q), c = math.cos(w);
    final a0 = 1 + al;
    switch (type) {
      case 0:
        b0 = (1 - c) / 2 / a0;
        b1 = (1 - c) / a0;
        b2 = b0;
      case 1:
        b0 = (1 + c) / 2 / a0;
        b1 = -(1 + c) / a0;
        b2 = b0;
      default:
        b0 = al / a0;
        b1 = 0;
        b2 = -al / a0;
    }
    a1 = -2 * c / a0;
    a2 = (1 - al) / a0;
  }

  double run(double x) {
    final y = b0 * x + b1 * _x1 + b2 * _x2 - a1 * _y1 - a2 * _y2;
    _x2 = _x1;
    _x1 = x;
    _y2 = _y1;
    _y1 = y;
    return y;
  }

  void process(Float32List b) {
    for (var i = 0; i < b.length; i++) {
      b[i] = run(b[i]);
    }
  }
}

/// A one-pole low pass whose cutoff can move every sample.
class OnePole {
  double _y = 0;
  double run(double x, double hz) {
    final k = 1 - math.exp(-tau * hz / sr);
    _y += (x - _y) * k;
    return _y;
  }
}

/// Soft saturation.
double sat(double x, [double drive = 1]) {
  final v = x * drive;
  return (v / (1 + v.abs())) * (1 + 1 / drive.clamp(1, 10)) / 2 * 1.9;
}

/// Exponential decay envelope value at t (seconds) for a time constant.
double decay(double t, double tc) => math.exp(-t / tc);

/// Attack-decay-sustain-release, gate [length] seconds.
double adsr(double t, double a, double d, double s, double r, double length) {
  if (t < 0) return 0;
  if (t < a) return t / a;
  if (t < a + d) return 1 - (1 - s) * (t - a) / d;
  if (t < length) return s;
  final rel = s * (1 - (t - length) / r);
  return rel > 0 ? rel : 0;
}

double mtof(num m) => 440 * math.pow(2, (m - 69) / 12).toDouble();

/// Peak level of [b].
double peak(Float32List b) {
  var p = 0.0;
  for (final v in b) {
    final a = v.abs();
    if (a > p) p = a;
  }
  return p;
}

void scale(Float32List b, double g) {
  for (var i = 0; i < b.length; i++) {
    b[i] *= g;
  }
}

void normalize(Float32List b, [double to = 0.9]) {
  final p = peak(b);
  if (p > 0) scale(b, to / p);
}

/// Cuts silence off both ends (below [floor]).
Float32List trim(Float32List b, [double floor = 0.01]) {
  var s = 0, e = b.length;
  while (s < e && b[s].abs() < floor) {
    s++;
  }
  while (e > s && b[e - 1].abs() < floor) {
    e--;
  }
  return Float32List.sublistView(b, s, e);
}

/// Linear-interpolated read at fractional [pos] (0 outside).
double readAt(Float32List b, double pos) {
  if (pos < 0 || pos >= b.length - 1) return 0;
  final i = pos.floor();
  final f = pos - i;
  return b[i] * (1 - f) + b[i + 1] * f;
}

/// Resamples [b] by [ratio] (2: twice as fast and high).
Float32List resample(Float32List b, double ratio) {
  final out = Float32List((b.length / ratio).floor());
  for (var i = 0; i < out.length; i++) {
    out[i] = readAt(b, i * ratio);
  }
  return out;
}

/// The SP-1200 treatment: 26.04 kHz, 12 bits, no smoothing between
/// samples, then the output filter.
void sp1200(Float32List b, {double filterHz = 11000}) {
  const rate = 26040.0;
  final step = sr / rate;
  var acc = 0.0, held = 0.0;
  final lp = Biquad.lowPass(filterHz);
  for (var i = 0; i < b.length; i++) {
    acc += 1;
    if (acc >= step) {
      acc -= step;
      held = (b[i].clamp(-1.0, 1.0) * 2047).roundToDouble() / 2047;
    }
    b[i] = lp.run(held);
  }
}

/// Vinyl surface: crackle pops and hiss.
Float32List vinyl(
  double seconds,
  int seed, {
  double crackle = 1,
  double hiss = 1,
}) {
  final r = Rng(seed);
  final out = buf(seconds);
  final hp = Biquad.highPass(900);
  final lp = Biquad.lowPass(7000);
  for (var i = 0; i < out.length; i++) {
    var v = r.noise * 0.004 * hiss;
    if (r.next < 0.0006 * crackle) v += r.noise * (0.05 + r.next * 0.25);
    out[i] = lp.run(hp.run(v));
  }
  return out;
}

/// Simple feedback-delay room reverb (mono in, mono out).
Float32List room(Float32List b, {double size = 0.3, double mix = 0.2}) {
  final delays = [
    1557,
    1617,
    1491,
    1422,
  ].map((d) => (d * (0.5 + size)).round()).toList();
  final lines = [for (final d in delays) Float32List(d)];
  final idx = List.filled(4, 0);
  final lp = [for (var i = 0; i < 4; i++) OnePole()];
  final out = Float32List(b.length);
  for (var n = 0; n < b.length; n++) {
    var wet = 0.0;
    for (var k = 0; k < 4; k++) {
      final y = lines[k][idx[k]];
      wet += y;
      lines[k][idx[k]] = b[n] + lp[k].run(y, 3500) * (0.72 + size * 0.2);
      idx[k] = (idx[k] + 1) % delays[k];
    }
    out[n] = b[n] * (1 - mix) + wet * 0.25 * mix;
  }
  return out;
}

/// Feed-forward compressor with makeup gain.
void compress(
  Float32List b, {
  double threshold = 0.3,
  double ratio = 4,
  double attack = 0.003,
  double release = 0.12,
  double makeup = 1.5,
}) {
  var env = 0.0;
  final ka = 1 - math.exp(-1 / (attack * sr)),
      kr = 1 - math.exp(-1 / (release * sr));
  for (var i = 0; i < b.length; i++) {
    final a = b[i].abs();
    env += (a - env) * (a > env ? ka : kr);
    var g = 1.0;
    if (env > threshold) g = (threshold + (env - threshold) / ratio) / env;
    b[i] *= g * makeup;
  }
}
