// A music video take as MP4, inside the real app (video_encoder's native
// MP4 writer). CI (.github/workflows/mv.yml) runs it on Windows per style:
//   flutter test integration_test/mv_video_test.dart -d windows
//     --dart-define=STYLE=cipher --dart-define=MAP=<songmap.json>
//     --dart-define=WAV=<song.wav> --dart-define=FROM_BAR=28
//     --dart-define=TO_BAR=39 --dart-define=OUT=<folder>
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:engine3d/engine3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:puppet_stage/src/export.dart';
import 'package:puppet_stage/src/movie.dart';
import 'package:puppet_stage/src/mv/check.dart';
import 'package:puppet_stage/src/mv/director.dart';
import 'package:puppet_stage/src/mv/song_map.dart';
import 'package:puppet_stage/src/mv/styles.dart';
import 'package:puppet_stage/src/staging.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const out = String.fromEnvironment('OUT', defaultValue: '.');
  const styleId = String.fromEnvironment('STYLE', defaultValue: 'cipher');
  const mapPath = String.fromEnvironment('MAP');
  const wav = String.fromEnvironment('WAV');
  const fromBar = int.fromEnvironment('FROM_BAR');
  const toBar = int.fromEnvironment('TO_BAR');
  const seed = int.fromEnvironment('SEED', defaultValue: 1);

  testWidgets('music video take', (tester) async {
    await tester.runAsync(() async {
      final Int16List music = decodeWav(File(wav).readAsBytesSync())!;
      final json = jsonDecode(File(mapPath).readAsStringSync()) as Map;
      final map = SongMap.fromJson(json);
      // The song's own take bars unless given.
      final take = json['take'] as List?;
      final from = fromBar > 0 || take == null ? fromBar : take[0] as int;
      final to = toBar > 0 || take == null ? toBar : take[1] as int;
      final style = styleById(styleId);
      final movie = Director(map, style, seed: seed).direct(
        music: MusicRef(
          'song',
          'wav',
          'Song',
          seconds: music.length / 2 / 44100,
        ),
      );
      final s = await Staging.build(movie);
      await fixDarkShots(s);
      File('$out${Platform.pathSeparator}${style.id}.puppet_movie.json')
          .writeAsStringSync(jsonEncode(movie.toJson()));
      final file = await exportMovie(
        movie: movie,
        places: s.places,
        pose: s.pose,
        fallbackCamera: Camera(),
        basePath: '$out${Platform.pathSeparator}${style.id}',
        width: 960,
        height: 720,
        fps: 30,
        music: music,
        progress: (_) {},
        cancelled: () => false,
        from: map.timeOf(from),
        to: to > 0 ? map.timeOf(to) : null,
      );
      // ignore: avoid_print
      print('wrote ${file?.path} ${file?.lengthSync()}');
      expect(file?.path.endsWith('.mp4'), isTrue);
    });
  }, timeout: const Timeout(Duration(hours: 1)));
}
