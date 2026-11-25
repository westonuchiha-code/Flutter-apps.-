import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Surface look: a colour, optionally a texture (tiled), lit or not.
class Surface {
  Surface({
    this.color = 0xFFFFFFFF,
    this.texture,
    this.lit = true,
    this.doubleSided = false,
    this.fogged = true,
    this.name = '',
  });

  /// ARGB, multiplied with the texture.
  int color;
  ui.Image? texture;

  /// Unlit surfaces ignore lights (skies, signs, glowing things).
  bool lit;
  bool doubleSided;

  /// Fades into the fog with distance (off for the sun, moon and sky).
  bool fogged;
  String name;
}

/// Triangles: positions, normals and texture coordinates per vertex.
class Mesh {
  Mesh({
    required this.positions,
    required this.normals,
    required this.uvs,
    required this.indices,
    this.colors,
  });

  /// x, y, z per vertex.
  final Float32List positions;
  final Float32List normals;

  /// u, v per vertex (0..1 across a texture; larger values tile).
  final Float32List uvs;
  final Uint32List indices;

  /// Optional ARGB per vertex (multiplied with the material).
  final Uint32List? colors;

  int get vertexCount => positions.length ~/ 3;
  int get triangleCount => indices.length ~/ 3;

  /// Smallest box around the mesh: (minX, minY, minZ, maxX, maxY, maxZ).
  List<double> get bounds {
    final b = [
      double.infinity,
      double.infinity,
      double.infinity,
      -double.infinity,
      -double.infinity,
      -double.infinity,
    ];
    for (var i = 0; i < positions.length; i += 3) {
      for (var k = 0; k < 3; k++) {
        b[k] = math.min(b[k], positions[i + k]);
        b[k + 3] = math.max(b[k + 3], positions[i + k]);
      }
    }
    return b;
  }
}

/// Builds a mesh piece by piece.
class MeshBuilder {
  final _p = <double>[], _n = <double>[], _uv = <double>[];
  final _i = <int>[];

  int vertex(
    double x,
    double y,
    double z,
    double nx,
    double ny,
    double nz,
    double u,
    double v,
  ) {
    _p.addAll([x, y, z]);
    _n.addAll([nx, ny, nz]);
    _uv.addAll([u, v]);
    return _p.length ~/ 3 - 1;
  }

  void triangle(int a, int b, int c) => _i.addAll([a, b, c]);

  /// A flat grid of [nu]×[nv] squares from [origin] along [du] and [dv]
  /// (small squares keep affine texture warping small, like PS1 games did).
  void grid(
    List<double> origin,
    List<double> du,
    List<double> dv,
    int nu,
    int nv, {
    double uScale = 1,
    double vScale = 1,
  }) {
    final nx = du[1] * dv[2] - du[2] * dv[1],
        ny = du[2] * dv[0] - du[0] * dv[2],
        nz = du[0] * dv[1] - du[1] * dv[0];
    final len = math.sqrt(nx * nx + ny * ny + nz * nz);
    final base = _p.length ~/ 3;
    for (var j = 0; j <= nv; j++) {
      for (var i = 0; i <= nu; i++) {
        final a = i / nu, b = j / nv;
        vertex(
          origin[0] + du[0] * a + dv[0] * b,
          origin[1] + du[1] * a + dv[1] * b,
          origin[2] + du[2] * a + dv[2] * b,
          nx / len,
          ny / len,
          nz / len,
          a * uScale,
          b * vScale,
        );
      }
    }
    for (var j = 0; j < nv; j++) {
      for (var i = 0; i < nu; i++) {
        final v0 = base + j * (nu + 1) + i,
            v1 = v0 + 1,
            v2 = v0 + nu + 1,
            v3 = v2 + 1;
        // Counter-clockwise around du × dv (the face's front).
        triangle(v0, v1, v2);
        triangle(v1, v3, v2);
      }
    }
  }

  Mesh build() => Mesh(
    positions: Float32List.fromList(_p),
    normals: Float32List.fromList(_n),
    uvs: Float32List.fromList(_uv),
    indices: Uint32List.fromList(_i),
  );
}

/// A box centred on the origin. Each face is split [split]×[split].
Mesh boxMesh(
  double sx,
  double sy,
  double sz, {
  int split = 2,
  double uvPerUnit = 0,
}) {
  final b = MeshBuilder();
  final hx = sx / 2, hy = sy / 2, hz = sz / 2;
  double us(double size) => uvPerUnit > 0 ? size * uvPerUnit : 1;
  // Faces as (origin, du, dv) seen from outside, counter-clockwise.
  b.grid(
    [-hx, -hy, hz],
    [sx, 0, 0],
    [0, sy, 0],
    split,
    split,
    uScale: us(sx),
    vScale: us(sy),
  ); // front +z
  b.grid(
    [hx, -hy, -hz],
    [-sx, 0, 0],
    [0, sy, 0],
    split,
    split,
    uScale: us(sx),
    vScale: us(sy),
  ); // back -z
  b.grid(
    [hx, -hy, hz],
    [0, 0, -sz],
    [0, sy, 0],
    split,
    split,
    uScale: us(sz),
    vScale: us(sy),
  ); // right +x
  b.grid(
    [-hx, -hy, -hz],
    [0, 0, sz],
    [0, sy, 0],
    split,
    split,
    uScale: us(sz),
    vScale: us(sy),
  ); // left -x
  b.grid(
    [-hx, hy, hz],
    [sx, 0, 0],
    [0, 0, -sz],
    split,
    split,
    uScale: us(sx),
    vScale: us(sz),
  ); // top +y
  b.grid(
    [-hx, -hy, -hz],
    [sx, 0, 0],
    [0, 0, sz],
    split,
    split,
    uScale: us(sx),
    vScale: us(sz),
  ); // bottom -y
  return _flipV(b.build());
}

/// A flat floor (y = 0) of [w]×[d], split into [split]² squares, its
/// texture repeating every [tile] units.
Mesh planeMesh(double w, double d, {int split = 16, double tile = 2}) {
  final b = MeshBuilder();
  b.grid(
    [-w / 2, 0, d / 2],
    [w, 0, 0],
    [0, 0, -d],
    split,
    split,
    uScale: w / tile,
    vScale: d / tile,
  );
  return b.build();
}

Mesh sphereMesh(double r, {int segments = 16, int rings = 10}) {
  final b = MeshBuilder();
  for (var j = 0; j <= rings; j++) {
    final t = j / rings, phi = t * math.pi;
    for (var i = 0; i <= segments; i++) {
      final s = i / segments, th = s * 2 * math.pi;
      final x = math.sin(phi) * math.cos(th),
          y = math.cos(phi),
          z = math.sin(phi) * math.sin(th);
      b.vertex(x * r, y * r, z * r, x, y, z, s, t);
    }
  }
  for (var j = 0; j < rings; j++) {
    for (var i = 0; i < segments; i++) {
      final a = j * (segments + 1) + i, c = a + segments + 1;
      b.triangle(a, a + 1, c);
      b.triangle(a + 1, c + 1, c);
    }
  }
  return b.build();
}

Mesh cylinderMesh(double r, double h, {int segments = 16}) {
  final b = MeshBuilder();
  for (var j = 0; j <= 1; j++) {
    for (var i = 0; i <= segments; i++) {
      final th = i / segments * 2 * math.pi;
      final x = math.cos(th), z = math.sin(th);
      b.vertex(x * r, j * h, z * r, x, 0, z, i / segments, 1.0 - j);
    }
  }
  for (var i = 0; i < segments; i++) {
    final a = i, c = i + segments + 1;
    b.triangle(a, c, a + 1);
    b.triangle(a + 1, c, c + 1);
  }
  for (final (y, ny) in [(h, 1.0), (0.0, -1.0)]) {
    final centre = b.vertex(0, y, 0, 0, ny, 0, 0.5, 0.5);
    final first = centre + 1;
    for (var i = 0; i <= segments; i++) {
      final th = i / segments * 2 * math.pi;
      b.vertex(
        math.cos(th) * r,
        y,
        math.sin(th) * r,
        0,
        ny,
        0,
        0.5 + math.cos(th) / 2,
        0.5 + math.sin(th) / 2,
      );
    }
    for (var i = 0; i < segments; i++) {
      if (ny > 0) {
        b.triangle(centre, first + i + 1, first + i);
      } else {
        b.triangle(centre, first + i, first + i + 1);
      }
    }
  }
  return b.build();
}

/// Terrain from a height function over [w]×[d] (centred), [n]×[n] squares.
Mesh terrainMesh(
  double w,
  double d,
  int n,
  double Function(double x, double z) height, {
  double tile = 4,
  bool Function(double x, double z)? hole,
}) {
  final b = MeshBuilder();
  double h(double x, double z) => height(x, z);
  for (var j = 0; j <= n; j++) {
    for (var i = 0; i <= n; i++) {
      final x = -w / 2 + w * i / n, z = -d / 2 + d * j / n;
      final e = w / n;
      final nx = h(x - e, z) - h(x + e, z),
          nz = h(x, z - e) - h(x, z + e),
          ny = 2 * e;
      final len = math.sqrt(nx * nx + ny * ny + nz * nz);
      b.vertex(x, h(x, z), z, nx / len, ny / len, nz / len, x / tile, z / tile);
    }
  }
  for (var j = 0; j < n; j++) {
    for (var i = 0; i < n; i++) {
      if (hole != null &&
          hole(-w / 2 + w * (i + 0.5) / n, -d / 2 + d * (j + 0.5) / n)) {
        continue;
      }
      final a = j * (n + 1) + i, c = a + n + 1;
      b.triangle(a, c, a + 1);
      b.triangle(a + 1, c, c + 1);
    }
  }
  return b.build();
}

/// Textures are drawn with v going down the image.
Mesh _flipV(Mesh m) {
  final uv = Float32List.fromList(m.uvs);
  for (var i = 1; i < uv.length; i += 2) {
    uv[i] = -uv[i];
  }
  return Mesh(
    positions: m.positions,
    normals: m.normals,
    uvs: uv,
    indices: m.indices,
  );
}
