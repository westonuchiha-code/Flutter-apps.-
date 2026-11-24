import 'dart:math' as math;

import '../mood.dart';
import 'canvas.dart';
import 'face.dart';

/// A kind of pet: draws its body for a mood and frame, and says where its
/// face is.
abstract class PetSpecies {
  const PetSpecies();
  String get id;
  String get name;
  String get about;
  int get outlineColor;
  Face draw(PixelCanvas c, Mood mood, int frame);
}

const builtInSpecies = <PetSpecies>[
  Slime(),
  CubeOoze(),
  Cat(),
  CatGirl(),
  Robot(),
  ShiftBot(),
  Car(),
  Dino(),
];

PetSpecies? speciesById(String id) {
  for (final s in builtInSpecies) {
    if (s.id == id) {
      return s;
    }
  }
  return null;
}

class Slime extends PetSpecies {
  const Slime();
  @override
  String get id => 'slime';
  @override
  String get name => 'Slime';
  @override
  String get about => 'A wobbly blob. Squishes when happy, puddles when tired.';
  @override
  int get outlineColor => 0xFF1F5E4C;

  @override
  Face draw(PixelCanvas c, Mood mood, int frame) {
    const base = 0xFF59C9A5, dark = 0xFF2F8F73, light = 0xFFC4F5E4;
    final squash = switch (mood) {
      Mood.happy => const [1, -1, -2, 0][frame],
      Mood.asleep || Mood.sleepy => const [1, 1, 2, 2][frame],
      Mood.eating => const [0, 1, 0, 1][frame],
      _ => const [0, 0, 1, 0][frame],
    };
    final rx = 11.0 + squash, ry = 8.0 - squash;
    const cx = 15.5, bottom = 29;
    final cy = bottom - ry + 3;
    c.ellipse(cx, cy, rx, ry, base, where: (x, y) => y <= bottom);
    c.ellipse(
      cx,
      cy + 2,
      rx - 1,
      ry - 2,
      dark,
      where: (x, y) => y >= cy + 3 && y <= bottom,
    );
    c.ellipse(cx - rx * 0.45, cy - ry * 0.5, 2.2, 1.2, light);
    c.set((cx - rx * 0.45 + 3).round(), (cy - ry * 0.65).round(), light);
    final ey = (cy - 2).round();
    return Face(
      eyes: [(11, ey), (19, ey)],
      mouth: (16, ey + 4),
      headX: 16,
      headTop: (cy - ry).round(),
      headWidth: (rx * 1.4).round(),
      ink: 0xFF163F33,
      food: Food.apple,
    );
  }
}

class CubeOoze extends PetSpecies {
  const CubeOoze();
  @override
  String get id => 'cube';
  @override
  String get name => 'Cube ooze';
  @override
  String get about => 'A see-through jelly cube. Things it ate float inside.';
  @override
  int get outlineColor => 0xFF2E6B4A;

  @override
  Face draw(PixelCanvas c, Mood mood, int frame) {
    const jelly = 0xFF9BE8B8,
        jelly2 = 0xFF86DBA6,
        top = 0xFFC9F7DA,
        deep = 0xFF6FC48F;
    final wob = switch (mood) {
      Mood.happy => const [0, 2, 0, -2][frame],
      Mood.asleep => 0,
      Mood.scared => const [1, -1, 1, -1][frame],
      _ => const [0, 1, 0, -1][frame],
    };
    final sag = mood == Mood.asleep || mood == Mood.sleepy ? 2 : 0;
    final y0 = 12 + sag, y1 = 29;
    for (var y = y0; y <= y1; y++) {
      final shift = (wob * (y1 - y) / (y1 - y0)).round();
      for (var x = 7; x <= 24; x++) {
        final edge = x == 7 || x == 24;
        final color = y <= y0 + 2
            ? top
            : y >= y1 - 2
            ? deep
            : edge
            ? deep
            : ((x + y).isEven ? jelly : jelly2);
        c.set(x + shift, y, color);
      }
    }
    // Things floating inside: a bone and a coin, and rising bubbles.
    final mid = y0 + (y1 - y0) ~/ 2;
    final s = (wob * 0.4).round();
    c.grid(9 + s, mid + 5, const ['w..w', '.ww.', 'w..w'], {'w': 0xFFE8F0EA});
    c.grid(
      19 + s,
      mid + 3,
      const ['.y.', 'yYy', '.y.'],
      {'y': 0xFFFFD54F, 'Y': 0xFFFFF59D},
    );
    final b = (frame * 3) % 9;
    c.set(13 + s, y1 - 3 - b, 0xFFFFFFFF);
    c.set(21 + s, y1 - 6 - ((b + 4) % 9), 0xFFFFFFFF);
    final ey = y0 + 5;
    return Face(
      eyes: [(11 + s, ey), (19 + s, ey)],
      mouth: (16 + s, ey + 4),
      headX: 16 + wob,
      headTop: y0,
      headWidth: 18,
      ink: 0xFF1E4D33,
      food: Food.bone,
    );
  }
}

class Cat extends PetSpecies {
  const Cat();
  @override
  String get id => 'cat';
  @override
  String get name => 'Cat';
  @override
  String get about => 'An orange tabby. Naps a lot, loves fish.';
  @override
  int get outlineColor => 0xFF5A3214;

  @override
  Face draw(PixelCanvas c, Mood mood, int frame) {
    const fur = 0xFFF0A04B,
        stripe = 0xFFC2702A,
        cream = 0xFFFFE6C7,
        pink = 0xFFFF9EB0;
    final curled = mood == Mood.asleep;
    // Tail (behind), swishing.
    final sway = const [0, 1, 2, 1][frame];
    final tail = [
      (21, 28),
      (24, 28),
      (26, 27),
      (27, 25),
      (27 + sway ~/ 2, 23),
      (26 + sway, 21),
    ];
    for (final (x, y) in tail) {
      c.ellipse(x.toDouble(), y.toDouble(), 1.3, 1.3, fur);
    }
    c.set(26 + sway, 20, stripe);
    // Body.
    c.ellipse(
      15.5,
      curled ? 26.0 : 25.0,
      curled ? 9.0 : 7.0,
      curled ? 4.0 : 5.0,
      fur,
    );
    c.ellipse(15.5, 26.5, 3.5, 3.0, cream);
    // Head.
    final hy = curled ? 20.0 : 16.0;
    c.ellipse(15.5, hy, 7.5, 6.0, fur);
    final ht = (hy - 6).round();
    c.triangle(8, ht + 4, 10, ht - 2, 14, ht + 1, fur);
    c.triangle(23, ht + 4, 21, ht - 2, 17, ht + 1, fur);
    c.triangle(10, ht + 2, 11, ht, 12, ht + 2, pink);
    c.triangle(21, ht + 2, 20, ht, 19, ht + 2, pink);
    // Forehead stripes and cheeks.
    for (final x in [13, 15, 16, 18]) {
      c.set(x, ht + 1, stripe);
    }
    c.set(15, ht + 2, stripe);
    c.set(16, ht + 2, stripe);
    c.ellipse(15.5, hy + 3, 2.6, 1.6, cream);
    c.set(15, (hy + 2).round(), pink);
    c.set(16, (hy + 2).round(), pink);
    // Paws.
    if (!curled) {
      c.ellipse(12.5, 29.0, 1.6, 1.0, cream);
      c.ellipse(18.5, 29.0, 1.6, 1.0, cream);
    }
    final ey = (hy - 1).round();
    return Face(
      eyes: [(11, ey), (19, ey)],
      mouth: (16, (hy + 3).round()),
      headX: 16,
      headTop: ht - 2,
      headWidth: 14,
      ink: 0xFF3A2410,
      food: Food.fish,
    );
  }
}

class CatGirl extends PetSpecies {
  const CatGirl();
  @override
  String get id => 'catgirl';
  @override
  String get name => 'Cat girl';
  @override
  String get about => 'A chibi cat girl with a swishy tail. Likes rice balls.';
  @override
  int get outlineColor => 0xFF3A2266;

  @override
  Face draw(PixelCanvas c, Mood mood, int frame) {
    const hair = 0xFF8E5BD6,
        hairDark = 0xFF6A40AE,
        skin = 0xFFFFDCC2,
        dress = 0xFFFF7EB6;
    const dressDark = 0xFFE0569A,
        white = 0xFFFFFFFF,
        pink = 0xFFFFB3C7,
        shoe = 0xFF5B3A29;
    final sway = const [0, 1, 2, 1][frame];
    // Tail.
    for (final (x, y) in [
      (20, 27),
      (23, 27),
      (25, 26),
      (26, 24),
      (26 + sway ~/ 2, 22),
      (25 + sway, 20),
    ]) {
      c.ellipse(x.toDouble(), y.toDouble(), 1.1, 1.1, hair);
    }
    // Legs and shoes.
    c.rect(13, 27, 14, 28, skin);
    c.rect(17, 27, 18, 28, skin);
    c.rect(12, 29, 14, 29, shoe);
    c.rect(17, 29, 19, 29, shoe);
    // Dress.
    for (var y = 20; y <= 26; y++) {
      final w = 3 + (y - 20) ~/ 2;
      c.rect(16 - w, y, 15 + w, y, y >= 25 ? dressDark : dress);
    }
    c.rect(14, 20, 17, 20, white);
    // Arms (up when happy).
    final up = mood == Mood.happy && frame.isOdd;
    c.rect(10, up ? 18 : 21, 11, up ? 20 : 23, skin);
    c.rect(20, up ? 18 : 21, 21, up ? 20 : 23, skin);
    // Hair back, head.
    c.rect(7, 12, 9, 21, hairDark);
    c.rect(22, 12, 24, 21, hairDark);
    c.ellipse(15.5, 12.0, 8.5, 8.0, hair);
    // Ears.
    c.triangle(8, 8, 9, 1, 13, 5, hair);
    c.triangle(23, 8, 22, 1, 18, 5, hair);
    c.triangle(9, 6, 10, 3, 11, 5, pink);
    c.triangle(22, 6, 21, 3, 20, 5, pink);
    // Face with bangs.
    c.ellipse(15.5, 14.5, 6.0, 4.8, skin, where: (x, y) => y >= 12);
    for (final x in [10, 13, 17, 20]) {
      c.set(x, 12, hair);
      c.set(x + 1, 12, hair);
    }
    c.set(11, 13, hair);
    c.set(20, 13, hair);
    // Blush.
    c.set(10, 17, pink);
    c.set(21, 17, pink);
    return const Face(
      eyes: [(11, 14), (19, 14)],
      mouth: (16, 17),
      style: EyeStyle.big,
      headX: 16,
      headTop: 3,
      headWidth: 17,
      ink: 0xFF3A2266,
      food: Food.riceBall,
    );
  }
}

class Robot extends PetSpecies {
  const Robot();
  @override
  String get id => 'robot';
  @override
  String get name => 'Robot';
  @override
  String get about => 'A boxy helper bot. Runs on batteries and good vibes.';
  @override
  int get outlineColor => 0xFF2C3440;

  @override
  Face draw(PixelCanvas c, Mood mood, int frame) {
    const metal = 0xFFB8C4D2,
        metalDark = 0xFF8592A3,
        screen = 0xFF1E2A38,
        bolt = 0xFF5D6877;
    final blink = frame.isEven ? 0xFFFF4D4D : 0xFFFF9A9A;
    final up = mood == Mood.happy && frame.isOdd;
    final droop = mood == Mood.asleep || mood == Mood.sleepy ? 1 : 0;
    // Antenna.
    c.rect(15, 4 + droop, 16, 6 + droop, bolt);
    c.rect(
      14,
      2 + droop,
      17,
      3 + droop,
      mood == Mood.asleep ? 0xFF7A3A3A : blink,
    );
    // Head.
    final h = droop;
    c.rect(8, 7 + h, 23, 17 + h, metal);
    c.rect(8, 17 + h, 23, 17 + h, metalDark);
    c.rect(10, 9 + h, 21, 15 + h, screen);
    c.rect(6, 11 + h, 7, 13 + h, bolt);
    c.rect(24, 11 + h, 25, 13 + h, bolt);
    // Neck and body.
    c.rect(14, 18, 17, 18, bolt);
    c.rect(10, 19, 21, 26, metal);
    c.rect(10, 26, 21, 26, metalDark);
    c.rect(13, 21, 18, 24, screen);
    final lights = [0xFF5CF2FF, 0xFF7CFF7C, 0xFFFFE066, 0xFFFF7CA8];
    c.rect(14, 22, 15, 23, lights[frame % 4]);
    c.rect(16, 22, 17, 23, lights[(frame + 2) % 4]);
    // Arms.
    c.rect(7, up ? 15 : 20, 9, up ? 20 : 25, metalDark);
    c.rect(22, up ? 15 : 20, 24, up ? 20 : 25, metalDark);
    // Legs.
    c.rect(11, 27, 14, 29, metalDark);
    c.rect(17, 27, 20, 29, metalDark);
    return Face(
      eyes: [(12, 11 + h), (17, 11 + h)],
      mouth: (16, 14 + h),
      style: EyeStyle.led,
      eyeColor: 0xFF5CF2FF,
      headX: 16,
      headTop: 2 + h,
      headWidth: 16,
      food: Food.battery,
    );
  }
}

/// Transforming robot: a car when asleep, changes form when happy.
class ShiftBot extends PetSpecies {
  const ShiftBot();
  @override
  String get id => 'shiftbot';
  @override
  String get name => 'Transforming robot';
  @override
  String get about => 'Robot by day, car by night. Transforms when happy.';
  @override
  int get outlineColor => 0xFF1C2630;

  static const teal = 0xFF2BB3A3, white = 0xFFF2F4F7, orange = 0xFFFF8A3D;
  static const dark = 0xFF39424E,
      glass = 0xFF7FD4FF,
      tyre = 0xFF22262B,
      hub = 0xFFA0A8B3;

  @override
  Face draw(PixelCanvas c, Mood mood, int frame) {
    final form = switch (mood) {
      Mood.asleep => 2,
      Mood.happy => const [0, 1, 2, 1][frame],
      _ => 0,
    };
    return switch (form) {
      0 => _robot(c, mood, frame),
      1 => _half(c),
      _ => _car(c),
    };
  }

  Face _robot(PixelCanvas c, Mood mood, int frame) {
    // Head with fins and visor.
    c.rect(12, 6, 19, 12, teal);
    c.rect(11, 5, 11, 8, orange);
    c.rect(20, 5, 20, 8, orange);
    c.rect(12, 8, 19, 10, dark);
    // Torso: the car's hood and windshield.
    c.rect(9, 13, 22, 21, white);
    c.rect(11, 14, 20, 16, glass);
    c.set(12, 14, white);
    c.rect(9, 18, 22, 18, orange);
    // Shoulder wheels.
    for (final x in [7.5, 23.5]) {
      c.ellipse(x, 14.0, 2.2, 2.2, tyre);
      c.set(x.floor(), 14, hub);
    }
    // Arms.
    final wave = mood == Mood.happy ? -3 : 0;
    c.rect(6, 17 + wave, 8, 22 + wave, teal);
    c.rect(23, 17, 25, 22, teal);
    // Waist and legs.
    c.rect(12, 22, 19, 22, dark);
    c.rect(11, 23, 14, 29, teal);
    c.rect(17, 23, 20, 29, teal);
    c.rect(11, 26, 12, 27, tyre);
    c.rect(19, 26, 20, 27, tyre);
    c.rect(11, 29, 14, 29, dark);
    c.rect(17, 29, 20, 29, dark);
    return const Face(
      eyes: [(12, 8), (17, 8)],
      style: EyeStyle.led,
      eyeColor: 0xFF9DFFF2,
      headX: 16,
      headTop: 5,
      headWidth: 10,
      food: Food.battery,
    );
  }

  void _carBody(PixelCanvas c) {
    c.rect(5, 28, 8, 29, tyre);
    c.rect(23, 28, 26, 29, tyre);
    c.rect(5, 20, 26, 27, teal);
    c.rect(4, 21, 27, 26, teal);
    c.rect(15, 20, 16, 27, orange);
    c.rect(11, 24, 20, 26, dark);
    c.rect(6, 27, 25, 27, white);
  }

  Face _half(PixelCanvas c) {
    _carBody(c);
    // Robot head popping out of the roof.
    c.rect(12, 12, 19, 19, teal);
    c.rect(12, 14, 19, 16, dark);
    c.rect(11, 11, 11, 14, orange);
    c.rect(20, 11, 20, 14, orange);
    return const Face(
      eyes: [(12, 14), (17, 14)],
      style: EyeStyle.led,
      eyeColor: 0xFF9DFFF2,
      headX: 16,
      headTop: 11,
      headWidth: 10,
      food: Food.battery,
    );
  }

  Face _car(PixelCanvas c) {
    _carBody(c);
    // Cabin and windshield.
    for (var y = 14; y <= 19; y++) {
      final w = 4 + (y - 14);
      c.rect(16 - w, y, 15 + w, y, white);
      if (y > 14) {
        c.rect(17 - w, y, 14 + w, y, glass);
      }
    }
    c.rect(12, 13, 19, 13, white);
    return const Face(
      eyes: [(6, 21), (23, 21)],
      mouth: (16, 25),
      style: EyeStyle.lamp,
      eyeColor: 0xFFFFE27A,
      headX: 16,
      headTop: 13,
      headWidth: 10,
      food: Food.fuel,
    );
  }
}

class Car extends PetSpecies {
  const Car();
  @override
  String get id => 'car';
  @override
  String get name => 'Car';
  @override
  String get about => 'A bubbly little car. Headlights for eyes, drinks fuel.';
  @override
  int get outlineColor => 0xFF4A1512;

  @override
  Face draw(PixelCanvas c, Mood mood, int frame) {
    const red = 0xFFE84A3F,
        redDark = 0xFFB0352D,
        glass = 0xFF9AD8FF,
        chrome = 0xFFDDE3EA,
        tyre = 0xFF2A2A2A;
    final bounce = mood == Mood.happy ? const [0, 1, 0, 1][frame] : 0;
    // Wheels.
    c.rect(5, 27, 9, 29, tyre);
    c.rect(22, 27, 26, 29, tyre);
    final y = bounce;
    // Roof and windshield.
    c.ellipse(15.5, 15.0 + y, 8.5, 5.5, red, where: (_, yy) => yy <= 18 + y);
    c.ellipse(15.5, 16.0 + y, 6.5, 3.8, glass, where: (_, yy) => yy <= 18 + y);
    c.set(11, 14 + y, 0xFFFFFFFF);
    c.set(12, 13 + y, 0xFFFFFFFF);
    // Body.
    c.rect(5, 18 + y, 26, 27, red);
    c.rect(4, 19 + y, 27, 26, red);
    c.rect(4, 25, 27, 26, redDark);
    c.rect(6, 27, 25, 27, chrome);
    // Mirrors.
    c.rect(2, 18 + y, 3, 19 + y, red);
    c.rect(28, 18 + y, 29, 19 + y, red);
    // Grille.
    c.rect(11, 23 + y, 20, 25, redDark);
    return Face(
      eyes: [(6, 20 + y), (23, 20 + y)],
      mouth: (16, 24 + y),
      style: EyeStyle.lamp,
      eyeColor: 0xFFFFE680,
      ink: 0xFF3A0E0B,
      headX: 16,
      headTop: 9 + y,
      headWidth: 16,
      food: Food.fuel,
    );
  }
}

class Dino extends PetSpecies {
  const Dino();
  @override
  String get id => 'dino';
  @override
  String get name => 'Dinosaur';
  @override
  String get about => 'A tiny T. rex with big feelings and short arms.';
  @override
  int get outlineColor => 0xFF22461A;

  @override
  Face draw(PixelCanvas c, Mood mood, int frame) {
    const green = 0xFF6CC24A,
        greenDark = 0xFF4E9A35,
        belly = 0xFFE3F5B5,
        spike = 0xFFFF9F43;
    final sway = const [0, -1, 0, 1][frame];
    final low = mood == Mood.asleep ? 3 : (mood == Mood.sleepy ? 1 : 0);
    // Tail.
    c.triangle(1, 25 + sway, 10, 20, 10, 27, green);
    // Body and belly.
    c.ellipse(13.0, 23.0, 6.5, 5.0, green);
    c.ellipse(14.5, 24.5, 3.5, 3.0, belly, where: (x, _) => x >= 12);
    // Legs.
    c.rect(9, 27, 11, 29, greenDark);
    c.rect(14, 27, 16, 29, greenDark);
    // Neck and head (lower when tired).
    c.rect(15, 16 + low, 19, 21, green);
    final hy = 13.0 + low;
    c.ellipse(21.0, hy, 6.0, 5.0, green);
    c.rect(22, (hy - 1).round(), 28, (hy + 4).round(), green);
    c.set(28, (hy - 1).round(), 0);
    c.set(28, (hy + 4).round(), 0);
    c.rect(22, (hy + 3).round(), 27, (hy + 4).round(), greenDark);
    c.set(27, (hy).round(), 0xFF22461A);
    // Arms.
    c.rect(19, 21, 20, 21, greenDark);
    c.set(20, 22, greenDark);
    // Back spikes.
    for (final (x, y) in [
      (8, 18),
      (11, 17),
      (14, 16 + low),
      (17, (hy - 5).round()),
      (20, (hy - 6).round()),
    ]) {
      c.rect(x, y, x + 1, y + 1, spike);
    }
    final ey = (hy - 2).round();
    return Face(
      eyes: [(22, ey)],
      mouth: (27, (hy + 2).round()),
      side: true,
      ink: 0xFF1D3A15,
      headX: 21,
      headTop: (hy - 5).round(),
      headWidth: 12,
      food: Food.meat,
    );
  }
}

/// A pet drawn in Pixel Forge: its frames play for every mood, with the
/// mood shown by movement and extras.
class SpritePet extends PetSpecies {
  SpritePet(this.name, this.frames, this.width, this.height);

  @override
  final String name;
  final List<List<int>> frames;
  final int width, height;

  @override
  String get id => 'custom';
  @override
  String get about => 'Drawn in Pixel Forge.';
  @override
  int get outlineColor => 0;

  @override
  Face draw(PixelCanvas c, Mood mood, int frame) {
    final f = frames[frame % frames.length];
    // Fit into 26×24 at the bottom, nearest pixels.
    final scale = math.min(26 / width, 24 / height);
    final k = scale >= 1 ? scale.floorToDouble() : scale;
    final w = (width * k).round(), h = (height * k).round();
    final x0 = (32 - w) ~/ 2, y0 = 30 - h;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final v =
            f[math.min(height - 1, y * height ~/ h) * width +
                math.min(width - 1, x * width ~/ w)];
        if ((v >>> 24) >= 128) {
          c.set(x0 + x, y0 + y, v | 0xFF000000);
        }
      }
    }
    return Face(eyes: const [], headX: 16, headTop: y0, headWidth: w);
  }
}
