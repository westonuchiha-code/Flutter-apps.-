import 'dart:math' as math;
import 'dart:collection';
import 'dart:typed_data';

/// Drawing on one cel ([pixels], [w]×[h], ARGB).
class Canvas {
  Canvas(
    this.pixels,
    this.w,
    this.h, {
    this.mirrorX = false,
    this.mirrorY = false,
    this.mask,
  });

  final Uint32List pixels;
  final int w, h;

  /// Mirror drawing around the vertical / horizontal centre line.
  bool mirrorX, mirrorY;

  /// When set, only pixels inside it can change (the selection).
  final Rect? mask;

  bool _ok(int x, int y) =>
      x >= 0 && y >= 0 && x < w && y < h && (mask?.contains(x, y) ?? true);

  void _put(int x, int y, int c) {
    if (_ok(x, y)) pixels[y * w + x] = c;
  }

  /// One pixel (and its mirrors).
  void plot(int x, int y, int c) {
    _put(x, y, c);
    if (mirrorX) _put(w - 1 - x, y, c);
    if (mirrorY) _put(x, h - 1 - y, c);
    if (mirrorX && mirrorY) _put(w - 1 - x, h - 1 - y, c);
  }

  int get(int x, int y) =>
      x >= 0 && y >= 0 && x < w && y < h ? pixels[y * w + x] : 0;

  /// A square brush of [size] centred on (x, y).
  void brush(int x, int y, int c, {int size = 1}) {
    final o = (size - 1) ~/ 2;
    for (var dy = 0; dy < size; dy++) {
      for (var dx = 0; dx < size; dx++) {
        plot(x - o + dx, y - o + dy, c);
      }
    }
  }

  /// Bresenham line.
  void line(int x0, int y0, int x1, int y1, int c, {int size = 1}) {
    var dx = (x1 - x0).abs(), dy = -(y1 - y0).abs();
    final sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
    var err = dx + dy;
    var x = x0, y = y0;
    while (true) {
      brush(x, y, c, size: size);
      if (x == x1 && y == y1) break;
      final e2 = 2 * err;
      if (e2 >= dy) {
        err += dy;
        x += sx;
      }
      if (e2 <= dx) {
        err += dx;
        y += sy;
      }
    }
  }

  void rect(int x0, int y0, int x1, int y1, int c, {bool filled = false}) {
    final l = x0 < x1 ? x0 : x1, r = x0 < x1 ? x1 : x0;
    final t = y0 < y1 ? y0 : y1, b = y0 < y1 ? y1 : y0;
    for (var y = t; y <= b; y++) {
      for (var x = l; x <= r; x++) {
        if (filled || x == l || x == r || y == t || y == b) plot(x, y, c);
      }
    }
  }

  /// Ellipse inside the box (x0,y0)-(x1,y1).
  void ellipse(int x0, int y0, int x1, int y1, int c, {bool filled = false}) {
    final l = math.min(x0, x1), r = math.max(x0, x1);
    final t = math.min(y0, y1), b = math.max(y0, y1);
    if (r - l < 2 || b - t < 2) {
      rect(l, t, r, b, c, filled: true);
      return;
    }
    // Pixel-centre test: pixel (x, y) is inside when its centre is inside
    // the ellipse that exactly covers the box.
    final a = (r - l + 1) / 2, bb = (b - t + 1) / 2;
    final cx = l + a, cy = t + bb;
    final xl = <int>[], xr = <int>[];
    for (var y = t; y <= b; y++) {
      final dy = (y + 0.5 - cy) / bb;
      final half = a * math.sqrt(math.max(0, 1 - dy * dy));
      xl.add((cx - half - 0.5).ceil().clamp(l, r));
      xr.add((cx + half - 0.5).floor().clamp(l, r));
    }
    for (var i = 0; i <= b - t; i++) {
      final y = t + i;
      if (filled || i == 0 || i == b - t) {
        for (var x = xl[i]; x <= xr[i]; x++) {
          plot(x, y, c);
        }
        continue;
      }
      // Join to the rows above and below so steep sides have no gaps.
      var leftEnd = xl[i], rightStart = xr[i];
      for (final n in [i - 1, i + 1]) {
        leftEnd = math.max(leftEnd, xl[n] - 1);
        rightStart = math.min(rightStart, xr[n] + 1);
      }
      for (var x = xl[i]; x <= math.min(leftEnd, xr[i]); x++) {
        plot(x, y, c);
      }
      for (var x = math.max(rightStart, xl[i]); x <= xr[i]; x++) {
        plot(x, y, c);
      }
    }
  }

  /// Fills the connected area of the colour at (x, y) (4-way). With
  /// [global], every pixel of that colour changes instead.
  void fill(int x, int y, int c, {bool global = false}) {
    if (!_ok(x, y)) return;
    final target = pixels[y * w + x];
    if (target == c) return;
    if (global) {
      for (var p = 0; p < pixels.length; p++) {
        if (pixels[p] == target && _ok(p % w, p ~/ w)) pixels[p] = c;
      }
      return;
    }
    final q = Queue<int>()..add(y * w + x);
    while (q.isNotEmpty) {
      final p = q.removeFirst();
      final px = p % w, py = p ~/ w;
      if (pixels[p] != target || !_ok(px, py)) continue;
      // Span fill: walk left and right, queue the rows above and below.
      var l = px, r = px;
      while (l > 0 && pixels[p - (px - l) - 1] == target && _ok(l - 1, py)) {
        l--;
      }
      while (r < w - 1 &&
          pixels[p + (r - px) + 1] == target &&
          _ok(r + 1, py)) {
        r++;
      }
      for (var i = l; i <= r; i++) {
        pixels[py * w + i] = c;
        if (py > 0 && pixels[(py - 1) * w + i] == target) {
          q.add((py - 1) * w + i);
        }
        if (py < h - 1 && pixels[(py + 1) * w + i] == target) {
          q.add((py + 1) * w + i);
        }
      }
    }
  }
}

/// A rectangle of pixels (inclusive left/top, exclusive right/bottom).
class Rect {
  const Rect(this.left, this.top, this.right, this.bottom);

  factory Rect.fromPoints(int x0, int y0, int x1, int y1) => Rect(
    x0 < x1 ? x0 : x1,
    y0 < y1 ? y0 : y1,
    (x0 < x1 ? x1 : x0) + 1,
    (y0 < y1 ? y1 : y0) + 1,
  );

  final int left, top, right, bottom;
  int get width => right - left;
  int get height => bottom - top;
  bool get isEmpty => width <= 0 || height <= 0;
  bool contains(int x, int y) =>
      x >= left && x < right && y >= top && y < bottom;

  Rect clampTo(int w, int h) => Rect(
    left.clamp(0, w),
    top.clamp(0, h),
    right.clamp(0, w),
    bottom.clamp(0, h),
  );

  Rect shift(int dx, int dy) =>
      Rect(left + dx, top + dy, right + dx, bottom + dy);

  @override
  bool operator ==(Object other) =>
      other is Rect &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);
}

/// Pixels lifted out of a cel (for moving, flipping, rotating, pasting).
class PixelPatch {
  PixelPatch(this.w, this.h, this.pixels);

  final int w, h;
  final Uint32List pixels;

  factory PixelPatch.copy(Uint32List src, int srcW, Rect r) {
    final p = Uint32List(r.width * r.height);
    for (var y = 0; y < r.height; y++) {
      for (var x = 0; x < r.width; x++) {
        p[y * r.width + x] = src[(r.top + y) * srcW + r.left + x];
      }
    }
    return PixelPatch(r.width, r.height, p);
  }

  PixelPatch flippedX() => PixelPatch(
    w,
    h,
    Uint32List.fromList([
      for (var y = 0; y < h; y++)
        for (var x = 0; x < w; x++) pixels[y * w + (w - 1 - x)],
    ]),
  );

  PixelPatch flippedY() => PixelPatch(
    w,
    h,
    Uint32List.fromList([
      for (var y = 0; y < h; y++)
        for (var x = 0; x < w; x++) pixels[(h - 1 - y) * w + x],
    ]),
  );

  /// 90° clockwise.
  PixelPatch rotated() => PixelPatch(
    h,
    w,
    Uint32List.fromList([
      for (var y = 0; y < w; y++)
        for (var x = 0; x < h; x++) pixels[(h - 1 - x) * w + y],
    ]),
  );

  /// Draws onto [dst] at (x, y); transparent pixels are skipped unless
  /// [opaque].
  void stamp(
    Uint32List dst,
    int dstW,
    int dstH,
    int x,
    int y, {
    bool opaque = false,
  }) {
    for (var py = 0; py < h; py++) {
      final ty = y + py;
      if (ty < 0 || ty >= dstH) continue;
      for (var px = 0; px < w; px++) {
        final tx = x + px;
        if (tx < 0 || tx >= dstW) continue;
        final v = pixels[py * w + px];
        if (opaque || v != 0) dst[ty * dstW + tx] = v;
      }
    }
  }
}

/// Clears [r] in [cel].
void clearRect(Uint32List cel, int w, Rect r) {
  for (var y = r.top; y < r.bottom; y++) {
    cel.fillRange(y * w + r.left, y * w + r.right, 0);
  }
}
