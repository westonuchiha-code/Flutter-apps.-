import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:save_kit/save_kit.dart';
import 'package:save_manager/src/art/art.dart';

import 'art_fixtures.dart';

Widget _host(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(child: child),
);

void main() {
  final ps2 = fakePs2Save(favorite: true);
  final ps1 = fakeFramesSave('PS1');
  final ps3 = fakePs3Save();
  final cards = [
    fakeCard('PS2'),
    fakeCard('PS1', color: 0xFF2A6FD6, finish: 'clear'),
    fakeCard('GC', color: 0xFFD9A441, finish: 'leopard'),
    fakeCard('DC', sticker: fakeSticker()),
    fakeCard('N64', color: 0xFF5D7046, finish: 'camo'),
    fakeCard('SATURN', color: 0xFFEEEEEE, finish: 'zebra'),
    fakeCard('NEO GEO', color: 0xFF1C1D22, finish: 'carbon'),
    fakeCard('PS3', color: 0xFFF6F0EA, finish: 'strawberry'),
  ];

  setUpAll(() async {
    await ArtImages.preload([ps2, ps1, ps3], cards);
  });

  for (final side in [24.0, 320.0]) {
    testWidgets('every widget builds and paints at $side', (tester) async {
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(
          MemoryBackdrop(
            tint: const [Colors.red, Colors.green, Colors.blue, Colors.white],
            tintAmount: 0.5,
            child: SingleChildScrollView(
              child: Wrap(
                children: [
                  for (final s in [ps2, ps1, ps3])
                    for (final k in [0, 1, 2])
                      SaveIcon(s, kind: k, size: side, selected: k == 1),
                  SaveIcon(ps3, size: side, wide: true),
                  FavoriteSparkle(
                    size: side,
                    child: SaveIcon(ps2, size: side),
                  ),
                  PaintButton('COPY', width: side * 3, height: side),
                  PaintButton(
                    'MOVE',
                    width: side * 3,
                    height: side,
                    selected: true,
                  ),
                  PaintTitle('MEMORY CARDS', width: side * 4, height: side),
                  for (final c in cards) ...[
                    CardArt(c, width: side, selected: c.system == 'PS2'),
                    BlockBar(c, save: ps2, width: side * 3, height: side / 8),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      expect(find.byType(SaveIcon), findsNWidgets(11));
      await tester.pumpWidget(const SizedBox());
    });
  }

  test('a PS2 model is drawn with every triangle, morphing as it plays', () {
    final ico = ps2.icons[0]!;
    final tex = ArtImages.peek(ico.texture!);
    expect(tex, isNotNull);
    final rec = ui.PictureRecorder();
    final n = IconRender.paintPs2(
      Canvas(rec),
      const Rect.fromLTWH(0, 0, 64, 64),
      ico,
      ps2,
      tex,
      IconPose.at(0.4, 1),
      0.5,
    );
    rec.endRecording().dispose();
    expect(n, 8);
    expect(ico.weights(0)[0], closeTo(1, 1e-9));
    expect(ico.weights(1)[1], closeTo(1, 1e-9)); // halfway through 2 s
  });

  test('a PS2 model renders visible pixels', () async {
    final ico = ps2.icons[0]!;
    final tex = ArtImages.peek(ico.texture!)!;
    final rec = ui.PictureRecorder();
    IconRender.paintPs2(
      Canvas(rec),
      const Rect.fromLTWH(0, 0, 64, 64),
      ico,
      ps2,
      tex,
      IconPose.still,
      0,
    );
    final img = await rec.endRecording().toImage(64, 64);
    final data = (await img.toByteData())!;
    var lit = 0;
    for (var i = 3; i < data.lengthInBytes; i += 4) {
      if (data.getUint8(i) > 0) lit++;
    }
    // A diamond across most of the square.
    expect(lit, greaterThan(64 * 64 ~/ 5));
    expect(data.getUint8((32 * 64 + 32) * 4 + 3), 255);
    expect(data.getUint8(3), 0); // corners stay clear
  });

  test('paint splashes are the same every time for a seed', () {
    final a = PaintSplash.make(3), b = PaintSplash.make(3);
    final c = PaintSplash.make(4);
    expect(a.rgba, b.rgba);
    expect(a.rgba, isNot(c.rgba));
    expect(PaintSplash.pixels(3), same(PaintSplash.pixels(3)));
    // Paint in the middle, clear in the corners.
    expect(a.at(0, 0), 0);
    var painted = 0;
    for (var x = 0; x < PaintSplash.w; x++) {
      if (a.at(x, PaintSplash.h ~/ 2) >> 24 != 0) painted++;
    }
    expect(painted, greaterThan(PaintSplash.w ~/ 2));
  });

  testWidgets('PaintButton taps and is drawn the same each time', (
    tester,
  ) async {
    var taps = 0;
    Future<List<int>> shot() async {
      final b = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('b')),
      );
      final img = (await tester.runAsync(() => b.toImage()))!;
      final d = (await tester.runAsync(img.toByteData))!;
      return d.buffer.asUint8List().toList();
    }

    await tester.runAsync(() => ArtImages.load(PaintSplash.pixels(2)));
    Future<void> build() async {
      await tester.pumpWidget(
        _host(
          RepaintBoundary(
            key: const Key('b'),
            child: PaintButton('GO', seed: 2, onTap: () => taps++),
          ),
        ),
      );
      await tester.pump();
    }

    await build();
    final first = await shot();
    await tester.pumpWidget(const SizedBox());
    await build();
    expect(await shot(), first);
    await tester.tap(find.byType(PaintButton));
    expect(taps, 1);
  });

  test('block bar counts', () {
    final c = fakeCard('PS1', free: 5, total: 15);
    final s = CardSave()..blocks = 3;
    expect(c.litBlocks(s), (3, 10));
  });
}
