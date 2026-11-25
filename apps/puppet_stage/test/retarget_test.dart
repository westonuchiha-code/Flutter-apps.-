import 'package:engine3d/engine3d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:puppet_stage/src/cast.dart';
import 'package:puppet_stage/src/figure.dart';
import 'package:puppet_stage/src/moves.dart';
import 'package:puppet_stage/src/movie.dart';
import 'package:puppet_stage/src/retarget.dart';

/// A bare T-pose skeleton named in a given style (no mesh).
Node skeleton(String Function(String part, String side) name) {
  Node j(String n, double x, double y, double z) =>
      Node(name: n, position: Vector3(x, y, z));
  final root = Node(name: 'Armature');
  final hips = root.add(j(name('hips', ''), 0, 1.0, 0));
  final spine = hips.add(j(name('spine', ''), 0, 0.1, 0));
  final chest = spine.add(j(name('chest', ''), 0, 0.2, 0));
  final neck = chest.add(j(name('neck', ''), 0, 0.25, 0));
  neck.add(j(name('head', ''), 0, 0.1, 0));
  for (final (side, sx) in [('L', 1.0), ('R', -1.0)]) {
    final up = chest.add(j(name('upperArm', side), 0.18 * sx, 0.22, 0));
    final low = up.add(j(name('lowerArm', side), 0.28 * sx, 0, 0));
    low.add(j(name('hand', side), 0.25 * sx, 0, 0));
    final thigh = hips.add(j(name('upperLeg', side), 0.1 * sx, -0.05, 0));
    final shin = thigh.add(j(name('lowerLeg', side), 0, -0.45, 0));
    shin.add(j(name('foot', side), 0, -0.45, 0));
  }
  return root;
}

const _mixamo = {
  'hips': 'Hips', 'spine': 'Spine', 'chest': 'Spine2', 'neck': 'Neck', //
  'head': 'Head', 'upperArm': 'Arm', 'lowerArm': 'ForeArm', 'hand': 'Hand',
  'upperLeg': 'UpLeg', 'lowerLeg': 'Leg', 'foot': 'Foot',
};

void main() {
  final styles = <String, String Function(String, String)>{
    'mixamo': (p, s) =>
        'mixamorig:${s == 'L'
            ? 'Left'
            : s == 'R'
            ? 'Right'
            : ''}${_mixamo[p]}',
    'blender': (p, s) {
      const n = {
        'hips': 'pelvis',
        'spine': 'spine',
        'chest': 'chest',
        'neck': 'neck',
        'head': 'head',
        'upperArm': 'upper_arm',
        'lowerArm': 'forearm',
        'hand': 'hand',
        'upperLeg': 'thigh',
        'lowerLeg': 'shin',
        'foot': 'foot',
      };
      return s.isEmpty ? n[p]! : '${n[p]}.$s';
    },
    'camel': (p, s) {
      final n = '${p[0].toUpperCase()}${p.substring(1)}';
      return '$n$s';
    },
  };

  for (final e in styles.entries) {
    test('finds a ${e.key}-style skeleton', () {
      final bones = findHumanBones(skeleton(e.value));
      expect(bones, isNotNull);
      for (final j in jointNames) {
        expect(bones![j], isNotNull, reason: j);
      }
      // Sides aren't mixed up.
      expect(bones!['upperArmL']!.position.x, greaterThan(0));
      expect(bones['upperLegR']!.position.x, lessThan(0));
    });
  }

  test('things without arms and legs are not people', () {
    final dog = Node(name: 'root')
      ..add(Node(name: 'Body'))
      ..add(Node(name: 'Tail'))
      ..add(Node(name: 'Leg_front'));
    expect(findHumanBones(dog), isNull);
  });

  test('moves land on a T-posed skeleton: arms rest down, wave goes up', () {
    final model = skeleton(styles['mixamo']!);
    final bones = findHumanBones(model)!;
    final proxy = buildCharacter(Kind.man, defaultLooks[Kind.man]!);
    final r = Retarget(proxy, model, bones);
    final clips = clipsFor(proxy);
    Vector3 at(Node n) {
      final w = <Node, Matrix4>{};
      model.visit(Matrix4.identity(), (k, m) => w[k] = m);
      return w[n]!.getTranslation();
    }

    applyState(proxy, clips, const ActorState(0, 0, 0, 'idle', 0));
    r.apply();
    final shoulder = at(bones['upperArmL']!);
    final hand = at(bones['handL']!);
    // T-pose arm (out to the side) now hangs down.
    expect(hand.y, lessThan(shoulder.y - 0.35));
    expect((hand.x - shoulder.x).abs(), lessThan(0.2));
    // Wave: the right hand ends above the head.
    applyState(proxy, clips, const ActorState(0, 0, 0, 'wave', 0.3));
    r.apply();
    expect(at(bones['handR']!).y, greaterThan(at(bones['head']!).y));
    // Sit lowers the hips.
    applyState(proxy, clips, const ActorState(0, 0, 0, 'sit', 2));
    r.apply();
    expect(at(bones['hips']!).y, lessThan(0.85));
    r.reset();
    expect(at(bones['hips']!).y, closeTo(1.0, 1e-6));
  });

  testWidgets('a model with no skeleton slides along and stays upright', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const obj = 'v 0 0 0\nv 1 0 0\nv 1 2 0\nv 0 2 0\nf 1 2 3\nf 1 3 4\n';
      final fig = await loadModelFigure(
        Uint8List.fromList(utf8.encode(obj)),
        'obj',
        height: 3,
      );
      expect(fig.humanoid, isFalse);
      expect(fig.rig, isNull);
      expect(fig.moves, isEmpty);
      fig.apply(const ActorState(2, -1, 90, 'walk', 0.4));
      expect(fig.root.position.x, 2);
      expect(fig.root.position.z, -1);
    });
  });
}
