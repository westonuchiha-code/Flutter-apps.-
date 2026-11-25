// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:vista/src/land.dart';
import 'package:vista/src/raytrace.dart';

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: '.');
  test('stills', () {
    const w = 480, h = 270;
    final sheet = img.Image(width: w, height: h * 3);
    var row = 0;
    for (final (key, time) in [
      ('alps', 16.5),
      ('islands', 18.2),
      ('moon', 22.0),
    ]) {
      final s = presets[key]!.$2.copyWith(time: time);
      final f = generate(s);
      final y = f.heightAt(0, 150) + 30;
      final job = TraceJob(s, f, Shot(0, y, 150, 0, -0.18), w, h);
      final sw = Stopwatch()..start();
      final px = Uint32List(w * h);
      placePass(px, w, h, tracePass((job, 0, 1, 1)), 0, 1, 1);
      print('$key: ${sw.elapsedMilliseconds} ms');
      for (var i = 0; i < w * h; i++) {
        final c = px[i];
        sheet.setPixelRgb(
          i % w,
          row * h + i ~/ w,
          (c >> 16) & 255,
          (c >> 8) & 255,
          c & 255,
        );
      }
      row++;
    }
    File('$out/vista_stills.png').writeAsBytesSync(img.encodePng(sheet));
  });
}
