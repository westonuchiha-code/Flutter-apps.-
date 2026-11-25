/// Beep voices: the robots "say" a chant as buzzy chip tones that follow
/// its rhythm and melody, coloured with vowel formants (talking, not
/// words), like game characters' gibberish. One voice is a record being
/// scratched instead.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'dsp.dart';

/// One syllable of a chant: where (16ths into the bar) and how long, its
/// note (semitones from the voice's base), vowel(s) and opening consonant
/// ('' none, 'p' a pop, 's' a hiss).
class Syl {
  const Syl(this.slot, this.len, this.semi, this.vowel, [this.onset = '']);
  final double slot, len;
  final int semi;

  /// 'a', 'e', 'i', 'o', 'u', or two of them for a glide ('ai').
  final String vowel;
  final String onset;
}

/// Formants (F1, F2) for each vowel.
const _formants = {
  'a': (750.0, 1200.0),
  'e': (550.0, 1750.0),
  'i': (320.0, 2250.0),
  'o': (480.0, 900.0),
  'u': (350.0, 800.0),
};

/// How a robot's beeps sound.
class BeepVoice {
  const BeepVoice(this.baseHz, {this.duty = 0.5, this.scratch = false});
  final double baseHz;

  /// Pulse width of the buzz (0.5: square).
  final double duty;

  /// A record scratch instead of a buzz: each syllable is a quick push and
  /// pull of the platter.
  final bool scratch;
}

/// Renders [line] by [voice] at [bpm], one bar long (plus a tail).
Float32List beepLine(List<Syl> line, BeepVoice voice, double bpm) {
  final sixteenth = 60 / bpm / 4;
  final out = buf(sixteenth * 16 + 0.5);
  final r = Rng(voice.baseHz.round());
  for (final s in line) {
    final start = (s.slot * sixteenth * sr).round();
    final n = (s.len * sixteenth * sr * 0.9).round();
    final hz = voice.baseHz * math.pow(2, s.semi / 12);
    final v1 = _formants[s.vowel[0]]!;
    final v2 = _formants[s.vowel[s.vowel.length - 1]]!;
    final f1a = Biquad.bandPass(v1.$1, 3), f2a = Biquad.bandPass(v1.$2, 4);
    final f1b = Biquad.bandPass(v2.$1, 3), f2b = Biquad.bandPass(v2.$2, 4);
    var ph = 0.0;
    for (var i = 0; i < n && start + i < out.length; i++) {
      final t = i / sr;
      // A speech-like scoop into the note, and a fall at the end.
      final scoop = 1 - 0.08 * math.exp(-t / 0.03);
      final fall = i > n * 0.75 ? 1 - 0.05 * (i - n * 0.75) / (n * 0.25) : 1.0;
      var f = hz * scoop * fall;
      if (voice.scratch) {
        // Push forward then pull back: pitch follows the platter's speed.
        final u = i / n;
        f =
            hz *
            (0.35 + 1.4 * math.sin(math.pi * u).abs()) *
            (u < 0.5 ? 1 : 0.8);
      }
      ph += f / sr;
      ph -= ph.floorToDouble();
      double x;
      if (voice.scratch) {
        // A sawtooth with grit, like a scratched horn stab.
        x = 2 * ph - 1 + (r.next - 0.5) * 0.15;
      } else {
        x = ph < voice.duty ? 1.0 : -1.0;
      }
      // Vowel colour (glides from the first vowel to the second).
      final k = s.vowel.length > 1 ? (i / n).clamp(0.0, 1.0) : 0.0;
      final a = f1a.run(x) + 0.6 * f2a.run(x);
      final b = f1b.run(x) + 0.6 * f2b.run(x);
      var y = 0.35 * x + 1.6 * (a * (1 - k) + b * k);
      // Envelope: quick attack, steady, short release.
      final att = math.min(1.0, t / 0.006);
      final rel = math.min(1.0, (n - i) / (0.03 * sr));
      y *= att * rel;
      // 6-bit steps, like a chip's output.
      y = (y * 32).roundToDouble() / 32;
      out[start + i] += y * 0.5;
    }
    // Consonant at the start.
    if (s.onset.isNotEmpty) {
      final m = ((s.onset == 's' ? 0.05 : 0.012) * sr).round();
      final hp = Biquad.highPass(s.onset == 's' ? 4500 : 1500);
      for (var i = 0; i < m && start + i < out.length; i++) {
        final e = 1 - i / m;
        out[start + i] += hp.run(r.next * 2 - 1) * e * 0.35;
      }
    }
  }
  return out;
}

/// "Drop the needle, let it ride / Liquid logic, side to side": the
/// Liquid Logic chorus (bar 1 called by one voice, bar 2 answered by all).
const liquidChorus = <List<Syl>>[
  [
    Syl(0, 2, 7, 'o', 'p'), // drop
    Syl(2, 1, 5, 'e'), // the
    Syl(3, 2, 7, 'i'), // nee
    Syl(5, 1, 3, 'e', 'p'), // dle
    Syl(8, 1, 0, 'e'), // let
    Syl(9, 1, 3, 'i', 'p'), // it
    Syl(10, 4, 0, 'ai'), // ride
  ],
  [
    Syl(0, 1, 7, 'i'), // liq
    Syl(1, 1, 7, 'i'), // uid
    Syl(2, 2, 10, 'o'), // lo
    Syl(4, 2, 7, 'i', 'p'), // gic
    Syl(8, 2, 5, 'ai', 's'), // side
    Syl(10, 1, 3, 'u', 'p'), // to
    Syl(11, 4, 0, 'ai', 's'), // side
  ],
];

/// The crew's beep voices: Lexicon (low square), Sputnik (thin pulse), Vox
/// (scratched).
const beepVoices = [
  BeepVoice(110),
  BeepVoice(220, duty: 0.25),
  BeepVoice(165, scratch: true),
];
