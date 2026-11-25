/// Drums and the instruments the "samples" are made from, all synthesized
/// (no records sampled): kicks, snares, hats; Rhodes, upright bass, horns,
/// vibes, strings, piano.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'dsp.dart';

// ---- Drums ----

/// A round, thumping boom bap kick.
Float32List kick({double tone = 1, int seed = 1}) {
  final b = buf(0.5);
  final r = Rng(seed);
  var ph = 0.0;
  for (var i = 0; i < b.length; i++) {
    final t = i / sr;
    final f = 46 * tone + 110 * tone * math.exp(-t / 0.035);
    ph += tau * f / sr;
    var v = math.sin(ph) * decay(t, 0.18);
    v += r.noise * decay(t, 0.004) * 0.35; // beater click
    b[i] = sat(v, 1.8) * 0.9;
  }
  return b;
}

/// A cracking snare: a tone, a burst of noise, a short body.
Float32List snare({double tone = 1, double snap = 1, int seed = 2}) {
  final b = buf(0.4);
  final r = Rng(seed);
  final bp = Biquad.bandPass(1800 * tone, 0.8);
  final hp = Biquad.highPass(400);
  var ph = 0.0;
  for (var i = 0; i < b.length; i++) {
    final t = i / sr;
    ph += tau * (185 * tone + 60 * math.exp(-t / 0.01)) / sr;
    final body = math.sin(ph) * decay(t, 0.05) * 0.6;
    final n = hp.run(r.noise) * decay(t, 0.09 * snap) * 0.8;
    final crack = bp.run(r.noise) * decay(t, 0.015) * 1.2;
    b[i] = sat(body + n + crack, 1.6) * 0.8;
  }
  return b;
}

/// A hi-hat; [open] rings longer.
Float32List hat({bool open = false, int seed = 3}) {
  final b = buf(open ? 0.35 : 0.08);
  final r = Rng(seed);
  final hp = Biquad.highPass(7000);
  final bp = Biquad.bandPass(10000, 1.2);
  for (var i = 0; i < b.length; i++) {
    final t = i / sr;
    // Six detuned square "cymbal" partials plus noise.
    var m = 0.0;
    for (final f in [205.3, 304.4, 369.6, 522.7, 540.0, 800.0]) {
      m += (math.sin(tau * f * 8 * t) > 0 ? 1 : -1);
    }
    final v = hp.run(bp.run(m * 0.12 + r.noise * 0.6));
    b[i] = v * decay(t, open ? 0.12 : 0.018) * 0.55;
  }
  return b;
}

/// A rimshot / side stick.
Float32List rim({int seed = 4}) {
  final b = buf(0.12);
  final r = Rng(seed);
  final bp = Biquad.bandPass(2500, 3);
  for (var i = 0; i < b.length; i++) {
    final t = i / sr;
    b[i] =
        (bp.run(r.noise) * 2 + math.sin(tau * 820 * t) * 0.6) *
        decay(t, 0.012) *
        0.7;
  }
  return b;
}

/// A shaker / tambourine shake.
Float32List shaker({int seed = 5}) {
  final b = buf(0.12);
  final r = Rng(seed);
  final hp = Biquad.highPass(5000);
  for (var i = 0; i < b.length; i++) {
    final t = i / sr;
    final env = math.sin(math.pi * (t / 0.12).clamp(0, 1)) * decay(t, 0.05);
    b[i] = hp.run(r.noise) * env * 0.35;
  }
  return b;
}

// ---- Instruments ----

/// A Fender Rhodes-ish electric piano: FM with a bell that fades.
Float32List rhodes(List<int> notes, double length, {double vel = 1}) {
  final b = buf(length + 1.2);
  for (final n in notes) {
    final f = mtof(n);
    for (var i = 0; i < b.length; i++) {
      final t = i / sr;
      final env = adsr(t, 0.003, 1.2, 0.35, 0.5, length) * vel;
      if (env <= 0 && t > length) break;
      final idx = 1.6 * math.exp(-t / 0.25) + 0.25;
      final mod = math.sin(tau * f * t) * idx;
      final bell = math.sin(tau * f * 14 * t) * math.exp(-t / 0.03) * 0.15;
      b[i] += (math.sin(tau * f * t + mod) + bell) * env * 0.16;
    }
  }
  // Tremolo, like the suitcase model.
  for (var i = 0; i < b.length; i++) {
    b[i] *= 0.85 + 0.15 * math.sin(tau * 4.5 * i / sr);
  }
  return b;
}

/// Upright bass: a plucked, woody low note.
Float32List bass(int note, double length, {double vel = 1}) {
  final b = buf(length + 0.3);
  final f = mtof(note);
  final lp = OnePole();
  var ph = 0.0;
  for (var i = 0; i < b.length; i++) {
    final t = i / sr;
    ph += tau * f / sr;
    final env = adsr(t, 0.004, 0.3, 0.55, 0.12, length) * vel;
    final pluck =
        math.sin(ph) + 0.35 * math.sin(ph * 2) + 0.12 * math.sin(ph * 3);
    final thump = math.sin(ph * 0.5) * math.exp(-t / 0.05) * 0.4;
    b[i] =
        lp.run((pluck + thump) * env, 900 + 2200 * math.exp(-t / 0.06)) * 0.45;
  }
  return b;
}

/// A horn section stab (trumpet + sax, slightly out of tune).
Float32List horns(List<int> notes, double length) {
  final b = buf(length + 0.4);
  for (final n in notes) {
    for (final det in [-0.08, 0.0, 0.11]) {
      final f = mtof(n + det);
      final lp = OnePole();
      var ph = 0.0;
      for (var i = 0; i < b.length; i++) {
        final t = i / sr;
        ph += f / sr;
        final saw = 2 * (ph - ph.floorToDouble()) - 1;
        final env = adsr(t, 0.02, 0.15, 0.7, 0.18, length);
        final bright = 700 + 3000 * adsr(t, 0.03, 0.2, 0.4, 0.2, length);
        b[i] += lp.run(saw * env, bright) * 0.07;
      }
    }
  }
  return b;
}

/// Vibraphone: pure bars with a slow motor tremolo.
Float32List vibes(List<int> notes, double length) {
  final b = buf(length + 2);
  for (final n in notes) {
    final f = mtof(n);
    for (var i = 0; i < b.length; i++) {
      final t = i / sr;
      final env = math.exp(-t / 1.4) * (t < 0.002 ? t / 0.002 : 1);
      b[i] +=
          (math.sin(tau * f * t) +
              0.2 * math.sin(tau * f * 4 * t) * math.exp(-t / 0.2)) *
          env *
          0.13;
    }
  }
  for (var i = 0; i < b.length; i++) {
    b[i] *= 0.7 + 0.3 * math.sin(tau * 5.5 * i / sr);
  }
  return b;
}

/// A string pad (detuned saws, slow swell).
Float32List strings(List<int> notes, double length) {
  final b = buf(length + 0.8);
  for (final n in notes) {
    for (final det in [-0.12, 0.0, 0.09]) {
      final f = mtof(n + det);
      final lp = OnePole();
      var ph = 0.0;
      for (var i = 0; i < b.length; i++) {
        final t = i / sr;
        ph += f / sr;
        final saw = 2 * (ph - ph.floorToDouble()) - 1;
        b[i] += lp.run(saw, 1800) * adsr(t, 0.4, 0.5, 0.8, 0.6, length) * 0.035;
      }
    }
  }
  return b;
}

/// An old upright piano stab.
Float32List piano(List<int> notes, double length) {
  final b = buf(length + 1.5);
  for (final n in notes) {
    final f = mtof(n);
    for (var i = 0; i < b.length; i++) {
      final t = i / sr;
      final env =
          adsr(t, 0.002, 1.5, 0.0, 0.3, length) + math.exp(-t / 0.6) * 0.3;
      var v = 0.0;
      for (var h = 1; h <= 6; h++) {
        v +=
            math.sin(tau * f * h * (1 + 0.0007 * h * h) * t) /
            (h * h) *
            math.exp(-t * h / 1.5);
      }
      b[i] += v * env * 0.12;
    }
  }
  return b;
}

/// A flute line note (breathy sine).
Float32List flute(int note, double length, {int seed = 7}) {
  final b = buf(length + 0.3);
  final r = Rng(seed);
  final f = mtof(note);
  final bp = Biquad.bandPass(f * 2, 2);
  for (var i = 0; i < b.length; i++) {
    final t = i / sr;
    final vib = 1 + 0.006 * math.sin(tau * 5 * t) * (t > 0.2 ? 1 : t / 0.2);
    final env = adsr(t, 0.06, 0.1, 0.8, 0.15, length);
    b[i] =
        (math.sin(tau * f * vib * t) * 0.8 + bp.run(r.noise) * 0.25) *
        env *
        0.2;
  }
  return b;
}
