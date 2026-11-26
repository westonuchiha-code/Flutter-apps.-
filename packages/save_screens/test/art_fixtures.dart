// Made-up saves and cards for the art tests and screenshots.
import 'dart:math' as math;

import 'package:save_kit/save_kit.dart';

/// A little textured, two-shape PS2 model: a squat diamond that stretches
/// tall and back (8 triangles), with a checker texture.
Ps2Icon fakePs2Icon({bool textured = true}) {
  final ico = Ps2Icon();
  const top = Vec3(0, 0.7, 0), bottom = Vec3(0, -0.7, 0);
  final ring = [
    for (var i = 0; i < 4; i++)
      Vec3(
        math.cos(i * math.pi / 2) * 0.55,
        0,
        math.sin(i * math.pi / 2) * 0.55,
      ),
  ];
  final tall = <Vec3>[], squat = <Vec3>[];
  for (var i = 0; i < 4; i++) {
    final a = ring[i], b = ring[(i + 1) % 4];
    for (final (tip, side) in [(top, 1.0), (bottom, -1.0)]) {
      final tri = side > 0 ? [tip, b, a] : [tip, a, b];
      final mid = (a + b) * 0.5;
      final n = Vec3(mid.x, side * 0.6, mid.z).normalized();
      for (var k = 0; k < 3; k++) {
        final p = tri[k];
        tall.add(p);
        squat.add(Vec3(p.x * 1.25, p.y * 0.6, p.z * 1.25));
        ico.normals.add(n);
        ico.uvs.add((k == 0 ? 0.5 : (k == 1 ? 1.0 : 0.0), k == 0 ? 0.0 : 1.0));
        ico.colors.add(
          Rgb.hsv(((i * 2 + (side > 0 ? 0 : 1)) / 8 + k * 0.03) % 1, 0.7, 1),
        );
      }
    }
  }
  ico.shapes
    ..add(tall)
    ..add(squat);
  ico
    ..length = 120
    ..speed = 1;
  ico.tracks
    ..add((shape: 0, keys: [(0.0, 1.0), (60.0, 0.0), (120.0, 1.0)]))
    ..add((shape: 1, keys: [(0.0, 0.0), (60.0, 1.0), (120.0, 0.0)]));
  if (textured) {
    final t = Pixels(128, 128);
    for (var y = 0; y < 128; y++) {
      for (var x = 0; x < 128; x++) {
        final on = (x ~/ 16 + y ~/ 16).isEven;
        t.set(x, y, on ? 255 : 90, on ? 255 : 90, on ? 255 : 120);
      }
    }
    ico.texture = t;
  }
  return ico;
}

CardSave fakePs2Save({String name = 'Diamond Days', bool favorite = false}) {
  final s = CardSave()
    ..system = 'PS2'
    ..setId('BASLUS-20000DIAMOND')
    ..favorite = favorite
    ..ambient = const Rgb(0.35, 0.35, 0.4)
    ..backAlpha = 0.6;
  s.titleLines.add(name);
  s.lightDirs.addAll([
    const Vec3(0.5, 0.5, 0.7),
    const Vec3(-0.6, 0.2, 0.5),
    const Vec3(0, -1, 0),
  ]);
  s.lightColors.addAll([
    const Rgb(0.6, 0.55, 0.5),
    const Rgb(0.2, 0.3, 0.6),
    const Rgb(0.1, 0.1, 0.1),
  ]);
  s.backColors.addAll([
    Rgb.hex('a02060'),
    Rgb.hex('3040a0'),
    Rgb.hex('204060'),
    Rgb.hex('20a060'),
  ]);
  final ico = fakePs2Icon();
  s.icons[0] = ico;
  s.icons[1] = fakePs2Icon(textured: false);
  s.icons[2] = ico;
  return s;
}

/// A 2D-icon save: three frames of a bouncing dot (PS1 style, 16×16).
CardSave fakeFramesSave(String system, {String name = 'Dot Hop'}) {
  final s = CardSave()
    ..system = system
    ..setId('BASLUS-00001$name');
  s.titleLines.add(name);
  for (var f = 0; f < 3; f++) {
    final p = Pixels(16, 16);
    p.fill(1, 1, 14, 14, 0xFF203080);
    p.fill(5, 3 + f * 3, 6, 6, 0xFFFFD040);
    p.fill(6, 4 + f * 3, 2, 2, 0xFFFFFFFF);
    s.frames.add(p);
  }
  return s;
}

CardSave fakePs3Save() {
  final s = CardSave()
    ..system = 'PS3'
    ..setId('BLUS00001-SAVE');
  s.titleLines.add('Chapter 3');
  final wide = Pixels(320, 176);
  for (var y = 0; y < 176; y++) {
    for (var x = 0; x < 320; x++) {
      wide.set(x, y, x * 255 ~/ 320, y * 255 ~/ 176, 160);
    }
  }
  s.wide = wide;
  final sq = Pixels(176, 176);
  for (var y = 0; y < 176; y++) {
    for (var x = 0; x < 176; x++) {
      sq.set(x, y, (x + 72) * 255 ~/ 320, y * 255 ~/ 176, 160);
    }
  }
  s.frames.add(sq);
  return s;
}

MemoryCard fakeCard(
  String system, {
  String name = 'Card 1',
  int color = 0,
  String finish = '',
  Pixels? sticker,
  int free = 300,
  int total = 1000,
}) => MemoryCard()
  ..system = system
  ..name = name
  ..color = color
  ..finish = finish
  ..stickerImage = sticker
  ..free = free
  ..total = total;

/// A sticker picture: a sunset.
Pixels fakeSticker() {
  final p = Pixels(80, 60);
  for (var y = 0; y < 60; y++) {
    for (var x = 0; x < 80; x++) {
      final d = math.sqrt((x - 40) * (x - 40) + (y - 40) * (y - 40));
      if (d < 14) {
        p.set(x, y, 255, 210, 60);
      } else if (y > 40) {
        p.set(x, y, 30, 60, 140);
      } else {
        p.set(x, y, 240, 100 + y * 2, 80);
      }
    }
  }
  return p;
}
