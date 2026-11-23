// Renders a mock ranch scene (background + creatures) at phone size.
// Run: flutter test tool/scene_test.dart --dart-define=OUT=/dir
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scan_ranch/model/genome.dart';
import 'package:scan_ranch/render/ranch_background.dart';
import 'package:scan_ranch/render/sprite_gen.dart';

Future<ui.Image> decode(Uint8List rgba, int w, int h) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: '.');
  test('scene', () async {
    const sw = 412.0, sh = 640.0, k = 2.5; // dp size and pixel scale
    final bw = (sw / k).round(), bh = (sh / k).round();
    final bg = await decode(ranchBackground(bw, bh), bw, bh);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final nearest = Paint()..filterQuality = FilterQuality.none;
    canvas.drawImageRect(
      bg,
      Rect.fromLTWH(0, 0, bw.toDouble(), bh.toDouble()),
      const Rect.fromLTWH(0, 0, sw, sh),
      nearest,
    );
    final spots = [
      (90.0, 300.0, 0),
      (250.0, 330.0, 1),
      (330.0, 420.0, 2),
      (150.0, 450.0, 3),
      (60.0, 560.0, 4),
      (280.0, 600.0, 5),
      (200.0, 250.0, 6),
    ];
    final sorted = [...spots]..sort((a, b) => a.$2.compareTo(b.$2));
    for (final (x, y, i) in sorted) {
      final g = Genome.fromBarcode(
        '0${(73519000123 + (i * 5 + 1) * 7919) % 99999999999}',
      );
      final look = Appearance(g, Individuality.roll(g, i));
      final grid = SpriteBuilder(
        look,
      ).build(SpritePose(step: i % 3, face: i == 2 ? Face.happy : Face.normal));
      final img = await decode(
        SpritePalette(look).rgba(grid),
        spriteW,
        spriteH,
      );
      final depth = 0.7 + 0.45 * ((y - sh * 0.3) / (sh * 0.7));
      final s = k * 1.3 * depth;
      canvas.save();
      canvas.translate(x, y);
      if (i.isOdd) canvas.scale(-1, 1);
      canvas.drawImageRect(
        img,
        const Rect.fromLTWH(0, 0, spriteW * 1.0, spriteH * 1.0),
        Rect.fromLTWH(-spriteW * s / 2, -spriteH * s, spriteW * s, spriteH * s),
        nearest,
      );
      canvas.restore();
    }
    final image = await recorder.endRecording().toImage(sw.toInt(), sh.toInt());
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$out/scene.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}
