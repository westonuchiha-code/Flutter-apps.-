import 'dart:convert';
import 'dart:typed_data';

import 'package:engine3d/engine3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landscape/landscape.dart';
import 'package:puppet_stage/src/cast.dart';
import 'package:puppet_stage/src/export.dart';
import 'package:puppet_stage/src/figure.dart';
import 'package:puppet_stage/src/look.dart';
import 'package:puppet_stage/src/movie.dart';
import 'package:puppet_stage/src/places.dart';
import 'package:puppet_stage/src/props.dart';
import 'package:puppet_stage/src/sets.dart';

Uint8List _wav(int rate, int channels, List<int> samples) {
  final data = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, samples[i], Endian.little);
  }
  final h = ByteData(44);
  void tag(int o, String s) {
    for (var i = 0; i < 4; i++) {
      h.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  h.setUint32(4, 36 + samples.length * 2, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  h.setUint32(16, 16, Endian.little);
  h.setUint16(20, 1, Endian.little);
  h.setUint16(22, channels, Endian.little);
  h.setUint32(24, rate, Endian.little);
  h.setUint32(28, rate * channels * 2, Endian.little);
  h.setUint16(32, channels * 2, Endian.little);
  h.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  h.setUint32(40, samples.length * 2, Endian.little);
  return Uint8List.fromList([
    ...h.buffer.asUint8List(),
    ...data.buffer.asUint8List(),
  ]);
}

void main() {
  test('WAVs become 44.1 kHz stereo', () {
    final stereo = decodeWav(_wav(44100, 2, [100, -100, 200, -200]))!;
    expect(stereo, [100, -100, 200, -200]);
    final mono = decodeWav(_wav(22050, 1, List.filled(100, 1000)))!;
    expect(mono.length, 400);
    expect(mono[0], mono[1]);
    expect(mono[10], closeTo(1000, 2));
    expect(
      decodeWav(Uint8List.fromList(utf8.encode('not a wav at all...'))),
      isNull,
    );
  });

  test('shots drift to their end and cut at the next shot', () {
    final m = Movie(
      shots: [
        Shot(0, 0, 1, 5, 0, 0, end: [4, 1, 5, 20, -10]),
        Shot(2, 9, 9, 9, 0, 0),
      ],
    );
    m.actors.add(Actor(kind: Kind.man, name: 'A'));
    final c = Camera();
    cameraAt(m, 0, c);
    expect(c.position.x, closeTo(0, 1e-9));
    cameraAt(m, 1, c);
    expect(c.position.x, closeTo(2, 1e-6));
    cameraAt(m, 1.999, c);
    expect(c.position.x, closeTo(4, 0.01));
    expect(c.yaw, closeTo(20, 0.1));
    cameraAt(m, 2.5, c);
    expect(c.position.x, 9);
  });

  test('places, music and looks survive saving', () {
    final m = Movie(
      places: [
        const Place(set: StageSet.dojo),
        Place(land: presets['alps']!.$2, name: 'Mountains'),
      ],
      music: const MusicRef('id1', 'wav', 'Liquid Logic', seconds: 179),
      look: FilmLook.presets['Noir']!,
      shots: [
        Shot(0, 1, 2, 3, 4, 5, place: 2, look: FilmLook.presets['Fisheye']),
      ],
    );
    m.actors.add(
      Actor(kind: Kind.robot, name: 'Lexicon', place: 1, holds: Prop.mic),
    );
    final back = Movie.fromJson(jsonDecode(jsonEncode(m.toJson())));
    expect(back.placeCount, 3);
    expect(back.placeAt(1).set, StageSet.dojo);
    expect(back.placeAt(2).land?.preset, presets['alps']!.$2.preset);
    expect(back.music?.name, 'Liquid Logic');
    expect(back.duration, greaterThanOrEqualTo(179));
    expect(back.look.mono, isTrue);
    expect(back.shots.single.place, 2);
    expect(back.shots.single.look?.fisheye, greaterThan(0));
    expect(back.actors.single.place, 1);
    expect(back.actors.single.holds, Prop.mic);
  });

  test('people hold props in the right hand; records spin', () {
    final fig = BuiltFigure(buildCharacter(Kind.man, defaultLooks[Kind.man]!));
    fig.hold(Prop.sword);
    final hand = fig.rig.joints['handR']!;
    expect(hand.children.where((n) => n.name == 'held'), hasLength(1));
    fig.hold(Prop.mic);
    expect(hand.children.where((n) => n.name == 'held'), hasLength(1));
    fig.hold(null);
    expect(hand.children.where((n) => n.name == 'held'), isEmpty);

    final decks = PropFigure(
      buildProp(Prop.turntables, propLooks[Prop.turntables]!),
    );
    const st = ActorState(0, 0, 0, 'idle', 0);
    decks.show(st, now: 0);
    final deck = decks.root.find('deck')!;
    final a = deck.rotation.clone();
    decks.show(st, now: 0.5);
    expect((deck.rotation - a).length, greaterThan(0.1));
    decks.show(st, groundY: 2);
    expect(decks.root.position.y, 2);
  });

  test('film looks change the picture', () {
    const w = 32, h = 24;
    final px = Uint32List(w * h)..fillRange(0, w * h, 0xFF3080C0);
    final noir = applyLook(px, w, h, FilmLook.presets['Noir']!, 3);
    final c = noir[(h ~/ 2) * w + w ~/ 2];
    expect((c >> 16) & 0xFF, c & 0xFF); // grey
    expect(noir[0] & 0xFFFFFF, 0); // letterbox
    expect(applyLook(px, w, h, FilmLook.none, 0), px);
  });

  test('a landscape place stands the action on its ground', () async {
    final p = await buildPlace(
      Place(land: presets['alps']!.$2, name: 'Mountains'),
    );
    expect(p.world, isNotNull);
    // The spot picked is moved to the origin.
    expect(p.ground(0, 0), closeTo(0, 0.6));
    p.follow(Camera(position: Vector3(0, 2, 5)));
    final set = await buildPlace(const Place(set: StageSet.rooftop));
    expect(set.ground(3, 4), 0);
  });
}
