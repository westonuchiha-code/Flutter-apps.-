import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:vector_math/vector_math_64.dart';

import 'animation.dart';
import 'camera.dart';
import 'mesh.dart';
import 'scene.dart';

/// How the picture is made. The default is the PS1 look: low internal
/// resolution, vertices snapped to whole pixels (the wobble), unfiltered
/// textures, fog.
class RenderOptions {
  const RenderOptions({
    this.lowRes = 240,
    this.wobble = true,
    this.fog = true,
    this.drawDistance = 40,
    this.lighting = true,
    this.smoothTextures = false,
  });

  /// Clean modern-ish look: full resolution, steady vertices, filtering.
  static const clean = RenderOptions(
    lowRes: 0,
    wobble: false,
    smoothTextures: true,
    drawDistance: 120,
  );

  /// Internal picture height (0: the screen's own resolution).
  final int lowRes;

  /// Snap vertices to whole pixels of the internal picture.
  final bool wobble;
  final bool fog;

  /// Nothing beyond this distance is drawn.
  final double drawDistance;
  final bool lighting;
  final bool smoothTextures;

  RenderOptions copyWith({
    int? lowRes,
    bool? wobble,
    bool? fog,
    double? drawDistance,
    bool? lighting,
    bool? smoothTextures,
  }) => RenderOptions(
    lowRes: lowRes ?? this.lowRes,
    wobble: wobble ?? this.wobble,
    fog: fog ?? this.fog,
    drawDistance: drawDistance ?? this.drawDistance,
    lighting: lighting ?? this.lighting,
    smoothTextures: smoothTextures ?? this.smoothTextures,
  );
}

class RenderStats {
  int triangles = 0, drawn = 0, batches = 0;
  int width = 0, height = 0;
  double ms = 0;
}

/// A projected triangle waiting to be drawn.
class _Tri {
  final xy = Float32List(6);
  final uv = Float32List(6);
  final rgb = Float32List(9);
  final fog = Float32List(3);
  double depth = 0;
  int layer = 0;
  Surface? material;
}

/// One clipped vertex in camera space with everything it carries.
class _V {
  double x = 0, y = 0, z = 0, u = 0, v = 0, r = 0, g = 0, b = 0, fog = 0;
  void lerp(_V a, _V c, double t) {
    x = a.x + (c.x - a.x) * t;
    y = a.y + (c.y - a.y) * t;
    z = a.z + (c.z - a.z) * t;
    u = a.u + (c.u - a.u) * t;
    v = a.v + (c.v - a.v) * t;
    r = a.r + (c.r - a.r) * t;
    g = a.g + (c.g - a.g) * t;
    b = a.b + (c.b - a.b) * t;
    fog = a.fog + (c.fog - a.fog) * t;
  }

  void copy(_V a) => lerp(a, a, 0);
}

double _ch(int c, int shift) => ((c >> shift) & 255) / 255;

/// Draws scenes as sorted, lit, textured triangles (no depth buffer:
/// far to near, like the PS1's ordering table).
class Renderer {
  final stats = RenderStats();
  final _pool = <_Tri>[];
  int _used = 0;
  final _clipIn = List.generate(4, (_) => _V()),
      _clipOut = List.generate(4, (_) => _V());
  final _shaders = <(ui.Image, bool), ui.ImageShader>{};
  final _defaultMaterial = Surface(color: 0xFFC0C0C0);

  /// Paints [scene] from [camera] into [size] on [canvas].
  void paint(
    ui.Canvas canvas,
    ui.Size size,
    Scene scene,
    Camera camera,
    RenderOptions o,
  ) {
    final watch = Stopwatch()..start();
    if (o.lowRes > 0 && o.lowRes < size.height) {
      final ih = o.lowRes,
          iw = math.max(1, (o.lowRes * size.width / size.height).round());
      final rec = ui.PictureRecorder();
      draw(ui.Canvas(rec), iw.toDouble(), ih.toDouble(), scene, camera, o);
      final image = rec.endRecording().toImageSync(iw, ih);
      canvas.drawImageRect(
        image,
        ui.Rect.fromLTWH(0, 0, iw.toDouble(), ih.toDouble()),
        ui.Offset.zero & size,
        ui.Paint()..filterQuality = ui.FilterQuality.none,
      );
      image.dispose();
      stats
        ..width = iw
        ..height = ih;
    } else {
      draw(canvas, size.width, size.height, scene, camera, o);
      stats
        ..width = size.width.round()
        ..height = size.height.round();
    }
    stats.ms = watch.elapsedMicroseconds / 1000;
  }

  /// Draws at [w]×[h] (pixels of the canvas given).
  void draw(
    ui.Canvas canvas,
    double w,
    double h,
    Scene scene,
    Camera camera,
    RenderOptions o,
  ) {
    final horizonColor = scene.skyHorizon;
    if (horizonColor == null) {
      canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, w, h),
        ui.Paint()..color = ui.Color(scene.sky),
      );
    } else {
      // Sky colour overhead fading to the horizon colour, which stays where
      // the horizon is as the camera tilts.
      final fy = 1 / math.tan(camera.fov * math.pi / 360);
      final horizon = h / 2 + math.tan(camera.pitch) * fy * h / 2;
      final top = horizon - h * 0.9;
      canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, w, h),
        ui.Paint()
          ..shader = ui.Gradient.linear(
            ui.Offset(0, top),
            ui.Offset(0, horizon),
            [ui.Color(scene.sky), ui.Color(horizonColor)],
          ),
      );
    }
    _used = 0;
    stats
      ..triangles = 0
      ..drawn = 0
      ..batches = 0;
    if (_hasSkins(scene.root)) updateSkins(scene.root);
    final view = camera.view;
    final f = 1 / math.tan(camera.fov * math.pi / 360);
    final half = h / 2, cx = w / 2, cy = h / 2;
    final far = o.drawDistance;
    final fogNear = math.min(scene.fogNear, far * 0.8),
        fogFar = math.min(scene.fogFar, far);
    final sun = scene.sunDirection;
    final ar = _ch(scene.ambient, 16),
        ag = _ch(scene.ambient, 8),
        ab = _ch(scene.ambient, 0);
    final sr = _ch(scene.sunColor, 16),
        sg = _ch(scene.sunColor, 8),
        sb = _ch(scene.sunColor, 0);

    scene.root.visit(Matrix4.identity(), (node, world) {
      final mesh = node.mesh;
      if (mesh == null) return;
      final n = mesh.vertexCount;
      final mv = (view * world).storage, ws = world.storage;
      final vx = Float64List(n), vy = Float64List(n), vz = Float64List(n);
      final lr = Float32List(n),
          lg = Float32List(n),
          lb = Float32List(n),
          fog = Float32List(n);
      final p = mesh.positions, nm = mesh.normals;
      final parts =
          node.parts ??
          [(0, mesh.triangleCount, node.material ?? _defaultMaterial)];
      final anyLit = o.lighting && parts.any((e) => e.$3.lit);
      for (var i = 0; i < n; i++) {
        final x = p[i * 3], y = p[i * 3 + 1], z = p[i * 3 + 2];
        vx[i] = mv[0] * x + mv[4] * y + mv[8] * z + mv[12];
        vy[i] = mv[1] * x + mv[5] * y + mv[9] * z + mv[13];
        vz[i] = mv[2] * x + mv[6] * y + mv[10] * z + mv[14];
        if (o.fog && scene.fogFar > scene.fogNear) {
          fog[i] = ((-vz[i] - fogNear) / math.max(0.001, fogFar - fogNear))
              .clamp(0.0, 1.0);
        }
        if (!anyLit) continue;
        // Normal in world space (uniform scale assumed).
        final nx0 = nm[i * 3], ny0 = nm[i * 3 + 1], nz0 = nm[i * 3 + 2];
        var nx = ws[0] * nx0 + ws[4] * ny0 + ws[8] * nz0;
        var ny = ws[1] * nx0 + ws[5] * ny0 + ws[9] * nz0;
        var nz = ws[2] * nx0 + ws[6] * ny0 + ws[10] * nz0;
        final len = math.sqrt(nx * nx + ny * ny + nz * nz);
        if (len > 0) {
          nx /= len;
          ny /= len;
          nz /= len;
        }
        final d = math.max(0.0, -(nx * sun.x + ny * sun.y + nz * sun.z));
        var r = ar + sr * d, g = ag + sg * d, b = ab + sb * d;
        if (scene.lights.isNotEmpty) {
          final wx = ws[0] * x + ws[4] * y + ws[8] * z + ws[12];
          final wy = ws[1] * x + ws[5] * y + ws[9] * z + ws[13];
          final wz = ws[2] * x + ws[6] * y + ws[10] * z + ws[14];
          for (final l in scene.lights) {
            final dx = l.position.x - wx,
                dy = l.position.y - wy,
                dz = l.position.z - wz;
            final dist = math.sqrt(dx * dx + dy * dy + dz * dz) + 1e-6;
            final k =
                math.max(0.0, (nx * dx + ny * dy + nz * dz) / dist) *
                l.intensity /
                (1 + (dist / l.range) * (dist / l.range) * 4);
            r += _ch(l.color, 16) * k;
            g += _ch(l.color, 8) * k;
            b += _ch(l.color, 0) * k;
          }
        }
        lr[i] = r;
        lg[i] = g;
        lb[i] = b;
      }
      final idx = mesh.indices, uvs = mesh.uvs, vc = mesh.colors;
      for (final (start, count, material) in parts) {
        final lit = o.lighting && material.lit;
        final tex = material.texture;
        final tw = tex?.width.toDouble() ?? 1, th = tex?.height.toDouble() ?? 1;
        for (var t = start; t < start + count; t++) {
          final a = idx[t * 3], b = idx[t * 3 + 1], c = idx[t * 3 + 2];
          stats.triangles++;
          final za = vz[a], zb = vz[b], zc = vz[c];
          final near = -camera.near;
          if (za > near && zb > near && zc > near) continue; // behind
          if (za < -far && zb < -far && zc < -far) continue; // too far
          var k = 0;
          for (final i in [a, b, c]) {
            final v = _clipIn[k++];
            v
              ..x = vx[i]
              ..y = vy[i]
              ..z = vz[i]
              ..u = uvs[i * 2] * tw
              ..v = uvs[i * 2 + 1] * th
              ..r = (lit ? lr[i] : 1) * (vc == null ? 1 : _ch(vc[i], 16))
              ..g = (lit ? lg[i] : 1) * (vc == null ? 1 : _ch(vc[i], 8))
              ..b = (lit ? lb[i] : 1) * (vc == null ? 1 : _ch(vc[i], 0))
              ..fog = material.fogged ? fog[i] : 0;
          }
          // Clip against the near plane (Sutherland–Hodgman, 3 → up to 4).
          var m = 0;
          for (var e = 0; e < 3; e++) {
            final p0 = _clipIn[e], p1 = _clipIn[(e + 1) % 3];
            final in0 = p0.z <= near, in1 = p1.z <= near;
            if (in0) _clipOut[m++].copy(p0);
            if (in0 != in1) {
              _clipOut[m++].lerp(p0, p1, (near - p0.z) / (p1.z - p0.z));
            }
          }
          for (var q = 1; q + 1 < m; q++) {
            _emit(
              _clipOut[0],
              _clipOut[q],
              _clipOut[q + 1],
              material,
              node.layer,
              node.depthBias,
              f,
              half,
              cx,
              cy,
              o.wobble,
            );
          }
        }
      }
    });

    // Far to near.
    final tris = _pool.sublist(0, _used)
      ..sort(
        (x, y) => x.layer != y.layer
            ? x.layer.compareTo(y.layer)
            : x.depth.compareTo(y.depth),
      );
    _flush(canvas, tris, scene, o);
  }

  void _emit(
    _V a,
    _V b,
    _V c,
    Surface m,
    int layer,
    double bias,
    double f,
    double half,
    double cx,
    double cy,
    bool wobble,
  ) {
    final t = _used < _pool.length ? _pool[_used] : (_pool..add(_Tri())).last;
    var k = 0;
    for (final v in [a, b, c]) {
      var sx = cx + v.x * f / -v.z * half, sy = cy - v.y * f / -v.z * half;
      if (wobble) {
        sx = sx.roundToDouble();
        sy = sy.roundToDouble();
      }
      t.xy[k * 2] = sx;
      t.xy[k * 2 + 1] = sy;
      t.uv[k * 2] = v.u;
      t.uv[k * 2 + 1] = v.v;
      t.rgb[k * 3] = v.r;
      t.rgb[k * 3 + 1] = v.g;
      t.rgb[k * 3 + 2] = v.b;
      t.fog[k] = v.fog;
      k++;
    }
    final area =
        (t.xy[2] - t.xy[0]) * (t.xy[5] - t.xy[1]) -
        (t.xy[4] - t.xy[0]) * (t.xy[3] - t.xy[1]);
    // Screen y points down, so front faces (counter-clockwise) have area < 0.
    if (area == 0 || (area > 0 && !m.doubleSided)) return;
    t
      ..depth = (a.z + b.z + c.z) / 3 + bias
      ..layer = layer
      ..material = m;
    _used++;
  }

  void _flush(ui.Canvas canvas, List<_Tri> tris, Scene scene, RenderOptions o) {
    var i = 0;
    while (i < tris.length) {
      final tex = tris[i].material!.texture;
      var j = i;
      while (j < tris.length &&
          identical(tris[j].material!.texture, tex) &&
          j - i < 4096) {
        j++;
      }
      _drawBatch(canvas, tris, i, j, tex, scene, o);
      i = j;
    }
  }

  void _drawBatch(
    ui.Canvas canvas,
    List<_Tri> tris,
    int from,
    int to,
    ui.Image? tex,
    Scene scene,
    RenderOptions o,
  ) {
    final n = to - from;
    final pos = Float32List(n * 6),
        uv = Float32List(n * 6),
        col = Int32List(n * 3);
    final fogCol = Int32List(n * 3);
    var anyFog = false;
    final fr = (scene.fogColor >> 16) & 255,
        fg = (scene.fogColor >> 8) & 255,
        fb = scene.fogColor & 255;
    for (var t = 0; t < n; t++) {
      final tri = tris[from + t];
      final mc = tri.material!.color;
      final mr = _ch(mc, 16), mg = _ch(mc, 8), mb = _ch(mc, 0);
      pos.setRange(t * 6, t * 6 + 6, tri.xy);
      uv.setRange(t * 6, t * 6 + 6, tri.uv);
      for (var k = 0; k < 3; k++) {
        var r = (mr * tri.rgb[k * 3] * 255).clamp(0.0, 255.0);
        var g = (mg * tri.rgb[k * 3 + 1] * 255).clamp(0.0, 255.0);
        var b = (mb * tri.rgb[k * 3 + 2] * 255).clamp(0.0, 255.0);
        final fo = tri.fog[k];
        if (tex == null && fo > 0) {
          // Untextured: blend straight to the fog colour.
          r += (fr - r) * fo;
          g += (fg - g) * fo;
          b += (fb - b) * fo;
        } else if (fo > 0.004) {
          anyFog = true;
        }
        col[t * 3 + k] =
            (0xFF << 24) | (r.round() << 16) | (g.round() << 8) | b.round();
        fogCol[t * 3 + k] =
            ((fo * 255).round() << 24) | (fr << 16) | (fg << 8) | fb;
      }
    }
    stats.drawn += n;
    stats.batches++;
    if (tex == null) {
      canvas.drawVertices(
        ui.Vertices.raw(ui.VertexMode.triangles, pos, colors: col),
        ui.BlendMode.dst,
        ui.Paint(),
      );
      return;
    }
    final shader = _shaders[(tex, o.smoothTextures)] ??= ui.ImageShader(
      tex,
      ui.TileMode.repeated,
      ui.TileMode.repeated,
      Matrix4.identity().storage,
      filterQuality: o.smoothTextures
          ? ui.FilterQuality.low
          : ui.FilterQuality.none,
    );
    canvas.drawVertices(
      ui.Vertices.raw(
        ui.VertexMode.triangles,
        pos,
        textureCoordinates: uv,
        colors: col,
      ),
      ui.BlendMode.modulate,
      ui.Paint()..shader = shader,
    );
    if (anyFog) {
      canvas.drawVertices(
        ui.Vertices.raw(ui.VertexMode.triangles, pos, colors: fogCol),
        ui.BlendMode.dst,
        ui.Paint(),
      );
    }
  }

  static bool _hasSkins(Node n) {
    if (n.skin != null) return true;
    for (final c in n.children) {
      if (_hasSkins(c)) return true;
    }
    return false;
  }

  /// Forget cached shaders (call when textures are replaced or filtering
  /// changes).
  void clearCache() => _shaders.clear();
}
