import 'dart:math' as math;

import 'package:engine3d/engine3d.dart';

/// The test world: a walled courtyard with pillars, crates, a torch, a
/// showcase that spins, and hills beyond the walls.
class LabWorld {
  LabWorld._(
    this.scene,
    this.walls,
    this.showcase,
    this.cube,
    this.floor,
    this.torch,
  );

  final Scene scene;
  final List<Box> walls;

  /// Spins in the middle; loaded models go on it.
  final Node showcase;

  /// The cube on the showcase (takes pictures as textures).
  final Node cube;
  final Node floor;
  final PointLight torch;
  Node? model;
  double _t = 0;

  static double hills(double x, double z) {
    final d = math.sqrt(x * x + z * z);
    if (d < 16) {
      return 0;
    }
    final k = math.min(1.0, (d - 16) / 10);
    return k *
        (2.5 +
            2 * math.sin(x * 0.21) * math.cos(z * 0.17) +
            math.sin((x + z) * 0.08) * 1.5);
  }

  static Future<LabWorld> build() async {
    final scene = Scene(
      sky: 0xFF3A4A78,
      ambient: 0xFF4A5068,
      sunDirection: Vector3(-0.5, -1, -0.35),
      sunColor: 0xFFE8D8C0,
      fogColor: 0xFF3A4A78,
      fogNear: 14,
      fogFar: 38,
    );
    final checker = await checkerTexture(
      0xFF8C8478,
      0xFF6E675E,
      size: 32,
      cells: 2,
    );
    final bricks = await brickTexture();
    final grass = await checkerTexture(
      0xFF4E7A3A,
      0xFF46703A,
      size: 16,
      cells: 4,
    );
    final crate = await checkerTexture(
      0xFFB07A3E,
      0xFF8E5E2C,
      size: 16,
      cells: 4,
    );
    final root = scene.root;

    final floor = root.add(
      Node(
        name: 'floor',
        mesh: planeMesh(24, 24, split: 24, tile: 2),
        material: Surface(texture: checker),
        layer: -1,
      ),
    );
    root.add(
      Node(
        name: 'hills',
        mesh: terrainMesh(
          90,
          90,
          36,
          hills,
          tile: 3,
          hole: (x, z) => x.abs() < 12 && z.abs() < 12,
        ),
        layer: -1,
        material: Surface(texture: grass),
        position: Vector3(0, -0.02, 0),
      ),
    );

    // Walls with a gap to the hills on the far side.
    final walls = <Box>[];
    final wallMat = Surface(texture: bricks);
    void wall(double x, double z, double w, double d) {
      root.add(
        Node(
          name: 'wall',
          mesh: boxMesh(w, 3, d, split: 3, uvPerUnit: 0.5),
          material: wallMat,
          position: Vector3(x, 1.5, z),
        ),
      );
      walls.add(Box(x - w / 2, z - d / 2, x + w / 2, z + d / 2));
    }

    wall(0, 12, 24, 0.6);
    wall(-12, 0, 0.6, 24);
    wall(12, 0, 0.6, 24);
    wall(-7, -12, 10, 0.6);
    wall(7, -12, 10, 0.6);

    // Pillars and crates.
    final stone = Surface(color: 0xFFB8B0A4);
    for (final (x, z) in [(-6.0, -6.0), (6.0, -6.0), (-6.0, 6.0), (6.0, 6.0)]) {
      root.add(
        Node(
          name: 'pillar',
          mesh: cylinderMesh(0.5, 3.2, segments: 10),
          material: stone,
          position: Vector3(x, 0, z),
        ),
      );
      walls.add(Box(x - 0.5, z - 0.5, x + 0.5, z + 0.5));
    }
    final crateMat = Surface(texture: crate);
    for (final (x, y, z, s) in [
      (8.0, 0.5, 2.0, 1.0),
      (8.6, 0.5, 3.1, 1.0),
      (8.3, 1.5, 2.5, 1.0),
      (-8.0, 0.4, -3.0, 0.8),
    ]) {
      root.add(
        Node(
          name: 'crate',
          mesh: boxMesh(s, s, s),
          material: crateMat,
          position: Vector3(x, y, z),
        ),
      );
      if (y < 1) {
        walls.add(Box(x - s / 2, z - s / 2, x + s / 2, z + s / 2));
      }
    }
    root.add(
      Node(
        name: 'ball',
        mesh: sphereMesh(0.7, segments: 14, rings: 9),
        material: Surface(color: 0xFFD8504A),
        position: Vector3(-4, 0.7, 3),
      ),
    );
    walls.add(const Box(-4.7, 2.3, -3.3, 3.7));

    // Showcase: plinth and a spinning cube.
    root.add(
      Node(
        name: 'plinth',
        mesh: cylinderMesh(1.1, 0.5, segments: 12),
        material: stone,
      ),
    );
    walls.add(const Box(-1.1, -1.1, 1.1, 1.1));
    final showcase = root.add(
      Node(name: 'showcase', position: Vector3(0, 0.5, 0)),
    );
    final cube = showcase.add(
      Node(
        name: 'cube',
        mesh: boxMesh(1, 1, 1),
        material: Surface(texture: crate),
        position: Vector3(0, 0.9, 0),
      ),
    );

    // Torch on a post, flickering.
    root.add(
      Node(
        name: 'post',
        mesh: boxMesh(0.15, 2, 0.15),
        material: Surface(color: 0xFF5A4030),
        position: Vector3(3, 1, -4),
      ),
    );
    root.add(
      Node(
        name: 'flame',
        mesh: sphereMesh(0.15, segments: 6, rings: 4),
        material: Surface(color: 0xFFFFC060, lit: false),
        position: Vector3(3, 2.15, -4),
      ),
    );
    final torch = PointLight(
      position: Vector3(3, 2.2, -4),
      color: 0xFFFFB060,
      range: 5,
      intensity: 1.4,
    );
    scene.lights.add(torch);
    return LabWorld._(scene, walls, showcase, cube, floor, torch);
  }

  /// Animates the world.
  void tick(double dt) {
    _t += dt;
    showcase.spinY(dt * 0.6);
    torch.intensity = 1.3 + 0.15 * math.sin(_t * 13) + 0.1 * math.sin(_t * 31);
  }

  /// Puts a model on the showcase (replacing the cube).
  void setModel(Node? m) {
    final old = model;
    if (old != null) {
      showcase.children.remove(old);
    }
    model = m == null ? null : fitModel(m, height: 1.8);
    cube.visible = m == null;
    if (model != null) {
      showcase.add(model!);
    }
  }
}
