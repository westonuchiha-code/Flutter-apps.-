import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:video_kit/video_kit.dart';

void main() {
  test(
    'clips keep frames exact (PNG) or close (JPEG), times and sound',
    () async {
      final dir = Directory.systemTemp.createTempSync('clip_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final w = await ClipWriter.create(File('${dir.path}/a.lfclip'));
      // A machine frame with few colours (exact) and a noisy full-colour one.
      final zx = runEffect(ZxSpectrum(), testCard(0), 0);
      final card = testCard(0.5);
      await w.addFrame(zx, 0);
      await w.addFrame(card, 0.1);
      await w.addFrame(zx, 0.25);
      final sound = Int16List.fromList(
        List.generate(4800, (i) => (i % 100) * 100 - 5000),
      );
      final file = await w.finish(
        sound: sound,
        sampleRate: 48000,
        length: 0.3,
        extra: {'effect': 'zx'},
      );

      final clip = VideoClip.fromBytes(await file.readAsBytes());
      expect(clip.frames.map((f) => f.format), ['png', 'jpg', 'png']);
      expect(clip.length, 0.3);
      expect(clip.extra['effect'], 'zx');
      expect(clip.frame(0).pixels, zx.pixels);
      expect(clip.indexAt(0.05), 0);
      expect(clip.indexAt(0.2), 1);
      expect(clip.indexAt(9), 2);
      final c = clip.frame(1);
      expect(c.width, card.width);
      var err = 0;
      for (var i = 0; i < c.pixels.length; i++) {
        err += (lumaOf(c.pixels[i]) - lumaOf(card.pixels[i])).abs();
      }
      expect(err / c.pixels.length, lessThan(6));
      expect(clip.sampleRate, 48000);
      expect(clip.sound, sound);
    },
  );

  test('not a clip', () {
    expect(() => VideoClip.fromBytes(Uint8List(40)), throwsFormatException);
  });
}
