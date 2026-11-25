import 'dart:math' as math;

import 'package:app_shell/app_shell.dart' show runInBackground;
import 'package:engine3d/engine3d.dart';
import 'package:landscape/landscape.dart';

import 'movie.dart';
import 'sets.dart';

/// A place, built: its scene, and its ground (actors stand on it).
class BuiltPlace {
  BuiltPlace(this.scene, {this.world, Vector3? origin})
    : origin = origin ?? Vector3.zero();

  final Scene scene;

  /// A Vista landscape (null: a built-in set, flat floor at y = 0).
  final VistaWorld? world;

  /// Where in the landscape the action is (moved to 0, 0, 0).
  final Vector3 origin;

  /// Height of the ground under (x, z), in the place's own coordinates.
  double ground(double x, double z) {
    final w = world;
    if (w == null) return 0;
    return w.groundAt(x + origin.x, z + origin.z) - origin.y;
  }

  /// Keeps a landscape's sun, moon and clouds around the camera, and the
  /// camera above the ground.
  void follow(Camera c) {
    final w = world;
    if (w == null) return;
    final g = ground(c.position.x, c.position.z) + 0.6;
    if (c.position.y < g) c.position.y = g;
    w.follow(Camera(position: c.position + origin, yaw: c.yaw, pitch: c.pitch));
  }
}

HeightField _generate(LandSettings s) => generate(s, n: 129);

/// Builds [p]. A landscape is generated (in the background) and the action
/// moved to a high, fairly flat spot near its middle, above any water.
Future<BuiltPlace> buildPlace(Place p) async {
  final land = p.land;
  if (land == null) return BuiltPlace(await buildSet(p.set ?? StageSet.studio));
  final field = await runInBackground(_generate, land);
  final world = await VistaWorld.build(land, field, detail: 97);
  final sea = land.water ? seaHeight(land) : -1e9;
  var best = Vector3(0, world.groundAt(0, 0), 0);
  var bestScore = -1e9;
  for (var j = -6; j <= 6; j++) {
    for (var i = -6; i <= 6; i++) {
      final x = i * 10.0, z = j * 10.0;
      final h = world.groundAt(x, z);
      if (h < sea + 1.5) continue;
      var slope = 0.0;
      for (final (dx, dz) in [
        (3.0, 0.0),
        (-3.0, 0.0),
        (0.0, 3.0),
        (0.0, -3.0),
      ]) {
        slope = math.max(slope, (world.groundAt(x + dx, z + dz) - h).abs() / 3);
      }
      final score = h * 0.15 - slope * 40 - math.sqrt(x * x + z * z) * 0.05;
      if (score > bestScore) {
        bestScore = score;
        best = Vector3(x, h, z);
      }
    }
  }
  // Move the land so that spot is at 0, 0, 0 (actors and shots are placed
  // around it, as on a set).
  final root = world.scene.root;
  final shifted = Node(name: 'land origin', position: -best)
    ..children.addAll(root.children);
  root.children
    ..clear()
    ..add(shifted);
  return BuiltPlace(world.scene, world: world, origin: best);
}
