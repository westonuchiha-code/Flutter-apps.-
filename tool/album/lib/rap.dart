/// Chip voices rapping on the beat: each word is spoken by a speech chip
/// (Speech Chip Lab's engines), squeezed or stretched to fit the syllables
/// it gets in the bar, and placed on the 16th-note grid.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:chip_synth/chip_synth.dart';

import 'dsp.dart';

/// An MC: a chip and how it sounds.
class Mc {
  const Mc(this.name, this.chip, this.pitch, {this.gain = 1});
  final String name;
  final SpeechChip chip;
  final double pitch;
  final double gain;
}

int syllables(List<String> ph) {
  final n = ph
      .where(
        (p) =>
            phonemes[p]?.kind == PhonemeKind.vowel ||
            phonemes[p]?.kind == PhonemeKind.diphthong,
      )
      .length;
  return math.max(1, n);
}

final _cache = <String, Float32List>{};

/// One word by [mc], [seconds] long (speed fitted), at 44.1 kHz.
Float32List word(SpokenWord w, Mc mc, double seconds, {double pitchMul = 1}) {
  final key =
      '${w.phonemes.join(' ')}|${mc.chip.name}|${mc.pitch}|$pitchMul|${seconds.toStringAsFixed(3)}';
  final hit = _cache[key];
  if (hit != null) return hit;
  final plain = SpokenWord(w.text, w.phonemes, pauseAfter: '');
  SpeechSettings s(double speed) => SpeechSettings(
    chip: mc.chip,
    pitch: mc.pitch * pitchMul,
    speed: speed,
    contour: Contour.flat,
  );
  var out = trim(renderSpeech([plain], s(1), rate: sr), 0.004);
  final len = out.length / sr;
  final speed = (len / seconds).clamp(0.5, 2.4);
  if ((speed - 1).abs() > 0.08) {
    out = trim(renderSpeech([plain], s(speed), rate: sr), 0.004);
  }
  final copy = Float32List.fromList(out);
  // Soft edges (no clicks).
  final edge = math.min(120, copy.length ~/ 4);
  for (var i = 0; i < edge; i++) {
    copy[i] *= i / edge;
    copy[copy.length - 1 - i] *= i / edge;
  }
  _cache[key] = copy;
  return copy;
}

/// One bar of rap: [line]'s words spread over 16 sixteenths starting at
/// [at] seconds. Ends of lines lean on the last beat; the pitch dips a
/// little at the end, like a real delivery.
void rapBar(
  Float32List dst,
  String line,
  Mc mc,
  double at,
  double bpm, {
  double gain = 1,
  double startSlot = 0,
}) {
  final words = textToSpeech(line);
  if (words.isEmpty) return;
  final sixteenth = 60 / bpm / 4;
  final syl = [for (final w in words) syllables(w.phonemes)];
  final total = syl.fold<int>(0, (a, b) => a + b);
  // Slots per syllable: fill the bar up to the last 16th (or a bit less
  // when there are few syllables, so short lines stay punchy).
  final double room = 16 - startSlot - (total < 10 ? 2 : 0.5);
  final per = math.min(1.6, room / total);
  var slot = startSlot;
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    final len = syl[i] * per * sixteenth;
    final last = i == words.length - 1;
    final double pm = 1 - (last ? 0.06 : 0) + (i == 0 ? 0.03 : 0);
    final v = word(w, mc, len * 0.92, pitchMul: pm);
    mixInto(dst, v, at + slot * sixteenth, gain * mc.gain * (last ? 1.1 : 1));
    slot += syl[i] * per;
  }
}

/// A spoken phrase (no grid), for scratch samples and ad-libs.
Float32List phrase(String text, Mc mc, {double speed = 1}) {
  final s = SpeechSettings(
    chip: mc.chip,
    pitch: mc.pitch,
    speed: speed,
    contour: Contour.statement,
  );
  return trim(renderSpeech(textToSpeech(text), s, rate: sr), 0.004);
}
