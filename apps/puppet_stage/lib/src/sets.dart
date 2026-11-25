import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:engine3d/engine3d.dart';

/// The places a movie can happen.
enum StageSet {
  studio('Studio'),
  street('Street'),
  park('Park'),
  room('Living room');

  const StageSet(this.label);
  final String label;
}

/// Builds [set] into a scene (floor and scenery; actors are added later).
Future<Scene> buildSet(StageSet set) async {
  final scene = Scene(
    sky: 0xFF2E3442,
    ambient: 0xFF60646E,
    sunDirection: Vector3(-0.35, -1, -0.5),
    sunColor: 0xFFE8E0D0,
    fogNear: 25,
    fogFar: 60,
  );
  final root = scene.root;
  Node add(
    Mesh m,
    Surface s,
    double x,
    double y,
    double z, {
    double turn = 0,
    int layer = 0,
  }) => root.add(
    Node(
      mesh: m,
      material: s,
      position: Vector3(x, y, z),
      rotation: Quaternion.axisAngle(Vector3(0, 1, 0), turn),
      layer: layer,
    ),
  );

  switch (set) {
    case StageSet.studio:
      scene
        ..sky = 0xFF1E2028
        ..fogColor = 0xFF1E2028;
      final floor = await checkerTexture(
        0xFF8E8A82,
        0xFF86827A,
        size: 16,
        cells: 2,
      );
      add(
        planeMesh(16, 16, split: 16, tile: 2),
        Surface(texture: floor),
        0,
        0,
        0,
        layer: -2,
      );
      // Curved backdrop (a "cyc" wall).
      final b = MeshBuilder();
      const w = 16.0, segs = 6, r = 2.5;
      for (var k = 0; k <= segs; k++) {
        final a = k / segs * math.pi / 2;
        final y = r - r * math.cos(a), z = -6 - r * math.sin(a);
        final ny = math.cos(a), nz = math.sin(a);
        b.vertex(-w / 2, y, z, 0, ny, nz, 0, 0);
        b.vertex(w / 2, y, z, 0, ny, nz, 1, 0);
      }
      b.vertex(-w / 2, 7, -6 - r, 0, 0, 1, 0, 1);
      b.vertex(w / 2, 7, -6 - r, 0, 0, 1, 1, 1);
      for (var k = 0; k <= segs; k++) {
        final a = k * 2;
        b.triangle(a, a + 1, a + 2);
        b.triangle(a + 1, a + 3, a + 2);
      }
      add(b.build(), Surface(color: 0xFFB8B4AC), 0, 0, 0, layer: -1);
      for (final x in [-5.0, 5.0]) {
        add(
          cylinderMesh(0.05, 2.6, segments: 6),
          Surface(color: 0xFF2A2A2A),
          x,
          0,
          -3,
        );
        add(boxMesh(0.5, 0.35, 0.4), Surface(color: 0xFF303030), x, 2.7, -3);
      }
      scene.lights.add(
        PointLight(
          position: Vector3(0, 3.5, 2),
          color: 0xFFFFF0D8,
          range: 9,
          intensity: 0.9,
        ),
      );
    case StageSet.street:
      scene
        ..sky = 0xFF7DA7D9
        ..skyHorizon = 0xFFD6E6F4
        ..fogColor = 0xFFC8DAEC
        ..ambient = 0xFF707888;
      final asphalt = await checkerTexture(
        0xFF4A4A4E,
        0xFF46464A,
        size: 16,
        cells: 8,
      );
      final paving = await checkerTexture(
        0xFFA8A49C,
        0xFF9C988F,
        size: 16,
        cells: 2,
      );
      add(
        planeMesh(40, 8, split: 20, tile: 2),
        Surface(texture: asphalt),
        0,
        0,
        0,
        layer: -2,
      );
      for (final z in [-5.5, 5.5]) {
        add(
          planeMesh(40, 3, split: 20, tile: 1.5),
          Surface(texture: paving),
          0,
          0.12,
          z,
          layer: -1,
        );
        add(
          boxMesh(40, 0.12, 0.2, split: 8),
          Surface(color: 0xFF8A8680),
          0,
          0.06,
          z > 0 ? 4 : -4,
        );
      }
      // Lane stripes.
      for (var x = -18.0; x <= 18; x += 4) {
        add(
          boxMesh(1.6, 0.01, 0.15, split: 1),
          Surface(color: 0xFFE8E0C0),
          x,
          0.01,
          0,
          layer: -1,
        );
      }
      final rnd = math.Random(4);
      final colours = [
        0xFFB06A4A,
        0xFF8A9AB0,
        0xFFC8B48A,
        0xFF7A8A6A,
        0xFFA07A9A,
      ];
      final windows = await _windows();
      for (var x = -16.0; x <= 16; x += 6.5) {
        final h = 5 + rnd.nextDouble() * 6;
        final c = colours[rnd.nextInt(colours.length)];
        add(boxMesh(6, h, 5, split: 2), Surface(color: c), x, h / 2, -9.6);
        add(
          boxMesh(5.2, h - 1.5, 0.05, split: 1),
          Surface(texture: windows, color: 0xFFFFFFFF, fogged: false),
          x,
          h / 2 + 0.4,
          -7.07,
        );
      }
      for (var x = -12.0; x <= 12; x += 8) {
        add(
          cylinderMesh(0.07, 3.2, segments: 6),
          Surface(color: 0xFF303438),
          x,
          0.12,
          -4.6,
        );
        add(
          boxMesh(0.35, 0.18, 0.35),
          Surface(color: 0xFFFFF0B0, lit: false),
          x,
          3.4,
          -4.6,
        );
      }
    case StageSet.park:
      scene
        ..sky = 0xFF6FA6E0
        ..skyHorizon = 0xFFDCEAF6
        ..fogColor = 0xFFCADFEE
        ..ambient = 0xFF6C7868;
      final grass = await checkerTexture(
        0xFF5E8E40,
        0xFF588838,
        size: 16,
        cells: 4,
      );
      final path = await checkerTexture(
        0xFFC8B08A,
        0xFFC0A882,
        size: 16,
        cells: 2,
      );
      add(
        planeMesh(50, 50, split: 25, tile: 3),
        Surface(texture: grass),
        0,
        0,
        0,
        layer: -2,
      );
      add(
        planeMesh(3, 50, split: 25, tile: 2),
        Surface(texture: path),
        0,
        0.01,
        0,
        layer: -1,
      );
      final rnd = math.Random(7);
      for (var k = 0; k < 14; k++) {
        final side = k.isEven ? 1 : -1;
        final x = side * (4 + rnd.nextDouble() * 14),
            z = -18 + rnd.nextDouble() * 30;
        final h = 2 + rnd.nextDouble() * 1.5;
        add(
          cylinderMesh(0.18, h, segments: 6),
          Surface(color: 0xFF6A4A30),
          x,
          0,
          z,
        );
        add(
          sphereMesh(1.2 + rnd.nextDouble() * 0.8, segments: 7, rings: 5),
          Surface(color: 0xFF3E7A34),
          x,
          h + 0.8,
          z,
        );
      }
      // A bench beside the path.
      add(
        boxMesh(1.8, 0.08, 0.5, split: 2),
        Surface(color: 0xFF8A5A34),
        2.4,
        0.48,
        -1,
        turn: math.pi / 2,
      );
      add(
        boxMesh(1.8, 0.5, 0.06, split: 2),
        Surface(color: 0xFF8A5A34),
        2.65,
        0.8,
        -1,
        turn: math.pi / 2,
      );
      for (final dz in [-0.8, 0.8]) {
        add(
          boxMesh(0.4, 0.48, 0.06, split: 1),
          Surface(color: 0xFF303030),
          2.4,
          0.24,
          -1 + dz,
          turn: math.pi / 2,
        );
      }
      add(
        cylinderMesh(3, 0.02, segments: 14),
        Surface(color: 0xFF3A6A9A),
        -6,
        0.01,
        4,
      );
    case StageSet.room:
      scene
        ..sky = 0xFF201C18
        ..fogColor = 0xFF201C18
        ..ambient = 0xFF6A6058;
      final boards = await checkerTexture(
        0xFF9A6E44,
        0xFF8E643C,
        size: 16,
        cells: 4,
      );
      add(
        planeMesh(10, 8, split: 10, tile: 1),
        Surface(texture: boards),
        0,
        0,
        0,
        layer: -2,
      );
      add(
        planeMesh(4, 2.6, split: 4, tile: 10),
        Surface(color: 0xFF8A3A3A),
        0,
        0.01,
        0.6,
        layer: -1,
      ); // rug
      final wall = Surface(color: 0xFFD8CCB4);
      add(boxMesh(10, 3, 0.2, split: 4), wall, 0, 1.5, -4);
      add(boxMesh(0.2, 3, 8, split: 4), wall, -5, 1.5, 0);
      add(boxMesh(0.2, 3, 8, split: 4), wall, 5, 1.5, 0);
      // Sofa, table, lamp, picture.
      final sofa = Surface(color: 0xFF4A6A8A);
      add(boxMesh(2.4, 0.45, 0.9, split: 2), sofa, 0, 0.32, -3.2);
      add(boxMesh(2.4, 0.6, 0.25, split: 2), sofa, 0, 0.75, -3.6);
      for (final x in [-1.3, 1.3]) {
        add(boxMesh(0.25, 0.65, 0.9, split: 1), sofa, x, 0.42, -3.2);
      }
      add(
        boxMesh(1.2, 0.08, 0.6, split: 2),
        Surface(color: 0xFF6A4A2E),
        0,
        0.42,
        -1.6,
      );
      for (final (x, z) in [
        (-0.5, -1.85),
        (0.5, -1.85),
        (-0.5, -1.35),
        (0.5, -1.35),
      ]) {
        add(
          boxMesh(0.06, 0.4, 0.06, split: 1),
          Surface(color: 0xFF5A3E26),
          x,
          0.2,
          z,
        );
      }
      add(
        cylinderMesh(0.04, 1.5, segments: 6),
        Surface(color: 0xFF2A2A2A),
        3.6,
        0,
        -3.3,
      );
      add(
        cylinderMesh(0.3, 0.35, segments: 8),
        Surface(color: 0xFFF0E0B0, lit: false),
        3.6,
        1.5,
        -3.3,
      );
      add(
        boxMesh(1.4, 0.9, 0.05, split: 1),
        Surface(color: 0xFF5A7A9A),
        -2,
        1.8,
        -3.88,
      );
      scene.lights.add(
        PointLight(
          position: Vector3(3.6, 1.6, -3.0),
          color: 0xFFFFD8A0,
          range: 6,
          intensity: 1.2,
        ),
      );
  }
  return scene;
}

/// Lit and dark windows in a grid.
Future<ui.Image> _windows() {
  const w = 32, h = 32;
  final px = Uint32List(w * h);
  final rnd = math.Random(2);
  final lit = List.generate(16, (_) => rnd.nextDouble() < 0.35);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final cx = x ~/ 8, cy = y ~/ 8;
      final inWindow = x % 8 >= 2 && x % 8 <= 6 && y % 8 >= 1 && y % 8 <= 6;
      px[y * w + x] = !inWindow
          ? 0
          : (lit[cy * 4 + cx] ? 0xFFF0D890 : 0xFF283848);
    }
  }
  return imageFromArgb(px, w, h);
}
