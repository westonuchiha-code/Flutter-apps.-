import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart';

import 'mesh.dart';
import 'scene.dart';

/// Reads a Wavefront OBJ (positions, texture coordinates, normals, faces of
/// any size). Materials files are not read: the model gets [material].
Node loadObj(String text, {String name = 'model', Surface? material}) {
  final v = <double>[], vt = <double>[], vn = <double>[];
  final pos = <double>[], nor = <double>[], uv = <double>[];
  final idx = <int>[];
  final seen = <String, int>{};
  var needNormals = false;

  int vertex(String key) {
    final hit = seen[key];
    if (hit != null) return hit;
    final parts = key.split('/');
    int at(String s, int count) {
      final i = int.parse(s);
      return i < 0 ? count + i : i - 1;
    }

    final p = at(parts[0], v.length ~/ 3);
    pos.addAll(v.sublist(p * 3, p * 3 + 3));
    if (parts.length > 1 && parts[1].isNotEmpty) {
      final t = at(parts[1], vt.length ~/ 2);
      uv.addAll([vt[t * 2], 1 - vt[t * 2 + 1]]);
    } else {
      uv.addAll([0, 0]);
    }
    if (parts.length > 2 && parts[2].isNotEmpty) {
      final n = at(parts[2], vn.length ~/ 3);
      nor.addAll(vn.sublist(n * 3, n * 3 + 3));
    } else {
      nor.addAll([0, 0, 0]);
      needNormals = true;
    }
    return seen[key] = pos.length ~/ 3 - 1;
  }

  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final f = line.split(RegExp(r'\s+'));
    switch (f[0]) {
      case 'v' when f.length >= 4:
        v.addAll([double.parse(f[1]), double.parse(f[2]), double.parse(f[3])]);
      case 'vt' when f.length >= 3:
        vt.addAll([double.parse(f[1]), double.parse(f[2])]);
      case 'vn' when f.length >= 4:
        vn.addAll([double.parse(f[1]), double.parse(f[2]), double.parse(f[3])]);
      case 'f' when f.length >= 4:
        final ids = [for (final k in f.skip(1)) vertex(k)];
        for (var i = 1; i + 1 < ids.length; i++) {
          idx.addAll([ids[0], ids[i], ids[i + 1]]);
        }
    }
  }
  if (needNormals) {
    final acc = List<double>.filled(pos.length, 0);
    for (var t = 0; t < idx.length; t += 3) {
      final a = idx[t], b = idx[t + 1], c = idx[t + 2];
      final e1 = Vector3(
        pos[b * 3] - pos[a * 3],
        pos[b * 3 + 1] - pos[a * 3 + 1],
        pos[b * 3 + 2] - pos[a * 3 + 2],
      );
      final e2 = Vector3(
        pos[c * 3] - pos[a * 3],
        pos[c * 3 + 1] - pos[a * 3 + 1],
        pos[c * 3 + 2] - pos[a * 3 + 2],
      );
      final n = e1.cross(e2);
      for (final k in [a, b, c]) {
        acc[k * 3] += n.x;
        acc[k * 3 + 1] += n.y;
        acc[k * 3 + 2] += n.z;
      }
    }
    for (var k = 0; k < pos.length; k += 3) {
      if (nor[k] != 0 || nor[k + 1] != 0 || nor[k + 2] != 0) continue;
      final l = math.sqrt(
        acc[k] * acc[k] + acc[k + 1] * acc[k + 1] + acc[k + 2] * acc[k + 2],
      );
      if (l > 0) {
        nor[k] = acc[k] / l;
        nor[k + 1] = acc[k + 1] / l;
        nor[k + 2] = acc[k + 2] / l;
      }
    }
  }
  if (idx.isEmpty) throw const FormatException('No faces in this OBJ');
  return Node(name: name)..add(
    Node(
      name: name,
      mesh: Mesh(
        positions: Float32List.fromList(pos),
        normals: Float32List.fromList(nor),
        uvs: Float32List.fromList(uv),
        indices: Uint32List.fromList(idx),
      ),
      material: material ?? Surface(color: 0xFFC8C8C8),
    ),
  );
}

/// The world-space box around everything under [node]:
/// (minX, minY, minZ, maxX, maxY, maxZ), or null if empty.
List<double>? boundsOf(Node node) {
  final b = [
    double.infinity,
    double.infinity,
    double.infinity,
    -double.infinity,
    -double.infinity,
    -double.infinity,
  ];
  var any = false;
  node.visit(Matrix4.identity(), (n, world) {
    final m = n.mesh;
    if (m == null) return;
    final p = m.positions;
    final v = Vector3.zero();
    for (var i = 0; i < p.length; i += 3) {
      v.setValues(p[i], p[i + 1], p[i + 2]);
      world.transform3(v);
      any = true;
      b[0] = math.min(b[0], v.x);
      b[1] = math.min(b[1], v.y);
      b[2] = math.min(b[2], v.z);
      b[3] = math.max(b[3], v.x);
      b[4] = math.max(b[4], v.y);
      b[5] = math.max(b[5], v.z);
    }
  });
  return any ? b : null;
}

/// Wraps [model] so it is [height] tall, centred, standing on y = 0.
Node fitModel(Node model, {double height = 1.6}) {
  final wrapper = Node(name: model.name, children: [model]);
  final b = boundsOf(wrapper);
  if (b == null) return wrapper;
  final size = math.max(
    b[4] - b[1],
    math.max((b[3] - b[0]) * 0.6, (b[5] - b[2]) * 0.6),
  );
  final k = size <= 0 ? 1.0 : height / size;
  wrapper
    ..scale = Vector3.all(k)
    ..position = Vector3(
      -(b[0] + b[3]) / 2 * k,
      -b[1] * k,
      -(b[2] + b[5]) / 2 * k,
    );
  return wrapper;
}
