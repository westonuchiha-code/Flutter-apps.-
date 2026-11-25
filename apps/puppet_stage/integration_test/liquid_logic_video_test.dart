// Makes the "Liquid Logic" music video as an MP4 inside the real app (so
// video_encoder's native H.264 + AAC writer is there). CI runs it on
// Windows (.github/workflows/album.yml):
//   flutter test integration_test/liquid_logic_video_test.dart -d windows
//     --dart-define=WAV=<Liquid Logic.wav> --dart-define=OUT=<folder>
import 'dart:io';
import 'dart:typed_data';

import 'package:engine3d/engine3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:puppet_stage/src/export.dart';
import 'package:puppet_stage/src/movie.dart';
import 'package:puppet_stage/src/staging.dart';

import '../tool/liquid_logic.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const wav = String.fromEnvironment('WAV');
  const out = String.fromEnvironment('OUT', defaultValue: '.');

  testWidgets('Liquid Logic music video', (tester) async {
    await tester.runAsync(() async {
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
      final s = await Staging.build(movie);
      var shown = -1;
      final file = await exportMovie(
        movie: movie,
        places: s.places,
        pose: s.pose,
        fallbackCamera: Camera(),
        basePath: '$out${Platform.pathSeparator}Liquid-Logic',
        width: 960,
        height: 720,
        fps: 30,
        music: music,
        progress: (p) {
          final pc = (p * 100).floor();
          if (pc ~/ 10 != shown ~/ 10) {
            shown = pc;
            // ignore: avoid_print
            print('video $pc%');
          }
        },
        cancelled: () => false,
      );
      // ignore: avoid_print
      print('wrote ${file?.path} ${file?.lengthSync()}');
      expect(file, isNotNull);
      expect(file!.path.endsWith('.mp4'), isTrue);
    });
  }, timeout: const Timeout(Duration(hours: 2)));
}
