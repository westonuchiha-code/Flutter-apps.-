import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart';

import 'mesh.dart';
import 'scene.dart';

enum AnimPath { translation, rotation, scale }

/// Keyframes for one property of one node.
class Channel {
  Channel(this.target, this.path, this.times, this.values, {this.step = false});

  final Node target;
  final AnimPath path;

  /// Seconds, increasing.
  final Float32List times;

  /// 3 (translation, scale) or 4 (rotation x, y, z, w) numbers per key.
  final Float32List values;

  /// Hold each key until the next (no in-between).
  final bool step;

  int get width => path == AnimPath.rotation ? 4 : 3;

  /// The value at [t] into [out] (length [width]).
  void sample(double t, List<double> out) {
    final n = times.length, w = width;
    if (n == 0) {
      return;
    }
    if (t <= times[0] || n == 1) {
      for (var k = 0; k < w; k++) {
        out[k] = values[k];
      }
      return;
    }
    if (t >= times[n - 1]) {
      for (var k = 0; k < w; k++) {
        out[k] = values[(n - 1) * w + k];
      }
      return;
    }
    var lo = 0, hi = n - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (times[mid] <= t) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final a = lo * w, b = hi * w;
    final f = step ? 0.0 : (t - times[lo]) / (times[hi] - times[lo]);
    if (path == AnimPath.rotation) {
      _slerp(values, a, b, f, out);
    } else {
      for (var k = 0; k < 3; k++) {
        out[k] = values[a + k] + (values[b + k] - values[a + k]) * f;
      }
    }
  }
}

void _slerp(Float32List v, int a, int b, double t, List<double> out) {
  var bx = v[b], by = v[b + 1], bz = v[b + 2], bw = v[b + 3];
  var d = v[a] * bx + v[a + 1] * by + v[a + 2] * bz + v[a + 3] * bw;
  if (d < 0) {
    d = -d;
    bx = -bx;
    by = -by;
    bz = -bz;
    bw = -bw;
  }
  double k0, k1;
  if (d > 0.9995) {
    k0 = 1 - t;
    k1 = t;
  } else {
    final th = math.acos(d), s = math.sin(th);
    k0 = math.sin((1 - t) * th) / s;
    k1 = math.sin(t * th) / s;
  }
  var x = v[a] * k0 + bx * k1,
      y = v[a + 1] * k0 + by * k1,
      z = v[a + 2] * k0 + bz * k1,
      w = v[a + 3] * k0 + bw * k1;
  final l = math.sqrt(x * x + y * y + z * z + w * w);
  x /= l;
  y /= l;
  z /= l;
  w /= l;
  out
    ..[0] = x
    ..[1] = y
    ..[2] = z
    ..[3] = w;
}

/// A named animation: channels over [duration] seconds.
class AnimationClip {
  AnimationClip(this.name, this.channels, {double? duration, this.loop = true})
    : duration =
          duration ??
          channels.fold<double>(
            0,
            (m, c) => c.times.isEmpty ? m : math.max(m, c.times.last),
          );

  final String name;
  final List<Channel> channels;
  final double duration;
  bool loop;

  /// The same clip moving another skeleton: channels re-targeted by node
  /// name (characters built the same way share clips).
  AnimationClip retarget(Map<String, Node> joints) => AnimationClip(
    name,
    [
      for (final c in channels)
        if (joints[c.target.name] != null)
          Channel(
            joints[c.target.name]!,
            c.path,
            c.times,
            c.values,
            step: c.step,
          ),
    ],
    duration: duration,
    loop: loop,
  );

  double _local(double t) =>
      duration <= 0 ? 0 : (loop ? t % duration : math.min(t, duration));

  /// Sets every target to its value at [t].
  void apply(double t) {
    final lt = _local(t);
    final tmp = [0.0, 0.0, 0.0, 0.0];
    for (final c in channels) {
      c.sample(lt, tmp);
      _set(c, tmp, 1);
    }
  }

  /// Blends this clip at [t] over whatever the targets hold, by [weight].
  void blend(double t, double weight) {
    final lt = _local(t);
    final tmp = [0.0, 0.0, 0.0, 0.0];
    for (final c in channels) {
      c.sample(lt, tmp);
      _set(c, tmp, weight);
    }
  }

  static void _set(Channel c, List<double> v, double w) {
    final n = c.target;
    switch (c.path) {
      case AnimPath.translation:
        final p = Vector3(v[0], v[1], v[2]);
        n.position = w >= 1 ? p : n.position + (p - n.position) * w;
      case AnimPath.scale:
        final s = Vector3(v[0], v[1], v[2]);
        n.scale = w >= 1 ? s : n.scale + (s - n.scale) * w;
      case AnimPath.rotation:
        final q = Quaternion(v[0], v[1], v[2], v[3]);
        n.rotation = w >= 1 ? q : slerp(n.rotation, q, w);
    }
  }
}

Quaternion slerp(Quaternion a, Quaternion b, double t) {
  final v = Float32List.fromList([a.x, a.y, a.z, a.w, b.x, b.y, b.z, b.w]);
  final out = [0.0, 0.0, 0.0, 0.0];
  _slerp(v, 0, 4, t, out);
  return Quaternion(out[0], out[1], out[2], out[3]);
}

/// Plays clips on a character, crossfading from one to the next.
class Animator {
  Animator(this.clips);

  final Map<String, AnimationClip> clips;
  AnimationClip? _current, _previous;
  double _time = 0, _prevTime = 0, _fade = 0, _fadeLength = 0.25;

  /// Rest pose of every animated node, so switching clips starts clean.
  final _rest = <Node, (Vector3, Quaternion, Vector3)>{};

  String? get playing => _current?.name;
  double get time => _time;

  void _remember(AnimationClip c) {
    for (final ch in c.channels) {
      _rest.putIfAbsent(
        ch.target,
        () => (
          ch.target.position.clone(),
          Quaternion.copy(ch.target.rotation),
          ch.target.scale.clone(),
        ),
      );
    }
  }

  void _resetPose() {
    _rest.forEach((n, r) {
      n
        ..position = r.$1.clone()
        ..rotation = Quaternion.copy(r.$2)
        ..scale = r.$3.clone();
    });
  }

  /// Starts [name] (from [from] seconds), fading over [fade] seconds.
  void play(String name, {double fade = 0.25, double from = 0}) {
    final c = clips[name];
    if (c == null) {
      return;
    }
    _remember(c);
    if (identical(c, _current) && from == _time) {
      return;
    }
    _previous = _current;
    _prevTime = _time;
    _current = c;
    _time = from;
    _fade = _previous == null ? 0 : fade;
    _fadeLength = math.max(1e-3, fade);
  }

  void update(double dt) {
    final c = _current;
    if (c == null) {
      return;
    }
    _time += dt;
    _prevTime += dt;
    _fade = math.max(0, _fade - dt);
    _resetPose();
    final p = _previous;
    if (p != null && _fade > 0) {
      p.apply(_prevTime);
      c.blend(_time, 1 - _fade / _fadeLength);
    } else {
      c.apply(_time);
    }
  }
}

/// Bends a mesh to a skeleton (glTF skins): each vertex follows up to four
/// joints by weight.
class Skin {
  Skin({
    required this.joints,
    required this.inverseBind,
    required this.jointIndices,
    required this.weights,
    required Mesh mesh,
  }) : bindPositions = Float32List.fromList(mesh.positions),
       bindNormals = Float32List.fromList(mesh.normals);

  final List<Node> joints;
  final List<Matrix4> inverseBind;

  /// 4 joint numbers and 4 weights per vertex.
  final Uint16List jointIndices;
  final Float32List weights;
  final Float32List bindPositions, bindNormals;

  /// Recomputes [mesh] for the joints' world matrices; [meshWorld] is the
  /// skinned node's own world matrix (vertices end up in its space).
  void update(Mesh mesh, Matrix4 meshWorld, Map<Node, Matrix4> worlds) {
    final inv = Matrix4.inverted(meshWorld);
    final mats = [
      for (var j = 0; j < joints.length; j++)
        (inv * (worlds[joints[j]] ?? Matrix4.identity()) * inverseBind[j])
            .storage,
    ];
    final p = mesh.positions, nrm = mesh.normals;
    final n = mesh.vertexCount;
    for (var i = 0; i < n; i++) {
      final x = bindPositions[i * 3],
          y = bindPositions[i * 3 + 1],
          z = bindPositions[i * 3 + 2];
      final nx = bindNormals[i * 3],
          ny = bindNormals[i * 3 + 1],
          nz = bindNormals[i * 3 + 2];
      var ox = 0.0, oy = 0.0, oz = 0.0, onx = 0.0, ony = 0.0, onz = 0.0;
      for (var k = 0; k < 4; k++) {
        final w = weights[i * 4 + k];
        if (w == 0) {
          continue;
        }
        final m = mats[jointIndices[i * 4 + k]];
        ox += (m[0] * x + m[4] * y + m[8] * z + m[12]) * w;
        oy += (m[1] * x + m[5] * y + m[9] * z + m[13]) * w;
        oz += (m[2] * x + m[6] * y + m[10] * z + m[14]) * w;
        onx += (m[0] * nx + m[4] * ny + m[8] * nz) * w;
        ony += (m[1] * nx + m[5] * ny + m[9] * nz) * w;
        onz += (m[2] * nx + m[6] * ny + m[10] * nz) * w;
      }
      p[i * 3] = ox;
      p[i * 3 + 1] = oy;
      p[i * 3 + 2] = oz;
      final l = math.sqrt(onx * onx + ony * ony + onz * onz);
      if (l > 0) {
        nrm[i * 3] = onx / l;
        nrm[i * 3 + 1] = ony / l;
        nrm[i * 3 + 2] = onz / l;
      }
    }
  }
}

/// Updates every skinned mesh under [root] (call after animating, before
/// drawing; the renderer does this itself).
void updateSkins(Node root) {
  final worlds = <Node, Matrix4>{};
  final skinned = <(Node, Matrix4)>[];
  root.visit(Matrix4.identity(), (n, world) {
    worlds[n] = world;
    if (n.skin != null) {
      skinned.add((n, world));
    }
  });
  for (final (n, world) in skinned) {
    n.skin!.update(n.mesh!, world, worlds);
  }
}
