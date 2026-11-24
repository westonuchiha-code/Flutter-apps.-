import 'dart:math' as math;
import 'dart:typed_data';

/// Size of every pet frame (pets stand in the lower part, extras above).
const petSize = 32;

/// A small ARGB picture to draw pets on (0 = see-through).
class PixelCanvas {
  PixelCanvas([this.w = petSize, this.h = petSize]) : px = Uint32List(w * h);

  final int w, h;
  final Uint32List px;

  bool inside(int x, int y) => x >= 0 && y >= 0 && x < w && y < h;
  int get(int x, int y) => inside(x, y) ? px[y * w + x] : 0;
  void set(int x, int y, int c) {
    if (inside(x, y)) {
      px[y * w + x] = c;
    }
  }

  void rect(int x0, int y0, int x1, int y1, int c) {
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        set(x, y, c);
      }
    }
  }

  /// Filled ellipse centred on (cx, cy), radii rx, ry (pixel centres).
  void ellipse(
    double cx,
    double cy,
    double rx,
    double ry,
    int c, {
    bool Function(int x, int y)? where,
  }) {
    for (var y = (cy - ry).floor(); y <= (cy + ry).ceil(); y++) {
      for (var x = (cx - rx).floor(); x <= (cx + rx).ceil(); x++) {
        final dx = (x - cx) / rx, dy = (y - cy) / ry;
        if (dx * dx + dy * dy <= 1.0 && (where == null || where(x, y))) {
          set(x, y, c);
        }
      }
    }
  }

  void line(int x0, int y0, int x1, int y1, int c) {
    final n = math.max((x1 - x0).abs(), (y1 - y0).abs());
    for (var i = 0; i <= n; i++) {
      final t = n == 0 ? 0.0 : i / n;
      set((x0 + (x1 - x0) * t).round(), (y0 + (y1 - y0) * t).round(), c);
    }
  }

  void triangle(int ax, int ay, int bx, int by, int cx, int cy, int c) {
    final x0 = [ax, bx, cx].reduce(math.min),
        x1 = [ax, bx, cx].reduce(math.max);
    final y0 = [ay, by, cy].reduce(math.min),
        y1 = [ay, by, cy].reduce(math.max);
    num side(num px, num py, num qx, num qy, num rx, num ry) =>
        (px - rx) * (qy - ry) - (qx - rx) * (py - ry);
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final d1 = side(x, y, ax, ay, bx, by),
            d2 = side(x, y, bx, by, cx, cy),
            d3 = side(x, y, cx, cy, ax, ay);
        final neg = d1 < 0 || d2 < 0 || d3 < 0,
            pos = d1 > 0 || d2 > 0 || d3 > 0;
        if (!(neg && pos)) {
          set(x, y, c);
        }
      }
    }
  }

  /// Draws a little picture given as rows of characters; [colors] maps a
  /// character to a colour ('.' and ' ' are skipped).
  void grid(int x0, int y0, List<String> rows, Map<String, int> colors) {
    for (var y = 0; y < rows.length; y++) {
      for (var x = 0; x < rows[y].length; x++) {
        final c = colors[rows[y][x]];
        if (c != null) {
          set(x0 + x, y0 + y, c);
        }
      }
    }
  }

  /// Adds a 1-pixel outline of [color] around everything drawn so far.
  void outline(int color) {
    final copy = Uint32List.fromList(px);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (copy[y * w + x] != 0) {
          continue;
        }
        for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final xx = x + dx, yy = y + dy;
          if (xx >= 0 &&
              yy >= 0 &&
              xx < w &&
              yy < h &&
              copy[yy * w + xx] != 0) {
            px[y * w + x] = color;
            break;
          }
        }
      }
    }
  }

  /// Draws [other] on top (its see-through pixels skipped), moved by (dx, dy).
  void paste(PixelCanvas other, [int dx = 0, int dy = 0]) {
    for (var y = 0; y < other.h; y++) {
      for (var x = 0; x < other.w; x++) {
        final c = other.px[y * other.w + x];
        if (c != 0) {
          set(x + dx, y + dy, c);
        }
      }
    }
  }
}

/// [c] darker by [k] (0..1).
int shade(int c, double k) {
  int ch(int s) => (((c >> s) & 255) * (1 - k)).round().clamp(0, 255);
  return 0xFF000000 | (ch(16) << 16) | (ch(8) << 8) | ch(0);
}

/// [c] lighter by [k] (0..1).
int tint(int c, double k) {
  int ch(int s) {
    final v = (c >> s) & 255;
    return (v + (255 - v) * k).round().clamp(0, 255);
  }

  return 0xFF000000 | (ch(16) << 16) | (ch(8) << 8) | ch(0);
}
