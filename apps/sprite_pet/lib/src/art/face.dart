import '../mood.dart';
import 'canvas.dart';

enum EyeStyle {
  /// Dark eyes with a shine (animals, slimes).
  normal,

  /// Taller anime eyes.
  big,

  /// Glowing screen eyes (robots).
  led,

  /// Headlights (cars).
  lamp,
}

enum Food { apple, fish, riceBall, bone, battery, fuel, meat }

/// Where a species' face and head are, so moods and extras can be drawn
/// on any body.
class Face {
  const Face({
    required this.eyes,
    this.mouth,
    this.style = EyeStyle.normal,
    this.eyeColor = 0xFF1A1A2E,
    this.ink = 0xFF1A1A2E,
    required this.headX,
    required this.headTop,
    this.headWidth = 12,
    this.side = false,
    this.food = Food.apple,
  });

  /// Top-left corner of each eye's 2×3 area.
  final List<(int, int)> eyes;
  final (int, int)? mouth;
  final EyeStyle style;
  final int eyeColor, ink;

  /// Centre and top of the head (hats and umbrellas sit here).
  final int headX, headTop, headWidth;

  /// Seen from the side (one eye, mouth at the snout).
  final bool side;
  final Food food;
}

const _white = 0xFFFFFFFF;
const _pink = 0xFFFF6F91;
const _blue = 0xFF7FD4FF;

void drawEyes(PixelCanvas c, Face f, Mood mood, int frame) {
  for (final (x, y) in f.eyes) {
    switch (f.style) {
      case EyeStyle.normal || EyeStyle.big:
        _animalEye(c, x, y, f, mood, frame);
      case EyeStyle.led:
        _ledEye(c, x, y, f, mood, frame);
      case EyeStyle.lamp:
        _lampEye(c, x, y, f, mood, frame);
    }
  }
}

void _animalEye(PixelCanvas c, int x, int y, Face f, Mood mood, int frame) {
  final ink = f.ink;
  final tall = f.style == EyeStyle.big;
  void open() {
    c.rect(x, y, x + 1, y + (tall ? 2 : 1), ink);
    c.set(x, y, _white);
  }

  switch (mood) {
    case Mood.idle:
      if (frame == 3) {
        c.rect(x, y + 1, x + 1, y + 1, ink); // blink
      } else {
        open();
      }
    case Mood.happy || Mood.eating:
      c
        ..set(x - 1, y + 2, ink)
        ..set(x, y + 1, ink)
        ..set(x + 1, y + 1, ink)
        ..set(x + 2, y + 2, ink);
    case Mood.sleepy:
      c.rect(x - 1, y + 1, x + 2, y + 1, ink);
      c.rect(x, y + 2, x + 1, y + 2, ink);
    case Mood.asleep:
      c
        ..set(x - 1, y + 1, ink)
        ..set(x, y + 2, ink)
        ..set(x + 1, y + 2, ink)
        ..set(x + 2, y + 1, ink);
    case Mood.hungry:
      open();
      c.set(x + 1, y + (tall ? 2 : 1), _white);
    case Mood.bored:
      c.rect(x - 1, y + 1, x + 2, y + 1, ink);
      c.set(x + (frame < 2 ? 0 : 1), y + 2, ink);
    case Mood.scared:
      c.rect(x - 1, y, x + 2, y + 2, _white);
      c.set(x + (frame.isEven ? 0 : 1), y + 1, ink);
  }
}

void _ledEye(PixelCanvas c, int x, int y, Face f, Mood mood, int frame) {
  final on = f.eyeColor, dim = shade(f.eyeColor, 0.55);
  switch (mood) {
    case Mood.idle:
      c.rect(x, y, x + 2, y + (frame == 3 ? 0 : 1), on);
    case Mood.happy || Mood.eating:
      c
        ..set(x, y + 1, on)
        ..set(x + 1, y, on)
        ..set(x + 2, y + 1, on);
    case Mood.sleepy:
      c.rect(x, y + 1, x + 2, y + 1, dim);
    case Mood.asleep:
      c.rect(x, y + 1, x + 2, y + 1, shade(on, 0.75));
    case Mood.hungry:
      c.rect(x, y, x + 2, y + 1, frame.isEven ? on : tint(on, 0.5));
    case Mood.bored:
      c.rect(x, y + 1, x + 2, y + 1, on);
    case Mood.scared:
      c.set(x + 1, y + (frame.isEven ? 0 : 1), on);
  }
}

void _lampEye(PixelCanvas c, int x, int y, Face f, Mood mood, int frame) {
  final on = f.eyeColor, off = shade(f.eyeColor, 0.7);
  void lamp(int color, {bool shine = true}) {
    c.rect(x, y, x + 2, y + 2, color);
    if (shine) {
      c.set(x, y, _white);
    }
  }

  switch (mood) {
    case Mood.asleep:
      lamp(off, shine: false);
    case Mood.sleepy:
      lamp(on);
      c.rect(x, y, x + 2, y, off);
    case Mood.idle:
      lamp(frame == 3 ? off : on, shine: frame != 3);
    case Mood.happy || Mood.eating:
      lamp(tint(on, 0.4));
      c.set(x + 1, y + 1, _white);
    case Mood.hungry:
      lamp(frame.isEven ? on : off);
    case Mood.bored:
      lamp(on);
      c.rect(x, y, x + 2, y, off);
      c.rect(x, y + 1, x + 2, y + 1, off);
    case Mood.scared:
      lamp(frame.isEven ? _white : on);
  }
}

void drawMouth(PixelCanvas c, Face f, Mood mood, int frame) {
  final m = f.mouth;
  if (m == null) {
    return;
  }
  final (x, y) = m;
  final ink = f.style == EyeStyle.led ? f.eyeColor : f.ink;
  final dir = f.side ? -1 : 1; // side view: mouth runs back from the snout
  void flat(int n) {
    for (var i = 0; i < n; i++) {
      c.set(f.side ? x - i : x - n ~/ 2 + i, y, ink);
    }
  }

  switch (mood) {
    case Mood.idle:
      if (f.side) {
        flat(3);
      } else {
        c
          ..set(x - 1, y, ink)
          ..set(x, y + 1, ink)
          ..set(x + 1, y, ink);
      }
    case Mood.happy:
      if (f.side) {
        flat(3);
        c.set(x - 2, y - 1, ink);
      } else {
        c.rect(x - 1, y, x + 1, y + 1, ink);
        c.set(x, y + 1, _pink);
      }
    case Mood.eating:
      if (frame.isEven) {
        c.rect(f.side ? x - 1 : x - 1, y, f.side ? x : x + 1, y + 1, ink);
      } else {
        flat(3);
      }
    case Mood.hungry:
      c.rect(f.side ? x - 1 : x - 1, y, f.side ? x : x, y + 1, ink);
      if (frame >= 2) {
        c.set(x + (f.side ? 0 : 0), y + 2 + (frame - 2), _blue);
      }
    case Mood.sleepy || Mood.bored:
      flat(f.side ? 2 : 3);
    case Mood.asleep:
      c.set(x, y, ink);
      if (frame >= 2) {
        c.set(x + dir, y, ink);
      }
    case Mood.scared:
      for (var i = -2; i <= 2; i++) {
        c.set(x + i, y + (i.isEven ? 1 : 0), ink);
      }
  }
}

/// Small pictures (5×5) of each kind of food.
void drawFood(PixelCanvas c, Food food, int x, int y, {int bites = 0}) {
  final rows = switch (food) {
    Food.apple => ['..g..', '.rrr.', 'rrwrr', 'rrrrr', '.rrr.'],
    Food.fish => ['.....', 'b.bbb', 'bbbwb', 'b.bbb', '.....'],
    Food.riceBall => ['..w..', '.www.', 'wwwww', 'kkkkk', 'kkkkk'],
    Food.bone => ['o...o', '.ooo.', '..o..', '.ooo.', 'o...o'],
    Food.battery => ['.kk..', 'yyyy.', 'yggy.', 'yggy.', 'yyyy.'],
    Food.fuel => ['.rr..', 'rrrr.', 'rwwr.', 'rrrr.', 'rrrr.'],
    Food.meat => ['..ww.', '.rrww', 'rrrr.', 'rrrr.', '.rr..'],
  };
  final colors = {
    'r': food == Food.meat ? 0xFFB5523B : 0xFFE8383D,
    'g': 0xFF4CAF50,
    'w': _white,
    'b': 0xFF6FA8DC,
    'k': 0xFF2B3A2F,
    'y': 0xFFFFC83D,
    'o': 0xFFD9C29A,
  };
  final cut = [...rows];
  // Bites come out of the right side.
  for (var b = 0; b < bites; b++) {
    for (var r = 0; r < cut.length; r++) {
      final col = 4 - b;
      if (col >= 0) {
        cut[r] = '${cut[r].substring(0, col)}.${cut[r].substring(col + 1)}';
      }
    }
  }
  c.grid(x, y, cut, colors);
}

void drawZ(PixelCanvas c, int x, int y, int color) {
  c.grid(x, y, const ['###', '..#', '.#.', '#..', '###'], {'#': color});
}

void drawHeart(PixelCanvas c, int x, int y) {
  c.grid(x, y, const ['.#.#.', '#####', '.###.', '..#..'], {'#': _pink});
}

void drawDrop(PixelCanvas c, int x, int y) {
  c.grid(x, y, const ['.#.', '###', '###', '.#.'], {'#': _blue});
}

/// Bubble with a picture inside (thoughts).
void drawBubble(
  PixelCanvas c,
  int x,
  int y,
  void Function(int x, int y) inside,
) {
  const paper = 0xFFE4EEFF;
  c.rect(x, y, x + 8, y + 6, paper);
  c.set(x, y, 0);
  c.set(x + 8, y, 0);
  c.set(x, y + 6, 0);
  c.set(x + 8, y + 6, 0);
  c.set(x + 1, y + 8, paper);
  c.set(x - 1, y + 9, paper);
  inside(x + 2, y + 1);
}

void drawDots(PixelCanvas c, int x, int y, int n, int ink) {
  for (var i = 0; i < n; i++) {
    c.set(x + i * 2, y, ink);
  }
}

void drawBolt(PixelCanvas c, int x, int y) {
  c.grid(
    x,
    y,
    const ['..##', '.##.', '####', '..#.', '.#..', '#...'],
    {'#': 0xFFFFE04D},
  );
}

void drawUmbrella(PixelCanvas c, int cx, int top) {
  const red = 0xFFE8383D, yellow = 0xFFFFC83D, stick = 0xFF5A3E2B;
  for (var i = 0; i < 6; i++) {
    final w = [3, 6, 8, 9, 9, 9][i];
    for (var dx = -w; dx <= w; dx++) {
      c.set(cx + dx, top + i, ((dx + 30) ~/ 3).isEven ? red : yellow);
    }
  }
  // Held at the side, clear of the face.
  for (var y = top + 6; y < top + 15; y++) {
    c.set(cx + 8, y, stick);
  }
  c.set(cx + 7, top + 15, stick);
}

void drawBeanie(PixelCanvas c, int cx, int top, int width) {
  const red = 0xFFD64545, white = 0xFFF5F5F5;
  final half = (width / 2).ceil();
  c.ellipse(cx.toDouble(), top + 3.0, half.toDouble(), 3.5, red);
  c.rect(cx - half, top + 4, cx + half, top + 5, white);
  c.rect(cx - 1, top - 2, cx + 1, top, white);
}

void drawShades(PixelCanvas c, Face f) {
  if (f.eyes.isEmpty || f.style == EyeStyle.lamp) {
    return;
  }
  const black = 0xFF101010;
  final xs = [for (final e in f.eyes) e.$1];
  final y = f.eyes.first.$2;
  final x0 = xs.reduce((a, b) => a < b ? a : b) - 1,
      x1 = xs.reduce((a, b) => a > b ? a : b) + 2;
  c.rect(x0, y, x1, y + 1, black);
  for (final x in xs) {
    c.rect(x - 1, y + 2, x + 2, y + 2, black);
    c.set(x, y, 0xFF6E7CFF);
  }
}
