// Checks rendered WAVs: level, peak, clipped samples, quiet gaps and how
// wide the stereo is.   dart run bin/check.dart <folder>
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

void main(List<String> args) {
  final files =
      Directory(args.first)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.wav'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    final bytes = f.readAsBytesSync();
    final pcm = Int16List.sublistView(bytes, 44);
    final n = pcm.length ~/ 2;
    var sum = 0.0, peak = 0, clipped = 0, sl = 0.0, sr2 = 0.0, slr = 0.0;
    for (var i = 0; i < n; i++) {
      final l = pcm[i * 2], r = pcm[i * 2 + 1];
      final m = (l + r) / 65536;
      sum += m * m;
      peak = math.max(peak, math.max(l.abs(), r.abs()));
      if (l.abs() >= 32760 || r.abs() >= 32760) clipped++;
      sl += l * l.toDouble();
      sr2 += r * r.toDouble();
      slr += l * r.toDouble();
    }
    // Quiet half-seconds inside the track (not the first 1 s or last 3 s).
    var quiet = 0;
    const win = 22050;
    for (var w = 2; w < n ~/ win - 6; w++) {
      var e = 0.0;
      for (var i = w * win; i < (w + 1) * win; i++) {
        final m = (pcm[i * 2] + pcm[i * 2 + 1]) / 65536;
        e += m * m;
      }
      if (10 * math.log(e / win + 1e-12) / math.ln10 < -45) quiet++;
    }
    final db = 10 * math.log(sum / n + 1e-12) / math.ln10;
    final corr = slr / math.sqrt(sl * sr2 + 1e-9);
    final name = f.uri.pathSegments.last;
    stdout.writeln(
      '${name.padRight(46).substring(0, 46)} ${(n / 44100).toStringAsFixed(0).padLeft(4)} s  '
      'rms ${db.toStringAsFixed(1).padLeft(6)} dB  peak ${(peak / 32768).toStringAsFixed(2)}  '
      'clipped $clipped  quiet ${quiet / 2} s  L/R ${corr.toStringAsFixed(2)}',
    );
  }
}
