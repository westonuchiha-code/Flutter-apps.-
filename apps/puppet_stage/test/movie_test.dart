import 'dart:convert';

import 'package:engine3d/engine3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puppet_stage/src/cast.dart';
import 'package:puppet_stage/src/movie.dart';
import 'package:puppet_stage/src/moves.dart';
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
      final child = kind == Kind.boy || kind == Kind.girl;
      expect(
        height,
        child ? inInclusiveRange(1.0, 1.35) : inInclusiveRange(1.55, 1.9),
        reason: kind.name,
      );
    }
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
