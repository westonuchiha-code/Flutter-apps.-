import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:engine3d/engine3d.dart';
import 'package:video_encoder/video_encoder.dart';

import 'look.dart';
import 'movie.dart';
import 'places.dart';

/// Puts a movie shot into [c].
void applyShot(Camera c, Shot s) {
  c
    ..position = Vector3(s.x, s.y, s.z)
    ..yaw = s.yaw
    ..pitch = s.pitch
    ..fov = s.fov;
}

/// The camera at [t]: the shot in use, drifting toward its end position
/// (eased) until the next cut. Null when the movie has no shots.
Shot? cameraAt(Movie m, double t, Camera c) {
  final s = m.shotAt(t);
  if (s == null) return null;
  applyShot(c, s);
  final e = s.end;
  if (e != null) {
    var next = m.duration;
    for (final o in m.shots) {
      if (o.time > s.time + 1e-6 && o.time < next) next = o.time;
    }
    final span = math.max(0.1, next - s.time);
    final u = ((t - s.time) / span).clamp(0.0, 1.0);
    final k = u * u * (3 - 2 * u);
    double lerp(double a, double b) => a + (b - a) * k;
    c
      ..position = Vector3(lerp(s.x, e[0]), lerp(s.y, e[1]), lerp(s.z, e[2]))
      ..yaw = lerp(s.yaw, e[3])
      ..pitch = lerp(s.pitch, e[4]);
  }
  return s;
}

/// A WAV file as 44.1 kHz stereo 16-bit (PCM 8/16/24/32 or float; any
/// rate is resampled). Null if it isn't a WAV it understands.
Int16List? decodeWav(Uint8List b) {
  if (b.length < 44 || String.fromCharCodes(b.sublist(0, 4)) != 'RIFF') {
    return null;
  }
  final d = ByteData.sublistView(b);
  var p = 12;
  int fmt = 1, ch = 2, rate = 44100, bits = 16;
  Uint8List? data;
  while (p + 8 <= b.length) {
    final id = String.fromCharCodes(b.sublist(p, p + 4));
    final size = d.getUint32(p + 4, Endian.little);
    final body = p + 8;
    if (id == 'fmt ') {
      fmt = d.getUint16(body, Endian.little);
      ch = d.getUint16(body + 2, Endian.little);
      rate = d.getUint32(body + 4, Endian.little);
      bits = d.getUint16(body + 14, Endian.little);
      if (fmt == 0xFFFE && size >= 26) {
        fmt = d.getUint16(body + 24, Endian.little);
      }
    } else if (id == 'data') {
      data = Uint8List.sublistView(b, body, math.min(b.length, body + size));
    }
    p = body + size + (size.isOdd ? 1 : 0);
  }
  if (data == null || ch < 1) return null;
  final bytes = bits ~/ 8;
  final frames = data.length ~/ (bytes * ch);
  final dd = ByteData.sublistView(data);
  double sample(int f, int c) {
    final o = (f * ch + c) * bytes;
    if (fmt == 3 && bits == 32) return dd.getFloat32(o, Endian.little);
    return switch (bits) {
      8 => (data![o] - 128) / 128,
      16 => dd.getInt16(o, Endian.little) / 32768,
      24 =>
        ((data![o] | (data[o + 1] << 8) | (data[o + 2] << 16)) << 8).toSigned(
              32,
            ) /
            2147483648,
      32 => dd.getInt32(o, Endian.little) / 2147483648,
      _ => 0,
    };
  }

  final outFrames = (frames * 44100 / rate).floor();
  final out = Int16List(outFrames * 2);
  for (var i = 0; i < outFrames; i++) {
    final src = i * rate / 44100;
    final f = src.floor(), k = src - f;
    for (var c = 0; c < 2; c++) {
      final cc = math.min(c, ch - 1);
      final a = sample(math.min(f, frames - 1), cc);
      final bb = sample(math.min(f + 1, frames - 1), cc);
      out[i * 2 + c] = ((a + (bb - a) * k) * 32767).round().clamp(
        -32768,
        32767,
      );
    }
  }
  return out;
}

/// Renders the movie to a video file: each shot in its place, through its
/// film look, with the music. [pose] poses every actor at a time.
Future<File?> exportMovie({
  required Movie movie,
  required List<BuiltPlace> places,
  required void Function(double t) pose,
  required Camera fallbackCamera,
  int fallbackPlace = 0,
  required String basePath,
  RenderOptions options = const RenderOptions(),
  int width = 854,
  int height = 480,
  int fps = 30,
  Int16List? music,
  required void Function(double p) progress,
  required bool Function() cancelled,
  bool preferMp4 = true,
}) async {
  final frames = math.max(2, (movie.duration * fps).ceil());
  final spec = VideoSpec(
    width: width,
    height: height,
    fps: fps,
    audio: music != null,
  );
  final writer = await openVideoWriter(basePath, spec, preferMp4: preferMp4);
  final renderer = Renderer();
  final cam = Camera();
  var audioAt = ((movie.music?.start ?? 0) * 44100).round() * 2;
  try {
    for (var i = 0; i < frames; i++) {
      if (cancelled()) {
        await writer.cancel();
        return null;
      }
      final t = i / fps;
      pose(t);
      final shot = cameraAt(movie, t, cam);
      if (shot == null) {
        cam
          ..position = fallbackCamera.position.clone()
          ..yaw = fallbackCamera.yaw
          ..pitch = fallbackCamera.pitch
          ..fov = fallbackCamera.fov;
      }
      final pi = (shot?.place ?? fallbackPlace).clamp(0, places.length - 1);
      final place = places[pi];
      place.follow(cam);
      final rec = ui.PictureRecorder();
      renderer.paint(
        ui.Canvas(rec),
        ui.Size(width.toDouble(), height.toDouble()),
        place.scene,
        cam,
        options,
      );
      final image = await rec.endRecording().toImage(width, height);
      final data = (await image.toByteData())!.buffer.asUint8List();
      image.dispose();
      var px = Uint32List(width * height);
      for (var k = 0; k < px.length; k++) {
        px[k] =
            0xFF000000 |
            (data[k * 4] << 16) |
            (data[k * 4 + 1] << 8) |
            data[k * 4 + 2];
      }
      px = applyLook(px, width, height, shot?.look ?? movie.look, i);
      await writer.addFrame(px);
      final m = music;
      if (m != null) {
        final n = spec.audioFramesFor(i) * 2;
        final chunk = Int16List(n);
        for (var k = 0; k < n; k++) {
          final j = audioAt + k;
          if (j >= 0 && j < m.length) chunk[k] = m[j];
        }
        // Fade the last second.
        final left = frames - i;
        if (left < fps) {
          for (var k = 0; k < n; k++) {
            chunk[k] = (chunk[k] * left / fps).round();
          }
        }
        audioAt += n;
        await writer.addAudio(chunk);
      }
      progress((i + 1) / frames);
    }
    return await writer.finish();
  } catch (e) {
    await writer.cancel();
    rethrow;
  }
}
