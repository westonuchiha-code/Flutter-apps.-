import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pixel_kit/pixel_kit.dart' as pk;

import 'art/canvas.dart';
import 'art/render.dart';
import 'art/species.dart';
import 'mood.dart';

/// A pet frame as a PNG, each pixel [scale]×[scale] (no smoothing).
Uint8List framePng(Uint32List px, {int scale = 6}) {
  final image = img.Image(
    width: petSize * scale,
    height: petSize * scale,
    numChannels: 4,
  );
  for (final p in image) {
    final c = px[(p.y ~/ scale) * petSize + p.x ~/ scale];
    p
      ..r = (c >> 16) & 255
      ..g = (c >> 8) & 255
      ..b = c & 255
      ..a = c >>> 24;
  }
  return img.encodePng(image);
}

/// Every mood's frames as one Pixel Forge sprite (mood after mood), so a
/// pet can be edited or reused in other apps.
pk.Sprite petToSprite(PetSpecies s) {
  final sprite = pk.Sprite.blank(petSize, petSize);
  var i = 0;
  for (final m in Mood.values) {
    for (var f = 0; f < framesPerMood; f++) {
      if (i > 0) sprite.addFrame(copy: false);
      sprite.cel(i, 0).setAll(0, renderPet(s, m, f));
      sprite.frames[i].durationMs = m == Mood.asleep ? 600 : 300;
      i++;
    }
  }
  return sprite;
}
