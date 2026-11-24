import 'dart:io';
import 'dart:typed_data';

import 'package:app_shell/app_shell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pixel_forge/main.dart';
import 'package:pixel_forge/src/editor.dart';
import 'package:pixel_forge/src/map_editor.dart';
import 'package:pixel_forge/src/ui/canvas_view.dart';
import 'package:pixel_forge/src/ui/home.dart';
import 'package:pixel_forge/src/ui/map_page.dart';
import 'package:pixel_kit/pixel_kit.dart';

const red = 0xFFFF0000, blue = 0xFF0000FF;

void main() {
  test(
    'frames: add copy and blank, draw per frame, time, move, delete, undo',
    () {
      final e = Editor(sprite: Sprite.blank(4, 4))..setPrimary(red);
      e.strokeStart(0, 0);
      e.strokeEnd();
      e.addFrame();
      expect(e.frame, 1);
      expect(e.cel[0], red, reason: 'copied');
      e.setPrimary(blue);
      e.strokeStart(1, 0);
      e.strokeEnd();
      expect(e.sprite.cel(0, 0)[1], 0, reason: 'frame 1 is separate');
      e.addFrame(copy: false);
      expect(e.cel.every((v) => v == 0), isTrue);
      e.setFrameDuration(0, 250, all: true);
      expect(e.sprite.frames.every((f) => f.durationMs == 250), isTrue);
      e.moveFrame(2, 0);
      expect(e.sprite.frames[0].cels[0].every((v) => v == 0), isTrue);
      e.deleteFrame(0);
      expect(e.sprite.frames, hasLength(2));
      e.undo();
      expect(e.sprite.frames, hasLength(3));
    },
  );

  test('onion skin shows the neighbours faintly under the current frame', () {
    final s = Sprite.blank(3, 1);
    s.cel(0, 0)[0] = red;
    s.addFrame(copy: false);
    s.cel(1, 0)[1] = blue;
    s.addFrame(copy: false);
    s.cel(2, 0)[2] = red;
    final o = onionComposite(s, 1);
    expect(o[1], blue, reason: 'current frame fully opaque');
    expect(
      alphaOf(o[0]),
      inInclusiveRange(1, 200),
      reason: 'previous frame ghost',
    );
    expect(alphaOf(o[2]), inInclusiveRange(1, 200), reason: 'next frame ghost');
    expect(
      blueOf(o[2]),
      greaterThan(blueOf(o[0])),
      reason: 'next is tinted blue',
    );
  });

  test(
    'pictures come in as a centred, fitted layer, optionally on the palette',
    () {
      final e = Editor(sprite: Sprite.blank(8, 8))
        ..setPalette(builtInPalettes.first);
      final pic = (
        width: 16,
        height: 8,
        pixels: Uint32List(128)..fillRange(0, 128, 0xFF808080),
      );
      e.importPicture(pic, snap: true);
      expect(e.sprite.layers, hasLength(2));
      expect(e.layer, 1);
      final cel = e.sprite.cel(0, 1);
      expect(cel[0], 0, reason: 'fitted 8x4, centred vertically');
      expect(cel[2 * 8], isNot(0));
      expect(builtInPalettes.first.colors, contains(cel[2 * 8]));
      e.undo();
      expect(e.sprite.layers, hasLength(1));
    },
  );

  test('map editor: paint, fill, pick, undo, retile, resize', () {
    final pixels = Uint32List(16 * 8)
      ..fillRange(0, 64, red); // left 8x8 red, right... top rows
    final m = MapEditor.fromPicture(pixels, 16, 8, 8, cols: 4, rows: 3);
    expect(m.map.tileSet.length, greaterThanOrEqualTo(2));
    m.selectTile(1);
    m.strokeStart(0, 0);
    m.strokeMove(1, 0);
    m.strokeEnd();
    expect(m.map.get(1, 0), 1);
    m.setTool(MapTool.fill);
    m.strokeStart(3, 2);
    m.strokeEnd();
    expect(m.map.cells.every((c) => c == 1), isTrue);
    m.undo();
    expect(m.map.get(3, 2), 0);
    m.setTool(MapTool.pick);
    m.strokeStart(0, 0);
    expect(m.tile, 1);
    m.retile(Uint32List(64), 8, 8);
    expect(m.map.tileSet.length, 1);
    expect(m.map.cells.every((c) => c == 0), isTrue);
    m.resize(6, 2);
    expect((m.map.cols, m.map.rows), (6, 2));
    expect(TileMap.fromJson(m.map.toJson()).cols, 6);
    expect(mapPng(m.map).isNotEmpty, isTrue);
  });

  testWidgets('timeline, onion skin and tile map mode', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('forge_pass2');
    addTearDown(() => dir.deleteSync(recursive: true));
    final services = (await tester.runAsync(
      () => ShellServices.create(appConfig, root: dir),
    ))!;
    final e = Editor(sprite: Sprite.blank(16, 16))..setPrimary(red);
    e.strokeStart(0, 0);
    e.strokeEnd();
    await tester.pumpWidget(
      ShellApp(
        services: services,
        home: (_) => HomePage(editor: e),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Add a copy of this frame'));
    await tester.pump();
    expect(e.sprite.frames, hasLength(2));
    expect(find.text('2'), findsWidgets);
    await tester.tap(
      find.byTooltip('Onion skin (see the frames before and after)'),
    );
    await tester.pump();
    expect(e.onionSkin, isTrue);

    await tester.tap(find.byTooltip('Sprite'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tile map from this sprite…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('8×8 pixels'));
    await tester.pumpAndSettle();
    expect(find.byType(MapPage), findsOneWidget);
    expect(find.textContaining('tiles ·'), findsOneWidget);
    expect(find.byType(CanvasView), findsNothing);
  });
}
