/// A song: a "sampled" loop, drums, bass, rapped verses, hooks with DJ cuts,
/// arranged and mixed to stereo.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'dsp.dart';
import 'instruments.dart';
import 'rap.dart';
import 'scratch.dart';

enum Part { intro, verse, hook, breakdown, outro }

class Section {
  const Section(
    this.part,
    this.bars, {
    this.mc,
    this.lines = const [],
    this.mcs = const [],
  });
  final Part part;
  final int bars;

  /// Who raps a verse.
  final Mc? mc;

  /// Hooks: everyone in [mcs] raps it together (a chip choir).
  final List<Mc> mcs;
  final List<String> lines;
}

class Song {
  const Song({
    required this.title,
    required this.bpm,
    required this.seed,
    required this.chords,
    required this.bassRoots,
    required this.keys,
    required this.drums,
    required this.scratchPhrase,
    required this.scratchMc,
    required this.sections,
    this.swing = 0.57,
    this.cuts = const ['chirp', 'baby', 'transform', 'stab'],
    this.loopHz = 5200,
  });

  final String title;
  final double bpm;
  final int seed;

  /// One chord (MIDI notes) per bar of the loop.
  final List<List<int>> chords;
  final List<int> bassRoots;

  /// Instruments the loop is made of: rhodes, vibes, piano, horns, strings,
  /// flute.
  final List<String> keys;
  final String drums;

  /// What the DJ cuts up in the hooks and intros.
  final String scratchPhrase;
  final Mc scratchMc;
  final List<String> cuts;
  final List<Section> sections;
  final double swing;

  /// The "sampler" low pass on the loop.
  final double loopHz;

  int get bars => sections.fold(0, (a, s) => a + s.bars);
  double get barSeconds => 4 * 60 / bpm;
}

/// Drum patterns: 16 steps per bar for kick, snare, hats, ghost snares, rim
/// and shaker ('x' hit, 'o' open hat / accent).
const drumPatterns = <String, Map<String, String>>{
  'boom': {
    'k': 'x.....x...x.....',
    's': '....x.......x...',
    'h': 'x.x.x.x.x.x.x.o.',
    'g': '.......x......x.',
  },
  'boom2': {
    'k': 'x..x......x..x..',
    's': '....x.......x..x',
    'h': 'xxxxxxxxxxxxxxxx',
    'g': '..x.......x.....',
  },
  'lazy': {
    'k': 'x.......xx......',
    's': '....x.......x...',
    'h': 'x.x.x.x.x.x.x.o.',
    'g': '.....x.........x',
  },
  'dark': {
    'k': 'x.....x.x.......',
    's': '....x.......x...',
    'h': 'x...x...x...x...',
    'r': '..............x.',
  },
  'bounce': {
    'k': 'x..x..x...x..x..',
    's': '....x.......x...',
    'h': 'x.x.x.x.x.x.x.x.',
    'sh': 'xxxxxxxxxxxxxxxx',
  },
};

/// The loop, as if sampled from an old record: instruments played, then
/// filtered, warbled, crushed to 12 bits and dusted with crackle.
Float32List makeLoop(Song song) {
  final beat = 60 / song.bpm;
  final bar = beat * 4;
  final out = buf(bar * song.chords.length + 2);
  for (var b = 0; b < song.chords.length; b++) {
    final c = song.chords[b];
    final at = b * bar;
    for (final k in song.keys) {
      switch (k) {
        case 'rhodes':
          mixInto(out, rhodes(c, bar * 0.6), at);
          mixInto(
            out,
            rhodes(c.sublist(1), beat * 0.8, vel: 0.6),
            at + beat * 2.5,
          );
        case 'vibes':
          for (var i = 0; i < 8; i++) {
            final n = c[(i * 2) % c.length] + (i >= 4 ? 12 : 0);
            mixInto(out, vibes([n], beat * 0.4), at + i * beat / 2, 0.9);
          }
        case 'piano':
          for (final (t, len) in [(0.0, 0.9), (1.75, 0.4), (3.0, 0.7)]) {
            mixInto(out, piano(c, beat * len), at + t * beat);
          }
        case 'horns':
          mixInto(out, horns(c.sublist(c.length - 3), beat * 0.5), at);
          mixInto(
            out,
            horns(c.sublist(c.length - 3), beat * 0.35),
            at + beat * 2.5,
            0.8,
          );
        case 'strings':
          mixInto(out, strings(c, bar * 0.95), at, 1.2);
        case 'flute':
          final top = c.last + 12;
          for (final (t, n, len) in [
            (0.0, top, 1.0),
            (1.5, top - 3, 0.5),
            (2.0, top - 5, 1.5),
            (3.5, top - 7, 0.5),
          ]) {
            mixInto(out, flute(n, beat * len, seed: b + 3), at + t * beat, 0.9);
          }
      }
    }
  }
  // The record player: wow and flutter (a slowly wandering speed).
  final warbled = Float32List(out.length);
  for (var i = 0; i < out.length; i++) {
    final t = i / sr;
    final d =
        0.0025 * math.sin(tau * 0.55 * t) + 0.0004 * math.sin(tau * 7 * t);
    warbled[i] = readAt(out, i - d * sr + 0.003 * sr);
  }
  final lp = Biquad.lowPass(song.loopHz);
  final hp = Biquad.highPass(90);
  for (var i = 0; i < warbled.length; i++) {
    warbled[i] = hp.run(lp.run(warbled[i]));
  }
  normalize(warbled, 0.8);
  sp1200(warbled, filterHz: song.loopHz + 2000);
  final dust = vinyl(warbled.length / sr, song.seed);
  for (var i = 0; i < warbled.length; i++) {
    warbled[i] += dust[i] * 0.8;
  }
  return Float32List.sublistView(
    warbled,
    0,
    (bar * song.chords.length * sr).round(),
  );
}

class Mix {
  Mix(double seconds) : l = buf(seconds), r = buf(seconds);
  final Float32List l, r;

  /// [pan]: -1 left .. 1 right (equal power).
  void add(Float32List src, double at, double gain, [double pan = 0]) {
    final a = (pan + 1) * math.pi / 4;
    mixInto(l, src, at, gain * math.cos(a));
    mixInto(r, src, at, gain * math.sin(a));
  }

  /// A wide stereo copy: the right side a little later.
  void addWide(Float32List src, double at, double gain) {
    mixInto(l, src, at, gain * 0.75);
    mixInto(r, src, at + 0.013, gain * 0.75);
  }
}

/// Renders [song] (with vocals, or the instrumental) to interleaved
/// stereo.
Float32List renderSong(
  Song song, {
  bool vocals = true,
  Set<String> stems = const {'beat', 'vocals', 'dj'},
  bool raw = false,
}) {
  final beat = 60 / song.bpm;
  final bar = song.barSeconds;
  final total = song.bars * bar + 3;
  final mix = Mix(total);
  final r = Rng(song.seed);
  final loop = makeLoop(song);
  final loopBars = song.chords.length;
  final pat = drumPatterns[song.drums]!;
  final kit = {
    'k': kick(tone: 0.95 + r.next * 0.1, seed: song.seed),
    's': snare(tone: 0.9 + r.next * 0.2, seed: song.seed + 1),
    'h': hat(seed: song.seed + 2),
    'o': hat(open: true, seed: song.seed + 3),
    'g': snare(tone: 1.1, snap: 0.5, seed: song.seed + 4),
    'r': rim(seed: song.seed + 5),
    'sh': shaker(seed: song.seed + 6),
  };
  // The DJ's samples: the song's phrase, and the classic "ahh".
  final cutSample = Float32List.fromList(
    phrase(song.scratchPhrase, song.scratchMc, speed: 0.9),
  );
  final ahhs = ahh(seed: song.seed);
  // Cut samples as loud as a record's vocal (the DJ is up front).
  normalize(cutSample, 0.95);
  normalize(ahhs, 0.95);
  final swingDelay = (song.swing - 0.5) * 2 * beat / 4;

  var at = 0.0;
  var barNo = 0;
  (String, Mc)? lastLine;
  for (final sec in song.sections) {
    for (var i = 0; i < sec.bars; i++, barNo++) {
      final t = at + i * bar;
      // The loop: every bar plays its bar of the sample.
      final lb = barNo % loopBars;
      final slice = Float32List.sublistView(
        loop,
        (lb * bar * sr).round(),
        math.min(loop.length, ((lb + 1) * bar * sr).round()),
      );
      if (!stems.contains('beat')) {
        // (stem render: no loop)
      } else if (sec.part == Part.intro && i < sec.bars - 1) {
        // Filtered intro: the loop thinned out, like a DJ's EQ.
        final hp = Biquad.highPass(500);
        final f = Float32List.fromList(slice);
        hp.process(f);
        mix.addWide(f, t, 2.4);
      } else {
        mix.addWide(slice, t, sec.part == Part.breakdown ? 0.75 : 1.0);
      }
      // Drums (not in the intro, lighter in breakdowns).
      final drumsOn = sec.part != Part.intro && stems.contains('beat');
      if (drumsOn) {
        for (final e in pat.entries) {
          if (sec.part == Part.breakdown && e.key == 'k' && i.isOdd) continue;
          for (var s = 0; s < 16; s++) {
            final ch = e.value[s];
            if (ch == '.') continue;
            final swing = s.isOdd ? swingDelay : 0.0;
            final human = (r.next - 0.5) * 0.006;
            final key = e.key == 'h' && ch == 'o' ? 'o' : e.key;
            final accent = e.key == 'h' ? (s % 4 == 0 ? 0.7 : 0.45) : 1.0;
            final g = switch (key) {
              'k' => 1.0,
              's' => 0.85,
              'g' => 0.18,
              'r' => 0.4,
              'sh' => 0.3,
              _ => 0.5,
            };
            final pan = switch (key) {
              'h' || 'o' => 0.25,
              'sh' => -0.3,
              'r' => -0.15,
              _ => 0.0,
            };
            mix.add(
              kit[key]!,
              t + s * beat / 4 + swing + human,
              g * accent * (0.9 + r.next * 0.15),
              pan,
            );
          }
        }
        // Bass: root on 1, a pickup before 3, and the octave answer.
        final root = song.bassRoots[lb];
        mix.add(bass(root, beat * 1.4), t, 0.9);
        mix.add(
          bass(root, beat * 0.45, vel: 0.7),
          t + beat * 1.75 + swingDelay,
          0.8,
        );
        mix.add(
          bass(root + (i.isEven ? 7 : 12), beat * 0.9, vel: 0.85),
          t + beat * 2.5,
          0.8,
        );
      }
      // Vocals and the DJ.
      switch (sec.part) {
        case Part.verse:
          if (vocals &&
              stems.contains('vocals') &&
              sec.mc != null &&
              i < sec.lines.length) {
            final v = buf(bar + 1);
            if (flow == 'line' || flow == 'chant') {
              final line = sec.lines[i];
              if (line.isNotEmpty) {
                if (flow == 'chant') {
                  rapChant(v, line, sec.mc!, 0, song.bpm);
                } else {
                  rapLine(v, line, sec.mc!, 0, song.bpm);
                }
                mix.add(_cleanVoice(v), t, vocalLevel);
                lastLine = (line, sec.mc!);
              } else if (lastLine != null && stems.contains('dj')) {
                // A bar left to the DJ: he cuts up what was just said.
                final cut = Float32List.fromList(
                  phrase(lastLine.$1, lastLine.$2, speed: 1.1),
                );
                normalize(cut, 0.95);
                mix.add(
                  routine(
                    cut,
                    const ['forward', 'chirp', 'baby', 'stab'],
                    song.bpm,
                    seed: barNo,
                  ),
                  t,
                  0.6,
                  i.isEven ? -0.3 : 0.3,
                );
              }
            } else {
              rapBar(v, sec.lines[i], sec.mc!, 0, song.bpm);
              mix.add(_voice(v), t, 1.5);
            }
          }
          // The DJ marks the end of a verse.
          if (i == sec.bars - 1) {
            mix.add(
              routine(ahhs, ['baby', 'chirp'], song.bpm, seed: barNo),
              t + 2 * beat,
              0.5,
              -0.4,
            );
          }
        case Part.hook:
          // A rapped line, then the DJ answers with cuts: bar by bar.
          final line = sec.lines.isEmpty
              ? ''
              : sec.lines[(i ~/ 2) % sec.lines.length];
          if (i.isEven) {
            if (vocals && stems.contains('vocals')) {
              for (final (k, mc) in sec.mcs.indexed) {
                final v = buf(bar + 1);
                if (flow == 'line') {
                  rapLine(v, line, mc, 0, song.bpm);
                  mix.add(
                    _cleanVoice(v),
                    t + k * 0.012,
                    vocalLevel * 0.75,
                    (k - 1) * 0.3,
                  );
                } else {
                  rapBar(v, line, mc, 0, song.bpm);
                  mix.add(_voice(v), t + k * 0.012, 1.15, (k - 1) * 0.3);
                }
              }
            }
          } else if (stems.contains('dj')) {
            final cut = song.cuts[(barNo ~/ 2) % song.cuts.length];
            mix.add(
              routine(
                cutSample,
                [cut, 'forward', cut, 'stab'],
                song.bpm,
                seed: barNo,
              ),
              t,
              0.75,
              (i ~/ 2).isEven ? -0.35 : 0.35,
            );
          }
        case Part.intro:
          if (i >= sec.bars - 2 && stems.contains('dj')) {
            mix.add(
              routine(
                cutSample,
                ['forward', 'chirp', 'baby', 'scribble'],
                song.bpm,
                seed: barNo,
              ),
              t,
              0.75,
              -0.2,
            );
          }
        case Part.breakdown:
          if (!stems.contains('dj')) break;
          final names = [
            'baby',
            'transform',
            'chirp',
            'flare',
            'tear',
            'scribble',
            'stab',
            'forward',
          ];
          mix.add(
            routine(
              i.isEven ? cutSample : ahhs,
              [for (var k = 0; k < 4; k++) names[(i * 4 + k) % names.length]],
              song.bpm,
              seed: barNo,
            ),
            t,
            0.8,
            i.isEven ? -0.3 : 0.3,
          );
        case Part.outro:
          if (i == 0 && stems.contains('dj')) {
            mix.add(
              routine(
                cutSample,
                ['forward', 'transform', 'chirp', 'baby'],
                song.bpm,
                seed: barNo,
              ),
              t,
              0.7,
              0.2,
            );
          }
      }
    }
    at += sec.bars * bar;
  }
  // Fade the outro.
  final end = at, fadeLen = song.sections.last.bars * bar;
  for (var i = 0; i < mix.l.length; i++) {
    final t = i / sr;
    if (t > end - fadeLen) {
      final g = ((end - t) / fadeLen).clamp(0.0, 1.0);
      mix.l[i] *= g;
      mix.r[i] *= g;
    }
  }
  if (raw) {
    final n = mix.l.length;
    final out = Float32List(n * 2);
    for (var i = 0; i < n; i++) {
      out[i * 2] = mix.l[i];
      out[i * 2 + 1] = mix.r[i];
    }
    return out;
  }
  return master(mix, seconds: end + 0.5);
}

/// Vocal level for the 'line' flow (the first render used 1.5).
var vocalLevel = 2.2;

/// 'clean' or 'record' (the voice as a dusty vocal sample).
var vocalChain = 'clean';

/// A clearer vocal chain: no drive, presence for the consonants, gentle
/// compression, almost dry.
Float32List _cleanVoice(Float32List v) {
  if (vocalChain == 'record') return _recordVoice(v);
  final hp = Biquad.highPass(140);
  final pres = Biquad.peak(3200, 4, 1.0);
  for (var i = 0; i < v.length; i++) {
    v[i] = pres.run(hp.run(v[i]));
  }
  compress(v, threshold: 0.3, ratio: 3, makeup: 1.3);
  return room(v, size: 0.15, mix: 0.06);
}

/// The voice as if sampled off a record: the chip's buzz filtered away
/// (telephone-ish band), a little warmth, a room around it.
Float32List _recordVoice(Float32List v) {
  final hp = Biquad.highPass(260);
  final lp1 = Biquad.lowPass(2800), lp2 = Biquad.lowPass(3400);
  final body = Biquad.peak(900, 2, 0.8);
  for (var i = 0; i < v.length; i++) {
    v[i] = sat(body.run(lp2.run(lp1.run(hp.run(v[i])))) * 1.2, 1.1);
  }
  compress(v, threshold: 0.25, ratio: 3, makeup: 1.4);
  return room(v, size: 0.35, mix: 0.22);
}

/// The vocal chain: a touch of drive, presence, compression and a small
/// room.
Float32List _voice(Float32List v) {
  final hp = Biquad.highPass(120);
  final pres = Biquad.peak(2500, 4, 0.8);
  for (var i = 0; i < v.length; i++) {
    v[i] = sat(pres.run(hp.run(v[i])) * 1.4, 1.3);
  }
  compress(v, threshold: 0.25, ratio: 4, makeup: 1.6);
  return room(v, size: 0.2, mix: 0.12);
}

/// Bus compression, a soft clip and the level, interleaved.
Float32List master(Mix m, {required double seconds}) {
  final n = math.min(m.l.length, (seconds * sr).round());
  final l = Float32List.sublistView(m.l, 0, n),
      r = Float32List.sublistView(m.r, 0, n);
  // Glue: the same gain on both sides (linked).
  var env = 0.0;
  final ka = 1 - math.exp(-1 / (0.01 * sr)), kr = 1 - math.exp(-1 / (0.2 * sr));
  for (var i = 0; i < n; i++) {
    final a = math.max(l[i].abs(), r[i].abs());
    env += (a - env) * (a > env ? ka : kr);
    final g = env > 0.5 ? (0.5 + (env - 0.5) / 3) / env : 1.0;
    l[i] *= g;
    r[i] *= g;
  }
  final p = math.max(peak(l), peak(r));
  final gain = p > 0 ? 1.05 / p : 1;
  final out = Float32List(n * 2);
  for (var i = 0; i < n; i++) {
    out[i * 2] = _clip(l[i] * gain) * 0.95;
    out[i * 2 + 1] = _clip(r[i] * gain) * 0.95;
  }
  return out;
}

double _clip(double x) {
  if (x.abs() < 0.8) return x;
  final s = x.sign, a = x.abs();
  final e = math.exp(2 * (a - 0.8) / 0.2);
  return s * (0.8 + 0.2 * (e - 1) / (e + 1));
}
