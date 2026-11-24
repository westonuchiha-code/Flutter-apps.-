// Prints loudness and length of a test phrase on each speech chip.
import 'dart:math' as math;

import 'package:chip_synth/chip_synth.dart';

void main() {
  final words = textToSpeech(
    'Hello world. This is a talking computer, testing one two three.',
  );
  for (final chip in SpeechChip.values) {
    for (final whisper in [false, true]) {
      final s = renderSpeech(
        words,
        SpeechSettings(chip: chip, whisper: whisper),
      );
      var sum = 0.0, peak = 0.0;
      for (final v in s) {
        sum += v * v;
        peak = math.max(peak, v.abs());
      }
      print(
        '${chip.name.padRight(8)} whisper=$whisper rms=${math.sqrt(sum / s.length).toStringAsFixed(3)} '
        'peak=${peak.toStringAsFixed(2)} secs=${(s.length / 48000).toStringAsFixed(2)}',
      );
    }
  }
}
