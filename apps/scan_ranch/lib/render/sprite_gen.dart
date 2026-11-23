// Procedural pixel-art sprites.
//
// Each creature is assembled on a small pixel grid from shaded parts
// (body, head, ears, horns, tail, wings, legs, face) chosen by its genome,
// then finished with pixel-art passes: a coloured outline, inner lines where
// parts overlap, and hue-shifted shading (cool shadows, warm highlights).
// Every pose (walk cycle, blink, happy, eating) is a separate frame.
import 'dart:math' as math;
import 'dart:typed_data';

import '../model/genome.dart';

/// Sprite size in pixels (facing right; flipped when walking left).
const spriteW = 40;
const spriteH = 36;

/// Pixel materials (resolved to colours by [SpritePalette]).
enum Mat {
  none,
  skinDark,
  skin,
  skinLight,
  belly,
  bellyDark,
  accentDark,
  accent,
  accentLight,
  eyeDark,
  eyeShine,
  eyeIris,
  mouth,
  tooth,
  beak,
  beakDark,
  cheek,
  wingGlass,
  wingVein,
  leaf,
  leafDark,
  flame,
  flameCore,
  innerLine,
  outline,
}

enum Face { normal, blink, happy, eat }

/// One animation frame's pose.
class SpritePose {
  const SpritePose({this.step = 0, this.bob = 0, this.face = Face.normal});

  /// Walk cycle: 0 = standing, 1 and 2 = alternating steps.
  final int step;

  /// 0 or 1 pixel body bounce.
  final int bob;
  final Face face;
}

/// The pixel grid of one frame: a material per pixel.
class SpriteGrid {
  SpriteGrid()
    : mats = Uint8List(spriteW * spriteH),
      parts = Uint8List(spriteW * spriteH);

  final Uint8List mats;

  /// Which part (z order) painted each pixel; 0 = empty.
  final Uint8List parts;

  Mat at(int x, int y) => x < 0 || y < 0 || x >= spriteW || y >= spriteH
      ? Mat.none
      : Mat.values[mats[y * spriteW + x]];

  int partAt(int x, int y) => x < 0 || y < 0 || x >= spriteW || y >= spriteH
      ? 0
      : parts[y * spriteW + x];

  void set(int x, int y, Mat m, int part) {
    if (x < 0 || y < 0 || x >= spriteW || y >= spriteH) return;
    mats[y * spriteW + x] = m.index;
    parts[y * spriteW + x] = part;
  }
}

/// Shading tone for a pixel inside a shape, light from the upper left.
enum _Tone { dark, mid, light }

/// Builds sprite frames for one creature.
class SpriteBuilder {
  SpriteBuilder(this.look) : g = look.genome;

  final Appearance look;
  final Genome g;

  late SpriteGrid _grid;
  int _part = 0;

  // Material sets for shaded fills.
  static const _skin = (Mat.skinDark, Mat.skin, Mat.skinLight);
  static const _accent = (Mat.accentDark, Mat.accent, Mat.accentLight);
  static const _belly = (Mat.bellyDark, Mat.belly, Mat.belly);

  SpriteGrid build(SpritePose pose) {
    _grid = SpriteGrid();
    _part = 0;
    final layout = _Layout(g, look.size, pose);
    switch (g.plan) {
      case BodyPlan.blob:
        _blob(layout, pose);
      case BodyPlan.biped:
        _biped(layout, pose);
      case BodyPlan.quadruped:
        _quadruped(layout, pose);
      case BodyPlan.avian:
        _avian(layout, pose);
      case BodyPlan.insect:
        _insect(layout, pose);
      case BodyPlan.serpent:
        _serpent(layout, pose);
      case BodyPlan.floater:
        _floater(layout, pose);
    }
    _innerLines();
    _outline();
    return _grid;
  }

  // ---------------------------------------------------------------------------
  // Primitive painters
  // ---------------------------------------------------------------------------

  int _newPart() => ++_part;

  _Tone _tone(double nx, double ny) {
    // nx, ny in -1..1 across the shape. Light from upper-left.
    final d = nx * 0.45 + ny * 0.8;
    if (d > 0.42) return _Tone.dark;
    if (d < -0.55 && nx * nx + ny * ny < 0.75) return _Tone.light;
    return _Tone.mid;
  }

  Mat _pick((Mat, Mat, Mat) set, _Tone t) => switch (t) {
    _Tone.dark => set.$1,
    _Tone.mid => set.$2,
    _Tone.light => set.$3,
  };

  /// Shaded ellipse.
  void _ellipse(
    double cx,
    double cy,
    double rx,
    double ry,
    (Mat, Mat, Mat) mats, {
    int? part,
    bool flat = false,
  }) {
    final p = part ?? _newPart();
    for (var y = (cy - ry).floor(); y <= (cy + ry).ceil(); y++) {
      for (var x = (cx - rx).floor(); x <= (cx + rx).ceil(); x++) {
        final nx = (x + 0.5 - cx) / rx;
        final ny = (y + 0.5 - cy) / ry;
        if (nx * nx + ny * ny > 1) continue;
        _grid.set(x, y, flat ? mats.$2 : _pick(mats, _tone(nx, ny)), p);
      }
    }
  }

  /// Shaded convex polygon (points in pixel coordinates).
  void _polygon(List<(double, double)> pts, (Mat, Mat, Mat) mats, {int? part}) {
    final p = part ?? _newPart();
    final minX = pts.map((e) => e.$1).reduce(math.min).floor();
    final maxX = pts.map((e) => e.$1).reduce(math.max).ceil();
    final minY = pts.map((e) => e.$2).reduce(math.min).floor();
    final maxY = pts.map((e) => e.$2).reduce(math.max).ceil();
    final cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
    final rx = math.max(1, (maxX - minX) / 2),
        ry = math.max(1, (maxY - minY) / 2);
    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        if (!_inside(pts, x + 0.5, y + 0.5)) continue;
        _grid.set(
          x,
          y,
          _pick(mats, _tone((x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry)),
          p,
        );
      }
    }
  }

  static bool _inside(List<(double, double)> pts, double x, double y) {
    var inside = false;
    for (var i = 0, j = pts.length - 1; i < pts.length; j = i++) {
      final (xi, yi) = pts[i];
      final (xj, yj) = pts[j];
      if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
        inside = !inside;
      }
    }
    return inside;
  }

  /// Rounded vertical bar (legs).
  void _bar(
    double x,
    double top,
    double w,
    double h,
    (Mat, Mat, Mat) mats, {
    int? part,
  }) {
    final p = part ?? _newPart();
    for (var y = top.round(); y < (top + h).round(); y++) {
      for (var xx = x.round(); xx < (x + w).round(); xx++) {
        final nx = ((xx + 0.5) - (x + w / 2)) / (w / 2);
        _grid.set(xx, y, nx > 0.2 ? mats.$1 : mats.$2, p);
      }
    }
  }

  void _px(int x, int y, Mat m, {int? part}) =>
      _grid.set(x, y, m, part ?? _part);

  // ---------------------------------------------------------------------------
  // Finishing passes
  // ---------------------------------------------------------------------------

  /// Darkens a part's edge where a later (front) part overlaps it.
  void _innerLines() {
    final copy = Uint8List.fromList(_grid.mats);
    for (var y = 0; y < spriteH; y++) {
      for (var x = 0; x < spriteW; x++) {
        final p = _grid.partAt(x, y);
        if (p == 0) continue;
        final m = Mat.values[_grid.mats[y * spriteW + x]];
        if (m == Mat.eyeDark ||
            m == Mat.eyeShine ||
            m == Mat.mouth ||
            m == Mat.tooth) {
          continue;
        }
        for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final q = _grid.partAt(x + dx, y + dy);
          if (q > p && _isBodyMat(_grid.at(x + dx, y + dy))) {
            copy[y * spriteW + x] = Mat.innerLine.index;
            break;
          }
        }
      }
    }
    _grid.mats.setAll(0, copy);
  }

  static bool _isBodyMat(Mat m) =>
      m != Mat.eyeDark &&
      m != Mat.eyeShine &&
      m != Mat.eyeIris &&
      m != Mat.mouth &&
      m != Mat.tooth &&
      m != Mat.cheek;

  /// One-pixel coloured outline around the whole sprite.
  void _outline() {
    final add = <int>[];
    for (var y = 0; y < spriteH; y++) {
      for (var x = 0; x < spriteW; x++) {
        if (_grid.partAt(x, y) != 0) continue;
        for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          if (_grid.partAt(x + dx, y + dy) != 0) {
            add.add(y * spriteW + x);
            break;
          }
        }
      }
    }
    for (final i in add) {
      _grid.mats[i] = Mat.outline.index;
      _grid.parts[i] = 255;
    }
  }

  // ---------------------------------------------------------------------------
  // Parts
  // ---------------------------------------------------------------------------

  (Mat, Mat, Mat) get _tipMats => g.pattern == Pattern.tips ? _accent : _skin;

  void _patternOnPart(int part, double cx, double cy, double rx, double ry) {
    final r = SeededRandom(hashString('px:${g.code}'));
    switch (g.pattern) {
      case Pattern.spots:
        final n = g.patternCount + 1;
        for (var i = 0; i < n; i++) {
          final sx = cx + rx * r.range(-0.7, 0.6);
          final sy = cy + ry * r.range(-0.75, 0.2);
          final big = r.chance(0.5);
          for (final (dx, dy)
              in big
                  ? const [(0, 0), (1, 0), (0, 1), (1, 1)]
                  : const [(0, 0)]) {
            final x = (sx + dx).round(), y = (sy + dy).round();
            if (_grid.partAt(x, y) == part && _grid.at(x, y) != Mat.belly) {
              _px(x, y, Mat.accent, part: part);
            }
          }
        }
      case Pattern.stripes:
        for (var i = 0; i < g.patternCount; i++) {
          final x0 = (cx - rx + (i + 1) * 2 * rx / (g.patternCount + 1))
              .round();
          for (var y = (cy - ry).round(); y <= (cy + ry * 0.1).round(); y++) {
            for (final x in [x0, x0 + 1]) {
              if (_grid.partAt(x, y) == part && _grid.at(x, y) != Mat.belly) {
                _px(x, y, Mat.accentDark, part: part);
              }
            }
          }
        }
      default:
        break;
    }
  }

  void _bellyPatch(int part, double cx, double cy, double rx, double ry) {
    final scale = g.pattern == Pattern.belly ? 0.8 : 0.6;
    final bx = cx + rx * 0.2, by = cy + ry * 0.35;
    for (
      var y = (by - ry * scale).floor();
      y <= (by + ry * scale).ceil();
      y++
    ) {
      for (
        var x = (bx - rx * scale).floor();
        x <= (bx + rx * scale).ceil();
        x++
      ) {
        final nx = (x + 0.5 - bx) / (rx * scale);
        final ny = (y + 0.5 - by) / (ry * scale);
        if (nx * nx + ny * ny > 1) continue;
        if (_grid.partAt(x, y) != part) continue;
        final m = _grid.at(x, y);
        if (m == Mat.skin || m == Mat.skinLight || m == Mat.skinDark) {
          _px(
            x,
            y,
            ny > 0.45 || nx > 0.6 ? Mat.bellyDark : Mat.belly,
            part: part,
          );
        }
      }
    }
  }

  void _legs(
    List<double> xs,
    double hipY,
    double footY,
    SpritePose pose, {
    bool thin = false,
    bool back = false,
  }) {
    for (var i = 0; i < xs.length; i++) {
      // Alternate legs lift on steps 1 and 2.
      final lifted =
          pose.step != 0 && (i.isEven ? pose.step == 1 : pose.step == 2);
      final lift = lifted ? 1.0 : 0.0;
      final x = xs[i] + (pose.step == 0 ? 0 : (lifted ? 1 : -0.5));
      final part = _newPart();
      if (thin) {
        for (var y = hipY.round(); y <= (footY - lift).round(); y++) {
          _px(x.round(), y, back ? Mat.beakDark : Mat.beak, part: part);
        }
        _px(x.round() + 1, (footY - lift).round(), Mat.beak, part: part);
        _px(x.round() - 1, (footY - lift).round(), Mat.beakDark, part: part);
      } else {
        final mats = back ? (Mat.skinDark, Mat.skinDark, Mat.skinDark) : _skin;
        _bar(x - 1.5, hipY, 3, footY - hipY + 1 - lift, mats, part: part);
        // Foot.
        final fy = (footY - lift).round();
        final foot = back
            ? Mat.skinDark
            : (g.pattern == Pattern.tips ? Mat.accent : Mat.skinDark);
        for (var dx = -1; dx <= 2; dx++) {
          _px((x - 0.5 + dx).round(), fy, foot, part: part);
        }
      }
    }
  }

  void _ears(double hx, double hy, double r) {
    void ear(double x, bool back) {
      final top = hy - r - 4;
      final mats = back ? (Mat.skinDark, Mat.skinDark, Mat.skin) : _tipMats;
      switch (g.ears) {
        case Ears.pointy:
          _polygon([
            (x - 2.2, hy - r + 2.5),
            (x + 0.3, top - 0.5),
            (x + 2.6, hy - r + 2.5),
          ], mats);
          if (!back) {
            _px(x.round(), (top + 3).round(), Mat.belly);
            _px(x.round(), (top + 4).round(), Mat.belly);
          }
        case Ears.round:
          _ellipse(x, hy - r + 0.5, 2.6, 2.6, mats);
          if (!back) _px(x.round(), (hy - r + 0.5).round(), Mat.belly);
        case Ears.floppy:
          _ellipse(x - 1.5, hy - r * 0.35, 2, 3.5, mats);
        case Ears.fins:
          _polygon([
            (x - 2.5, hy - r + 2),
            (x - 1, top),
            (x + 0.5, top + 2),
            (x + 2, top - 0.5),
            (x + 2.6, hy - r + 2),
          ], back ? (Mat.accentDark, Mat.accentDark, Mat.accent) : _accent);
        case Ears.none:
          break;
      }
    }

    if (g.ears == Ears.none) return;
    ear(hx - r * 0.45, true);
    ear(hx + r * 0.15, false);
  }

  void _horns(double hx, double hy, double r) {
    final top = hy - r;
    switch (g.horns) {
      case Horns.none:
        break;
      case Horns.single:
        _polygon([
          (hx - 1.2, top + 1.5),
          (hx + 1.5, top - 4.5),
          (hx + 2.2, top + 1.5),
        ], _accent);
      case Horns.pair:
        _polygon(
          [
            (hx - r * 0.6 - 1, top + 2),
            (hx - r * 0.6 - 2.5, top - 3),
            (hx - r * 0.6 + 1, top + 1.5),
          ],
          (Mat.accentDark, Mat.accentDark, Mat.accent),
        );
        _polygon([
          (hx + r * 0.35 - 1, top + 1.5),
          (hx + r * 0.35 + 2.5, top - 3.5),
          (hx + r * 0.35 + 1.5, top + 2),
        ], _accent);
      case Horns.curled:
        final p = _newPart();
        for (final (dx, dy) in const [
          (0, 0),
          (1, -1),
          (2, -2),
          (3, -2),
          (4, -1),
          (4, 0),
          (3, 1),
        ]) {
          _px(
            (hx - 2 + dx).round(),
            (top + 1 + dy).round(),
            Mat.accent,
            part: p,
          );
          _px(
            (hx - 2 + dx).round(),
            (top + 2 + dy).round(),
            Mat.accentDark,
            part: p,
          );
        }
      case Horns.antennae:
        final p = _newPart();
        for (final (bx, lean) in [(hx - 1.0, -1.0), (hx + 2.0, 1.0)]) {
          for (var i = 0; i < 4; i++) {
            _px(
              (bx + lean * i * 0.5).round(),
              (top - i).round(),
              Mat.skinDark,
              part: p,
            );
          }
          _ellipse(bx + lean * 2.2, top - 4.5, 1.3, 1.3, _accent, part: p);
        }
      case Horns.sprout:
        final p = _newPart();
        _px(hx.round(), (top - 0).round(), Mat.leafDark, part: p);
        _px(hx.round(), (top - 1).round(), Mat.leafDark, part: p);
        for (final (dx, dy) in const [
          (-1, -2),
          (-2, -2),
          (-2, -3),
          (-1, -3),
          (1, -2),
          (2, -3),
          (1, -3),
          (2, -2),
          (3, -3),
        ]) {
          _px(
            (hx + dx).round(),
            (top + dy).round(),
            dy == -3 ? Mat.leaf : Mat.leafDark,
            part: p,
          );
        }
    }
  }

  void _tail(double x, double y, SpritePose pose) {
    final wag = pose.step == 2 || pose.bob == 1 ? -1.0 : 0.0;
    switch (g.tail) {
      case Tail.none:
        break;
      case Tail.thin:
        final p = _newPart();
        final pts = [(0, 0), (-1, -1), (-2, -2), (-3, -3), (-3, -4), (-3, -5)];
        for (final (dx, dy) in pts) {
          _px((x + dx + wag).round(), (y + dy).round(), Mat.skin, part: p);
          _px(
            (x + dx + wag).round(),
            (y + dy + 1).round(),
            Mat.skinDark,
            part: p,
          );
        }
        _ellipse(x - 3 + wag, y - 6.5, 1.8, 1.8, _tipMats, part: p);
      case Tail.fluffy:
        _ellipse(x - 2 + wag, y - 2, 3.5, 3.2, _skin);
        _ellipse(x - 4 + wag, y - 4.5, 2.4, 2.4, _tipMats);
      case Tail.flame:
        final p = _newPart();
        final flick = pose.bob == 1 || pose.step == 1 ? 1.0 : 0.0;
        _polygon(
          [
            (x, y + 1),
            (x - 3, y - 1),
            (x - 5 - flick, y - 7),
            (x - 2, y - 4),
            (x - 1, y - 6 - flick),
            (x + 0.5, y - 2),
          ],
          (Mat.flame, Mat.flame, Mat.flameCore),
          part: p,
        );
        _px((x - 2).round(), (y - 2).round(), Mat.flameCore, part: p);
      case Tail.leaf:
        final p = _newPart();
        _polygon(
          [(x, y), (x - 3, y - 3 + wag), (x - 7, y - 2 + wag), (x - 4, y + 1)],
          (Mat.leafDark, Mat.leaf, Mat.leaf),
          part: p,
        );
      case Tail.spiked:
        final p = _newPart();
        _polygon(
          [(x + 1, y - 1), (x - 5, y - 1 + wag), (x + 1, y + 2)],
          _skin,
          part: p,
        );
        for (final dx in [-1.0, -3.0]) {
          _polygon(
            [
              (x + dx - 1, y - 1 + wag * 0.5),
              (x + dx, y - 4 + wag),
              (x + dx + 1, y - 1),
            ],
            _accent,
            part: p,
          );
        }
      case Tail.fin:
        _polygon([
          (x + 1, y),
          (x - 5, y - 4 + wag),
          (x - 4, y + 1),
          (x - 5, y + 4 + wag),
        ], _accent);
    }
  }

  void _wing(double x, double y, SpritePose pose, {required bool back}) {
    final up = pose.step == 1 || pose.bob == 1;
    final dy = up ? -2.0 : 0.0;
    switch (g.wings) {
      case Wings.none:
        break;
      case Wings.feather:
        final mats = back ? (Mat.skinDark, Mat.skinDark, Mat.skin) : _skin;
        _polygon([
          (x + 2, y),
          (x - 3, y - 3 + dy),
          (x - 7, y - 1 + dy),
          (x - 6, y + 2),
          (x - 3, y + 4),
        ], mats);
        if (!back) {
          for (var i = 0; i < 3; i++) {
            _px((x - 5 + i * 2).round(), (y + 2).round(), Mat.skinDark);
          }
        }
      case Wings.bat:
        final mats = back
            ? (Mat.accentDark, Mat.accentDark, Mat.accent)
            : _accent;
        _polygon([
          (x + 1, y),
          (x - 2, y - 5 + dy),
          (x - 8, y - 4 + dy),
          (x - 6, y - 1),
          (x - 7, y + 2),
          (x - 3, y + 1),
        ], mats);
      case Wings.bug:
        final p = _newPart();
        const glass = (Mat.wingGlass, Mat.wingGlass, Mat.wingGlass);
        _ellipse(x - 3, y - 3 + dy, 4.5, 2.5, glass, part: p, flat: true);
        for (var i = -3; i <= 2; i++) {
          _px((x - 3 + i).round(), (y - 3 + dy).round(), Mat.wingVein, part: p);
        }
    }
  }

  /// Eyes and mouth. [fx], [fy]: centre of the face; [r]: face radius.
  void _face(
    double fx,
    double fy,
    double r,
    SpritePose pose, {
    bool beak = false,
  }) {
    final part = _newPart();
    // Big, shiny matching eyes set close together (cute "chibi" face).
    final w = r >= 7.5 ? 3 : 2;
    final h = w + 1;
    final gap = w == 3 ? 2 : 2;
    final eyeX = fx.round() + 1; // left edge of the right-hand eye
    final eyeY = (fy - h / 2).round() - 1; // top of the eyes
    final eyes = <(int, int, int)>[
      if (g.eyes == 1) (eyeX - 1, eyeY, w + 1),
      if (g.eyes >= 2) ...[(eyeX, eyeY, w), (eyeX - w - gap, eyeY, w)],
      if (g.eyes == 3) (eyeX - w ~/ 2 - 1, eyeY - h - 1, w),
    ];
    for (final (ex, ey, ew) in eyes) {
      switch (pose.face) {
        case Face.blink:
          for (var xx = -1; xx <= ew; xx++) {
            _px(ex + xx, ey + h - 1, Mat.eyeDark, part: part);
          }
        case Face.happy:
          // ^ shaped closed eyes.
          _px(ex - 1, ey + 2, Mat.eyeDark, part: part);
          for (var xx = 0; xx < ew; xx++) {
            _px(ex + xx, ey + 1, Mat.eyeDark, part: part);
          }
          _px(ex + ew, ey + 2, Mat.eyeDark, part: part);
        default:
          for (var yy = 0; yy < h; yy++) {
            for (var xx = 0; xx < ew; xx++) {
              final iris =
                  g.eyeStyle == EyeStyle.sparkle && yy >= h - 2 && ew > 1;
              _px(
                ex + xx,
                ey + yy,
                iris ? Mat.eyeIris : Mat.eyeDark,
                part: part,
              );
            }
          }
          // Highlights: top-left, plus a small low one on big eyes.
          _px(ex, ey, Mat.eyeShine, part: part);
          if (ew >= 3) _px(ex + 2, ey + h - 2, Mat.eyeShine, part: part);
          if (ew >= 2 && h >= 4) _px(ex + 1, ey, Mat.eyeShine, part: part);
          if (g.eyeStyle == EyeStyle.sleepy) {
            for (var xx = 0; xx < ew; xx++) {
              _px(ex + xx, ey, Mat.skinDark, part: part);
            }
          }
          if (g.eyeStyle == EyeStyle.fierce) {
            for (var xx = -1; xx <= ew; xx++) {
              _px(ex + xx, ey - 1 + (xx + 1) ~/ 2, Mat.eyeDark, part: part);
            }
          }
      }
    }

    // Rosy cheeks when happy.
    if (pose.face == Face.happy) {
      _px(eyeX + w + 1, eyeY + h, Mat.cheek, part: part);
      _px(eyeX - w - gap - 2, eyeY + h, Mat.cheek, part: part);
    }

    final mx = eyeX - gap ~/ 2 - 1 + (g.eyes == 1 ? 1 : 0), my = eyeY + h + 1;
    if (beak) {
      final bp = _newPart();
      final open = pose.face == Face.eat;
      for (var i = 0; i < 4; i++) {
        _px((fx + r - 1 + i).round(), (fy - 1).round(), Mat.beak, part: bp);
        if (i < 3)
          _px(
            (fx + r - 1 + i).round(),
            (fy).round(),
            open ? Mat.mouth : Mat.beakDark,
            part: bp,
          );
        if (i < 2)
          _px(
            (fx + r - 1 + i).round(),
            (fy + 1).round(),
            Mat.beakDark,
            part: bp,
          );
      }
      return;
    }
    if (pose.face == Face.eat) {
      _px(mx, my, Mat.mouth, part: part);
      _px(mx + 1, my, Mat.mouth, part: part);
      _px(mx, my + 1, Mat.mouth, part: part);
      _px(mx + 1, my + 1, Mat.mouth, part: part);
      return;
    }
    switch (g.mouth) {
      case Mouth.tiny:
        _px(mx, my, Mat.mouth, part: part);
      case Mouth.fangs:
        _px(mx - 1, my, Mat.mouth, part: part);
        _px(mx, my, Mat.mouth, part: part);
        _px(mx + 1, my, Mat.mouth, part: part);
        _px(mx - 1, my + 1, Mat.tooth, part: part);
        _px(mx + 1, my + 1, Mat.tooth, part: part);
      case Mouth.tusks:
        _px(mx - 1, my, Mat.mouth, part: part);
        _px(mx, my, Mat.mouth, part: part);
        _px(mx + 1, my, Mat.mouth, part: part);
        _px(mx + 2, my - 1, Mat.tooth, part: part);
        _px(mx - 2, my - 1, Mat.tooth, part: part);
      default:
        // Small "w" smile, wider when happy.
        _px(mx - 1, my, Mat.mouth, part: part);
        _px(mx, my + 1, Mat.mouth, part: part);
        _px(mx + 1, my, Mat.mouth, part: part);
        if (pose.face == Face.happy) {
          _px(mx + 2, my - 1, Mat.mouth, part: part);
          _px(mx - 2, my - 1, Mat.mouth, part: part);
        }
    }
  }

  // ---------------------------------------------------------------------------
  // Body plans (all facing right; ground at y = 34)
  // ---------------------------------------------------------------------------

  void _blob(_Layout l, SpritePose pose) {
    final rx = (8.5 * l.w).clamp(6.5, 12.0);
    final ry = (7.5 * l.h).clamp(5.5, 10.0) - pose.bob * 0.5;
    final cx = 20.0, cy = 34 - 1 - ry + pose.bob * 0.5;
    _tail(cx - rx + 1, cy + ry * 0.3, pose);
    _wing(cx - 1, cy - ry * 0.3, pose, back: true);
    // Little feet.
    _legs([cx - rx * 0.4, cx + rx * 0.45], cy + ry - 1, 34, pose);
    final body = _newPart();
    _ellipse(cx, cy, rx, ry, _skin, part: body);
    _bellyPatch(body, cx, cy, rx, ry);
    _patternOnPart(body, cx, cy, rx, ry);
    _ears(cx + 1, cy + 1, ry);
    _horns(cx + 1, cy + 1, ry);
    _wing(cx - 2, cy - ry * 0.1, pose, back: false);
    _face(cx + rx * 0.3, cy - ry * 0.15, math.min(rx, ry), pose);
  }

  void _biped(_Layout l, SpritePose pose) {
    final bodyRx = (5.5 * l.w).clamp(4.5, 7.5);
    final bodyRy = (6 * l.h).clamp(5.0, 8.0);
    final legH = 2.5 + 2 * l.leg;
    final bodyCy = 34 - legH - bodyRy + 1 + pose.bob;
    final headR = (7.8 * l.head).clamp(6.5, 9.5);
    final cx = 19.0;
    final headCx = cx + 1.5, headCy = bodyCy - bodyRy - headR + 4;
    _tail(cx - bodyRx + 1, bodyCy + 1, pose);
    _wing(cx - 1, bodyCy - bodyRy + 2, pose, back: true);
    _legs([cx - bodyRx * 0.45], bodyCy + bodyRy - 2, 34, pose, back: true);
    final body = _newPart();
    _ellipse(cx, bodyCy, bodyRx, bodyRy, _skin, part: body);
    _bellyPatch(body, cx, bodyCy, bodyRx, bodyRy);
    _patternOnPart(body, cx, bodyCy, bodyRx, bodyRy);
    _legs([cx + bodyRx * 0.35], bodyCy + bodyRy - 2, 34, pose);
    // Arm.
    final armUp = pose.step == 1 ? -1.0 : 0.0;
    _ellipse(cx + bodyRx * 0.55, bodyCy + armUp, 1.8, 2.6, _skin);
    _ears(headCx, headCy, headR);
    final head = _newPart();
    _ellipse(headCx, headCy, headR, headR * 0.92, _skin, part: head);
    if (g.pattern == Pattern.mask) _mask(head, headCx, headCy, headR);
    _horns(headCx, headCy, headR);
    _wing(cx - 1, bodyCy - bodyRy + 3, pose, back: false);
    _face(headCx + headR * 0.2, headCy + 1, headR, pose);
  }

  void _quadruped(_Layout l, SpritePose pose) {
    final rx = (9 * l.w).clamp(7.0, 11.5);
    final ry = (5 * l.h).clamp(4.0, 6.5);
    final legH = 3 + 2.5 * l.leg;
    final cx = 18.0, cy = 34 - legH - ry + 1 + pose.bob * 0.5;
    final headR = (6.6 * l.head).clamp(5.5, 8.0);
    final headCx = cx + rx - 1, headCy = cy - ry - headR * 0.35 + 2;
    _tail(cx - rx + 1, cy - 1, pose);
    _legs([cx - rx * 0.55, cx + rx * 0.45], cy + ry - 2, 34, pose, back: true);
    final body = _newPart();
    _ellipse(cx, cy, rx, ry, _skin, part: body);
    _bellyPatch(body, cx, cy, rx, ry);
    _patternOnPart(body, cx, cy, rx, ry);
    _wing(cx, cy - ry + 1, pose, back: false);
    _legs(
      [cx - rx * 0.4, cx + rx * 0.6],
      cy + ry - 2,
      34,
      SpritePose(
        step: pose.step == 0 ? 0 : 3 - pose.step,
        bob: pose.bob,
        face: pose.face,
      ),
    );
    _ears(headCx - 1, headCy, headR);
    final head = _newPart();
    _ellipse(headCx, headCy, headR, headR * 0.9, _skin, part: head);
    if (g.pattern == Pattern.mask) _mask(head, headCx, headCy, headR);
    // Snout.
    _ellipse(
      headCx + headR * 0.75,
      headCy + headR * 0.35,
      headR * 0.45,
      headR * 0.35,
      _belly,
    );
    _horns(headCx - 1, headCy, headR);
    _face(headCx + headR * 0.1, headCy, headR, pose);
  }

  void _avian(_Layout l, SpritePose pose) {
    final rx = (7 * l.w).clamp(5.5, 9.0);
    final ry = (6.5 * l.h).clamp(5.0, 8.0);
    final legH = 3 + 2 * l.leg;
    final cx = 18.0, cy = 34 - legH - ry + 1 + pose.bob * 0.5;
    final headR = (5.8 * l.head).clamp(5.0, 7.0);
    final headCx = cx + rx * 0.6, headCy = cy - ry - headR + 4.5;
    _tail(cx - rx + 1, cy, pose);
    _wing(cx, cy - 1, pose, back: true);
    _legs([cx - 1.5, cx + 2.0], cy + ry - 1, 34, pose, thin: true);
    final body = _newPart();
    _ellipse(cx, cy, rx, ry, _skin, part: body);
    _bellyPatch(body, cx, cy, rx, ry);
    _patternOnPart(body, cx, cy, rx, ry);
    final head = _newPart();
    _ellipse(headCx, headCy, headR, headR, _skin, part: head);
    // Crest.
    _polygon([
      (headCx - 2, headCy - headR + 1.5),
      (headCx - 3.5, headCy - headR - 3),
      (headCx + 1, headCy - headR + 1),
    ], _accent);
    _wing(cx + 1, cy, pose, back: false);
    _face(headCx, headCy, headR, pose, beak: true);
  }

  void _insect(_Layout l, SpritePose pose) {
    final cx = 17.0;
    final legH = 3 + 1.5 * l.leg;
    final ry = (4.5 * l.h).clamp(3.5, 6.0);
    final cy = 34 - legH - ry + 1 + pose.bob * 0.5;
    final abdRx = (7 * l.w).clamp(5.5, 9.0);
    final headR = (5.4 * l.head).clamp(4.8, 7.0);
    final headCx = cx + abdRx + 3.5, headCy = cy - 2;
    _wing(cx, cy - ry, pose, back: true);
    _legs(
      [cx - 3, cx + 1, cx + 5],
      cy + ry - 1,
      34,
      pose,
      thin: true,
      back: true,
    );
    final abd = _newPart();
    _ellipse(cx, cy, abdRx, ry, _skin, part: abd);
    _patternOnPart(abd, cx, cy, abdRx, ry);
    _bellyPatch(abd, cx, cy, abdRx, ry);
    _ellipse(cx + abdRx + 0.5, cy - 0.5, 3, 3, _accent);
    final head = _newPart();
    _ellipse(headCx, headCy, headR, headR * 0.95, _skin, part: head);
    _horns(headCx - 1, headCy, headR);
    _legs([cx - 1, cx + 3, cx + 7], cy + ry - 1, 34, pose, thin: true);
    _wing(cx + 1, cy - ry + 1, pose, back: false);
    _face(headCx, headCy, headR, pose);
  }

  void _serpent(_Layout l, SpritePose pose) {
    final thick = (3.3 * l.h + 1).clamp(3.0, 5.0);
    final phase = pose.step * 1.1 + pose.bob * 0.5;
    final body = _newPart();
    const segments = 9;
    double? lastX, lastY;
    for (var i = 0; i <= segments; i++) {
      final t = i / segments;
      final x = 5 + t * 24;
      final y =
          34 -
          thick -
          math.sin(t * math.pi * 2.2 + phase) * 1.8 * (1 - t * 0.3);
      final r = thick * (0.55 + 0.45 * t);
      _ellipse(x, y, r, r * 0.9, _skin, part: body);
      lastX = x;
      lastY = y;
    }
    _patternOnPart(body, 17, 34 - thick, 12, thick);
    // Neck rising to the head.
    final headR = (6.2 * l.head).clamp(5.2, 7.5);
    final headCx = lastX! + 3, headCy = lastY! - thick - headR + 1 + pose.bob;
    final neck = _newPart();
    _polygon(
      [
        (lastX - thick * 0.9, lastY),
        (headCx - headR * 0.7, headCy + 1),
        (headCx + headR * 0.3, headCy + 2),
        (lastX + thick * 0.8, lastY),
      ],
      _skin,
      part: neck,
    );
    _bellyPatch(neck, lastX, lastY - thick, thick, thick * 1.6);
    _tail(5, 34 - thick, pose);
    _ears(headCx, headCy, headR);
    final head = _newPart();
    _ellipse(headCx, headCy, headR, headR * 0.85, _skin, part: head);
    _horns(headCx, headCy, headR);
    _face(headCx + 1, headCy, headR, pose);
  }

  void _floater(_Layout l, SpritePose pose) {
    final rx = (8 * l.w).clamp(6.0, 10.0);
    final ry = (8 * l.h).clamp(6.0, 10.0);
    final hover = 4.0 + pose.bob;
    final cx = 20.0, cy = 34 - hover - ry;
    _wing(cx - 1, cy - 2, pose, back: true);
    final body = _newPart();
    _ellipse(cx, cy, rx, ry * 0.85, _skin, part: body);
    // Wavy hem.
    final waveShift = pose.step == 1 || pose.bob == 1 ? 1 : 0;
    for (var x = (cx - rx).round(); x <= (cx + rx).round(); x++) {
      final nx = (x - cx) / rx;
      if (nx.abs() > 0.97) continue;
      final depth = 3 + (((x + waveShift) % 4) < 2 ? 1 : 0);
      for (var y = cy.round(); y <= (cy + ry * 0.4 + depth).round(); y++) {
        _px(x, y, nx > 0.35 ? Mat.skinDark : Mat.skin, part: body);
      }
    }
    _bellyPatch(body, cx, cy - 1, rx, ry * 0.8);
    _patternOnPart(body, cx, cy, rx, ry);
    _ears(cx + 1, cy + 1, ry * 0.85);
    _horns(cx + 1, cy + 1, ry * 0.85);
    _wing(cx - 2, cy, pose, back: false);
    _face(cx + rx * 0.3, cy - 1, math.min(rx, ry), pose);
  }

  void _mask(int part, double cx, double cy, double r) {
    for (var y = (cy - r * 0.45).round(); y <= (cy - r * 0.05).round(); y++) {
      for (var x = (cx - r).round(); x <= (cx + r).round(); x++) {
        if (_grid.partAt(x, y) == part) _px(x, y, Mat.accentDark, part: part);
      }
    }
  }
}

/// Size multipliers from the genome (shared by the body plans).
class _Layout {
  _Layout(Genome g, double size, SpritePose pose)
    : w = g.bodyWidth * (0.85 + 0.25 * (size - 1)),
      h = g.bodyHeight * (0.85 + 0.25 * (size - 1)),
      head = g.headSize * (0.9 + 0.2 * (size - 1)),
      leg = g.legLength;

  final double w, h, head, leg;
}

/// Colours for each [Mat], derived from the creature's colours with
/// pixel-art hue shifting (shadows cooler, highlights warmer).
class SpritePalette {
  SpritePalette(Appearance look) {
    final b = look.body;
    final a = look.accent;
    final belly = look.belly;
    Hsl dark(Hsl c, double dl) =>
        Hsl((c.h - 12) % 360, (c.s + 0.05).clamp(0, 1), (c.l - dl).clamp(0, 1));
    Hsl light(Hsl c, double dl) =>
        Hsl((c.h + 10) % 360, (c.s - 0.05).clamp(0, 1), (c.l + dl).clamp(0, 1));
    final eye = look.genome.eyeColor;
    colors = Int32List(Mat.values.length)
      ..[Mat.none.index] = 0
      ..[Mat.skinDark.index] = dark(b, 0.13).argb
      ..[Mat.skin.index] = b.argb
      ..[Mat.skinLight.index] = light(b, 0.12).argb
      ..[Mat.belly.index] = belly.argb
      ..[Mat.bellyDark.index] = dark(belly, 0.1).argb
      ..[Mat.accentDark.index] = dark(a, 0.14).argb
      ..[Mat.accent.index] = a.argb
      ..[Mat.accentLight.index] = light(a, 0.14).argb
      ..[Mat.eyeDark.index] = const Hsl(240, 0.3, 0.1).argb
      ..[Mat.eyeShine.index] = 0xFFFFFFFF
      ..[Mat.eyeIris.index] = (eye.l < 0.2 ? Hsl(a.h, 0.8, 0.5) : eye).argb
      ..[Mat.mouth.index] = 0xFF5A1626
      ..[Mat.tooth.index] = 0xFFFFFFFF
      ..[Mat.beak.index] = 0xFFF4B23C
      ..[Mat.beakDark.index] = 0xFFC57A1E
      ..[Mat.cheek.index] = 0xFFFF8FA3
      ..[Mat.wingGlass.index] = 0xFFA6DDF4
      ..[Mat.wingVein.index] = 0xFF5C9CC4
      ..[Mat.leaf.index] = 0xFF7FD158
      ..[Mat.leafDark.index] = 0xFF3F8F3A
      ..[Mat.flame.index] = 0xFFFF7A22
      ..[Mat.flameCore.index] = 0xFFFFE15A
      ..[Mat.innerLine.index] = dark(b, 0.3).argb
      ..[Mat.outline.index] = Hsl(
        (b.h - 20) % 360,
        (b.s * 0.6).clamp(0, 1),
        0.13,
      ).argb;
  }

  late final Int32List colors;

  /// RGBA bytes for a grid (for decoding into an image).
  Uint8List rgba(SpriteGrid grid) {
    final out = Uint8List(spriteW * spriteH * 4);
    for (var i = 0; i < spriteW * spriteH; i++) {
      final c = colors[grid.mats[i]];
      out[i * 4] = (c >> 16) & 0xFF;
      out[i * 4 + 1] = (c >> 8) & 0xFF;
      out[i * 4 + 2] = c & 0xFF;
      out[i * 4 + 3] = (c >> 24) & 0xFF;
    }
    return out;
  }
}
