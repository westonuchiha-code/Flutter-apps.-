import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:puppet_stage/src/look.dart';
import 'package:puppet_stage/src/movie.dart';
import 'package:puppet_stage/src/mv/director.dart';
import 'package:puppet_stage/src/mv/song_map.dart';
import 'package:puppet_stage/src/mv/styles.dart';

SongMap _map() => SongMap(
  bpm: 86,
  bars: [
    for (var i = 0; i < 4; i++) const BarInfo('intro', energy: 0.3),
    for (var i = 0; i < 8; i++) BarInfo('verse', energy: 0.55, dj: i == 7),
    for (var i = 0; i < 8; i++)
      BarInfo('hook', energy: 0.9, vocal: i.isEven, dj: i.isOdd),
    for (var i = 0; i < 4; i++) const BarInfo('outro', energy: 0.3),
  ],
);

void main() {
  test('song maps: from audio, and saved', () {
    // 16 bars at 120 BPM: quiet, loud, quiet, loud (4 bars each).
    const bpm = 120.0;
    final bar = (240 / bpm * 44100).round();
    final pcm = Int16List(bar * 16 * 2);
    for (var i = 0; i < bar * 16; i++) {
      final loud = (i ~/ (bar * 4)).isOdd;
      final v = (math.sin(i * 0.05) * (loud ? 20000 : 2000)).round();
      pcm[i * 2] = v;
      pcm[i * 2 + 1] = v;
    }
    final m = SongMap.fromAudio(pcm, bpm);
    expect(m.bars, hasLength(16));
    expect(m.bars[0].section, 'intro');
    expect(m.bars[5].section, 'hook');
    expect(m.bars[9].section, isNot('hook'));
    expect(m.bars[15].section, 'outro');
    final back = SongMap.fromJson(jsonDecode(jsonEncode(m.toJson())));
    expect(back.bars.length, 16);
    expect(back.bpm, bpm);
    expect(back.timeOf(2), closeTo(4, 1e-9));
  });

  test('tempo from taps', () {
    expect(tempoFromTaps([0, 0.5, 1.0, 1.5, 2.0]), 120);
    expect(tempoFromTaps([0, 1.4, 2.8, 4.2]), closeTo(85.7, 0.1));
    expect(tempoFromTaps([0, 1]), isNull);
  });

  test('every style directs a movie cut on the bar', () {
    final map = _map();
    for (final style in styles) {
      final m = Director(map, style, seed: 3).direct();
      expect(m.shots, isNotEmpty, reason: style.id);
      for (final s in m.shots) {
        // On a half bar at least.
        final bars = s.time / map.barSeconds;
        expect((bars * 2 - (bars * 2).round()).abs(), lessThan(1e-6));
        expect(s.place, inInclusiveRange(0, m.placeCount - 1));
        expect(s.x.isFinite && s.y.isFinite && s.yaw.isFinite, isTrue);
      }
      // Everyone's actions cover the song.
      for (final a in m.actors.where((a) => a.prop == null)) {
        final len = a.actions.fold<double>(0, (t, x) => t + x.seconds);
        expect(
          len,
          closeTo(map.seconds, 0.01),
          reason: '${style.id} ${a.name}',
        );
      }
      // The leads mouth the vocal bars.
      final lead = m.actors.firstWhere(
        (a) => a.name == style.cast.firstWhere((c) => c.role == 'lead').name,
      );
      final s0 = stateAt(lead, map.timeOf(12) + 0.5);
      expect(s0.move, 'rapMic', reason: style.id);
      // It saves and loads.
      final back = Movie.fromJson(jsonDecode(jsonEncode(m.toJson())));
      expect(back.shots.length, m.shots.length);
      expect(back.placeCount, m.placeCount);
    }
  });

  test('cameras keep clear of people and props', () {
    final m = Director(_map(), styleById('backyard'), seed: 2).direct();
    for (final s in m.shots.where((s) => s.place == 0)) {
      for (final a in m.actors.where((a) => a.place == 0)) {
        final d = math.sqrt(math.pow(s.x - a.x, 2) + math.pow(s.z - a.z, 2));
        if (s.y < 2.5) expect(d, greaterThan(0.3), reason: a.name);
      }
    }
  });

  test('moods and the new looks survive saving', () {
    const p = Place(
      name: 'Night',
      mood: Mood(
        sky: 0xFF000000,
        sunDir: [0, -1, 0],
        lamps: [(x: 1, y: 2, z: 3, color: 0xFFFF0000, range: 5, power: 1)],
      ),
    );
    final back = Place.fromJson(jsonDecode(jsonEncode(p.toJson())));
    expect(back.mood!.sky, 0xFF000000);
    expect(back.mood!.lamps.single.range, 5);
    final look = FilmLook.presets['Bile']!;
    final l2 = FilmLook.fromJson(jsonDecode(jsonEncode(look.toJson())));
    expect(l2.hold, 2);
    expect(l2.tint, 5);
    final px = Uint32List(16)..fillRange(0, 16, 0xFF808080);
    expect(applyLook(px, 4, 4, FilmLook.presets['Cosmic']!, 10), isNot(px));
  });
}
