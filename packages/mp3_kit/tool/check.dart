// Encodes a WAV (16-bit, 44.1 kHz), decodes it again and prints the time
// taken and the signal-to-noise ratio.  dart run tool/check.dart song.wav
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:mp3_kit/mp3_kit.dart';
import 'package:mp3_kit/src/encoder.dart' show shapeAmount;
import 'package:mp3_kit/src/check_decoder.dart';

void main(List<String> args) {
  final b = File(args.first).readAsBytesSync();
  final d = ByteData.sublistView(b);
  var p = 12, ch = 2;
  late Int16List pcm;
  while (p + 8 <= b.length) {
    final id = String.fromCharCodes(b, p, p + 4);
    final n = d.getUint32(p + 4, Endian.little);
    if (id == 'fmt ') ch = d.getUint16(p + 10, Endian.little);
    if (id == 'data') {
      final end = math.min(b.length, p + 8 + n) & ~1;
      pcm = Int16List.fromList(Int16List.sublistView(b, p + 8, end));
    }
    p += 8 + n + (n & 1);
  }
  final alpha = Platform.environment["ALPHA"];
  if (alpha != null) shapeAmount = double.parse(alpha);
  final kbps = args.length > 1 ? int.parse(args[1]) : 320;
  final sw = Stopwatch()..start();
  final mp3 = encodeMp3(pcm, channels: ch, kbps: kbps);
  final enc = sw.elapsedMilliseconds;
  final back = decodeOwnMp3(mp3);
  var sig = 0.0, err = 0.0, hs = 0.0, he = 0.0;
  final n = math.min(pcm.length, back.length);
  for (var i = 0; i < n; i++) {
    sig += pcm[i] * pcm[i].toDouble();
    err += math.pow(pcm[i] - back[i], 2);
    // Upper mids and treble (peaks at 11 kHz, nothing at 22 kHz).
    if (i >= 2 * ch) {
      final a = pcm[i] - pcm[i - 2 * ch];
      final b = back[i] - back[i - 2 * ch];
      hs += a * a.toDouble();
      he += math.pow(a - b, 2);
    }
  }
  double db(double x) => 10 * math.log(x) / math.ln10;
  final secs = pcm.length / ch / 44100;
  stdout.writeln(
    '${secs.toStringAsFixed(1)} s audio, encoded in ${enc / 1000} s, '
    '${mp3.length} bytes, SNR ${db(sig / err).toStringAsFixed(1)} dB, '
    'treble SNR ${db(hs / he).toStringAsFixed(1)} dB',
  );
  if (args.length > 2) File(args[2]).writeAsBytesSync(mp3);
}
