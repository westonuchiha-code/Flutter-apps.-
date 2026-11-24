// Rough speed check: seconds of audio rendered per second of CPU.
import 'dart:typed_data';

import 'package:beat_kit/beat_kit.dart';

void main() {
  final e = BeatEngine()..handle(const SetTempo(140, 0.1));
  for (var p = 0; p < padCount; p++) {
    e
      ..handle(SetSample(p, Float32List(48000 * 2)..fillRange(0, 96000, 0.1)))
      ..handle(SetPad(p, PadSettings(pitch: p - 8.0, mode: PadMode.loop)))
      ..handle(Trigger(p));
  }
  for (var l = 0; l < 4; l++) {
    e.handle(AddLayer(l, Float32List(48000 * 4), 0));
  }
  e
    ..handle(SetPattern(List.filled(padCount, 0x5555), 16))
    ..handle(const SetPlaying(true));
  final out = Float32List(192 * 2);
  final sw = Stopwatch()..start();
  const seconds = 20;
  for (var i = 0; i < 48000 * seconds ~/ 192; i++) {
    e.render(out, 192);
  }
  final t = sw.elapsedMilliseconds / 1000;
  print(
    'Rendered ${seconds}s in ${t.toStringAsFixed(2)}s: ${(seconds / t).toStringAsFixed(0)}x real time',
  );
}
