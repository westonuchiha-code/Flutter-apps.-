// Drawn single-cycle waves as a band-limited, morphable wavetable.
import 'dart:math' as math;
import 'dart:typed_data';

/// Samples per cycle inside a wavetable.
const tableSize = 2048;

/// Mip levels: level k keeps at most `tableSize/2 >> k` harmonics.
const _levels = 11;

/// In-place radix-2 FFT on (re, im); [inverse] scales by 1/n.
void fft(Float64List re, Float64List im, {bool inverse = false}) {
  final n = re.length;
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; j & bit != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      var t = re[i];
      re[i] = re[j];
      re[j] = t;
      t = im[i];
      im[i] = im[j];
      im[j] = t;
    }
  }
  for (var len = 2; len <= n; len <<= 1) {
    final ang = 2 * math.pi / len * (inverse ? 1 : -1);
    final wr = math.cos(ang), wi = math.sin(ang);
    for (var i = 0; i < n; i += len) {
      var cr = 1.0, ci = 0.0;
      for (var k = 0; k < len ~/ 2; k++) {
        final a = i + k, b = a + len ~/ 2;
        final xr = re[b] * cr - im[b] * ci;
        final xi = re[b] * ci + im[b] * cr;
        re[b] = re[a] - xr;
        im[b] = im[a] - xi;
        re[a] += xr;
        im[a] += xi;
        final nr = cr * wr - ci * wi;
        ci = cr * wi + ci * wr;
        cr = nr;
      }
    }
  }
  if (inverse) {
    for (var i = 0; i < n; i++) {
      re[i] /= n;
      im[i] /= n;
    }
  }
}

/// Resamples a drawn cycle of any length to [size] points (linear,
/// wrapping), removes DC and scales the peak to 1 (silence stays silent).
Float32List prepareCycle(List<double> points, {int size = tableSize}) {
  final out = Float32List(size);
  final n = points.length;
  if (n == 0) return out;
  for (var i = 0; i < size; i++) {
    final p = i * n / size;
    final i0 = p.floor() % n;
    final i1 = (i0 + 1) % n;
    final t = p - p.floor();
    out[i] = points[i0] + (points[i1] - points[i0]) * t;
  }
  var mean = 0.0;
  for (final v in out) {
    mean += v;
  }
  mean /= size;
  var peak = 0.0;
  for (var i = 0; i < size; i++) {
    out[i] -= mean;
    peak = math.max(peak, out[i].abs());
  }
  if (peak > 1e-6) {
    for (var i = 0; i < size; i++) {
      out[i] /= peak;
    }
  }
  return out;
}

/// Up to a few single-cycle waves to morph between, each band-limited at
/// every octave so high notes don't alias.
class Wavetable {
  Wavetable._(this.cycles, this._mips);

  /// Builds a table from drawn cycles (any length each).
  factory Wavetable.fromCycles(List<List<double>> drawn) {
    final cycles = [for (final d in drawn) prepareCycle(d)];
    if (cycles.isEmpty) cycles.add(Float32List(tableSize));
    return Wavetable._(cycles, [for (final c in cycles) _bandLimit(c)]);
  }

  /// Prepared cycles (tableSize each).
  final List<Float32List> cycles;
  final List<List<Float32List>> _mips;

  int get length => cycles.length;

  static List<Float32List> _bandLimit(Float32List cycle) {
    final re = Float64List(tableSize), im = Float64List(tableSize);
    for (var i = 0; i < tableSize; i++) {
      re[i] = cycle[i];
    }
    fft(re, im);
    final levels = <Float32List>[];
    for (var k = 0; k < _levels; k++) {
      final keep = (tableSize ~/ 2) >> k; // highest harmonic kept
      final r = Float64List.fromList(re), m = Float64List.fromList(im);
      for (var h = keep + 1; h < tableSize - keep; h++) {
        r[h] = 0;
        m[h] = 0;
      }
      if (keep == tableSize ~/ 2) {
        // Nyquist bin is ambiguous; drop it.
        r[keep] = 0;
        m[keep] = 0;
      }
      fft(r, m, inverse: true);
      levels.add(Float32List.fromList(r));
    }
    return levels;
  }

  /// Mip level for a phase increment ([hz] / sample rate).
  static int levelFor(double inc) {
    if (inc <= 0) return 0;
    final maxHarm = 0.5 / inc; // harmonics below Nyquist
    var k = 0;
    while (k < _levels - 1 && ((tableSize ~/ 2) >> k) > maxHarm) {
      k++;
    }
    return k;
  }

  static double _read(Float32List t, double phase) {
    final p = phase * tableSize;
    final i0 = p.floor() & (tableSize - 1);
    final i1 = (i0 + 1) & (tableSize - 1);
    final f = p - p.floor();
    return t[i0] + (t[i1] - t[i0]) * f;
  }

  /// One sample at [phase] (0..1), morph position [morph] (0..1 across
  /// the cycles) and phase increment [inc] (for band-limiting).
  double sample(double phase, double morph, double inc) {
    final level = levelFor(inc);
    if (cycles.length == 1) return _read(_mips[0][level], phase);
    final pos = morph.clamp(0.0, 1.0) * (cycles.length - 1);
    final i0 = pos.floor().clamp(0, cycles.length - 1);
    final i1 = math.min(i0 + 1, cycles.length - 1);
    final t = pos - i0;
    final a = _read(_mips[i0][level], phase);
    if (t == 0 || i0 == i1) return a;
    return a + (_read(_mips[i1][level], phase) - a) * t;
  }

  /// The full-bandwidth cycle at a morph position (for export/preview).
  Float32List cycleAt(double morph) {
    final out = Float32List(tableSize);
    for (var i = 0; i < tableSize; i++) {
      out[i] = sample(i / tableSize, morph, 0);
    }
    return out;
  }
}
