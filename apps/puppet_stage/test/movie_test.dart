import 'dart:convert';

import 'package:engine3d/engine3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puppet_stage/src/animals.dart';
import 'package:puppet_stage/src/cast.dart';
import 'package:puppet_stage/src/figure.dart';
import 'package:puppet_stage/src/movie.dart';
import 'package:puppet_stage/src/moves.dart';
import 'package:puppet_stage/src/props.dart';
import 'package:puppet_stage/src/sets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every character gets every move, and moves stay on their feet', () {
    for (final kind in Kind.values) {
      final c = buildCharacter(kind, defaultLooks[kind]!);
      final clips = clipsFor(c);
      expect(clips.length, moves.length);
      for (final m in moves) {
        restPose(c);
        clips[m.id]!.apply(m.duration * 0.5);
        final b = boundsOf(c.root)!;
        expect(
          b[1],
          greaterThan(-0.25),
          reason: '${kind.name} ${m.id} sinks into the floor',
        );
      }
      restPose(c);
      final b = boundsOf(c.root)!;
      final height = b[4] - b[1];
      final range = switch (kind) {
        Kind.boy || Kind.girl => (1.0, 1.35),
        Kind.toddler => (0.75, 1.0),
        Kind.teen => (1.35, 1.65),
        _ => (1.55, 1.95),
      };
      expect(height, inInclusiveRange(range.$1, range.$2), reason: kind.name);
      // Feet on the floor at rest, for any body.
      expect(b[1], closeTo(0, 0.03), reason: '${kind.name} feet');
    }
  });

  test('every animal does its moves without sinking or floating off', () {
    for (final an in Animal.values) {
      final c = buildAnimal(an, animalLooks[an]!);
      final clips = clipsFor(c);
      expect(clips.keys, containsAll(['idle', 'walk', 'run', 'call']));
      restPose(c);
      final rest = boundsOf(c.root)!;
      // Feet on the floor at rest.
      expect(rest[1], closeTo(0, 0.03), reason: '${an.name} rest');
      final h = rest[4] - rest[1];
      for (final m in movesFor(an.rig)) {
        for (final t in [0.0, 0.3, 0.6, 1.0]) {
          restPose(c);
          clips[m.id]!.apply(m.duration * t);
          final b = boundsOf(c.root)!;
          expect(
            b[1],
            greaterThan(-h * 0.25),
            reason: '${an.name} ${m.id} at $t sinks into the floor',
          );
          if (m.id != 'fly' && m.id != 'jump' && m.id != 'hop') {
            expect(
              b[1],
              lessThan(h * 0.2 + 0.03),
              reason: '${an.name} ${m.id} at $t floats',
            );
          }
        }
      }
      if (an.rig == 'bird') {
        restPose(c);
        clips['fly']!.apply(0.1);
        expect(boundsOf(c.root)![1], greaterThan(1.0), reason: an.name);
      }
    }
    // Sizes: a cat is small, a horse is big.
    double height(Animal a) {
      final c = buildAnimal(a, animalLooks[a]!);
      final b = boundsOf(c.root)!;
      return b[4] - b[1];
    }

    expect(height(Animal.cat), lessThan(0.65)); // tail up
    expect(height(Animal.horse), greaterThan(1.4));
  });

  test('props stand on the floor; wheels turn only when driving', () {
    for (final p in Prop.values) {
      final b = boundsOf(buildProp(p, propLooks[p]!))!;
      expect(b[1], closeTo(0, 0.05), reason: '${p.name} floor');
      expect(b[4] - b[1], greaterThan(0.05), reason: p.name);
    }
    final car = PropFigure(buildProp(Prop.car, propLooks[Prop.car]!));
    final wheel = car.root.find('wheel')!;
    car.apply(const ActorState(0, 0, 0, 'idle', 1));
    final parked = wheel.rotation.radians;
    car.apply(const ActorState(0, 0, 0, 'walk', 1));
    expect(wheel.rotation.radians, isNot(closeTo(parked, 1e-6)));
    final tree = PropFigure(buildProp(Prop.tree, propLooks[Prop.tree]!));
    tree.apply(const ActorState(0, 0, 0, 'idle', 0.5));
    final a = tree.root.find('sway')!.rotation.clone();
    tree.apply(const ActorState(0, 0, 0, 'idle', 1.7));
    expect(tree.root.find('sway')!.rotation.x, isNot(closeTo(a.x, 1e-6)));
    // Saved and opened again.
    final back = Actor.fromJson(
      jsonDecode(
        jsonEncode(
          Actor(kind: Kind.man, name: 'T', prop: Prop.pine, scale: 2).toJson(),
        ),
      ) as Map,
    );
    expect(back.prop, Prop.pine);
    expect(back.scale, 2);
    expect(back.look.top, propLooks[Prop.pine]!.top);
  });

  test('body sliders change the figure; feet stay on the floor', () {
    double h(Body body, [Set<Extra> extras = const {}]) {
      final c = buildCharacter(
        Kind.man,
        defaultLooks[Kind.man]!,
        body: body,
        extras: extras,
      );
      restPose(c);
      final b = boundsOf(c.root)!;
      expect(b[1], closeTo(0, 0.03));
      return b[4] - b[1];
    }

    final normal = h(const Body());
    expect(h(const Body(height: 1.2)), greaterThan(normal * 1.15));
    expect(h(const Body(legs: 1.3)), greaterThan(normal + 0.2));
    expect(h(const Body(head: 1.5)), greaterThan(normal + 0.05));
    expect(h(const Body(), {Extra.hat}), greaterThan(normal + 0.05));
    // Every extra on every kind builds, and moves still work.
    for (final k in Kind.values) {
      final c = buildCharacter(
        k,
        defaultLooks[k]!,
        body: const Body(build: 1.6, arms: 0.7),
        extras: Extra.values.toSet(),
      );
      expect(clipsFor(c).length, moves.length);
    }
  });

  test('templates keep kind, colours, body and extras', () {
    final a = Actor(
      kind: Kind.teen,
      name: 'Kim',
      look: defaultLooks[Kind.teen]!.copyWith(accent: 0xFF123456),
      body: const Body(height: 1.1, head: 1.3),
      extras: {Extra.cap, Extra.backpack},
      actions: [Action(ActionType.wait)],
    );
    final b = actorFromTemplate(
      jsonDecode(jsonEncode(templateJson(a))),
      x: 2,
      z: 1,
    )!;
    expect(b.kind, Kind.teen);
    expect(b.name, 'Kim');
    expect(b.look.accent, 0xFF123456);
    expect(b.body.head, 1.3);
    expect(b.extras, {Extra.cap, Extra.backpack});
    expect(b.actions, isEmpty);
    expect((b.x, b.z), (2.0, 1.0));
    expect(b.id, isNot(a.id));
    expect(actorFromTemplate({'kind': 'other'}), isNull);
  });

  test('actions laid out in time: walking takes distance / speed', () {
    final a = Actor(
      kind: Kind.man,
      name: 'Al',
      actions: [
        Action(ActionType.move, move: 'wave', seconds: 2),
        Action(ActionType.walk, x: 0, z: 2.6), // 2 s at 1.3 m/s
        Action(ActionType.turn, angle: 90),
        Action(ActionType.wait, seconds: 1),
      ],
    );
    final p = plan(a);
    expect(p[0].end, 2);
    expect(p[1].end, closeTo(4, 1e-9));
    expect(p[2].f1, 90);
    final mid = stateAt(a, 3);
    expect(mid.move, 'walk');
    expect(mid.z, closeTo(1.3, 1e-9));
    expect(stateAt(a, 2.1).blend, lessThan(1)); // crossfading from the wave
    final end = stateAt(a, 99);
    expect(end.z, closeTo(2.6, 1e-9));
    expect(end.facing, 90);
    expect(end.move, 'idle');
  });

  test('poses: angles round-trip, and pose actions pose the character', () {
    for (final (x, y, z) in [
      (20.0, 0.0, 0.0),
      (-40.0, 30.0, 10.0),
      (0.0, -60.0, 45.0),
    ]) {
      final e = toEuler(euler(x, y, z));
      expect(e.$1, closeTo(x, 1e-6));
      expect(e.$2, closeTo(y, 1e-6));
      expect(e.$3, closeTo(z, 1e-6));
    }
    final c = buildCharacter(Kind.oldWoman, defaultLooks[Kind.oldWoman]!);
    final clips = clipsFor(c);
    final a = Actor(
      kind: Kind.oldWoman,
      name: 'Ida',
      actions: [
        Action(ActionType.pose, seconds: 0.5, pose: {'upperArmR': (-90, 0, 0)}),
      ],
    );
    applyState(c, clips, stateAt(a, 0.2));
    final p = poseOf(c);
    expect(p['upperArmR']!.$1, closeTo(-90, 1e-6));
    expect(p.containsKey('spine'), isFalse); // her stoop is rest, not pose
  });

  test('movies save and load', () async {
    final m = Movie(
      name: 'Test',
      set: StageSet.park,
      actors: [
        Actor(
          kind: Kind.girl,
          name: 'Bo',
          x: 1,
          actions: [
            Action(ActionType.run, x: 3, z: -2),
            Action(ActionType.pose, pose: {'head': (10, 0, 0)}),
          ],
        ),
      ],
      shots: [Shot(0, 0, 2, 6, 0, -0.1), Shot(2.5, 3, 2, 3, 0.8, -0.2)],
    );
    final back = Movie.fromJson(jsonDecode(jsonEncode(m.toJson())));
    expect(back.set, StageSet.park);
    expect(back.actors.single.actions[1].pose['head']!.$1, 10);
    expect(back.shotAt(3)!.time, 2.5);
    expect(back.shotAt(1)!.time, 0);
    expect(back.duration, greaterThan(1));
    for (final s in StageSet.values) {
      expect((await buildSet(s)).root.children, isNotEmpty);
    }
  });
}
