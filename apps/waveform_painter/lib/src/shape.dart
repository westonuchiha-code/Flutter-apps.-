import 'dart:math' as math;
import 'dart:typed_data';

/// Points in one drawn cycle.
const wavePoints = 256;

Float32List blankWave() => Float32List(wavePoints);

enum WavePreset {
  sine('Sine'),
  triangle('Triangle'),
  saw('Saw'),
  square('Square'),
  pulse('Pulse 25%'),
  noise('Noise');

  const WavePreset(this.label);
  final String label;

  Float32List build([math.Random? rnd]) {
    final r = rnd ?? math.Random();
    return Float32List.fromList(
      List.generate(wavePoints, (i) {
        final t = i / wavePoints;
        return switch (this) {
          sine => math.sin(2 * math.pi * t),
          triangle => 1 - 4 * (t - 0.25 - (t >= 0.75 ? 1 : 0)).abs(),
          saw => 1 - 2 * t,
          square => t < 0.5 ? 1.0 : -1.0,
          pulse => t < 0.25 ? 1.0 : -1.0,
          noise => r.nextDouble() * 2 - 1,
        };
      }),
    );
  }
}

/// Paints a stroke from (x0,y0) to (x1,y1) in wave coordinates
/// (x 0..1, y -1..1), filling every point in between.
void drawSegment(Float32List w, double x0, double y0, double x1, double y1) {
  final n = w.length;
  var a = (x0 * n).floor().clamp(0, n - 1);
  var b = (x1 * n).floor().clamp(0, n - 1);
  var ya = y0, yb = y1;
  if (a > b) {
    (a, b) = (b, a);
    (ya, yb) = (yb, ya);
  }
  for (var i = a; i <= b; i++) {
    final t = b == a ? 1.0 : (i - a) / (b - a);
    w[i] = (ya + (yb - ya) * t).clamp(-1.0, 1.0);
  }
}

/// Moving-average smoothing (wraps around the cycle).
Float32List smooth(Float32List w, {int radius = 3}) {
  final n = w.length;
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    var sum = 0.0;
    for (var k = -radius; k <= radius; k++) {
      sum += w[(i + k) % n];
    }
    out[i] = sum / (2 * radius + 1);
  }
  return out;
}

/// Second half becomes the upside-down mirror of the first (no even
/// harmonics: hollow, clarinet-like).
Float32List mirror(Float32List w) {
  final n = w.length, h = n ~/ 2;
  final out = Float32List.fromList(w);
  for (var i = 0; i < h; i++) {
    out[h + i] = -w[i];
  }
  return out;
}

/// Removes the offset and scales the loudest point to full height.
Float32List normalize(Float32List w) {
  var mean = 0.0;
  for (final v in w) {
    mean += v;
  }
  mean /= w.length;
  var peak = 0.0;
  for (final v in w) {
    peak = math.max(peak, (v - mean).abs());
  }
  if (peak < 1e-6) return Float32List(w.length);
  return Float32List.fromList([for (final v in w) (v - mean) / peak]);
}

Float32List invert(Float32List w) =>
    Float32List.fromList([for (final v in w) -v]);

Float32List reverse(Float32List w) => Float32List.fromList(w.reversed.toList());

double _luma(Uint8List rgba, int i) =>
    (0.2126 * rgba[i] + 0.7152 * rgba[i + 1] + 0.0722 * rgba[i + 2]) / 255;

/// Brightness along image row [row] (0..1) becomes the wave.
Float32List waveFromRow(Uint8List rgba, int width, int height, double row) {
  final y = (row * (height - 1)).round().clamp(0, height - 1);
  return Float32List.fromList(
    List.generate(wavePoints, (i) {
      final x = (i * width / wavePoints).floor().clamp(0, width - 1);
      return _luma(rgba, (y * width + x) * 4) * 2 - 1;
    }),
  );
}

/// The skyline of the image: in each column, the first point (from the
/// top) that differs from the top-left background colour.
Float32List waveFromOutline(
  Uint8List rgba,
  int width,
  int height, {
  double threshold = 0.18,
}) {
  final bg = _luma(rgba, 0);
  return Float32List.fromList(
    List.generate(wavePoints, (i) {
      final x = (i * width / wavePoints).floor().clamp(0, width - 1);
      var top = height - 1;
      for (var y = 0; y < height; y++) {
        if ((_luma(rgba, (y * width + x) * 4) - bg).abs() > threshold) {
          top = y;
          break;
        }
      }
      return 1 - 2 * top / (height - 1);
    }),
  );
}
