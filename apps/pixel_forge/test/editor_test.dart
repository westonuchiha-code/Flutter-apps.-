import 'dart:io';

import 'package:app_shell/app_shell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_forge/src/editor.dart';
import 'package:pixel_forge/src/library.dart';
import 'package:pixel_kit/pixel_kit.dart';

const red = 0xFFFF0000, blue = 0xFF0000FF;

Editor make([int w = 8, int h = 8]) =>
    Editor(sprite: Sprite.blank(w, h))..setPrimary(red);

int px(Editor e, int x, int y) => e.cel[y * e.sprite.width + x];

void main() {
  test('pencil strokes connect, undo and redo', () {
    final e = make();
    e.strokeStart(0, 0);
    e.strokeMove(7, 0);
    e.strokeEnd();
    expect(
      [for (var x = 0; x < 8; x++) px(e, x, 0)].every((v) => v == red),
      isTrue,
    );
    e.undo();
    expect(e.cel.every((v) => v == 0), isTrue);
    e.redo();
    expect(px(e, 4, 0), red);
  });

  test('shapes preview while dragging and leave one undo step', () {
    final e = make()..setTool(Tool.rect);
    e.strokeStart(1, 1);
    e.strokeMove(6, 6);
    e.strokeMove(3, 3);
    e.strokeEnd();
    expect(px(e, 3, 3), red);
    expect(px(e, 6, 6), 0, reason: 'earlier preview removed');
    expect(px(e, 2, 2), 0, reason: 'outline only');
    e.undo();
    expect(e.cel.every((v) => v == 0), isTrue);
    expect(e.canUndo, isFalse);
  });

  test('a second finger cancels the stroke in progress', () {
    final e = make();
    e.strokeStart(0, 0);
    e.strokeMove(5, 5);
    e.strokeCancel();
    expect(e.cel.every((v) => v == 0), isTrue);
    expect(e.canUndo, isFalse);
  });

  test('fill, eraser and colour picker', () {
    final e = make()..setTool(Tool.fill);
    e.strokeStart(3, 3);
    e.strokeEnd();
    expect(e.cel.every((v) => v == red), isTrue);
    e.setTool(Tool.eraser);
    e.strokeStart(0, 0);
    e.strokeEnd();
    expect(px(e, 0, 0), 0);
    e
      ..setPrimary(blue)
      ..setTool(Tool.picker)
      ..strokeStart(5, 5);
    expect(e.primary, red);
  });

  test('select, move the pixels, then undo in one step', () {
    final e = make();
    e.strokeStart(1, 1);
    e.strokeEnd();
    e.setTool(Tool.select);
    e.strokeStart(0, 0);
    e.strokeMove(2, 2);
    e.strokeEnd();
    expect(e.selection, const Rect(0, 0, 3, 3));
    // Drag from inside the selection.
    e.strokeStart(1, 1);
    e.strokeMove(4, 3);
    e.strokeEnd();
    e.commitFloating();
    expect(px(e, 1, 1), 0);
    expect(px(e, 4, 3), red);
    e.undo();
    expect(px(e, 1, 1), red);
    expect(px(e, 4, 3), 0);
  });

  test('flip inside a selection; copy and paste', () {
    final e = make();
    e.strokeStart(0, 0);
    e.strokeEnd();
    e.setTool(Tool.select);
    e.strokeStart(0, 0);
    e.strokeMove(3, 0);
    e.strokeEnd();
    e.flipX();
    e.commitFloating();
    expect(px(e, 0, 0), 0);
    expect(px(e, 3, 0), red);
    e.copySelection();
    e.deselect();
    e.paste();
    e.commitFloating();
    expect(px(e, 3, 0), red);
    expect(e.clipboard!.w, 4);
  });

  test('mirror drawing', () {
    final e = make()..toggleMirrorX();
    e.strokeStart(1, 2);
    e.strokeEnd();
    expect(px(e, 6, 2), red);
  });

  test('layers: add, draw on, hide, merge, undo', () {
    final e = make();
    e.addLayer();
    expect(e.layer, 1);
    e.strokeStart(2, 2);
    e.strokeEnd();
    expect(e.sprite.cel(0, 0)[2 * 8 + 2], 0, reason: 'drew on the new layer');
    e.setLayerVisible(1, false);
    expect(e.sprite.flatten(0)[2 * 8 + 2], 0);
    e.setLayerVisible(1, true);
    e.mergeDown(1);
    expect(e.sprite.layers, hasLength(1));
    expect(e.sprite.cel(0, 0)[2 * 8 + 2], red);
    e.undo();
    expect(e.sprite.layers, hasLength(2));
  });

  test('snap to palette and palette from the sprite', () {
    final e = make()..setPalette(builtInPalettes.first); // Game Boy greens
    e.strokeStart(0, 0);
    e.strokeEnd();
    e.reduceToPalette();
    expect(builtInPalettes.first.colors, contains(px(e, 0, 0)));
    expect(e.paletteFromSprite().colors, [px(e, 0, 0)]);
  });

  test('resizing keeps the picture and can be undone', () {
    final e = make(4, 4);
    e.strokeStart(3, 3);
    e.strokeEnd();
    e.resize(6, 5);
    expect((e.sprite.width, e.sprite.height), (6, 5));
    expect(e.sprite.cel(0, 0)[3 * 6 + 3], red);
    e.undo();
    expect(e.sprite.width, 4);
  });

  test('save to and open from the Asset Locker', () async {
    final dir = Directory.systemTemp.createTempSync('forge_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final locker = AssetLocker.atDirectory('pixel_forge', dir);
    final lib = ForgeLibrary(locker);
    final e = make()..name = 'Hero';
    e.strokeStart(2, 3);
    e.strokeEnd();
    final saved = await lib.saveSprite(e);
    expect(saved.hasThumbnail, isTrue);
    final back = await lib.open(saved);
    expect(back.cel(0, 0)[3 * 8 + 2], red);
    // Saving again replaces the same asset.
    e.strokeStart(0, 0);
    e.strokeEnd();
    await lib.saveSprite(e, replace: saved);
    expect(await locker.list(type: AssetType.sprite), hasLength(1));
    // A PNG opens as a one-layer sprite.
    final png = await lib.exportPng(e, 2);
    final fromPng = await lib.open(png);
    expect((fromPng.width, fromPng.height), (16, 16));
    expect(fromPng.cel(0, 0)[0], red);
    // Palettes round trip.
    final p = await lib.savePalette(builtInPalettes[3]);
    expect((await lib.openPalette(p)).colors, builtInPalettes[3].colors);
  });
}
