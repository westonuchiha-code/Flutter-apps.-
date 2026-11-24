import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:video_kit/video_kit.dart';

VideoFrame camera([double t = 0]) => testCard(t);

Set<int> colorsIn(VideoFrame f, {int x0 = 0, int y0 = 0, int? w, int? h}) => {
  for (var y = y0; y < y0 + (h ?? f.height); y++)
    for (var x = x0; x < x0 + (w ?? f.width); x++) f.pixels[y * f.width + x],
};

VideoFrame solid(int c, [int w = 320, int h = 240]) =>
    VideoFrame(w, h, Uint32List(w * h)..fillRange(0, w * h, c));

void main() {
  test('frames: resize, rotate, mirror, YUV and BGRA conversion', () {
    final f = VideoFrame(
      4,
      2,
      Uint32List.fromList(
        [1, 2, 3, 4, 5, 6, 7, 8].map((v) => 0xFF000000 | v).toList(),
      ),
    );
    expect(f.rotated(1).at(0, 0), f.at(0, 1));
    expect(f.rotated(1).width, 2);
    expect(f.rotated(4).at(3, 1), f.at(3, 1));
    expect(f.mirrored().at(0, 0), f.at(3, 0));
    expect(solid(0xFF804020, 8, 8).resized(2, 2).at(1, 1), 0xFF804020);
    // Grey YUV stays grey; Y=76 U=85 V=255 is red.
    final y = Uint8List.fromList([76, 76, 76, 76]);
    final red = yuv420ToFrame(
      width: 2,
      height: 2,
      y: y,
      u: Uint8List.fromList([85]),
      v: Uint8List.fromList([255]),
      yRowStride: 2,
      uvRowStride: 1,
      uvPixelStride: 1,
    );
    expect(redOf(red.at(0, 0)), greaterThan(230));
    expect(greenOf(red.at(0, 0)), lessThan(30));
    final bgra = VideoFrame.fromBgra(Uint8List.fromList([255, 0, 0, 0]), 1, 1);
    expect(bgra.at(0, 0), 0xFF0000FF);
  });

  group('machines keep their hardware limits', () {
    test('ZX Spectrum: two colours per 8×8 cell', () {
      final out = runEffect(ZxSpectrum(), camera(), 0);
      expect((out.width, out.height), (256, 192));
      for (var cy = 0; cy < 24; cy++) {
        for (var cx = 0; cx < 32; cx++) {
          expect(
            colorsIn(out, x0: cx * 8, y0: cy * 8, w: 8, h: 8).length,
            lessThanOrEqualTo(2),
          );
        }
      }
    });

    test('C64: four colours per 4×8 cell (fat pixels)', () {
      final out = runEffect(C64Multicolor(), camera(), 0);
      expect((out.width, out.height), (320, 200));
      for (var cy = 0; cy < 25; cy++) {
        for (var cx = 0; cx < 40; cx++) {
          expect(
            colorsIn(out, x0: cx * 8, y0: cy * 8, w: 8, h: 8).length,
            lessThanOrEqualTo(4),
          );
        }
      }
      expect(out.at(0, 0), out.at(1, 0), reason: 'double-wide pixels');
    });

    test('Atari 2600: two palette colours per line', () {
      final out = runEffect(Atari2600(), camera(), 0);
      for (var y = 0; y < out.height; y++) {
        final line = colorsIn(out, y0: y, h: 1);
        expect(line.length, lessThanOrEqualTo(2));
        expect(Atari2600.palette.toSet().containsAll(line), isTrue);
      }
    });

    test('Game Boy Camera, LCD and Teletext stick to their palettes', () {
      expect(
        colorsIn(runEffect(GameBoyCamera(), camera(), 0)).length,
        lessThanOrEqualTo(4),
      );
      expect(
        colorsIn(runEffect(HandheldLcd(), camera(), 0)).length,
        lessThanOrEqualTo(4),
      );
      final tt = runEffect(Teletext(), camera(), 0);
      expect(colorsIn(tt).length, lessThanOrEqualTo(8));
      expect((tt.width, tt.height), (480, 432));
    });
  });

  group('signals', () {
    test(
      'NTSC keeps grey grey and red red; dot crawl changes between frames',
      () {
        final n = NtscComposite()..values['noise'] = 0;
        final g = runEffect(n, solid(0xFF808080), 0).at(320, 100);
        expect((redOf(g) - blueOf(g)).abs(), lessThan(12));
        final r = runEffect(n, solid(0xFFC02020), 0).at(320, 100);
        expect(redOf(r), greaterThan(greenOf(r) + 60));
        final a = runEffect(n, camera(), 0), b = runEffect(n, camera(), 0);
        var diff = 0;
        for (var i = 0; i < a.pixels.length; i++) {
          if (a.pixels[i] != b.pixels[i]) diff++;
        }
        expect(
          diff,
          greaterThan(0),
          reason: 'subcarrier phase alternates frame to frame',
        );
      },
    );

    test('artifact colour makes colours out of black-and-white dots', () {
      final cga = runEffect(ArtifactColor(), camera(), 0);
      expect(colorsIn(cga).length, greaterThan(8));
      final apple = ArtifactColor()..values['machine'] = 1;
      expect(runEffect(apple, camera(), 0).width, 560);
    });

    test('VHS, antenna, sync and interlace run and animate', () {
      for (final e in [Vhs(), BadAntenna(), SyncLoss()..values['roll'] = 0.6]) {
        final a = runEffect(e, camera(), 0.5), b = runEffect(e, camera(), 1.7);
        expect(a.width, 320);
        expect(a.pixels, isNot(b.pixels), reason: e.name);
      }
      // Interlace: odd lines lag behind.
      final il = Interlace()..values['gap'] = 1;
      runEffect(il, solid(0xFF000000), 0);
      final out = runEffect(il, solid(0xFFFFFFFF), 0.1);
      expect(out.at(10, 0), 0xFFFFFFFF);
      expect(out.at(10, 1), 0xFF000000);
    });
  });

  group('strange machines and digital faults', () {
    test('slit-scan: top row is newest, bottom row oldest', () {
      final s = SlitScan()..values['delay'] = 4;
      for (final c in [0xFF000000, 0xFF555555, 0xFFAAAAAA]) {
        runEffect(s, solid(c), 0);
      }
      final out = runEffect(s, solid(0xFFFFFFFF), 0);
      expect(out.at(5, 0), 0xFFFFFFFF);
      expect(out.at(5, out.height - 1), 0xFF000000);
    });

    test('datamosh drags the old picture when nothing new arrives', () {
      final d = Datamosh();
      runEffect(d, solid(0xFFFF0000), 0);
      final out = runEffect(d, camera(), 0.1);
      final reds = out.pixels
          .where((p) => redOf(p) > 200 && greenOf(p) < 40)
          .length;
      expect(
        reds,
        greaterThan(out.pixels.length * 0.8),
        reason: 'still mostly the old frame',
      );
    });

    test('JPEG: light compression is close, heavy compression is blocky', () {
      final light = JpegBlocks()..values['crush'] = 0;
      final heavy = JpegBlocks()..values['crush'] = 1;
      final src = camera().resized(320, 240);
      double err(VideoFrame f) {
        var e = 0;
        for (var i = 0; i < f.pixels.length; i++) {
          e += (lumaOf(f.pixels[i]) - lumaOf(src.pixels[i])).abs();
        }
        return e / f.pixels.length;
      }

      expect(
        err(runEffect(light, src, 0)),
        lessThan(err(runEffect(heavy, src, 0))),
      );
    });

    test('feedback, Rutt/Etra, slow-scan and PXL-2000 run', () {
      final fb = VideoFeedback();
      runEffect(fb, camera(), 0);
      expect(runEffect(fb, camera(0.1), 0.1).width, 240);
      final re = runEffect(RuttEtra(), camera(), 0);
      expect(re.pixels.where((p) => p != 0xFF000000).length, greaterThan(100));
      final sstv = SlowScanTv();
      var half = runEffect(sstv, camera(), 0);
      for (var t = 0.1; t < 4; t += 0.1) {
        half = runEffect(sstv, camera(), t);
      }
      expect(half.at(80, 10), isNot(0), reason: 'top lines painted');
      final pxl = runEffect(Pxl2000(), camera(), 0);
      expect((pxl.width, pxl.height), (160, 120));
      expect(pxl.at(0, 0), 0, reason: 'black border area (unpainted)');
    });
  });

  test('every effect is fast enough for live video (320×240 camera)', () {
    for (final e in allEffects()) {
      runEffect(e, camera(), 0);
      final sw = Stopwatch()..start();
      for (var i = 1; i <= 5; i++) {
        runEffect(e, camera(i / 10), i / 10);
      }
      final ms = sw.elapsedMilliseconds / 5;
      // ignore: avoid_print
      print('${e.name.padRight(34)} ${ms.toStringAsFixed(1)} ms/frame');
      expect(ms, lessThan(150), reason: e.name);
    }
  });
}
