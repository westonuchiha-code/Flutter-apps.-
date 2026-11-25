// Renders the "Liquid Logic" music video (tool/liquid_logic.dart).
//   flutter test tool/liquid_logic_test.dart --dart-define=OUT=dir
//     writes Liquid Logic.puppet_movie.json and a contact sheet of shots;
//   add --dart-define=WAV=<song.wav> --dart-define=VIDEO=true
//     to render the whole video with sound (AVI here; the app makes MP4).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:engine3d/engine3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puppet_stage/src/export.dart';
import 'package:puppet_stage/src/look.dart';
import 'package:puppet_stage/src/movie.dart';
import 'package:puppet_stage/src/staging.dart';

import 'liquid_logic.dart';

Future<Uint32List> _frame(Staging s, double t, int w, int h, int i) async {
  s.pose(t);
  final cam = Camera();
  final shot = cameraAt(s.movie, t, cam)!;
  final place = s.places[shot.place];
  place.follow(cam);
  final rec = ui.PictureRecorder();
  Renderer().paint(
    ui.Canvas(rec),
    ui.Size(w.toDouble(), h.toDouble()),
    place.scene,
    cam,
    const RenderOptions(),
  );
  final img = await rec.endRecording().toImage(w, h);
  final d = (await img.toByteData())!.buffer.asUint8List();
  final px = Uint32List(w * h);
  for (var k = 0; k < px.length; k++) {
    px[k] = 0xFF000000 | (d[k * 4] << 16) | (d[k * 4 + 1] << 8) | d[k * 4 + 2];
  }
  return applyLook(px, w, h, shot.look ?? s.movie.look, i);
}

Future<void> _png(Uint32List px, int w, int h, String path) async {
  final rgba = Uint8List(w * h * 4);
  for (var k = 0; k < px.length; k++) {
    rgba[k * 4] = (px[k] >> 16) & 0xFF;
    rgba[k * 4 + 1] = (px[k] >> 8) & 0xFF;
    rgba[k * 4 + 2] = px[k] & 0xFF;
    rgba[k * 4 + 3] = 255;
  }
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, c.complete);
  final img = await c.future;
  File(path).writeAsBytesSync(
    (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const out = String.fromEnvironment('OUT', defaultValue: '.');
  const wav = String.fromEnvironment('WAV');
  const video = bool.fromEnvironment('VIDEO');
  const from = int.fromEnvironment('FROM');
  const count = int.fromEnvironment('COUNT', defaultValue: 32);

  test('Liquid Logic', () async {
    Int16List? music;
    if (wav.isNotEmpty) music = decodeWav(File(wav).readAsBytesSync());
    final movie = liquidLogic(
      music: MusicRef(
        'liquid-logic',
        'wav',
        'Liquid Logic',
        seconds: music == null ? 179.1 : music.length / 2 / 44100,
      ),
    );
    File('$out/Liquid Logic.puppet_movie.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(movie.toJson()),
    );
    final s = await Staging.build(movie);
    if (!video) {
      const w = 320, h = 180, cols = 4;
      final shots = movie.shots.skip(from).take(count).toList();
      final rows = (shots.length / cols).ceil();
      final sheet = Uint32List(w * cols * h * rows);
      for (var i = 0; i < shots.length; i++) {
        final next = movie.shots.indexOf(shots[i]) + 1 < movie.shots.length
            ? movie.shots[movie.shots.indexOf(shots[i]) + 1].time
            : movie.duration;
        final t = shots[i].time + (next - shots[i].time) * 0.6;
        final px = await _frame(s, t, w, h, i);
        final ox = (i % cols) * w, oy = (i ~/ cols) * h;
        for (var y = 0; y < h; y++) {
          sheet.setRange(
            (oy + y) * w * cols + ox,
            (oy + y) * w * cols + ox + w,
            px,
            y * w,
          );
        }
      }
      await _png(
        sheet,
        w * cols,
        h * rows,
        '$out/liquid_logic_sheet_$from.png',
      );
      return;
    }
    var last = -1;
    final file = await exportMovie(
      movie: movie,
      places: s.places,
      pose: s.pose,
      fallbackCamera: Camera(),
      basePath: '$out/Liquid Logic',
      width: 640,
      height: 480,
      fps: 24,
      music: music,
      progress: (p) {
        final pc = (p * 100).floor();
        if (pc ~/ 5 != last ~/ 5) stdout.writeln('$pc%');
        last = math.max(last, pc);
      },
      cancelled: () => false,
      preferMp4: false,
    );
    stdout.writeln('wrote ${file?.path} ${file?.lengthSync()}');
  }, timeout: const Timeout(Duration(hours: 2)));
}
