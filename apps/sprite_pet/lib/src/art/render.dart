import 'dart:math' as math;
import 'dart:typed_data';

import '../mood.dart';
import 'canvas.dart';
import 'face.dart';
import 'species.dart';

/// Frames in every mood's loop.
const framesPerMood = 4;

/// One frame of [species] in [mood], with weather extras. 32×32 ARGB.
Uint32List renderPet(
  PetSpecies species,
  Mood mood,
  int frame, {
  WeatherLook weather = WeatherLook.none,
}) {
  frame %= framesPerMood;
  final body = PixelCanvas();
  final face = species.draw(body, mood, frame);
  if (species.outlineColor != 0) {
    body.outline(species.outlineColor);
  }
  drawEyes(body, face, mood, frame);
  drawMouth(body, face, mood, frame);
  if (weather == WeatherLook.sun && mood != Mood.asleep) {
    drawShades(body, face);
  }

  final (dx, dy) = switch (mood) {
    Mood.happy => (0, const [0, -1, -3, -1][frame]),
    Mood.idle => (0, const [0, 0, 1, 0][frame]),
    Mood.asleep => (0, const [0, 0, 1, 1][frame]),
    Mood.sleepy => (0, const [0, 1, 1, 0][frame]),
    Mood.eating => (0, const [0, 1, 0, 1][frame]),
    Mood.hungry => (0, const [0, 0, 0, 1][frame]),
    Mood.bored => (0, 0),
    Mood.scared => (const [-1, 1, -1, 1][frame], 0),
  };
  final out = PixelCanvas();
  out.ellipse(15.5, 30.6, dy < -2 ? 6.0 : 9.0, 1.2, 0x50000000);
  out.paste(body, dx, dy);

  final extra = PixelCanvas();
  final hx = face.headX + dx, ht = face.headTop + dy;
  switch (weather) {
    case WeatherLook.rain || WeatherLook.storm:
      drawUmbrella(extra, hx, math.max(0, ht - 7));
    case WeatherLook.snow:
      drawBeanie(extra, hx, ht - 2, face.headWidth);
    default:
      break;
  }
  switch (mood) {
    case Mood.asleep:
      drawZ(extra, hx + 6, math.max(0, ht - 6) + 3 - frame, 0xFFA8C8FF);
      if (frame >= 2) {
        drawZ(
          extra,
          hx + 10,
          math.max(0, ht - 11) + 1 - (frame - 2),
          0xFFD0E2FF,
        );
      }
    case Mood.happy:
      drawHeart(extra, hx - 11, math.max(1, ht - 1) + 4 - frame * 2);
      drawHeart(extra, hx + 7, math.max(1, ht - 3) + 4 - ((frame + 2) % 4) * 2);
    case Mood.eating:
      final m = face.mouth ?? (hx, ht + 6);
      drawFood(
        extra,
        face.food,
        m.$1 + (face.side ? 1 : 3) + dx,
        m.$2 - 3 + dy,
        bites: frame,
      );
    case Mood.hungry:
      drawBubble(
        extra,
        (hx + 4).clamp(0, 23),
        (ht - 11).clamp(0, 31),
        (x, y) => drawFood(extra, face.food, x, y),
      );
    case Mood.bored:
      drawBubble(
        extra,
        (hx + 4).clamp(0, 23),
        (ht - 11).clamp(0, 31),
        (x, y) =>
            drawDots(extra, x, y + 2, const [1, 2, 3, 3][frame], 0xFF333333),
      );
    case Mood.scared:
      drawDrop(extra, hx + 8, ht + 2 + frame % 2);
    case Mood.idle || Mood.sleepy:
      break;
  }
  if (weather == WeatherLook.storm && frame.isEven) {
    drawBolt(extra, 2, 1);
  }
  extra.outline(0xFF1A1A2E);
  out.paste(extra);

  // Falling weather in front.
  if (weather == WeatherLook.rain || weather == WeatherLook.storm) {
    for (var i = 0; i < 9; i++) {
      final x = (i * 7 + 3) % 32, y = (i * 11 + frame * 5) % 30;
      if (out.get(x, y) == 0) {
        out.set(x, y, 0xFF8FC9FF);
        out.set(x, y + 1, 0xFF8FC9FF);
      }
    }
  } else if (weather == WeatherLook.snow) {
    for (var i = 0; i < 10; i++) {
      final x = (i * 9 + (frame + i) % 3) % 32, y = (i * 7 + frame * 2) % 30;
      if (out.get(x, y) == 0) {
        out.set(x, y, 0xFFFFFFFF);
      }
    }
  } else if (weather == WeatherLook.clear && mood == Mood.asleep) {
    for (final (x, y, f) in const [
      (3, 3, 0),
      (27, 5, 1),
      (8, 9, 2),
      (29, 12, 3),
    ]) {
      if (out.get(x, y) == 0 && (frame + f) % 4 != 0) {
        out.set(x, y, 0xFFFFF5B0);
      }
    }
  }
  return out.px;
}
