// "Liquid Logic" (Twelve-Bit Science, track 6): the music video, written
// as a Puppet Stage movie. 86 BPM, 64 bars: intro 4, Lexicon 8, hook 8,
// Vox 8, hook 8, DJ breakdown 8, Sputnik 8, hook 8, outro 4.
//
// Four places: a black stage with one light, a dojo with a chess floor,
// a rooftop at night (the DJ) and a misty Vista mountain range (a lone
// swordsman). Cuts land on the bar; most shots drift.
import 'dart:math' as math;

import 'package:engine3d/engine3d.dart' show Vector3;
import 'package:landscape/landscape.dart';
import 'package:puppet_stage/src/cast.dart';
import 'package:puppet_stage/src/look.dart';
import 'package:puppet_stage/src/movie.dart';
import 'package:puppet_stage/src/props.dart';
import 'package:puppet_stage/src/sets.dart';

const bpm = 86.0;
const bar = 240 / bpm;
double at(num bars) => bars * bar;

const spot = 0, dojo = 1, roof = 2, land = 3;

/// An actor's timeline, built in bars.
class _Line {
  _Line(this.actor);
  final Actor actor;
  double _t = 0;

  /// Does [move] until bar [until].
  void to(num until, String move) {
    final end = at(until);
    if (end <= _t + 1e-6) return;
    actor.actions.add(
      move == 'wait'
          ? Action(ActionType.wait, seconds: end - _t)
          : Action(ActionType.move, move: move, seconds: end - _t),
    );
    _t = end;
  }

  /// Raps from bar [from] to [until], changing flow every two bars.
  void rap(num from, num until, {String rest = 'bounce'}) {
    to(from, rest);
    // The instrumental cut: the MCs ride the beat instead.
    final flows = _rapping
        ? const ['rapMic', 'rap', 'rap2', 'rapMic']
        : const ['bounce', 'bounce', 'stance', 'bounce'];
    var k = 0;
    for (var b = from; b < until; b += 2) {
      to(math.min(b + 2, until), flows[k++ % flows.length]);
    }
  }

  void walk(double x, double z) {
    actor.actions.add(Action(ActionType.walk, x: x, z: z));
  }
}

FilmLook _look(String name) => FilmLook.presets[name]!;

var _rapping = true;

/// [rapping]: false for the instrumental (nobody mouths words).
Movie liquidLogic({MusicRef? music, bool rapping = true}) {
  _rapping = rapping;
  final mountains = presets['alps']!.$2.copyWith(
    seed: 86,
    time: 17.3,
    haze: 0.8,
    clouds: 0.55,
  );
  final m = Movie(
    set: StageSet.spotlight,
    places: [
      const Place(set: StageSet.dojo),
      const Place(set: StageSet.rooftop),
      Place(land: mountains, name: 'Misty mountains'),
    ],
    music: music,
    look: _look('90s Video'),
  )..name = 'Liquid Logic';

  // Ids from the clock can repeat when made this fast: number them.
  Actor add(Actor a) {
    final b = Actor.fromJson({...a.toJson(), 'id': 'a${m.actors.length}'});
    m.actors.add(b);
    return b;
  }

  Actor robot(
    String name,
    int glow,
    int body,
    double x,
    double z,
    double facing,
    int place,
  ) => add(
    Actor(
      kind: Kind.robot,
      name: name,
      x: x,
      z: z,
      facing: facing,
      place: place,
      holds: Prop.mic,
      look: Look(
        skin: 0xFF8A9098,
        hair: glow,
        top: body,
        bottom: 0xFF4A4E56,
        shoes: 0xFF2A2C30,
        accent: glow,
      ),
    ),
  );

  // ---- The black stage: the three MCs. ----
  final lexicon = _Line(
    robot('Lexicon', 0xFFE04A4A, 0xFFB8C0C8, 0, 0.3, 0, spot),
  );
  final vox = _Line(robot('Vox', 0xFF4A9AE0, 0xFF5A6068, -1.4, -0.5, 18, spot));
  final sputnik = _Line(
    robot('Sputnik', 0xFFE0B040, 0xFFE8E4DA, 1.4, -0.5, -18, spot),
  );
  lexicon
    ..to(4, 'stance')
    ..rap(4, 12)
    ..rap(12, 20)
    ..to(28, 'bounce')
    ..rap(28, 36)
    ..to(52, 'bounce')
    ..rap(52, 60)
    ..to(61, 'bow')
    ..to(64, 'stance');
  for (final l in [vox, sputnik]) {
    l
      ..to(4, 'stance')
      ..to(12, 'bounce')
      ..rap(12, 20)
      ..to(28, 'bounce')
      ..rap(28, 36)
      ..to(52, 'bounce')
      ..rap(52, 60)
      ..to(61, 'bow')
      ..to(64, 'stance');
  }

  // ---- The dojo: Vox's verse, the swordsman, giant chess pieces. ----
  final vox2 = _Line(
    robot('Vox (dojo)', 0xFF4A9AE0, 0xFF5A6068, -0.3, 0.6, 20, dojo),
  );
  vox2
    ..to(20, 'stance')
    ..rap(20, 22)
    ..to(23, 'bow')
    ..rap(23, 28)
    ..to(64, 'stance');
  final samurai = _Line(
    add(
      Actor(
        kind: Kind.bigMan,
        name: 'Swordsman',
        x: 1.3,
        z: -0.6,
        facing: -35,
        place: dojo,
        holds: Prop.sword,
        extras: {Extra.jacket, Extra.beard},
        look: const Look(
          skin: 0xFFB07850,
          hair: 0xFF141010,
          top: 0xFF1A1A22,
          bottom: 0xFF101014,
          shoes: 0xFF0A0A0A,
          accent: 0xFF6A1A1A,
        ),
      ),
    ),
  );
  samurai
    ..to(13, 'kneel')
    ..to(14, 'swordStance')
    ..to(15, 'swordCut')
    ..to(22, 'swordStance')
    ..to(23, 'bow')
    ..to(26, 'swordStance')
    ..to(27, 'swordCut')
    ..to(38, 'swordStance')
    ..to(39, 'swordCut')
    ..to(41, 'swordStance')
    ..to(42, 'swordCut')
    ..to(54, 'swordStance')
    ..to(56, 'swordCut')
    ..to(64, 'kneel');
  for (final (p, x, z, f) in [
    (Prop.chessKing, -1.5, -1.5, 0.0),
    (Prop.chessKnight, 1.5, 1.5, -120.0),
    (Prop.chessRook, -2.1, 1.5, 0.0),
    (Prop.chessKnight, -0.9, -2.1, 40.0),
  ]) {
    add(
      Actor(
        kind: Kind.man,
        prop: p,
        name: p.label,
        x: x,
        z: z,
        facing: f,
        place: dojo,
        scale: 1.7,
      ),
    );
  }
  for (final (x, z) in [(-2.7, -2.7), (2.7, -2.7), (2.7, 2.7), (-2.7, 2.7)]) {
    add(
      Actor(
        kind: Kind.man,
        prop: Prop.candle,
        name: 'Candle',
        x: x,
        z: z,
        place: dojo,
      ),
    );
  }

  // ---- The rooftop: DJ Crossfade and Sputnik's verse. ----
  add(
    Actor(
      kind: Kind.man,
      prop: Prop.turntables,
      name: 'Turntables',
      x: 0,
      z: -1.0,
      place: roof,
    ),
  );
  for (final x in [-1.7, 1.7]) {
    add(
      Actor(
        kind: Kind.man,
        prop: Prop.speakers,
        name: 'Speakers',
        x: x,
        z: -1.9,
        facing: x < 0 ? 15 : -15,
        place: roof,
      ),
    );
  }
  add(
    Actor(
      kind: Kind.man,
      prop: Prop.boombox,
      name: 'Boombox',
      x: -2.4,
      z: 0.8,
      facing: 30,
      place: roof,
    ),
  );
  final dj = _Line(
    add(
      Actor(
        kind: Kind.man,
        name: 'DJ Crossfade',
        x: 0,
        z: -1.55,
        place: roof,
        extras: {Extra.cap, Extra.glasses, Extra.jacket},
        look: const Look(
          skin: 0xFF7A5038,
          hair: 0xFF1A1410,
          top: 0xFF2A4A3A,
          bottom: 0xFF2A2A34,
          shoes: 0xFFE8E8E8,
          accent: 0xFF1E1E24,
        ),
      ),
    ),
  );
  dj
    ..to(12, 'bounce')
    ..to(20, 'scratch')
    ..to(28, 'bounce')
    ..to(44, 'scratch')
    ..to(52, 'bounce')
    ..to(60, 'scratch')
    ..to(64, 'bounce');
  final sputnik2 = _Line(
    robot('Sputnik (roof)', 0xFFE0B040, 0xFFE8E4DA, 1.3, 0.3, -25, roof),
  );
  sputnik2
    ..to(44, 'bounce')
    ..rap(44, 52)
    ..to(64, 'bounce');

  // ---- The mountains: the lone swordsman. ----
  final ronin = _Line(
    add(
      Actor(
        kind: Kind.man,
        name: 'Ronin',
        place: land,
        facing: 160,
        holds: Prop.sword,
        extras: {Extra.hat, Extra.beard},
        look: const Look(
          skin: 0xFFC09070,
          hair: 0xFF1A1410,
          top: 0xFF3A3430,
          bottom: 0xFF24201E,
          shoes: 0xFF1A1614,
          accent: 0xFFB09A6A,
        ),
      ),
    ),
  );
  ronin
    ..to(20, 'kneel')
    ..to(21, 'swordStance')
    ..to(24, 'stance')
    ..to(47, 'swordStance')
    ..to(48, 'swordCut')
    ..to(60, 'stance');
  ronin.actor.actions.add(Action(ActionType.turn, angle: 180, seconds: 1.2));
  ronin.walk(0, -9);

  // ---- Shots. ----
  void shot(
    num b,
    int place,
    (double, double, double) from,
    (double, double, double) target, {
    (double, double, double)? driftFrom,
    (double, double, double)? driftTarget,
    String? look,
    double fov = 55,
  }) {
    (double, double) aim(
      (double, double, double) f,
      (double, double, double) t,
    ) {
      final d = Vector3(t.$1 - f.$1, t.$2 - f.$2, t.$3 - f.$3);
      final yaw = math.atan2(-d.x, -d.z);
      final pitch = math.asin(d.y / d.length);
      return (yaw, pitch);
    }

    final (yaw, pitch) = aim(from, target);
    List<double>? end;
    if (driftFrom != null || driftTarget != null) {
      final f2 = driftFrom ?? from, t2 = driftTarget ?? target;
      final (y2, p2) = aim(f2, t2);
      end = [f2.$1, f2.$2, f2.$3, y2, p2];
    }
    m.shots.add(
      Shot(
        at(b),
        from.$1,
        from.$2,
        from.$3,
        yaw,
        pitch,
        fov: fov,
        place: place,
        look: look == null ? null : _look(look),
        end: end,
      ),
    );
  }

  // Mountain spot: the ronin stands at 0, 0, 0 facing the valley (+Z-ish).
  // Intro (bars 0-4).
  shot(
    0,
    land,
    (-14, 6, 30),
    (0, 2, 0),
    driftFrom: (-8, 4, 18),
    look: 'Black & White',
    fov: 50,
  );
  shot(
    2,
    dojo,
    (-2.7, 0.35, 0.6),
    (-1.5, 1.2, -1.5),
    driftFrom: (-2.5, 0.35, -0.1),
    look: 'Noir',
  );
  shot(
    3,
    spot,
    (0, 1.4, -4.5),
    (0, 1.3, 0),
    driftFrom: (0, 1.4, -2.8),
    look: 'Noir',
  );
  // Lexicon's verse (4-12).
  shot(
    4,
    dojo,
    (0, 6.5, 0.2),
    (0, 0, 0),
    driftFrom: (0, 5.2, 0.2),
    look: 'Sepia Film',
    fov: 60,
  );
  shot(5, spot, (0.3, 0.5, 1.7), (0, 1.55, 0.3), look: 'Fisheye', fov: 75);
  shot(
    6,
    dojo,
    (-2.6, 0.3, 0.4),
    (-1.5, 0.9, -1.5),
    driftFrom: (-2.2, 0.3, -0.4),
    look: 'Sepia Film',
  );
  shot(7, spot, (0, 0.4, 3.0), (0, 1.5, 0.3), driftFrom: (0, 0.5, 2.2));
  shot(
    8,
    roof,
    (4.5, 2.6, 5.5),
    (0, 1.2, -1),
    driftFrom: (3.0, 2.2, 4.5),
    look: 'Night Blue',
  );
  shot(9, spot, (-3.4, 1.6, 3.4), (0, 1.2, 0), driftFrom: (-2.4, 1.4, 4.0));
  shot(
    10,
    dojo,
    (3.6, 0.4, 3.8),
    (1.5, 0.9, 1.5),
    driftFrom: (3.0, 0.4, 3.1),
    look: 'Noir',
  );
  shot(11, spot, (0, 1.55, 3.4), (0, 1.5, 0.3), driftFrom: (0, 1.55, 1.6));
  // Hook (12-20).
  shot(12, spot, (0, 2.2, 6.5), (0, 1.0, -0.2), driftFrom: (0, 1.6, 4.8));
  shot(
    13,
    spot,
    (-1.0, 0.45, 1.5),
    (-1.4, 1.6, -0.5),
    look: 'Fisheye',
    fov: 75,
  );
  shot(
    14,
    dojo,
    (3.2, 1.1, 0.9),
    (1.3, 1.0, -0.6),
    driftFrom: (2.8, 1.0, 0.3),
    look: 'Noir',
  );
  shot(15, roof, (0, 1.6, 0.9), (0, 0.95, -1.0), fov: 50);
  shot(16, spot, (1.0, 0.45, 1.5), (1.4, 1.6, -0.5), look: 'Fisheye', fov: 75);
  shot(17, spot, (4.0, 1.2, 3.0), (0, 1.2, -0.2), driftFrom: (2.0, 1.2, 4.2));
  shot(18, dojo, (-1.0, 0.25, 0.2), (-1.5, 1.4, -1.5), look: 'Noir', fov: 70);
  shot(
    19,
    spot,
    (0, 0.3, 3.8),
    (0, 1.3, 0),
    driftFrom: (0, 2.6, 5.5),
    look: 'Black & White',
  );
  // Vox's verse in the dojo (20-28).
  shot(
    20,
    land,
    (3, 1.2, 6),
    (0, 1.0, 0),
    driftFrom: (5, 1.6, 9),
    look: 'Black & White',
  );
  shot(21, dojo, (0.4, 1.5, 3.3), (-0.3, 1.4, 0.6), driftFrom: (0.2, 1.5, 2.6));
  shot(
    22,
    dojo,
    (4.5, 2.2, 3.5),
    (0.5, 0.9, 0),
    driftFrom: (3.6, 1.8, 4.0),
    look: 'Sepia Film',
  );
  shot(23, dojo, (-0.1, 0.45, 1.9), (-0.3, 1.6, 0.6), look: 'Fisheye', fov: 75);
  shot(
    24,
    land,
    (0, 6, 22),
    (0, 5, -80),
    driftFrom: (6, 6, 16),
    look: 'Black & White',
    fov: 45,
  );
  shot(
    25,
    dojo,
    (0, 7, 0.1),
    (0, 0, 0),
    driftFrom: (0.1, 7, 0.1),
    look: 'Noir',
    fov: 60,
  );
  shot(26, dojo, (2.6, 1.0, 0.6), (1.3, 1.2, -0.6), look: 'Noir', fov: 45);
  shot(
    27,
    dojo,
    (-0.3, 0.3, 2.4),
    (-0.3, 1.5, 0.6),
    driftFrom: (-0.8, 0.3, 2.0),
    look: 'Noir',
  );
  // Hook (28-36).
  shot(28, spot, (0, 2.2, 6.5), (0, 1.0, -0.2), driftFrom: (0, 1.6, 4.8));
  shot(29, roof, (2.0, 0.5, 1.4), (0, 1.3, -1.4), look: 'Fisheye', fov: 75);
  shot(
    30,
    spot,
    (-1.0, 0.45, 1.5),
    (-1.4, 1.6, -0.5),
    look: 'Fisheye',
    fov: 75,
  );
  shot(31, spot, (1.0, 0.45, 1.5), (1.4, 1.6, -0.5), look: 'Fisheye', fov: 75);
  shot(
    32,
    dojo,
    (0.3, 2.5, 4.5),
    (0, 0.6, 0),
    driftFrom: (-0.3, 2.0, 3.6),
    look: 'Sepia Film',
  );
  shot(33, spot, (-4.0, 1.2, 3.0), (0, 1.2, -0.2), driftFrom: (-2.0, 1.2, 4.2));
  shot(34, spot, (0, 1.55, 2.4), (0, 1.5, 0.3), driftFrom: (0, 1.55, 1.5));
  shot(
    35,
    land,
    (0, 3, -6),
    (0, 1, 30),
    driftFrom: (0, 2.2, -4),
    look: 'Black & White',
  );
  // DJ breakdown on the roof (36-44).
  shot(
    36,
    roof,
    (6.5, 3.5, 6.5),
    (0, 1.0, -1),
    driftFrom: (4.2, 2.6, 4.8),
    fov: 50,
  );
  shot(37, roof, (0.6, 1.7, -0.2), (0.4, 0.95, -1.0), fov: 50);
  shot(38, dojo, (2.8, 0.9, 0.2), (1.3, 1.1, -0.6), look: 'Noir', fov: 45);
  shot(39, roof, (0, 0.35, 0.9), (0, 1.5, -1.6), look: 'Fisheye', fov: 80);
  shot(40, roof, (-3.5, 1.4, 1.0), (0, 1.2, -1.5), driftFrom: (-2.5, 1.3, 2.0));
  shot(41, dojo, (2.9, 0.7, 1.6), (1.3, 1.1, -0.6), look: 'Noir', fov: 50);
  shot(42, roof, (-0.5, 1.7, -0.2), (-0.4, 0.95, -1.0), fov: 50);
  shot(43, roof, (0, 2.0, 4.5), (0, 1.2, -1.2), driftFrom: (0, 1.4, 2.6));
  // Sputnik's verse on the roof (44-52).
  shot(44, roof, (2.0, 1.5, 2.8), (1.3, 1.45, 0.3), driftFrom: (1.8, 1.5, 2.2));
  shot(
    45,
    dojo,
    (0, 3.5, 3.5),
    (0, 0, 0),
    driftFrom: (0, 2.5, 2.8),
    look: 'Sepia Film',
  );
  shot(46, roof, (1.0, 0.45, 1.5), (1.3, 1.6, 0.3), look: 'Fisheye', fov: 75);
  shot(
    47,
    land,
    (2.5, 1.6, 4),
    (0, 1.3, 0),
    driftFrom: (1.5, 1.5, 3),
    look: 'Black & White',
  );
  shot(
    48,
    dojo,
    (-4.5, 2.6, 4.5),
    (0, 0.8, 0),
    driftFrom: (-3.0, 2.0, 5.0),
    look: 'Noir',
  );
  shot(
    49,
    roof,
    (-2.0, 4.5, 6.5),
    (0, 1.0, -2),
    driftFrom: (-3.0, 6.0, 9.0),
    look: 'Night Blue',
  );
  shot(50, dojo, (-0.5, 0.25, 0.0), (-1.5, 1.5, -1.5), look: 'Noir', fov: 70);
  shot(
    51,
    roof,
    (1.3, 1.55, 2.6),
    (1.3, 1.5, 0.3),
    driftFrom: (1.3, 1.55, 1.5),
  );
  // Last hook (52-60).
  shot(52, spot, (0, 2.2, 6.5), (0, 1.0, -0.2), driftFrom: (0, 1.6, 4.8));
  shot(53, roof, (0, 0.35, 0.9), (0, 1.5, -1.6), look: 'Fisheye', fov: 80);
  shot(
    54,
    dojo,
    (3.2, 1.1, 0.9),
    (1.3, 1.0, -0.6),
    driftFrom: (2.6, 1.0, 0.0),
    look: 'Noir',
  );
  shot(56, spot, (0, 0.3, 2.2), (0, 1.6, 0.3), look: 'Fisheye', fov: 80);
  shot(57, spot, (5.0, 3.0, 0.0), (0, 1.1, -0.1), driftFrom: (0.0, 3.0, 5.0));
  shot(58, dojo, (0, 7, 0.1), (0, 0, 0), look: 'Noir', fov: 60);
  shot(
    59,
    spot,
    (0, 1.4, 3.2),
    (0, 1.3, 0),
    driftFrom: (0, 1.8, 6.0),
    look: 'Black & White',
  );
  // Outro (60-64): the ronin walks off into the mist.
  shot(
    60,
    land,
    (0, 2.2, 5),
    (0, 1.2, -2),
    driftFrom: (0, 7, 14),
    driftTarget: (0, 1, -10),
    look: 'Black & White',
  );
  shot(
    62,
    spot,
    (0, 1.6, 7.5),
    (0, 1.0, 0),
    driftFrom: (0, 2.4, 11),
    look: 'Noir',
  );
  return m;
}
