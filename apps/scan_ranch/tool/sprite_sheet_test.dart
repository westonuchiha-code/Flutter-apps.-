// Renders generated pixel sprites (upscaled) to a PNG for review.
// Run: flutter test tool/sprite_sheet_test.dart --dart-define=OUT=/dir
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scan_ranch/model/genome.dart';
import 'package:scan_ranch/render/sprite_gen.dart';

Future<ui.Image> decode(SpriteGrid grid, SpritePalette pal) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pal.rgba(grid),
    spriteW,
    spriteH,
    ui.PixelFormat.rgba8888,
    c.complete,
  );
  return c.future;
}

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: '.');
  const start = int.fromEnvironment('START', defaultValue: 0);
  test('sprite sheet', () async {
    const cols = 6, rows = 4, scale = 4.0;
    const cellW = spriteW * scale + 8, cellH = spriteH * scale + 8;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, cols * cellW, rows * cellH),
      Paint()..color = const Color(0xFF8CCB5E),
    );
    for (var i = 0; i < cols * rows; i++) {
      final g = Genome.fromBarcode(
        '0${(73519000123 + (i + start) * 7919) % 99999999999}',
      );
      final look = Appearance(g, Individuality.roll(g, i));
      final face = [Face.normal, Face.normal, Face.happy, Face.eat][i % 4];
      final grid = SpriteBuilder(look)
          .build(SpritePose(step: i % 3, face: face));
      final img = await decode(grid, SpritePalette(look));
      final x = (i % cols) * cellW + 4, y = (i ~/ cols) * cellH + 4;
      canvas.drawImageRect(
        img,
        const Rect.fromLTWH(0, 0, spriteW * 1.0, spriteH * 1.0),
        Rect.fromLTWH(x, y, spriteW * scale, spriteH * scale),
        Paint()..filterQuality = FilterQuality.none,
      );
    }
    final image = await recorder.endRecording().toImage(
      (cols * cellW).toInt(),
      (rows * cellH).toInt(),
    );
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$out/sprites.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}
