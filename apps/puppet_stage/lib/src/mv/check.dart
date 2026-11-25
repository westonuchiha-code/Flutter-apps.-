/// Checks a directed movie before it is rendered: each shot is drawn small
/// through its film look, and shots that come out too dark are brightened
/// (exposure), twice at most. Returns the shots still too dark.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:engine3d/engine3d.dart';

import '../export.dart';
import '../look.dart';
import '../movie.dart';
import '../staging.dart';

/// Renders the frame at [t] (ARGB, through the shot's look).
Future<Uint32List> renderAt(
  Staging s,
  double t,
  int w,
  int h, {
  RenderOptions options = const RenderOptions(),
  int frame = 0,
}) async {
  s.pose(t);
  final cam = Camera();
  final shot = cameraAt(s.movie, t, cam);
  final place = s.places[(shot?.place ?? 0).clamp(0, s.places.length - 1)];
  place.follow(cam);
  final rec = ui.PictureRecorder();
  Renderer().paint(
    ui.Canvas(rec),
    ui.Size(w.toDouble(), h.toDouble()),
    place.scene,
    cam,
    options,
  );
  final img = await rec.endRecording().toImage(w, h);
  final d = (await img.toByteData())!.buffer.asUint8List();
  img.dispose();
  final px = Uint32List(w * h);
  for (var k = 0; k < px.length; k++) {
    px[k] = 0xFF000000 | (d[k * 4] << 16) | (d[k * 4 + 1] << 8) | d[k * 4 + 2];
  }
  return applyLook(px, w, h, shot?.look ?? s.movie.look, frame);
}

double _luma(Uint32List px) {
  var sum = 0.0;
  for (final c in px) {
    sum +=
        0.299 * ((c >> 16) & 255) +
        0.587 * ((c >> 8) & 255) +
        0.114 * (c & 255);
  }
  return sum / px.length / 255;
}

/// The middle of each shot (seconds).
double _middle(Movie m, int i) {
  final s = m.shots[i];
  final next = i + 1 < m.shots.length ? m.shots[i + 1].time : m.duration;
  return s.time + (next - s.time) * 0.5;
}

Future<List<int>> fixDarkShots(Staging s, {double floor = 0.07}) async {
  final dark = <int>[];
  final m = s.movie;
  for (var i = 0; i < m.shots.length; i++) {
    for (var tries = 0; ; tries++) {
      final px = await renderAt(s, _middle(m, i), 96, 54);
      if (_luma(px) >= floor) break;
      if (tries == 2) {
        dark.add(i);
        break;
      }
      final shot = m.shots[i];
      final look = shot.look ?? m.look;
      shot.look = look.copyWith(
        exposure: (look.exposure + 0.6).clamp(-1.0, 1.0),
        contrast: (look.contrast * 0.7).clamp(0.0, 1.0),
      );
    }
  }
  return dark;
}
