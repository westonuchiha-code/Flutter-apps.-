import 'dart:math' as math;

import 'package:engine3d/engine3d.dart';

import 'cast.dart';

/// Plants and things to dress a scene with (built in code, blocky).
enum Prop {
  tree('Tree', 'Plants'),
  pine('Pine tree', 'Plants'),
  palm('Palm tree', 'Plants'),
  bush('Bush', 'Plants'),
  flowers('Flowers', 'Plants'),
  cactus('Cactus', 'Plants'),
  pottedPlant('Potted plant', 'Plants'),
  rock('Rock', 'Plants'),
  table('Table', 'Furniture'),
  chair('Chair', 'Furniture'),
  bench('Bench', 'Furniture'),
  bed('Bed', 'Furniture'),
  sofa('Sofa', 'Furniture'),
  lamp('Lamp', 'Furniture'),
  car('Car', 'Outdoors'),
  fence('Fence', 'Outdoors'),
  lampPost('Lamp post', 'Outdoors'),
  mailbox('Mailbox', 'Outdoors'),
  box('Box', 'Small things'),
  ball('Ball', 'Small things'),
  cup('Cup', 'Small things'),
  sign('Sign', 'Small things');

  const Prop(this.label, this.group);
  final String label, group;
}

/// Colours: top = main, bottom = second, hair = accent, skin = detail.
const propLooks = {
  Prop.tree: Look(
    top: 0xFF4E8A3A,
    bottom: 0xFF6A4A30,
    hair: 0xFF5E9A44,
    skin: 0xFF3E7230,
  ),
  Prop.pine: Look(
    top: 0xFF2E6A44,
    bottom: 0xFF5A3E28,
    hair: 0xFF387A50,
    skin: 0xFF285E3C,
  ),
  Prop.palm: Look(
    top: 0xFF4E9A40,
    bottom: 0xFF9A7A50,
    hair: 0xFF6A4A2A,
    skin: 0xFF3E8034,
  ),
  Prop.bush: Look(
    top: 0xFF4A8038,
    bottom: 0xFF3E7030,
    hair: 0xFFD84A6A,
    skin: 0xFF5A9044,
  ),
  Prop.flowers: Look(
    top: 0xFFE04A5A,
    bottom: 0xFF4A8A3A,
    hair: 0xFFF0C840,
    skin: 0xFFA05AD0,
  ),
  Prop.cactus: Look(
    top: 0xFF4E8A4A,
    bottom: 0xFFC08A50,
    hair: 0xFFF07AA0,
    skin: 0xFF3E7A3E,
  ),
  Prop.pottedPlant: Look(
    top: 0xFF4E9A44,
    bottom: 0xFFB85A3A,
    hair: 0xFF3E8034,
    skin: 0xFF5A3E2A,
  ),
  Prop.rock: Look(
    top: 0xFF8A8680,
    bottom: 0xFF6E6A66,
    hair: 0xFF9A968E,
    skin: 0xFF7A766E,
  ),
  Prop.table: Look(
    top: 0xFF9A6A40,
    bottom: 0xFF7A5232,
    hair: 0xFFE8E0D0,
    skin: 0xFF6A4428,
  ),
  Prop.chair: Look(
    top: 0xFF9A6A40,
    bottom: 0xFF7A5232,
    hair: 0xFFC0485A,
    skin: 0xFF6A4428,
  ),
  Prop.bench: Look(
    top: 0xFF8A5A34,
    bottom: 0xFF2E3238,
    hair: 0xFF8A5A34,
    skin: 0xFF2E3238,
  ),
  Prop.bed: Look(
    top: 0xFFE8E4DC,
    bottom: 0xFF7A5232,
    hair: 0xFF3E6AB0,
    skin: 0xFFF4F0EA,
  ),
  Prop.sofa: Look(
    top: 0xFF4A6A9A,
    bottom: 0xFF3A5480,
    hair: 0xFFE0B040,
    skin: 0xFF2A2420,
  ),
  Prop.lamp: Look(
    top: 0xFFF0E0B0,
    bottom: 0xFF2E2A28,
    hair: 0xFFFFF0C8,
    skin: 0xFF2E2A28,
  ),
  Prop.car: Look(
    top: 0xFFC0383A,
    bottom: 0xFF1E1E22,
    hair: 0xFF8AB0D0,
    skin: 0xFFD8D8D8,
  ),
  Prop.fence: Look(
    top: 0xFFE8E4DC,
    bottom: 0xFFD8D4CC,
    hair: 0xFFE8E4DC,
    skin: 0xFFD8D4CC,
  ),
  Prop.lampPost: Look(
    top: 0xFF2E3238,
    bottom: 0xFF2E3238,
    hair: 0xFFFFF0C0,
    skin: 0xFF3E4248,
  ),
  Prop.mailbox: Look(
    top: 0xFF3E6AB0,
    bottom: 0xFF6A4A30,
    hair: 0xFFC0383A,
    skin: 0xFFD8D8D8,
  ),
  Prop.box: Look(
    top: 0xFFC8A070,
    bottom: 0xFFB08A5A,
    hair: 0xFFE0C090,
    skin: 0xFF8A6A40,
  ),
  Prop.ball: Look(
    top: 0xFFE04A4A,
    bottom: 0xFFF0F0F0,
    hair: 0xFF3E6AB0,
    skin: 0xFFF0C840,
  ),
  Prop.cup: Look(
    top: 0xFFF0ECE4,
    bottom: 0xFF6A3E28,
    hair: 0xFFC0485A,
    skin: 0xFFE8E4DC,
  ),
  Prop.sign: Look(
    top: 0xFFE8D8A0,
    bottom: 0xFF7A5232,
    hair: 0xFF2A2420,
    skin: 0xFF6A4428,
  ),
};

Node _p(Mesh m, int c, double x, double y, double z, {String name = 'part'}) =>
    Node(
      name: name,
      mesh: m,
      material: Surface(color: c),
      position: Vector3(x, y, z),
    );
Mesh _b(double w, double h, double d) => boxMesh(w, h, d, split: 1);

/// Builds [p] standing on y = 0, facing +Z. Parts that move are named:
/// 'sway' (plants: the top bends in the wind), 'wheel' (car) and 'spin'
/// (ball: rolls).
Node buildProp(Prop p, Look l) {
  final root = Node(name: 'actor');
  final top = l.top, second = l.bottom, accent = l.hair, detail = l.skin;
  switch (p) {
    case Prop.tree:
      root.add(_p(cylinderMesh(0.14, 1.6, segments: 6), second, 0, 0, 0));
      final sway = root.add(Node(name: 'sway', position: Vector3(0, 1.4, 0)));
      for (final (x, y, z, r, c) in [
        (0.0, 0.6, 0.0, 0.9, top),
        (0.5, 0.3, 0.2, 0.6, accent),
        (-0.45, 0.35, -0.2, 0.6, detail),
        (0.1, 1.15, -0.1, 0.55, accent),
      ]) {
        sway.add(_p(sphereMesh(r, segments: 7, rings: 5), c, x, y, z));
      }
    case Prop.pine:
      root.add(_p(cylinderMesh(0.12, 0.8, segments: 6), second, 0, 0, 0));
      final sway = root.add(Node(name: 'sway', position: Vector3(0, 0.6, 0)));
      for (var k = 0; k < 4; k++) {
        final r = 0.95 - k * 0.22;
        sway.add(
          _p(
            cylinderMesh(r, 0.55, segments: 7),
            k.isEven ? top : accent,
            0,
            k * 0.5,
            0,
          ),
        );
      }
      sway.add(_p(_b(0.15, 0.4, 0.15), top, 0, 2.15, 0));
    case Prop.palm:
      final sway = root.add(Node(name: 'sway'));
      // A leaning, segmented trunk.
      for (var k = 0; k < 7; k++) {
        sway.add(
          _p(
            cylinderMesh(0.13 - k * 0.008, 0.42, segments: 6),
            k.isEven ? second : accent,
            k * k * 0.008,
            k * 0.4,
            0,
          ),
        );
      }
      final crown = sway.add(Node(position: Vector3(0.36, 2.85, 0)));
      for (var k = 0; k < 6; k++) {
        final leaf = crown.add(
          Node(
            rotation: Quaternion.axisAngle(Vector3(0, 1, 0), k * math.pi / 3),
          ),
        );
        final blade = leaf.add(
          _p(_b(0.28, 0.04, 1.3), k.isEven ? top : detail, 0, 0, 0.6),
        );
        blade.rotation = Quaternion.axisAngle(Vector3(1, 0, 0), 0.45);
      }
      crown.add(
        _p(sphereMesh(0.14, segments: 6, rings: 4), 0xFF5A3E22, 0, -0.1, 0),
      );
    case Prop.bush:
      final sway = root.add(Node(name: 'sway'));
      for (final (x, y, z, r, c) in [
        (0.0, 0.5, 0.0, 0.5, top),
        (0.35, 0.38, 0.15, 0.38, second),
        (-0.35, 0.4, -0.1, 0.4, detail),
      ]) {
        sway.add(_p(sphereMesh(r, segments: 7, rings: 5), c, x, y, z));
      }
      final rnd = math.Random(3);
      for (var k = 0; k < 7; k++) {
        final a = rnd.nextDouble() * math.pi * 2;
        sway.add(
          _p(
            _b(0.07, 0.07, 0.07),
            accent,
            math.cos(a) * 0.45,
            0.45 + rnd.nextDouble() * 0.4,
            math.sin(a) * 0.45,
          ),
        );
      }
    case Prop.flowers:
      final sway = root.add(Node(name: 'sway'));
      final rnd = math.Random(8);
      final colours = [top, accent, detail];
      for (var k = 0; k < 9; k++) {
        final x = (rnd.nextDouble() - 0.5) * 0.6;
        final z = (rnd.nextDouble() - 0.5) * 0.6;
        final h = 0.25 + rnd.nextDouble() * 0.2;
        sway.add(_p(_b(0.02, h, 0.02), second, x, h / 2, z));
        sway.add(_p(_b(0.09, 0.05, 0.09), colours[k % 3], x, h, z));
        sway.add(_p(_b(0.03, 0.055, 0.03), 0xFFF0E040, x, h + 0.005, z));
      }
      for (var k = 0; k < 5; k++) {
        sway.add(
          _p(
            _b(0.08, 0.1, 0.03),
            second,
            (rnd.nextDouble() - 0.5) * 0.5,
            0.05,
            (rnd.nextDouble() - 0.5) * 0.5,
          ),
        );
      }
    case Prop.cactus:
      root.add(_p(_b(0.26, 1.3, 0.26), top, 0, 0.65, 0));
      for (final (sx, y, h) in [(1.0, 0.55, 0.45), (-1.0, 0.75, 0.35)]) {
        root.add(_p(_b(0.22, 0.14, 0.16), top, sx * 0.22, y, 0));
        root.add(_p(_b(0.16, h, 0.16), detail, sx * 0.32, y + h / 2, 0));
      }
      root.add(_p(_b(0.12, 0.08, 0.12), accent, 0, 1.33, 0));
      root.add(_p(_b(0.6, 0.06, 0.5), second, 0, 0.03, 0));
    case Prop.pottedPlant:
      root.add(_p(cylinderMesh(0.18, 0.32, segments: 8), second, 0, 0, 0));
      root.add(_p(cylinderMesh(0.16, 0.02, segments: 8), detail, 0, 0.3, 0));
      final sway = root.add(Node(name: 'sway', position: Vector3(0, 0.3, 0)));
      for (var k = 0; k < 7; k++) {
        final leaf = sway.add(
          Node(
            rotation:
                Quaternion.axisAngle(Vector3(0, 1, 0), k * math.pi * 2 / 7) *
                Quaternion.axisAngle(Vector3(1, 0, 0), 0.35 + (k % 3) * 0.15),
          ),
        );
        leaf.add(_p(_b(0.1, 0.5, 0.03), k.isEven ? top : accent, 0, 0.25, 0));
      }
    case Prop.rock:
      root.add(
        _p(sphereMesh(0.45, segments: 6, rings: 4), top, 0, 0.3, 0)
          ..scale = Vector3(1.2, 0.7, 1),
      );
      root.add(
        _p(sphereMesh(0.28, segments: 5, rings: 4), second, 0.42, 0.19, 0.2)
          ..scale = Vector3(1, 0.7, 1.1),
      );
    case Prop.table:
      root.add(_p(_b(1.2, 0.06, 0.75), top, 0, 0.74, 0));
      for (final (x, z) in [
        (0.52, 0.3),
        (-0.52, 0.3),
        (0.52, -0.3),
        (-0.52, -0.3),
      ]) {
        root.add(_p(_b(0.06, 0.72, 0.06), second, x, 0.36, z));
      }
    case Prop.chair:
      root.add(_p(_b(0.46, 0.05, 0.44), top, 0, 0.45, 0));
      root.add(_p(_b(0.4, 0.04, 0.38), accent, 0, 0.48, 0));
      for (final (x, z) in [
        (0.2, 0.19),
        (-0.2, 0.19),
        (0.2, -0.19),
        (-0.2, -0.19),
      ]) {
        root.add(_p(_b(0.04, 0.45, 0.04), second, x, 0.225, z));
      }
      // Back (behind: -Z, so whoever sits faces +Z).
      root.add(_p(_b(0.46, 0.5, 0.04), top, 0, 0.72, -0.2));
    case Prop.bench:
      for (var k = 0; k < 3; k++) {
        root.add(_p(_b(1.6, 0.04, 0.1), top, 0, 0.45, 0.13 - k * 0.13));
      }
      for (var k = 0; k < 2; k++) {
        root.add(_p(_b(1.6, 0.1, 0.03), top, 0, 0.6 + k * 0.15, -0.22));
      }
      for (final x in [-0.7, 0.7]) {
        root.add(_p(_b(0.06, 0.45, 0.4), second, x, 0.225, 0));
        root.add(_p(_b(0.06, 0.4, 0.05), second, x, 0.65, -0.22));
      }
    case Prop.bed:
      root.add(_p(_b(1.1, 0.3, 2.0), second, 0, 0.15, 0));
      root.add(_p(_b(1.04, 0.16, 1.94), top, 0, 0.38, 0));
      root.add(_p(_b(1.06, 0.05, 1.3), accent, 0, 0.47, 0.3));
      root.add(_p(_b(0.7, 0.12, 0.35), detail, 0, 0.52, -0.7));
      root.add(_p(_b(1.1, 0.8, 0.08), second, 0, 0.4, -1.0));
    case Prop.sofa:
      root.add(_p(_b(1.8, 0.4, 0.8), top, 0, 0.2, 0));
      root.add(_p(_b(1.6, 0.12, 0.65), second, 0, 0.46, 0.05));
      root.add(_p(_b(1.8, 0.45, 0.2), top, 0, 0.62, -0.3));
      for (final x in [-0.84, 0.84]) {
        root.add(_p(_b(0.14, 0.62, 0.8), top, x, 0.31, 0));
      }
      root.add(_p(_b(0.35, 0.3, 0.1), accent, -0.45, 0.6, -0.17));
    case Prop.lamp:
      root.add(_p(cylinderMesh(0.16, 0.03, segments: 8), second, 0, 0, 0));
      root.add(_p(_b(0.03, 1.4, 0.03), detail, 0, 0.7, 0));
      root.add(
        Node(
          name: 'part',
          mesh: cylinderMesh(0.22, 0.3, segments: 8),
          material: Surface(color: accent, lit: false),
          position: Vector3(0, 1.3, 0),
        ),
      );
    case Prop.car:
      // Body, cabin, windows, lights; wheels turn when it drives.
      root.add(_p(_b(1.7, 0.5, 3.8), top, 0, 0.55, 0));
      root.add(_p(_b(1.5, 0.45, 1.9), top, 0, 1.02, -0.2));
      for (final sx in [-1.0, 1.0]) {
        root.add(_p(_b(0.01, 0.32, 1.6), accent, sx * 0.755, 1.03, -0.2));
      }
      root.add(_p(_b(1.36, 0.34, 0.01), accent, 0, 1.03, 0.755));
      root.add(_p(_b(1.36, 0.3, 0.01), accent, 0, 1.03, -1.155));
      for (final sx in [-1.0, 1.0]) {
        root.add(
          Node(
            name: 'part',
            mesh: _b(0.3, 0.14, 0.02),
            material: Surface(color: 0xFFFFF4C0, lit: false),
            position: Vector3(sx * 0.58, 0.6, 1.905),
          ),
        );
        root.add(_p(_b(0.3, 0.12, 0.02), 0xFFC02020, sx * 0.62, 0.62, -1.905));
      }
      root.add(_p(_b(1.72, 0.12, 0.1), detail, 0, 0.36, 1.9));
      root.add(_p(_b(1.72, 0.12, 0.1), detail, 0, 0.36, -1.9));
      for (final (x, z) in [
        (0.8, 1.2),
        (-0.8, 1.2),
        (0.8, -1.2),
        (-0.8, -1.2),
      ]) {
        final w = root.add(Node(name: 'wheel', position: Vector3(x, 0.34, z)));
        final tyre = w.add(
          _p(cylinderMesh(0.34, 0.24, segments: 8), second, 0, 0, 0),
        );
        tyre.rotation = Quaternion.axisAngle(Vector3(0, 0, 1), math.pi / 2);
        tyre.position = Vector3(x > 0 ? 0.12 : -0.12, 0, 0);
        final hub = w.add(
          _p(_b(0.02, 0.24, 0.08), detail, x > 0 ? 0.125 : -0.125, 0, 0),
        );
        hub.name = 'part';
      }
    case Prop.fence:
      for (var k = 0; k < 6; k++) {
        root.add(_p(_b(0.1, 0.9, 0.04), top, -1.0 + k * 0.4, 0.45, 0));
        root.add(
          _p(_b(0.07, 0.07, 0.04), top, -1.0 + k * 0.4, 0.92, 0)
            ..rotation = Quaternion.axisAngle(Vector3(0, 0, 1), math.pi / 4),
        );
      }
      for (final y in [0.25, 0.65]) {
        root.add(_p(_b(2.2, 0.08, 0.03), second, 0, y, -0.035));
      }
    case Prop.lampPost:
      root.add(_p(cylinderMesh(0.15, 0.2, segments: 8), detail, 0, 0, 0));
      root.add(_p(cylinderMesh(0.06, 3.2, segments: 6), top, 0, 0, 0));
      root.add(_p(_b(0.5, 0.06, 0.06), top, 0.2, 3.15, 0));
      root.add(
        Node(
          name: 'part',
          mesh: _b(0.26, 0.22, 0.26),
          material: Surface(color: accent, lit: false),
          position: Vector3(0.42, 3.02, 0),
        ),
      );
    case Prop.mailbox:
      root.add(_p(_b(0.08, 1.0, 0.08), second, 0, 0.5, 0));
      root.add(_p(_b(0.24, 0.24, 0.48), top, 0, 1.1, 0.05));
      root.add(_p(_b(0.04, 0.16, 0.04), accent, 0.14, 1.22, -0.08));
      root.add(_p(_b(0.04, 0.04, 0.14), accent, 0.14, 1.32, -0.03));
    case Prop.box:
      root.add(_p(_b(0.5, 0.4, 0.4), top, 0, 0.2, 0));
      root.add(_p(_b(0.51, 0.06, 0.41), detail, 0, 0.4, 0));
      root.add(_p(_b(0.1, 0.405, 0.405), accent, 0, 0.2, 0));
    case Prop.ball:
      final spin = root.add(Node(name: 'spin', position: Vector3(0, 0.15, 0)));
      spin.add(_p(sphereMesh(0.15, segments: 8, rings: 6), top, 0, 0, 0));
      spin.add(_p(_b(0.31, 0.06, 0.06), second, 0, 0, 0));
      spin.add(_p(_b(0.06, 0.06, 0.31), accent, 0, 0, 0));
    case Prop.cup:
      root.add(_p(cylinderMesh(0.05, 0.11, segments: 8), top, 0, 0, 0));
      root.add(_p(cylinderMesh(0.042, 0.005, segments: 8), second, 0, 0.1, 0));
      root.add(_p(_b(0.015, 0.06, 0.04), top, 0.06, 0.055, 0));
      root.add(_p(_b(0.07, 0.02, 0.005), accent, 0, 0.06, 0.05));
    case Prop.sign:
      root.add(_p(_b(0.08, 1.3, 0.08), second, 0, 0.65, 0));
      root.add(_p(_b(0.9, 0.5, 0.05), top, 0, 1.25, 0.06));
      for (var k = 0; k < 3; k++) {
        root.add(
          _p(_b(0.6 - k * 0.12, 0.05, 0.01), accent, 0, 1.38 - k * 0.12, 0.09),
        );
      }
  }
  return root;
}
