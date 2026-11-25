// Voice check: one phrase, slowly, by each chip, no music (MP3).
//   dart run bin/voices.dart <out.mp3> [phrase]
import 'dart:io';
import 'dart:typed_data';

import 'package:album/album.dart';
import 'package:album/dsp.dart';
import 'package:chip_synth/chip_synth.dart';
import 'package:mp3_kit/mp3_kit.dart';

void main(List<String> args) {
  final text = args.length > 1
      ? args[1]
      : 'sixty four squares and a single candle';
  final parts = <Float32List>[];
  for (final mc in crew) {
    final s = SpeechSettings(
      chip: mc.chip,
      pitch: mc.pitch * 1.1,
      speed: 0.85,
      contour: Contour.statement,
    );
    parts.add(trim(renderSpeech(textToSpeech(text), s, rate: sr), 0.004));
    parts.add(Float32List((0.8 * sr).round()));
  }
  final total = parts.fold<int>(0, (a, p) => a + p.length);
  final pcm = Int16List(total * 2);
  var o = 0;
  var peakV = 0.0;
  for (final p in parts) {
    for (final v in p) {
      if (v.abs() > peakV) peakV = v.abs();
    }
  }
  for (final p in parts) {
    for (final v in p) {
      final x = (v / peakV * 0.8 * 32767).round();
      pcm[o++] = x;
      pcm[o++] = x;
    }
  }
  File(
    args[0],
  ).writeAsBytesSync(encodeMp3(pcm, tags: const Mp3Tags(title: 'Voice check')));
  stdout.writeln(
    'order: ${crew.map((m) => '${m.name} (${m.chip.name})').join(', ')}',
  );
}
