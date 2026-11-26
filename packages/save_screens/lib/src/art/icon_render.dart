/// Drawing one save icon in 3D, the way the PC's SaveIconStage does it:
/// a PS2 icon's model (morphed by its animation, lit per vertex by the
/// save's ambient colour and three coloured lights, textured), or a 2D
/// picture on a thick tile; all gently swaying.
///
/// This is a small purpose-built painter on `Canvas.drawVertices` rather
/// than engine3d's scene renderer: the PC lights icons with the save's own
/// ambient + three directional lights on the model's colours (scaled for
/// textured icons), morphs between shapes every frame and draws them smooth
/// and full resolution (no PS1 wobble), none of which engine3d's
/// `Scene`/`Surface` lighting expresses. One icon is one or two draw calls.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:save_kit/save_kit.dart';

/// Where an icon is turned at a moment (SaveIconStage._pose).
class IconPose {
  const IconPose(this.yaw, this.pitch, this.roll, this.bob, this.grow);

  final double yaw, pitch, roll, bob, grow;

  static const still = IconPose(0, 0.1, 0, 0, 1);

  factory IconPose.at(double t, double phase, {bool selected = false}) {
    final bob = 0.055 * math.sin(t * 2.1 + phase);
    if (selected) {
      return IconPose(
        0.62 * math.sin(t * math.pi / 3),
        0.13,
        0,
        bob * 0.4,
        IconRender.selectedGrow,
      );
    }
    return IconPose(
      0.38 * math.sin(t * 1.05 + phase),
      0.1,
      0.07 * math.sin(t * 1.6 + phase * 1.3),
      bob,
      1,
    );
  }
}

/// Model data laid out for drawing, made once per icon.
class _IconData {
  _IconData(Ps2Icon ico) : count = ico.vertexCount - ico.vertexCount % 3 {
    shapes = [
      for (final s in ico.shapes)
        Float32List(count * 3)..setAll(0, [
          for (var i = 0; i < count; i++) ...[s[i].x, s[i].y, s[i].z],
        ]),
    ];
    normals = Float32List(count * 3);
    colors = Float32List(count * 3);
    uv = Float32List(count * 2);
    final tw = (ico.texture?.w ?? 128).toDouble();
    final th = (ico.texture?.h ?? 128).toDouble();
    for (var i = 0; i < count; i++) {
      final n = ico.normals[i];
      normals.setAll(i * 3, [n.x, n.y, n.z]);
      final c = ico.colors[i];
      colors.setAll(i * 3, [
        c.r * ico.colorScale,
        c.g * ico.colorScale,
        c.b * ico.colorScale,
      ]);
      uv[i * 2] = ico.uvs[i].$1 * tw;
      uv[i * 2 + 1] = ico.uvs[i].$2 * th;
    }
    final tris = count ~/ 3;
    order = List<int>.generate(tris, (i) => i);
    keys = Float64List(tris);
    pos = Float32List(tris * 6);
    uvOut = Float32List(tris * 6);
    rgb = Int32List(tris * 3);
    xyz = Float32List(count * 3);
    lit = Int32List(count);
  }

  final int count;
  late final List<Float32List> shapes;
  late final Float32List normals, colors, uv;

  // Scratch, reused every frame.
  late final List<int> order;
  late final Float64List keys;
  late final Float32List pos, uvOut, xyz;
  late final Int32List rgb, lit;
}

abstract final class IconRender {
  static const slotFill = 0.6;
  static const selectedGrow = 1.13;
  static const minAmbient = 0.42;

  /// How far the eye is, in model units per unit of slot: the PC's camera
  /// is far away, so there's only a hint of perspective.
  static const eye = 12.0;
  static const tileHalf = (0.64, 0.64, 0.17);
  static const wideHalf = (0.9, 0.495, 0.1);
  static const tileSide = (0.23, 0.23, 0.3);

  /// Bigger pictures (PS3) are drawn smooth, not as pixels.
  static const pixelArtMax = 64;

  static final _data = Expando<_IconData>('ps2IconData');
  static final _shaders = Expando<Map<ui.FilterQuality, ui.ImageShader>>();

  static ui.ImageShader _shader(ui.Image img, ui.FilterQuality q) =>
      (_shaders[img] ??= {})[q] ??= ui.ImageShader(
        img,
        ui.TileMode.repeated,
        ui.TileMode.repeated,
        Float64List.fromList([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]),
        filterQuality: q,
      );

  /// Rotation: roll about Z × pitch about X × yaw about Y (Godot's Basis
  /// order in SaveIconStage), row-major.
  static List<double> _turn(IconPose p) {
    final cy = math.cos(p.yaw), sy = math.sin(p.yaw);
    final cx = math.cos(p.pitch), sx = math.sin(p.pitch);
    final cz = math.cos(p.roll), sz = math.sin(p.roll);
    // Rx * Ry
    final a = [cy, 0.0, sy, sx * sy, cx, -sx * cy, -cx * sy, sx, cx * cy];
    // Rz * (Rx * Ry)
    return [
      cz * a[0] - sz * a[3], cz * a[1] - sz * a[4], cz * a[2] - sz * a[5], //
      sz * a[0] + cz * a[3], sz * a[1] + cz * a[4], sz * a[2] + cz * a[5],
      a[6], a[7], a[8],
    ];
  }

  static int _argb(double r, double g, double b) =>
      0xFF000000 |
      ((r.clamp(0.0, 1.0) * 255).round() << 16) |
      ((g.clamp(0.0, 1.0) * 255).round() << 8) |
      (b.clamp(0.0, 1.0) * 255).round();

  /// A PS2 icon's model in [box]. [tex] null = vertex colours only (no
  /// texture, or not loaded yet). Returns the triangles drawn.
  static int paintPs2(
    ui.Canvas canvas,
    ui.Rect box,
    Ps2Icon ico,
    CardSave save,
    ui.Image? tex,
    IconPose pose,
    double seconds, {
    double shade = 1,
  }) {
    final d = _data[ico] ??= _IconData(ico);
    if (d.count < 3) return 0;
    final n = d.count;
    final xyz = d.xyz;
    // Morph between the shapes.
    if (d.shapes.length > 1) {
      final w = ico.weights(seconds);
      xyz.fillRange(0, n * 3, 0);
      for (var s = 0; s < d.shapes.length; s++) {
        final k = w[s];
        if (k == 0) continue;
        final src = d.shapes[s];
        for (var i = 0; i < n * 3; i++) {
          xyz[i] += src[i] * k;
        }
      }
    } else {
      xyz.setAll(0, d.shapes[0]);
    }
    final m = _turn(pose);
    // The save's lights, with an ambient floor (some ship nearly black).
    final amb = save.ambient;
    final ar = math.max(amb.r, minAmbient);
    final ag = math.max(amb.g, minAmbient);
    final ab = math.max(amb.b, minAmbient);
    final dirs = <Vec3>[], cols = <Rgb>[];
    for (
      var i = 0;
      i < math.min(3, math.min(save.lightDirs.length, save.lightColors.length));
      i++
    ) {
      dirs.add(save.lightDirs[i]);
      cols.add(save.lightColors[i]);
    }
    final side = math.min(box.width, box.height);
    final unit = side * slotFill * pose.grow;
    final cx = box.center.dx, cy = box.center.dy;
    final lift = pose.bob * side * slotFill;
    final nrm = d.normals, col = d.colors;
    for (var i = 0; i < n; i++) {
      final x = xyz[i * 3], y = xyz[i * 3 + 1], z = xyz[i * 3 + 2];
      xyz[i * 3] = m[0] * x + m[1] * y + m[2] * z;
      xyz[i * 3 + 1] = m[3] * x + m[4] * y + m[5] * z;
      xyz[i * 3 + 2] = m[6] * x + m[7] * y + m[8] * z;
      final nx0 = nrm[i * 3], ny0 = nrm[i * 3 + 1], nz0 = nrm[i * 3 + 2];
      final nx = m[0] * nx0 + m[1] * ny0 + m[2] * nz0;
      final ny = m[3] * nx0 + m[4] * ny0 + m[5] * nz0;
      final nz = m[6] * nx0 + m[7] * ny0 + m[8] * nz0;
      var r = ar, g = ag, b = ab;
      for (var k = 0; k < dirs.length; k++) {
        final l = dirs[k];
        final dot = nx * l.x + ny * l.y + nz * l.z;
        if (dot > 0) {
          r += cols[k].r * dot;
          g += cols[k].g * dot;
          b += cols[k].b * dot;
        }
      }
      d.lit[i] = _argb(
        math.min(r, 1.25) * col[i * 3] * shade,
        math.min(g, 1.25) * col[i * 3 + 1] * shade,
        math.min(b, 1.25) * col[i * 3 + 2] * shade,
      );
    }
    // Far triangles first (no depth buffer; the models are small).
    final tris = n ~/ 3;
    for (var t = 0; t < tris; t++) {
      d.keys[t] = xyz[t * 9 + 2] + xyz[t * 9 + 5] + xyz[t * 9 + 8];
    }
    final keys = d.keys;
    d.order.sort((a, b) => keys[a].compareTo(keys[b]));
    for (var o = 0; o < tris; o++) {
      final t = d.order[o];
      for (var k = 0; k < 3; k++) {
        final v = t * 3 + k;
        final p = eye / (eye - xyz[v * 3 + 2]);
        d.pos[o * 6 + k * 2] = cx + xyz[v * 3] * unit * p;
        d.pos[o * 6 + k * 2 + 1] = cy - (xyz[v * 3 + 1] * unit * p + lift);
        d.uvOut[o * 6 + k * 2] = d.uv[v * 2];
        d.uvOut[o * 6 + k * 2 + 1] = d.uv[v * 2 + 1];
        d.rgb[o * 3 + k] = d.lit[v];
      }
    }
    if (tex == null) {
      canvas.drawVertices(
        ui.Vertices.raw(ui.VertexMode.triangles, d.pos, colors: d.rgb),
        ui.BlendMode.dst,
        ui.Paint(),
      );
    } else {
      canvas.drawVertices(
        ui.Vertices.raw(
          ui.VertexMode.triangles,
          d.pos,
          textureCoordinates: d.uvOut,
          colors: d.rgb,
        ),
        ui.BlendMode.modulate,
        ui.Paint()..shader = _shader(tex, ui.FilterQuality.low),
      );
    }
    return tris;
  }

  /// A 2D picture (or PS3 picture) on a thick tile in [box].
  static void paintTile(
    ui.Canvas canvas,
    ui.Rect box,
    ui.Image? face,
    IconPose pose, {
    bool wide = false,
    double shade = 1,
  }) {
    final half = wide ? wideHalf : tileHalf;
    final m = _turn(pose);
    final side = math.min(box.width, box.height);
    final unit = side * slotFill * pose.grow;
    final cx = box.center.dx, cy = box.center.dy;
    final lift = pose.bob * side * slotFill;
    (double, double, double) turn(double x, double y, double z) => (
      m[0] * x + m[1] * y + m[2] * z,
      m[3] * x + m[4] * y + m[5] * z,
      m[6] * x + m[7] * y + m[8] * z,
    );
    ui.Offset project((double, double, double) v) {
      final p = eye / (eye - v.$3);
      return ui.Offset(cx + v.$1 * unit * p, cy - (v.$2 * unit * p + lift));
    }

    // Faces: normal, u axis, v axis (SaveIconStage._box).
    const faces = [
      ((0.0, 0.0, 1.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)),
      ((0.0, 0.0, -1.0), (-1.0, 0.0, 0.0), (0.0, 1.0, 0.0)),
      ((1.0, 0.0, 0.0), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0)),
      ((-1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0)),
      ((0.0, 1.0, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, -1.0)),
      ((0.0, -1.0, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0)),
    ];
    const corners = [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)];
    // The PC's tile light: grey ambient, a key light up-right-front.
    final key = Vec3(0.3, 0.6, 1).normalized();
    final pos = <double>[];
    final rgb = <int>[];
    List<ui.Offset> quad(
      (double, double, double) f,
      (double, double, double) u,
      (double, double, double) v,
      double out,
    ) => [
      for (final c in corners)
        project(
          turn(
            (f.$1 * out + u.$1 * c.$1 + v.$1 * c.$2) * half.$1,
            (f.$2 * out + u.$2 * c.$1 + v.$2 * c.$2) * half.$2,
            (f.$3 * out + u.$3 * c.$1 + v.$3 * c.$2) * half.$3,
          ),
        ),
    ];
    bool facing(List<ui.Offset> q) =>
        (q[1].dx - q[0].dx) * (q[2].dy - q[0].dy) -
            (q[1].dy - q[0].dy) * (q[2].dx - q[0].dx) <
        0;
    for (final (f, u, v) in faces) {
      final q = quad(f, u, v, 1);
      if (!facing(q)) continue;
      final nw = turn(f.$1, f.$2, f.$3);
      final kd = math.max(nw.$1 * key.x + nw.$2 * key.y + nw.$3 * key.z, 0.0);
      final ud = math.max(nw.$2, 0.0);
      final l = 0.72 + 0.36 * kd + 0.1 * ud;
      final c = _argb(
        tileSide.$1 * l * shade,
        tileSide.$2 * l * shade,
        tileSide.$3 * l * shade,
      );
      for (final i in const [0, 1, 2, 0, 2, 3]) {
        pos
          ..add(q[i].dx)
          ..add(q[i].dy);
        rgb.add(c);
      }
    }
    if (pos.isNotEmpty) {
      canvas.drawVertices(
        ui.Vertices.raw(
          ui.VertexMode.triangles,
          Float32List.fromList(pos),
          colors: Int32List.fromList(rgb),
        ),
        ui.BlendMode.dst,
        ui.Paint(),
      );
    }
    if (face == null) return;
    // The picture, just proud of the front face.
    final q = quad((0, 0, 1), (1, 0, 0), (0, 1, 0), 1 + 0.006 / half.$3);
    if (!facing(q)) return;
    final w = face.width.toDouble(), h = face.height.toDouble();
    final uv = [(0.0, h), (w, h), (w, 0.0), (0.0, 0.0)];
    final fp = <double>[], fuv = <double>[];
    for (final i in const [0, 1, 2, 0, 2, 3]) {
      fp
        ..add(q[i].dx)
        ..add(q[i].dy);
      fuv
        ..add(uv[i].$1)
        ..add(uv[i].$2);
    }
    final s = (shade.clamp(0.0, 1.0) * 255).round();
    final pixel = math.max(face.width, face.height) <= pixelArtMax;
    canvas.drawVertices(
      ui.Vertices.raw(
        ui.VertexMode.triangles,
        Float32List.fromList(fp),
        textureCoordinates: Float32List.fromList(fuv),
        colors: Int32List.fromList(
          List.filled(6, 0xFF000000 | s << 16 | s << 8 | s),
        ),
      ),
      ui.BlendMode.modulate,
      ui.Paint()
        ..shader = _shader(
          face,
          pixel ? ui.FilterQuality.none : ui.FilterQuality.medium,
        ),
    );
  }
}
