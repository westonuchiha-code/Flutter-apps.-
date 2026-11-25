/// Turntable scratches, synthesized: a virtual record carries a sample, the
/// hand moves it (its speed and direction bend the pitch) and the
/// crossfader cuts it in and out. Baby, chirp, transformer, flare, scribble,
/// tear and stab patterns, timed to the beat.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'dsp.dart';

/// One hand movement: from [from] to [to] seconds of the record, over
/// [beats] beats; [fader] says when the crossfader is open (0..1 of the
/// move → open?).
class Stroke {
  const Stroke(this.beats, this.from, this.to, {this.fader});
  final double beats, from, to;
  final bool Function(double u)? fader;
}

bool _open(double u) => true;

/// Scratch patterns as strokes, for a sample whose sound starts at 0 and
/// lasts [len] seconds; one pattern takes [beats] beats.
List<Stroke> pattern(String name, double len, {double beats = 1}) {
  final a = len * 0.7;
  switch (name) {
    case 'baby': // forward and back, fader open
      return [Stroke(beats / 2, 0, a), Stroke(beats / 2, a, 0)];
    case 'chirp': // the fader closes as the sound peaks
      return [
        Stroke(beats / 2, 0, a, fader: (u) => u < 0.55),
        Stroke(beats / 2, a, 0, fader: (u) => u > 0.45),
      ];
    case 'transform': // a slow push while the fader taps
      return [
        Stroke(beats, 0, len * 0.9, fader: (u) => ((u * 8).floor()).isEven),
      ];
    case 'flare': // fader open, clicked shut twice per push
      return [
        Stroke(
          beats / 2,
          0,
          a,
          fader: (u) => !((u > 0.3 && u < 0.38) || (u > 0.62 && u < 0.7)),
        ),
        Stroke(
          beats / 2,
          a,
          0,
          fader: (u) => !((u > 0.3 && u < 0.38) || (u > 0.62 && u < 0.7)),
        ),
      ];
    case 'tear': // forward in two bursts, back in one
      return [
        Stroke(beats / 4, 0, a * 0.5),
        Stroke(beats / 4, a * 0.5, a),
        Stroke(beats / 2, a, 0),
      ];
    case 'scribble': // tiny fast wiggles
      return [
        for (var i = 0; i < 8; i++)
          Stroke(beats / 8, i.isEven ? 0.05 : 0.11, i.isEven ? 0.11 : 0.05),
      ];
    case 'stab': // a quick forward stab, then silence back
      return [
        Stroke(beats / 4, 0, a),
        Stroke(beats * 3 / 4, a, 0, fader: (u) => false),
      ];
    default: // 'forward': the sample played forward, fader open
      return [Stroke(beats, 0, len)];
  }
}

/// Renders [strokes] at [bpm] scratching [sample] (mono). The record is
/// pushed and pulled along eased curves; vinyl friction noise follows the
/// hand's speed.
Float32List scratch(
  Float32List sample,
  List<Stroke> strokes,
  double bpm, {
  int seed = 11,
}) {
  final beat = 60 / bpm;
  final total = strokes.fold<double>(0, (s, k) => s + k.beats) * beat;
  final out = buf(total + 0.05);
  final r = Rng(seed);
  final hiss = Biquad.bandPass(2500, 0.7);
  final dc = Biquad.highPass(60);
  var t0 = 0.0;
  var fade = 0.0;
  for (final k in strokes) {
    final dur = k.beats * beat;
    final n = (dur * sr).round();
    final fader = k.fader ?? _open;
    for (var i = 0; i < n; i++) {
      final u = i / n;
      // Ease in and out like a hand (half a cosine).
      final e = 0.5 - 0.5 * math.cos(math.pi * u);
      final pos = (k.from + (k.to - k.from) * e) * sr;
      final speed =
          ((k.to - k.from) * math.pi / 2 * math.sin(math.pi * u) / dur).abs();
      final target = fader(u) ? 1.0 : 0.0;
      fade += (target - fade) * 0.25; // a fast but click-free fader
      final v =
          readAt(sample, pos) + hiss.run(r.noise) * 0.04 * speed.clamp(0, 3);
      final j = ((t0 * sr).round() + i);
      if (j < out.length) out[j] = dc.run(v) * fade;
    }
    t0 += dur;
  }
  return out;
}

/// A scratch routine: pattern names, one per beat, over a sample.
Float32List routine(
  Float32List sample,
  List<String> names,
  double bpm, {
  int seed = 11,
}) {
  final len = sample.length / sr;
  return scratch(
    sample,
    [for (final n in names) ...pattern(n, len)],
    bpm,
    seed: seed,
  );
}

/// The classic "ahhh" scratch sample: a short swelling vowel stab.
Float32List ahh({int seed = 9}) {
  final b = buf(0.6);
  final r = Rng(seed);
  final f1 = Biquad.bandPass(750, 4),
      f2 = Biquad.bandPass(1200, 5),
      f3 = Biquad.bandPass(2600, 6);
  var ph = 0.0;
  for (var i = 0; i < b.length; i++) {
    final t = i / sr;
    ph += 140 / sr;
    final saw = 2 * (ph - ph.floorToDouble()) - 1 + r.noise * 0.1;
    final env = adsr(t, 0.03, 0.1, 0.8, 0.15, 0.4);
    b[i] = (f1.run(saw) + f2.run(saw) * 0.7 + f3.run(saw) * 0.3) * env * 1.4;
  }
  return b;
}
