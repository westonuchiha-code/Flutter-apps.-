// Renders every chip sound and prints level, peak and render speed.
// Run: dart run tool/render_check.dart [outDir]
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:optical_theremin/src/synth/catalog.dart';
import 'package:optical_theremin/src/synth/engine.dart';

void main(List<String> args) {
  const sr = 48000.0;
  for (final chip in chipCatalog) {
    for (final patch in chip.patches) {
      final e = SynthEngine(sr)
        ..configure(SoundSpec(chipId: chip.id, patchId: patch.id));
      const seconds = 2.0;
      final n = (sr * seconds).toInt();
      final out = Float32List(n * 2);
      final sw = Stopwatch()..start();
      // Slide from A2 to A5 with the shape sweeping.
      const block = 480;
      for (var i = 0; i < n; i += block) {
        final t = i / n;
        e.setControls(110 * math.pow(8, t).toDouble(), 1, t);
        e.render(out, math.min(block, n - i), offset: i);
      }
      sw.stop();
      var sum = 0.0, peak = 0.0;
      var bad = false;
      for (final v in out) {
        if (v.isNaN || v.isInfinite) bad = true;
        sum += v * v;
        peak = math.max(peak, v.abs());
      }
      final rms = math.sqrt(sum / out.length);
      final speed = seconds * 1000 / sw.elapsedMilliseconds;
      stdout.writeln(
        '${chip.id.padRight(7)} ${patch.id.padRight(9)} '
        'rms ${rms.toStringAsFixed(3)} peak ${peak.toStringAsFixed(2)} '
        'speed ${speed.toStringAsFixed(0)}x realtime${bad ? '  NaN!' : ''}',
      );
    }
  }
}
