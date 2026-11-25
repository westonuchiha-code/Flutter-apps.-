import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:engine3d/engine3d.dart';
import 'package:video_encoder/video_encoder.dart';

import 'movie.dart';

/// Puts a movie shot into [c].
void applyShot(Camera c, Shot s) {
  c
    ..position = Vector3(s.x, s.y, s.z)
    ..yaw = s.yaw
    ..pitch = s.pitch
    ..fov = s.fov;
}

/// Renders the movie to a video file. [pose] poses every actor at a time.
Future<File?> exportMovie({
  required Movie movie,
  required Scene scene,
  required void Function(double t) pose,
  required Camera fallbackCamera,
  required String basePath,
  RenderOptions options = const RenderOptions(),
  int width = 854,
  int height = 480,
  int fps = 30,
  required void Function(double p) progress,
  required bool Function() cancelled,
  bool preferMp4 = true,
}) async {
  final frames = math.max(2, (movie.duration * fps).ceil());
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
      final t = i / fps;
      pose(t);
      final shot = movie.shotAt(t);
      if (shot != null) {
        applyShot(cam, shot);
      } else {
        cam
          ..position = fallbackCamera.position.clone()
          ..yaw = fallbackCamera.yaw
          ..pitch = fallbackCamera.pitch
          ..fov = fallbackCamera.fov;
      }
      final rec = ui.PictureRecorder();
      renderer.paint(
        ui.Canvas(rec),
        ui.Size(width.toDouble(), height.toDouble()),
        scene,
        cam,
        options,
      );
      final image = await rec.endRecording().toImage(width, height);
      final data = (await image.toByteData())!.buffer.asUint8List();
      image.dispose();
      final px = Uint32List(width * height);
      for (var k = 0; k < px.length; k++) {
        px[k] =
            0xFF000000 |
            (data[k * 4] << 16) |
            (data[k * 4 + 1] << 8) |
            data[k * 4 + 2];
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
