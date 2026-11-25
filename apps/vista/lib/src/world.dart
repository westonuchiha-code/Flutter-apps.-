import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:engine3d/engine3d.dart';

import 'land.dart';
import 'sky.dart';

/// The real-time scene of a landscape.
class VistaWorld {
  VistaWorld._(
    this.settings,
    this.field,
    this.scene,
    this.sunNode,
    this.moonNode,
    this.clouds,
  );

  final LandSettings settings;

  /// Full-detail heights (for walking, flying and stills).
  final HeightField field;
  final Scene scene;
  final Node sunNode, moonNode, clouds;

  static Future<VistaWorld> build(
    LandSettings s,
    HeightField field, {
    int detail = 97,
  }) async {
    final sky = skyFor(s);
    final scene = Scene(
      sky: sky.zenith,
      skyHorizon: sky.horizon,
      ambient: sky.ambient,
      sunDirection: Vector3(-sky.sun.$1, -sky.sun.$2, -sky.sun.$3),
      sunColor: sky.sunHeight > -0.05
          ? sky.sunColor
          : scaleColor(0xFF8090C0, 0.35),
      fogColor: sky.horizon,
      fogNear: LandSettings.worldSize * (0.55 - s.haze * 0.4),
      fogFar: LandSettings.worldSize * (1.4 - s.haze * 0.7),
    );
    final coarse = field.resample(detail);
    final sea = seaHeight(s);
    scene.root.add(
      Node(
        name: 'land',
        mesh: _landMesh(s, coarse, sea),
        material: Surface(),
        layer: -1,
      ),
    );
    if (s.water) {
      final water = _waterMesh(coarse, sea);
      if (water != null) {
        final waterColor = mixColor(0xFF1E4C78, sky.horizon, 0.35);
        scene.root.add(
          Node(
            name: 'water',
            mesh: water,
            material: Surface(color: waterColor),
            layer: -1,
          ),
        );
      }
    }
    // Sun and moon: far away, never fogged, unlit.
    final sunNode = scene.root.add(
      Node(
        name: 'sun',
        mesh: sphereMesh(8, segments: 10, rings: 6),
        material: Surface(color: 0xFFFFF4D8, lit: false, fogged: false),
      ),
    );
    final moonNode = scene.root.add(
      Node(
        name: 'moon',
        mesh: sphereMesh(5, segments: 10, rings: 6),
        material: Surface(
          color: s.preset == 'moon' ? 0xFF6A9AE0 : 0xFFE8ECF4,
          lit: false,
          fogged: false,
        ),
      ),
    );
    sunNode.visible = sky.sunHeight > -0.05;
    moonNode.visible = sky.night > 0.3;
    final clouds = scene.root.add(Node(name: 'clouds'));
    if (s.clouds > 0.02) {
      final tex = await _cloudTexture(s.seed);
      final rnd = math.Random(s.seed + 5);
      final count = (s.clouds * 26).round();
      final tint = mixColor(0xFFFFFFFF, sky.horizon, sky.night * 0.7 + 0.1);
      for (var k = 0; k < count; k++) {
        final w = 40 + rnd.nextDouble() * 60;
        // Stood upright; turned to face the camera every frame.
        final mesh = planeMesh(w, w * 0.45, split: 2, tile: 1e9);
        // Texture once across the plane.
        final uv = mesh.uvs;
        for (var i = 0; i < uv.length; i += 2) {
          uv[i] = (i ~/ 2 % 3) / 2;
          uv[i + 1] = (i ~/ 2 ~/ 3) / 2;
        }
        clouds.add(
          Node(
            name: 'cloud',
            mesh: mesh,
            material: Surface(
              texture: tex,
              color: tint,
              lit: false,
              doubleSided: true,
              // The fog pass would paint the whole see-through square.
              fogged: false,
            ),
            position: Vector3(
              (rnd.nextDouble() - 0.5) * LandSettings.worldSize * 1.4,
              LandSettings.maxHeight * 1.3 + rnd.nextDouble() * 20,
              (rnd.nextDouble() - 0.5) * LandSettings.worldSize * 1.4,
            ),
          ),
        );
      }
    }
    return VistaWorld._(s, field, scene, sunNode, moonNode, clouds);
  }

  /// Keeps the sun and moon on the sky around the camera.
  void follow(Camera c) {
    final sky = skyFor(settings);
    const d = 300.0;
    sunNode.position =
        c.position + Vector3(sky.sun.$1, sky.sun.$2, sky.sun.$3) * d;
    moonNode.position =
        c.position + Vector3(sky.moon.$1, sky.moon.$2, sky.moon.$3) * d;
    // Clouds stand upright and turn to face the camera.
    for (final cloud in clouds.children) {
      final dx = c.position.x - cloud.position.x;
      final dz = c.position.z - cloud.position.z;
      cloud.rotation =
          Quaternion.axisAngle(Vector3(0, 1, 0), math.atan2(dx, dz)) *
          Quaternion.axisAngle(Vector3(1, 0, 0), math.pi / 2);
    }
  }

  double groundAt(double x, double z) => math.max(
    field.heightAt(x, z),
    settings.water ? seaHeight(settings) : -1e9,
  );
}

Mesh _landMesh(LandSettings s, HeightField f, double sea) {
  final n = f.n;
  final b = MeshBuilder();
  for (var j = 0; j < n; j++) {
    for (var i = 0; i < n; i++) {
      final x = -f.size / 2 + i * f.cell, z = -f.size / 2 + j * f.cell;
      final (nx, ny, nz) = f.normalAt(x, z);
      b.vertex(x, f.at(i, j), z, nx, ny, nz, x / 8, z / 8);
    }
  }
  for (var j = 0; j < n - 1; j++) {
    for (var i = 0; i < n - 1; i++) {
      final a = j * n + i, c = a + n;
      b.triangle(a, c, a + 1);
      b.triangle(a + 1, c, c + 1);
    }
  }
  final m = b.build();
  final colors = Uint32List(m.vertexCount);
  for (var v = 0; v < m.vertexCount; v++) {
    colors[v] = groundColor(
      s,
      m.positions[v * 3 + 1],
      m.normals[v * 3 + 1],
      sea,
    );
  }
  return Mesh(
    positions: m.positions,
    normals: m.normals,
    uvs: m.uvs,
    indices: m.indices,
    colors: colors,
  );
}

/// Flat water only over cells that dip below the sea.
Mesh? _waterMesh(HeightField f, double sea) {
  final n = f.n;
  final b = MeshBuilder();
  for (var j = 0; j < n - 1; j++) {
    for (var i = 0; i < n - 1; i++) {
      if (f.at(i, j) >= sea &&
          f.at(i + 1, j) >= sea &&
          f.at(i, j + 1) >= sea &&
          f.at(i + 1, j + 1) >= sea) {
        continue;
      }
      final x = -f.size / 2 + i * f.cell,
          z = -f.size / 2 + j * f.cell,
          e = f.cell;
      final a = b.vertex(x, sea, z, 0, 1, 0, 0, 0);
      final bb = b.vertex(x + e, sea, z, 0, 1, 0, 1, 0);
      final c = b.vertex(x, sea, z + e, 0, 1, 0, 0, 1);
      final d = b.vertex(x + e, sea, z + e, 0, 1, 0, 1, 1);
      b.triangle(a, c, bb);
      b.triangle(bb, c, d);
    }
  }
  final m = b.build();
  return m.triangleCount == 0 ? null : m;
}

/// A soft round cloud with see-through edges.
Future<ui.Image> _cloudTexture(int seed) {
  const size = 64;
  final px = Uint32List(size * size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final dx = (x - size / 2) / (size / 2), dy = (y - size / 2) / (size / 2);
      final r = math.sqrt(dx * dx + dy * dy);
      final puff =
          noise(x / 9, y / 9, seed) * 0.6 +
          noise(x / 4, y / 4, seed + 1) * 0.25;
      // Round puff, and always clear at the square's edges.
      final edge = ((1 - math.max(dx.abs(), dy.abs())) * 5).clamp(0.0, 1.0);
      final a =
          ((1 - r) * 2.2 + puff * 0.7 - 0.15).clamp(0.0, 1.0) * 0.85 * edge;
      // Premultiplied (what decodeImageFromPixels expects): colour × alpha.
      final v = ((235 + puff * 30).clamp(0, 255) * a).round();
      px[y * size + x] = ((a * 255).round() << 24) | (v << 16) | (v << 8) | v;
    }
  }
  return imageFromArgb(px, size, size);
}
