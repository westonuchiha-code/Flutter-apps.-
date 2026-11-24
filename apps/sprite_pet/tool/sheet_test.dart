// Contact sheet of every pet in every mood (art check).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sprite_pet/src/art/render.dart';
import 'package:sprite_pet/src/art/species.dart';
import 'package:sprite_pet/src/mood.dart';

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: '.');
  const frame = int.fromEnvironment('FRAME', defaultValue: 0);
  test('sheet', () {
    const k = 5, cell = 34;
    final looks = [
      WeatherLook.rain,
      WeatherLook.snow,
      WeatherLook.sun,
      WeatherLook.storm,
    ];
    final cols = Mood.values.length + looks.length;
    final sheet = img.Image(
      width: cols * cell * k,
      height: builtInSpecies.length * cell * k,
      numChannels: 3,
    );
    img.fill(sheet, color: img.ColorRgb8(58, 62, 78));
    for (var r = 0; r < builtInSpecies.length; r++) {
      for (var col = 0; col < cols; col++) {
        final mood = col < Mood.values.length ? Mood.values[col] : Mood.idle;
        final w = col < Mood.values.length
            ? WeatherLook.none
            : looks[col - Mood.values.length];
        final px = renderPet(
          builtInSpecies[r],
          w == WeatherLook.storm ? Mood.scared : mood,
          frame,
          weather: w,
        );
        for (var y = 0; y < 32; y++) {
          for (var x = 0; x < 32; x++) {
            final c = px[y * 32 + x];
            final a = (c >>> 24) / 255;
            if (a == 0) continue;
            for (var yy = 0; yy < k; yy++) {
              for (var xx = 0; xx < k; xx++) {
                final sx = (col * cell + 1 + x) * k + xx,
                    sy = (r * cell + 1 + y) * k + yy;
                final bg = sheet.getPixel(sx, sy);
                sheet.setPixelRgb(
                  sx,
                  sy,
                  (((c >> 16) & 255) * a + bg.r * (1 - a)).round(),
                  (((c >> 8) & 255) * a + bg.g * (1 - a)).round(),
                  ((c & 255) * a + bg.b * (1 - a)).round(),
                );
              }
            }
          }
        }
      }
    }
    File('$out/pets_f$frame.png').writeAsBytesSync(img.encodePng(sheet));
  });
}
