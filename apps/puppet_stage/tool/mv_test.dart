// The music video pipeline, driven from here (CI makes the MP4 with
// integration_test/mv_video_test.dart):
//   flutter test tool/mv_test.dart --dart-define=STYLE=cipher
//     --dart-define=MAP=<song.songmap.json> --dart-define=WAV=<song.wav>
//     --dart-define=FROM_BAR=28 --dart-define=TO_BAR=39 --dart-define=OUT=dir
//     [--dart-define=SEED=1] [--dart-define=VIDEO=true]
// Writes the movie JSON and a contact sheet of the shots in the range
// (with the darkness check applied), or an AVI preview with VIDEO=true.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:engine3d/engine3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puppet_stage/src/export.dart';
import 'package:puppet_stage/src/movie.dart';
import 'package:puppet_stage/src/mv/check.dart';
import 'package:puppet_stage/src/mv/director.dart';
import 'package:puppet_stage/src/mv/song_map.dart';
import 'package:puppet_stage/src/mv/styles.dart';
import 'package:puppet_stage/src/staging.dart';

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
  const styleId = String.fromEnvironment('STYLE', defaultValue: 'cipher');
  const mapPath = String.fromEnvironment('MAP');
  const wav = String.fromEnvironment('WAV');
  const fromBar = int.fromEnvironment('FROM_BAR');
  const toBar = int.fromEnvironment('TO_BAR');
  const seed = int.fromEnvironment('SEED', defaultValue: 1);
  const video = bool.fromEnvironment('VIDEO');

  test('music video', () async {
    Int16List? music;
    if (wav.isNotEmpty) music = decodeWav(File(wav).readAsBytesSync());
    final map = mapPath.isNotEmpty
        ? SongMap.fromJson(jsonDecode(File(mapPath).readAsStringSync()) as Map)
        : SongMap.fromAudio(music!, 90);
    final style = styleById(styleId);
    final movie = Director(map, style, seed: seed).direct(
      music: MusicRef(
        'song',
        'wav',
        'Song',
        seconds: music == null ? map.seconds : music.length / 2 / 44100,
      ),
    );
    final s = await Staging.build(movie);
    final dark = await fixDarkShots(s);
    stdout.writeln(
      '${style.name}: ${movie.shots.length} shots, ${movie.actors.length} '
      'actors, still dark: $dark',
    );
    File('$out/${style.id}.puppet_movie.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(movie.toJson()),
    );
    final from = map.timeOf(fromBar);
    final to = toBar > 0 ? map.timeOf(toBar) : movie.duration;
    if (!video) {
      const w = 320, h = 180, cols = 4;
      final picks = [
        for (var i = 0; i < movie.shots.length; i++)
          if (movie.shots[i].time >= from - 0.01 && movie.shots[i].time < to) i,
      ];
      final rows = (picks.length / cols).ceil();
      final sheet = Uint32List(w * cols * h * rows);
      for (var k = 0; k < picks.length; k++) {
        final i = picks[k];
        final next = i + 1 < movie.shots.length
            ? movie.shots[i + 1].time
            : movie.duration;
        final t = movie.shots[i].time + (next - movie.shots[i].time) * 0.6;
        final px = await renderAt(s, t, w, h, frame: k);
        final ox = (k % cols) * w, oy = (k ~/ cols) * h;
        for (var y = 0; y < h; y++) {
          sheet.setRange(
            (oy + y) * w * cols + ox,
            (oy + y) * w * cols + ox + w,
            px,
            y * w,
          );
        }
      }
      await _png(sheet, w * cols, h * rows, '$out/${style.id}_sheet.png');
      return;
    }
    final file = await exportMovie(
      movie: movie,
      places: s.places,
      pose: s.pose,
      fallbackCamera: Camera(),
      basePath: '$out/${style.id}',
      width: 640,
      height: 480,
      fps: 24,
      music: music,
      progress: (_) {},
      cancelled: () => false,
      preferMp4: false,
      from: from,
      to: to,
    );
    stdout.writeln('wrote ${file?.path}');
  }, timeout: const Timeout(Duration(hours: 2)));
}
