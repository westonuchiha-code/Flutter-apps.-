// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:vista/src/land.dart';

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: '.');
  test('maps', () {
    final sheet = img.Image(width: 5 * 260, height: 260);
    var k = 0;
    for (final e in presets.entries) {
      final s = e.value.$2;
      final sw = Stopwatch()..start();
      final f = generate(s);
      print('${e.key}: ${sw.elapsedMilliseconds} ms');
      final sea = seaHeight(s);
      for (var j = 0; j < f.n; j++) {
        for (var i = 0; i < f.n; i++) {
          final x = -f.size / 2 + i * f.cell, z = -f.size / 2 + j * f.cell;
          final y = f.at(i, j);
          final (nx, ny, nz) = f.normalAt(x, z);
          var c = groundColor(s, y, ny, sea);
          var l = math.max(0.0, -0.5 * nx + 0.8 * ny + 0.3 * nz) * 0.8 + 0.3;
          if (s.water && y < sea) {
            c = 0xFF2A5A8A;
            l = 1;
          }
          sheet.setPixelRgb(
            k * 260 + i,
            j,
            (((c >> 16) & 255) * l).clamp(0, 255).toInt(),
            (((c >> 8) & 255) * l).clamp(0, 255).toInt(),
            ((c & 255) * l).clamp(0, 255).toInt(),
          );
        }
      }
      k++;
    }
    File('$out/vista_maps.png').writeAsBytesSync(img.encodePng(sheet));
  });
}
