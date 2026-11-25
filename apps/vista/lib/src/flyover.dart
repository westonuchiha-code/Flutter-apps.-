import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_shell/app_shell.dart' show runInBackground;
import 'package:engine3d/engine3d.dart';
import 'package:video_encoder/video_encoder.dart';

import 'package:landscape/landscape.dart';

import 'raytrace.dart';

/// A smooth camera flight through the points you set.
class CameraPath {
  CameraPath([List<Shot>? keys]) : keys = keys ?? [];
  final List<Shot> keys;

  /// The camera at [u] (0 start .. 1 end), Catmull-Rom through the points.
  Shot at(double u) {
    if (keys.isEmpty) {
      return const Shot(0, 40, 150, 0, -0.2);
    }
    if (keys.length == 1) {
      return keys.first;
    }
    final segs = keys.length - 1;
    final x = (u.clamp(0.0, 1.0) * segs);
    final i = math.min(segs - 1, x.floor());
    final t = x - i;
    Shot k(int j) => keys[j.clamp(0, keys.length - 1)];
    double cr(double p0, double p1, double p2, double p3) =>
        0.5 *
        (2 * p1 +
            (-p0 + p2) * t +
            (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t +
            (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t);
    final a = k(i - 1), b = k(i), c = k(i + 1), d = k(i + 2);
    // Turn the short way round.
    double unwrap(double from, double to) {
      var v = to;
      while (v - from > math.pi) {
        v -= 2 * math.pi;
      }
      while (v - from < -math.pi) {
        v += 2 * math.pi;
      }
      return v;
    }

    final yb = b.yaw,
        ya = unwrap(yb, a.yaw),
        yc = unwrap(yb, c.yaw),
        yd = unwrap(yc, d.yaw);
    return Shot(
      cr(a.x, b.x, c.x, d.x),
      cr(a.y, b.y, c.y, d.y),
      cr(a.z, b.z, c.z, d.z),
      cr(ya, yb, yc, yd),
      cr(a.pitch, b.pitch, c.pitch, d.pitch),
    );
  }
}

/// Plays a path in the viewport.
class PathRig extends CameraRig {
  PathRig(this.path, this.seconds, {this.ground});
  final CameraPath path;
  final double seconds;
  final double Function(double x, double z)? ground;
  double t = 0;

  @override
  final camera = Camera();

  bool get finished => t >= seconds;

  @override
  void drag(double dx, double dy) {}
  @override
  void zoom(double factor) {}
  @override
  void move(double forward, double strafe, double dt) {}

  @override
  void update(double dt) {
    t = math.min(seconds, t + dt);
    apply(camera, path.at(t / seconds), ground);
  }
}

/// Puts [s] into [c], keeping above the ground.
void apply(Camera c, Shot s, double Function(double x, double z)? ground) {
  c
    ..position = Vector3(
      s.x,
      math.max(s.y, (ground?.call(s.x, s.z) ?? -1e9) + 1.5),
      s.z,
    )
    ..yaw = s.yaw
    ..pitch = s.pitch;
}

Shot shotOf(Camera c) =>
    Shot(c.position.x, c.position.y, c.position.z, c.yaw, c.pitch, fov: c.fov);

/// Workers for ray tracing: one per core but one.
int get traceWorkers =>
    math.max(1, math.min(8, Platform.numberOfProcessors - 1));

/// A full ray-traced picture (all workers, one pass).
Future<Uint32List> traceFrame(TraceJob job) async {
  final n = traceWorkers;
  final parts = await Future.wait([
    for (var k = 0; k < n; k++) runInBackground(tracePass, (job, k, n, 1)),
  ]);
  final img = Uint32List(job.width * job.height);
  for (var k = 0; k < n; k++) {
    placePass(img, job.width, job.height, parts[k], k, n, 1);
  }
  return img;
}

/// Makes a flyover video. [rayTraced]: every frame ray traced (slow);
/// otherwise drawn like the explorer ([options]). Reports 0..1 progress;
/// returns null if [cancelled] said stop.
Future<File?> exportFlyover({
  required VistaWorld world,
  required CameraPath path,
  required double seconds,
  required String basePath,
  required bool rayTraced,
  RenderOptions options = const RenderOptions(),
  int width = 854,
  int height = 480,
  int fps = 30,
  required void Function(double p) progress,
  required bool Function() cancelled,
  bool preferMp4 = true,
}) async {
  final frames = math.max(2, (seconds * fps).round());
  final writer = await openVideoWriter(
    basePath,
    VideoSpec(width: width, height: height, fps: fps, audio: false),
    preferMp4: preferMp4,
  );
  final renderer = Renderer();
  final cam = Camera();
  try {
    for (var i = 0; i < frames; i++) {
      if (cancelled()) {
        await writer.cancel();
        return null;
      }
      final shot = path.at(i / (frames - 1));
      Uint32List px;
      if (rayTraced) {
        apply(cam, shot, world.groundAt);
        px = await traceFrame(
          TraceJob(world.settings, world.field, shotOf(cam), width, height),
        );
      } else {
        apply(cam, shot, world.groundAt);
        world.follow(cam);
        final rec = ui.PictureRecorder();
        renderer.paint(
          ui.Canvas(rec),
          ui.Size(width.toDouble(), height.toDouble()),
          world.scene,
          cam,
          options,
        );
        final image = await rec.endRecording().toImage(width, height);
        final data = (await image.toByteData())!.buffer.asUint8List();
        image.dispose();
        px = Uint32List(width * height);
        for (var k = 0; k < px.length; k++) {
          px[k] =
              0xFF000000 |
              (data[k * 4] << 16) |
              (data[k * 4 + 1] << 8) |
              data[k * 4 + 2];
        }
      }
      await writer.addFrame(px);
      progress((i + 1) / frames);
    }
    return await writer.finish();
  } catch (e) {
    await writer.cancel();
    rethrow;
  }
}

/// The height field as a greyscale PNG-ready picture (black low, white
/// high), [n]×[n].
Uint32List heightMapPixels(HeightField f) {
  var lo = double.infinity, hi = -double.infinity;
  for (final v in f.h) {
    lo = math.min(lo, v);
    hi = math.max(hi, v);
  }
  final out = Uint32List(f.n * f.n);
  for (var i = 0; i < out.length; i++) {
    final g = ((f.h[i] - lo) / math.max(1e-6, hi - lo) * 255).round();
    out[i] = 0xFF000000 | (g << 16) | (g << 8) | g;
  }
  return out;
}

/// Path points as JSON (saved with the landscape).
List<List<double>> pathToJson(CameraPath p) => [
  for (final s in p.keys) [s.x, s.y, s.z, s.yaw, s.pitch],
];

CameraPath pathFromJson(Object? j) => CameraPath([
  if (j is List)
    for (final e in j)
      if (e is List && e.length >= 5)
        Shot(
          (e[0] as num).toDouble(),
          (e[1] as num).toDouble(),
          (e[2] as num).toDouble(),
          (e[3] as num).toDouble(),
          (e[4] as num).toDouble(),
        ),
]);
