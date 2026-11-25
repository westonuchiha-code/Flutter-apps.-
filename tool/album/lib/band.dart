/// A band engine for the non-hip-hop video styles: new instruments
/// (plucked and distorted guitar, synth and slap bass, clavinet, trumpet,
/// a synth whistle, toms, claps) and songs written bar by bar, in any
/// meter. Every sound is synthesized here, like the rest of the album.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'dsp.dart';
import 'instruments.dart';
import 'song.dart' show Mix, master;

// ---- A resonant filter that can move (state variable). ----

class Svf {
  double _lp = 0, _bp = 0;

  /// Low pass at [hz] with resonance [q] (0.5 soft .. 8 whistling).
  double lp(double x, double hz, [double q = 0.7]) {
    final f = 2 * math.sin(math.pi * math.min(hz, sr / 6) / sr);
    final hp = x - _lp - _bp / q;
    _bp += f * hp;
    _lp += f * _bp;
    return _lp;
  }

  double bp(double x, double hz, [double q = 2]) {
    lp(x, hz, q);
    return _bp;
  }
}

// ---- Instruments ----

/// A plucked string (Karplus-Strong): [bright] 0 dark .. 1 bright.
Float32List pluck(
  int note,
  double length, {
  double bright = 0.5,
  int seed = 1,
}) {
  final b = buf(length + 0.6);
  final r = Rng(seed + note);
  final n = math.max(2, (sr / mtof(note)).round());
  final line = Float32List(n);
  for (var i = 0; i < n; i++) {
    line[i] = r.noise;
  }
  final damp = 0.5 - 0.48 * (1 - bright);
  var k = 0;
  final rel = (length * sr).round();
  for (var i = 0; i < b.length; i++) {
    final next = (k + 1) % n;
    var v = line[k] * (1 - damp) + line[next] * damp;
    v *= i > rel ? 0.985 : 0.9995;
    line[k] = v;
    b[i] = v * 0.5;
    k = next;
  }
  return b;
}

/// A strummed chord: strings a few ms apart ([down] low to high).
Float32List strum(
  List<int> notes,
  double length, {
  bool down = true,
  double bright = 0.6,
  int seed = 1,
}) {
  final order = down ? notes : notes.reversed.toList();
  final b = buf(length + 0.8);
  for (final (i, n) in order.indexed) {
    mixInto(
      b,
      pluck(n, length, bright: bright, seed: seed + i),
      i * 0.012,
      0.5,
    );
  }
  return b;
}

/// A distorted power chord (root, fifth, octave): two detuned saws a note,
/// driven hard, through a speaker cabinet. [mute]: palm-muted chug.
Float32List power(int root, double length, {bool mute = false}) {
  final b = buf(length + (mute ? 0.05 : 0.3));
  final svf = Svf(), hp = Biquad.highPass(90);
  final notes = [root, root + 7, root + 12];
  final ph = List.filled(notes.length * 2, 0.0);
  for (var i = 0; i < b.length; i++) {
    final t = i / sr;
    var x = 0.0;
    for (var k = 0; k < ph.length; k++) {
      final f = mtof(notes[k ~/ 2] + (k.isEven ? -0.07 : 0.07));
      ph[k] += f / sr;
      x += 2 * (ph[k] - ph[k].floorToDouble()) - 1;
    }
    final env = mute
        ? math.exp(-t / 0.07) * (t < length ? 1 : 0.2)
        : adsr(t, 0.003, 0.4, 0.75, 0.15, length);
    var v = sat(x * 0.6 * env, 6);
    v = svf.lp(v, mute ? 1300 : 3600, 0.9);
    b[i] = hp.run(v) * 0.35;
  }
  return b;
}

/// An analog synth bass: saw + square sub through a resonant low pass
/// that opens on each note; [from] slides in from another note.
Float32List synthBass(
  int note,
  double length, {
  double cutoff = 900,
  double res = 2.5,
  int? from,
}) {
  final b = buf(length + 0.2);
  final svf = Svf();
  var ph = 0.0, sub = 0.0;
  for (var i = 0; i < b.length; i++) {
    final t = i / sr;
    final glide = from == null ? 1.0 : math.min(1.0, t / 0.06);
    final m = from == null ? note.toDouble() : from + (note - from) * glide;
    final f = mtof(m);
    ph += f / sr;
    sub += f / 2 / sr;
    final saw = 2 * (ph - ph.floorToDouble()) - 1;
    final sq = (sub - sub.floorToDouble()) < 0.5 ? 1.0 : -1.0;
    final env = adsr(t, 0.004, 0.25, 0.6, 0.08, length);
    final fc = cutoff * (0.6 + 3 * math.exp(-t / 0.08));
    b[i] = sat(svf.lp((saw * 0.6 + sq * 0.5) * env, fc, res), 1.4) * 0.5;
  }
  return b;
}

/// A slapped bass note (thumb), or [pop] (a snapped higher string).
Float32List slap(int note, double length, {bool pop = false}) {
  final b = buf(length + 0.2);
  final f = mtof(note);
  final svf = Svf();
  var ph = 0.0;
  for (var i = 0; i < b.length; i++) {
    final t = i / sr;
    ph += tau * f / sr;
    final env = adsr(t, 0.002, 0.18, 0.5, 0.06, length);
    final tone =
        math.sin(ph) +
        0.6 * math.sin(2 * ph) +
        0.45 * math.sin(3 * ph) +
        0.3 * math.sin(5 * ph);
    final bright = (pop ? 4500 : 2600) * math.exp(-t / 0.04) + 500;
    b[i] = sat(svf.lp(tone * env, bright, 1.2) * (pop ? 1.2 : 1), 1.5) * 0.4;
  }
  return b;
}

/// A clavinet chop: thin pulse strings, a fast decay and a wah sweep.
Float32List clav(List<int> notes, double length, {double wah = 1}) {
  final b = buf(length + 0.1);
  final svf = Svf(), hp = Biquad.highPass(250);
  final ph = List.filled(notes.length, 0.0);
  for (var i = 0; i < b.length; i++) {
    final t = i / sr;
    var x = 0.0;
    for (var k = 0; k < notes.length; k++) {
      ph[k] += mtof(notes[k]) / sr;
      x += (ph[k] - ph[k].floorToDouble()) < 0.22 ? 1 : -0.3;
    }
    final env =
        math.exp(-t / 0.12) * (t < length ? 1 : math.exp(-(t - length) / 0.01));
    final sweep =
        600 + 2400 * wah * math.min(1.0, t / 0.05) * math.exp(-t / 0.2);
    b[i] = hp.run(svf.bp(x * env, sweep, 3)) * 0.4;
  }
  return b;
}

/// A trumpet line note: brassy saw, brightness swelling with the breath,
/// vibrato after a moment, a little air.
Float32List trumpet(int note, double length, {int seed = 3}) {
  final b = buf(length + 0.25);
  final r = Rng(seed + note);
  final svf = Svf();
  var ph = 0.0;
  for (var i = 0; i < b.length; i++) {
    final t = i / sr;
    final vib = t > 0.18 ? math.sin(tau * 5.5 * t) * 0.12 : 0.0;
    final scoop = -0.4 * math.exp(-t / 0.03);
    ph += mtof(note + vib + scoop) / sr;
    final saw = 2 * (ph - ph.floorToDouble()) - 1;
    final env = adsr(t, 0.03, 0.1, 0.85, 0.12, length);
    final v = saw + r.noise * 0.08;
    b[i] = sat(svf.lp(v * env, 900 + 3200 * env, 1.1), 1.3) * 0.32;
  }
  return b;
}

/// A synth lead whistle (the space-funk kind): sine and triangle, a slow
/// slide from [from], wide vibrato.
Float32List whistle(int note, double length, {int? from}) {
  final b = buf(length + 0.3);
  var ph = 0.0;
  for (var i = 0; i < b.length; i++) {
    final t = i / sr;
    final glide = from == null ? 1.0 : math.min(1.0, t / 0.18);
    final m = (from ?? note) + (note - (from ?? note)) * glide;
    final vib = math.sin(tau * 6 * t) * 0.25 * math.min(1.0, t / 0.3);
    ph += mtof(m + vib) / sr;
    final p = ph - ph.floorToDouble();
    final tri = 4 * (p < 0.5 ? p : 1 - p) - 1;
    final env = adsr(t, 0.02, 0.1, 0.9, 0.2, length);
    b[i] = (math.sin(tau * p) * 0.7 + tri * 0.3) * env * 0.3;
  }
  return b;
}

/// A tom: a falling sine and a slap of noise.
Float32List tom(int note, {int seed = 5}) {
  final b = buf(0.6);
  final r = Rng(seed + note);
  final f0 = mtof(note);
  var ph = 0.0;
  for (var i = 0; i < b.length; i++) {
    final t = i / sr;
    ph += tau * f0 * (1 + 0.6 * math.exp(-t / 0.03)) / sr;
    b[i] =
        sat(
          math.sin(ph) * decay(t, 0.22) + r.noise * decay(t, 0.01) * 0.3,
          1.4,
        ) *
        0.7;
  }
  return b;
}

/// Hand claps: three quick noise bursts and a tail.
Float32List clap({int seed = 6}) {
  final b = buf(0.35);
  final r = Rng(seed);
  final bp = Biquad.bandPass(1300, 1.4);
  for (var i = 0; i < b.length; i++) {
    final t = i / sr;
    var e = 0.0;
    for (final s in [0.0, 0.011, 0.022]) {
      if (t >= s) e = math.max(e, math.exp(-(t - s) / 0.006));
    }
    e = math.max(e, t >= 0.03 ? 0.45 * math.exp(-(t - 0.03) / 0.09) : 0);
    b[i] = bp.run(r.noise) * e * 1.3;
  }
  return b;
}

// ---- Songs written bar by bar ----

/// One section: its name in the song map (intro, verse, hook, break,
/// outro), a label for the bar function, how many bars and how hard.
typedef BandSection = ({String map, String part, int bars, double energy});

class BandSong {
  const BandSong({
    required this.title,
    required this.bpm,
    required this.steps,
    required this.sections,
    required this.bar,
    this.room = 0.15,
    this.dry = false,
  });
  final String title;
  final double bpm;

  /// 16ths in a bar (16 for 4/4, 14 for 7/8).
  final int steps;
  final List<BandSection> sections;

  /// Plays one bar: (mix, part, bar in the section, bar number, start
  /// time, length of a 16th).
  final void Function(Mix m, String part, int i, int barNo, double t, double s)
  bar;
  final double room;
  final bool dry;

  double get sixteenth => 60 / bpm / 4;
  double get barSeconds => sixteenth * steps;
  int get bars => sections.fold(0, (a, s) => a + s.bars);
}

Float32List renderBand(BandSong song) {
  final mix = Mix(song.bars * song.barSeconds + 3);
  var barNo = 0;
  for (final sec in song.sections) {
    for (var i = 0; i < sec.bars; i++, barNo++) {
      song.bar(
        mix,
        sec.part,
        i,
        barNo,
        barNo * song.barSeconds,
        song.sixteenth,
      );
    }
  }
  if (!song.dry) {
    final l = room(mix.l, size: 0.35, mix: song.room);
    final r = room(mix.r, size: 0.38, mix: song.room);
    mix.l.setRange(0, mix.l.length, l);
    mix.r.setRange(0, mix.r.length, r);
  }
  return master(mix, seconds: song.bars * song.barSeconds + 1.5);
}

/// The song map (bar length = the bar, whatever the meter).
Map<String, Object?> bandMapJson(BandSong song) => {
  'kind': 'song_map',
  'bpm': 240 / song.barSeconds,
  'bars': [
    for (final s in song.sections)
      for (var i = 0; i < s.bars; i++) {'s': s.map, 'e': s.energy},
  ],
};

/// Drums from a pattern ('x' hit, 'o' accent, 'g' ghost) on 16ths.
void drums(
  Mix m,
  Map<Float32List, String> parts,
  double t,
  double s, {
  double gain = 1,
  double swing = 0,
}) {
  parts.forEach((sound, pat) {
    for (var k = 0; k < pat.length; k++) {
      final c = pat[k];
      if (c == '.') continue;
      final v = c == 'o' ? 1.15 : (c == 'g' ? 0.35 : 0.85);
      final sw = k.isOdd ? swing * s : 0.0;
      m.add(sound, t + k * s + sw, v * gain);
    }
  });
}

// ---- The three band songs ----

/// "Undertow" (for the Tool-style video): 7/8, drop-D riff, tribal toms,
/// a clean arpeggio break, heavy sections.
BandSong undertowSong() {
  final k = kick(tone: 0.85, seed: 31), s = snare(tone: 0.8, seed: 32);
  final h = hat(seed: 33),
      lowTom = tom(40),
      floorTom = tom(35),
      hiTom = tom(47);
  // 7/8 riff (14 sixteenths, 2+2+3 feel): (step, note, length in 16ths).
  const riffA = [
    (0, 38, 2),
    (2, 38, 1),
    (4, 41, 2),
    (6, 38, 1),
    (8, 43, 2),
    (10, 44, 2),
    (12, 41, 2),
  ];
  const riffB = [
    (0, 38, 2),
    (2, 38, 1),
    (4, 39, 2),
    (6, 38, 1),
    (8, 36, 2),
    (10, 37, 2),
    (12, 38, 2),
  ];
  const arp = [62, 65, 69, 74, 69, 65, 62, 60, 63, 67, 72, 67, 63, 60];
  return BandSong(
    title: 'Undertow',
    bpm: 100,
    steps: 14,
    room: 0.25,
    sections: const [
      (map: 'intro', part: 'intro', bars: 4, energy: 0.3),
      (map: 'verse', part: 'verse', bars: 8, energy: 0.5),
      (map: 'verse', part: 'build', bars: 4, energy: 0.65),
      (map: 'hook', part: 'heavy', bars: 8, energy: 0.95),
      (map: 'break', part: 'break', bars: 6, energy: 0.4),
      (map: 'hook', part: 'heavy', bars: 8, energy: 1.0),
      (map: 'outro', part: 'outro', bars: 4, energy: 0.3),
    ],
    bar: (m, part, i, barNo, t, st) {
      final riff = (i ~/ 2).isOdd ? riffB : riffA;
      final fill = i % 4 == 3;
      switch (part) {
        case 'intro':
        case 'outro':
          for (final (p, n, l) in riff) {
            m.add(
              synthBass(n - 12, l * st, cutoff: 500, res: 1.2),
              t + p * st,
              part == 'outro' ? 0.8 * (1 - i / 5) : 0.8,
            );
          }
          if (part == 'intro' && i >= 2) {
            drums(
              m,
              {floorTom: 'x.....x......x', lowTom: '...x.....x....'},
              t,
              st,
              gain: 0.7,
            );
          }
        case 'verse':
        case 'build':
          for (final (p, n, l) in riff) {
            m.add(
              synthBass(n - 12, l * st, cutoff: 600, res: 1.5),
              t + p * st,
              0.85,
            );
          }
          drums(
            m,
            {
              floorTom: 'x.....x......x',
              lowTom: '...x.....x..x.',
              h: 'x.x.x.x.x.x.x.',
              if (part == 'build') s: '....x......x..',
              if (part == 'build') k: 'x.....x.......',
            },
            t,
            st,
            gain: part == 'build' ? 0.9 + i * 0.05 : 0.8,
          );
          if (part == 'build') {
            for (var j = 0; j < 14; j++) {
              m.add(
                pluck(arp[j], st * 1.5, bright: 0.7, seed: j),
                t + j * st,
                0.35,
                (j.isEven ? -0.4 : 0.4),
              );
            }
          }
        case 'heavy':
          for (final (p, n, l) in riff) {
            final mute = l == 1;
            m.add(power(n, l * st, mute: mute), t + p * st, 0.55, -0.45);
            m.add(power(n, l * st, mute: mute), t + p * st + 0.011, 0.55, 0.45);
            m.add(
              synthBass(n - 12, l * st, cutoff: 700, res: 1.5),
              t + p * st,
              0.8,
            );
          }
          drums(
            m,
            {
              k: 'o.x...x.o...x.',
              s: '....o......o..',
              h: 'x.x.x.x.x.x.x.',
              if (fill) hiTom: '.........x.x..',
              if (fill) lowTom: '..........x.x.',
            },
            t,
            st,
          );
        case 'break':
          for (var j = 0; j < 14; j++) {
            m.add(
              pluck(
                arp[(j + i) % 14] - (i.isOdd ? 2 : 0),
                st * 2,
                bright: 0.45,
                seed: j + i,
              ),
              t + j * st,
              0.45,
              math.sin(j * 0.9) * 0.6,
            );
          }
          drums(
            m,
            {floorTom: 'x......x......', lowTom: '....x......x..'},
            t,
            st,
            gain: 0.55,
          );
      }
    },
  );
}

/// "Deadpan" (for the Cake-style video): dry drums, a melodic bass up
/// front, muted then open strums, a trumpet tune in the hooks.
BandSong deadpanSong() {
  final k = kick(tone: 1.05, seed: 41),
      s = snare(tone: 1.1, snap: 0.6, seed: 42);
  final h = hat(seed: 43), sh = shaker(seed: 44);
  const chords = [
    [55, 59, 62, 67], // G
    [52, 55, 59, 64], // Em
    [48, 52, 55, 60], // C
    [50, 54, 57, 62], // D
  ];
  const roots = [43, 40, 36, 38];
  // The trumpet tune, two bars: (step, note, length in 16ths).
  const tune = [
    [(0, 74, 3), (4, 71, 2), (6, 74, 2), (8, 76, 4), (12, 74, 4)],
    [(0, 71, 2), (2, 69, 2), (4, 67, 4), (10, 69, 2), (12, 71, 4)],
  ];
  return BandSong(
    title: 'Deadpan',
    bpm: 112,
    steps: 16,
    dry: true,
    sections: const [
      (map: 'intro', part: 'intro', bars: 4, energy: 0.3),
      (map: 'verse', part: 'verse', bars: 8, energy: 0.5),
      (map: 'hook', part: 'hook', bars: 8, energy: 0.85),
      (map: 'verse', part: 'verse', bars: 8, energy: 0.5),
      (map: 'hook', part: 'hook', bars: 8, energy: 0.9),
      (map: 'break', part: 'break', bars: 4, energy: 0.4),
      (map: 'hook', part: 'hook', bars: 8, energy: 0.9),
      (map: 'outro', part: 'outro', bars: 4, energy: 0.3),
    ],
    bar: (m, part, i, barNo, t, st) {
      final c = barNo % 4;
      final root = roots[c];
      // The bass walks: root, fifth, octave, a passing note into the next.
      final next = roots[(c + 1) % 4];
      final line = [
        (0, root, 3),
        (4, root + 7, 2),
        (6, root + 12, 2),
        (8, root + 7, 3),
        (12, root, 2),
        (14, next + (next > root ? -1 : 1), 2),
      ];
      if (part != 'outro' || i < 3) {
        for (final (p, n, l) in line) {
          m.add(bass(n, l * st, vel: 0.95), t + p * st, 1.0);
        }
      }
      final open = part == 'hook';
      if (part != 'break') {
        for (var j = 0; j < 8; j++) {
          m.add(
            strum(
              chords[c],
              open ? st * 2.2 : st * 0.7,
              down: j.isEven,
              bright: open ? 0.7 : 0.4,
              seed: j,
            ),
            t + j * 2 * st,
            open ? 0.5 : 0.4,
            0.35,
          );
        }
      }
      if (part != 'intro') {
        drums(
          m,
          {
            k: 'x.......x.......',
            s: '....x.......x...',
            h: 'x.x.x.x.x.x.x.x.',
            if (part == 'hook') sh: '..x...x...x...x.',
          },
          t,
          st,
          gain: 0.8,
        );
      }
      if (part == 'hook' || part == 'break') {
        for (final (p, n, l) in tune[i % 2]) {
          m.add(
            trumpet(n - (part == 'break' ? 5 : 0), l * st),
            t + p * st,
            0.7,
            -0.25,
          );
        }
      }
    },
  );
}

/// "Mothership" (for the Parliament-style video): a space-funk vamp:
/// on-the-one drums, slap bass, wah clavinet, horn stabs, a synth whistle.
BandSong mothershipSong() {
  final k = kick(tone: 1.0, seed: 51), s = snare(tone: 1.0, seed: 52);
  final h = hat(seed: 53), o = hat(open: true, seed: 54), cl = clap();
  const em7 = [64, 67, 71, 74], a7 = [61, 64, 67, 69];
  // Slap line, one bar: (step, note, length, pop).
  const lineA = [
    (0, 40, 3, false),
    (3, 52, 1, true),
    (6, 40, 1, false),
    (8, 43, 2, false),
    (10, 45, 1, false),
    (11, 47, 1, false),
    (13, 52, 1, true),
    (14, 50, 2, false),
  ];
  const lineB = [
    (0, 45, 3, false),
    (3, 57, 1, true),
    (6, 45, 1, false),
    (8, 48, 2, false),
    (10, 47, 1, false),
    (11, 45, 1, false),
    (13, 55, 1, true),
    (14, 43, 2, false),
  ];
  const whistleTune = [(0, 76, 6, 71), (8, 79, 4, null), (12, 81, 4, null)];
  return BandSong(
    title: 'Mothership',
    bpm: 104,
    steps: 16,
    room: 0.12,
    sections: const [
      (map: 'intro', part: 'intro', bars: 4, energy: 0.35),
      (map: 'verse', part: 'groove', bars: 8, energy: 0.6),
      (map: 'hook', part: 'hook', bars: 8, energy: 0.95),
      (map: 'verse', part: 'groove', bars: 8, energy: 0.6),
      (map: 'break', part: 'space', bars: 8, energy: 0.7),
      (map: 'hook', part: 'hook', bars: 8, energy: 1.0),
      (map: 'outro', part: 'outro', bars: 4, energy: 0.4),
    ],
    bar: (m, part, i, barNo, t, st) {
      final second = barNo.isOdd;
      final chord = second ? a7 : em7;
      if (part != 'intro') {
        for (final (p, n, l, pop) in second ? lineB : lineA) {
          m.add(slap(n, l * st, pop: pop), t + p * st, 0.95);
        }
        drums(
          m,
          {
            k: 'o......x..x.....',
            s: '....o..g.g..o..g',
            h: 'xgxgxgxgxgxgxg.g',
            o: '..............x.',
            cl: '....x.......x...',
          },
          t,
          st,
          swing: 0.08,
        );
      } else {
        drums(
          m,
          {cl: '....x.......x...', h: 'x.x.x.x.x.x.x.x.'},
          t,
          st,
          gain: 0.8,
        );
      }
      if (part == 'groove' || part == 'hook' || part == 'intro') {
        for (final p in const [2, 6, 10, 14]) {
          m.add(clav(chord, st * 0.8), t + p * st, 0.55, 0.4);
        }
      }
      if (part == 'hook') {
        m.add(horns([for (final n in chord) n - 12], st * 2), t, 0.9, -0.3);
        m.add(
          horns([for (final n in chord) n - 12], st * 1.5),
          t + 10 * st,
          0.8,
          -0.3,
        );
      }
      if (part == 'space' ||
          part == 'intro' ||
          (part == 'hook' && i % 4 == 3)) {
        for (final (p, n, l, from) in whistleTune) {
          m.add(
            whistle(n - (second ? 2 : 0), l * st, from: from),
            t + p * st,
            0.6,
            0.2,
          );
        }
        if (part == 'space') {
          m.add(
            synthBass(second ? 33 : 28, st * 6, cutoff: 500, res: 4),
            t,
            0.7,
          );
          m.add(
            synthBass(second ? 45 : 40, st * 4, cutoff: 900, res: 4, from: 52),
            t + 10 * st,
            0.6,
          );
        }
      }
      if (part == 'outro') {
        for (final p in const [2, 6, 10, 14]) {
          m.add(
            clav(chord, st * 0.8, wah: 1 - i / 4),
            t + p * st,
            0.4 * (1 - i / 5),
            0.4,
          );
        }
      }
    },
  );
}
