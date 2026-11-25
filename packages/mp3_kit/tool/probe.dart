import 'dart:math' as math;
import 'dart:typed_data';
import 'package:mp3_kit/src/synth.dart';

void main() {
  final resp = <Float64List>[];
  for (var k = 0; k < 32; k++) {
    final s = SynthBank();
    final out = Float64List(576 * 3);
    for (var g = 0; g < 3; g++) {
      final gr = Float64List(576);
      if (g == 0) gr[18 * k] = 1;
      out.setRange(576 * g, 576 * g + 576, s.run(gr));
    }
    resp.add(out);
  }
  var first = 9999, last = 0;
  for (final r in resp) {
    for (var n = 0; n < r.length; n++) {
      if (r[n].abs() > 1e-6) {
        first = math.min(first, n);
        last = math.max(last, n);
      }
    }
  }
  print('nonzero $first..$last');
  // Orthogonality: <g_k shifted by 32m, g_j>.
  double dot(int k, int j, int m) {
    var s = 0.0;
    for (var n = 0; n < 1024; n++) {
      final a = n + 32 * m;
      if (a >= 0 && a < 1700) s += resp[k][n] * resp[j][a];
    }
    return s;
  }

  print(
    'e00 ${dot(0, 0, 0)} e55 ${dot(5, 5, 0)} e05 ${dot(0, 5, 0)} e01 ${dot(0, 1, 0)} e00m1 ${dot(0, 0, 1)} e01m1 ${dot(0, 1, 1)}',
  );
  // Reconstruction of an impulse at sample t through analysis (correlation) + synthesis.
  for (final t in [300, 517, 700]) {
    final y = Float64List(1700);
    for (var m = -40; m < 60; m++) {
      for (var k = 0; k < 32; k++) {
        // s_k[m] = sum_n x[n] g_k[n - 32m], x = delta at t
        final idx = t - 32 * m;
        if (idx < 0 || idx >= 1700) continue;
        final sk = resp[k][idx];
        for (var n = 0; n < 1700; n++) {
          final j = n - 32 * m;
          if (j >= 0 && j < 1700) y[n] += sk * resp[k][j];
        }
      }
    }
    var peak = 0, err = 0.0;
    for (var n = 0; n < 1700; n++) {
      if (y[n].abs() > y[peak].abs()) peak = n;
    }
    for (var n = 0; n < 1700; n++) {
      if (n != peak) err = math.max(err, y[n].abs());
    }
    print('t=$t peak at $peak = ${y[peak]} max other $err');
  }
}
