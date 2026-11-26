// Pokéville's look, ported from the PC's PokeBoxLook.gd (the approved
// mock-up, mock-a): a watercolour wash, cream panels with navy edges, box
// wallpapers (sky, brick, sand, mint, grass), type chips, button hints, the
// see-through ball, eggs drawn (not a sprite). Titles are Pixelify Sans,
// text is DotGothic16 (both SIL OFL 1.1, bundled in this package).
//
// Everything is painted on a Canvas through [Pen]; sizes are the PC's
// 1920×1080 layout units times [Pen.u] (1 on wide screens, smaller on the
// compact layouts).
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

abstract final class Look {
  static const ink = Color(0xFF1D2140);
  static const line = Color(0xFF2B3070);
  static const paper = Color(0xFFFFFDF4);
  static const lilac = Color(0xFFCFD3F5);
  static const soft = Color(0xFF6A6F9E);
  static const faint = Color(0xFF9AA0C8);
  static const gold = Color(0xFFFFD54A);
  static const star = Color(0xFFFFB300);
  static const label = Color(0xFFD9A63A);
  static const labelEdge = Color(0xFF7A5310);
  static const red = Color(0xFFE8463C);
  static const blue = Color(0xFF4A7BD8);
  static const bg = Color(0xFFF7F2E8);
  static const lit = Color(0xFFFFF3B0); // a highlighted row / banner
  static const white = Color(0xFFFFFFFF);
  static const buttons = {
    'A': Color(0xFF22A447),
    'B': Color(0xFFD93A3A),
    'X': Color(0xFF2D67E0),
    'Y': Color(0xFFE5B51D),
  };
  static const typeColors = {
    'Normal': 0xFFA8A77A,
    'Fire': 0xFFEE8130,
    'Water': 0xFF4A90E2,
    'Electric': 0xFFE5B51D,
    'Grass': 0xFF5FBD58,
    'Ice': 0xFF5CC4C0,
    'Fighting': 0xFFC22E28,
    'Poison': 0xFFA33EA1,
    'Ground': 0xFFC9A24A,
    'Flying': 0xFF8A6AD8,
    'Psychic': 0xFFF95587,
    'Bug': 0xFF92A81A,
    'Rock': 0xFFB6A136,
    'Ghost': 0xFF735797,
    'Dragon': 0xFF6F35FC,
    'Dark': 0xFF705746,
    'Steel': 0xFF8F97B8,
    'Fairy': 0xFFD685AD,
  };
  static const wallpapers = ['sky', 'brick', 'sand', 'mint', 'grass'];
  static const statNames = [
    'HP',
    'ATTACK',
    'DEFENSE',
    'SP. ATK',
    'SP. DEF',
    'SPEED',
  ];
  static const statColors = [
    Color(0xFFFF6B8A),
    Color(0xFFFF9A3C),
    Color(0xFFF5C518),
    Color(0xFF5AA0FF),
    Color(0xFF57C78A),
    Color(0xFFC77DFF),
  ];

  static Color typeColor(String t) => Color(typeColors[t] ?? 0xFF8A8FB8);

  static String wallOf(int page) => wallpapers[page % wallpapers.length];

  /// Pixelify Sans, bold (a variable font: weight 700).
  static const titleFamily = 'PixelifySans';

  /// DotGothic16.
  static const textFamily = 'DotGothic16';
  static const package = 'pokeville';
}

/// Which font a piece of text uses.
enum Face { title, text }

/// Paints the look on a canvas. [u] scales borders, radii and tiles.
class Pen {
  Pen(this.c, {this.u = 1});

  final Canvas c;
  final double u;

  static final _texts = <(String, Face, double, int, double), TextPainter>{};

  static TextStyle style(Face f, double size, Color color) => TextStyle(
    fontFamily: f == Face.title ? Look.titleFamily : Look.textFamily,
    package: Look.package,
    fontSize: size,
    color: color,
    height: 1.0,
    fontWeight: f == Face.title ? FontWeight.w700 : FontWeight.w400,
    // the title font lacks ★ ♂ ♀ and kana: DotGothic16 has them
    fontFamilyFallback: f == Face.title
        ? const ['packages/${Look.package}/${Look.textFamily}']
        : null,
    fontVariations: f == Face.title
        ? const [ui.FontVariation('wght', 700)]
        : null,
  );

  /// Text as the fonts can draw it: Game Boy names come from PKHeX with
  /// U+2024 (one dot leader) for their "." ("D․I․Z․"), which neither font
  /// has.
  static String shown(String s) =>
      s.replaceAll('\u2024', '.').replaceAll('\u2025', '..');

  static TextPainter _painter(
    String s,
    Face f,
    double size,
    Color col,
    double maxW,
  ) {
    final k = (s, f, size, col.toARGB32(), maxW);
    final got = _texts[k];
    if (got != null) return got;
    if (_texts.length > 3000) {
      for (final t in _texts.values) {
        t.dispose();
      }
      _texts.clear();
    }
    final tp = TextPainter(
      text: TextSpan(text: shown(s), style: style(f, size, col)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxW > 0 ? maxW : double.infinity);
    return _texts[k] = tp;
  }

  /// The width [s] takes.
  double width(String s, Face f, double size) =>
      _painter(s, f, size, Look.ink, 0).width;

  /// Text with its baseline at [at]. align: 0 left, 1 centre, 2 right.
  /// Longer than [maxW] (when > 0): cut with "…". Returns the width drawn.
  double say(
    String s,
    Offset at,
    Face f,
    double size,
    Color col, {
    int align = 0,
    double maxW = 0,
  }) {
    if (s.isEmpty) return 0;
    final tp = _painter(s, f, size, col, maxW);
    final base = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    var x = at.dx;
    if (align == 1) x -= tp.width / 2;
    if (align == 2) x -= tp.width;
    tp.paint(c, Offset(x, at.dy - base));
    return tp.width;
  }

  // ---- shapes ----------------------------------------------------------------

  /// A rounded box: [fill] inside, a [bw]-wide [border] drawn inside its edge
  /// (as Godot's StyleBoxFlat).
  void box(
    Rect r,
    Color fill,
    Color border,
    double bw,
    double radius, {
    bool center = true,
  }) {
    final rad = Radius.circular(math.max(0, radius));
    if (center) {
      c.drawRRect(RRect.fromRectAndRadius(r, rad), Paint()..color = fill);
    }
    if (bw > 0) {
      c.drawRRect(
        RRect.fromRectAndRadius(
          r.deflate(bw / 2),
          Radius.circular(math.max(0, radius - bw / 2)),
        ),
        Paint()
          ..color = border
          ..style = PaintingStyle.stroke
          ..strokeWidth = bw,
      );
    }
  }

  /// The cream panel: navy edge, white and lilac rings, a navy drop below.
  void panel(
    Rect r, {
    Color fill = Look.paper,
    double radius = 14,
    bool rings = true,
    bool shadow = true,
  }) {
    final rad = radius * u;
    if (shadow) {
      box(
        r.shift(Offset(0, 6 * u)),
        Look.line.withValues(alpha: 0.35),
        Look.line,
        0,
        rad,
      );
    }
    box(r, fill, Look.line, 5 * u, rad);
    if (rings) {
      box(
        r.deflate(5 * u),
        fill,
        Look.white,
        4 * u,
        math.max(rad - 5 * u, 2),
        center: false,
      );
      box(
        r.deflate(9 * u),
        fill,
        Look.lilac,
        3 * u,
        math.max(rad - 9 * u, 2),
        center: false,
      );
    }
  }

  /// A panel whose inside is a box wallpaper.
  void wallPanel(Rect r, String kind, {double radius = 22, double bw = 5}) {
    final rad = radius * u;
    final w = bw * u;
    box(
      r.shift(Offset(0, 6 * u)),
      Look.line.withValues(alpha: 0.35),
      Look.line,
      0,
      rad,
    );
    box(r, Look.line, Look.line, 0, rad);
    wallpaper(r.deflate(w), kind, math.max(rad - w, 2));
    box(
      r.deflate(w),
      Look.white,
      Look.white,
      3 * u,
      math.max(rad - w, 2),
      center: false,
    );
  }

  void wallpaper(Rect r, String kind, double radius) {
    c.save();
    c.clipRRect(RRect.fromRectAndRadius(r, Radius.circular(radius)));
    final t = u; // tile scale
    void tiles(double size, void Function(Offset o) one) {
      for (var y = r.top; y < r.bottom; y += size * t) {
        for (var x = r.left; x < r.right; x += size * t) {
          one(Offset(x, y));
        }
      }
    }

    void dot(Offset o, double cx, double cy, double rad, Color col) =>
        c.drawCircle(o + Offset(cx * t, cy * t), rad * t, Paint()..color = col);

    switch (kind) {
      case 'grass':
        c.drawRect(r, Paint()..color = const Color(0xFF8FD16A));
        final stripe = Paint()..color = const Color(0xFF86C862);
        for (var x = r.left + 14 * t; x < r.right; x += 16 * t) {
          c.drawRect(Rect.fromLTWH(x, r.top, 2 * t, r.height), stripe);
        }
        tiles(64, (o) {
          dot(o, 16, 19, 5, const Color(0xFFA3DB84));
          dot(o, 48, 45, 4, const Color(0xFF7BBD57));
        });
      case 'brick':
        c.drawRect(r, Paint()..color = const Color(0xFFE9B8C3));
        final m = Paint()..color = const Color(0xFFD99AAB);
        tiles(48, (o) {
          c.drawRect(Rect.fromLTWH(o.dx, o.dy, 48 * t, 3 * t), m);
          c.drawRect(Rect.fromLTWH(o.dx, o.dy + 24 * t, 48 * t, 3 * t), m);
          c.drawRect(Rect.fromLTWH(o.dx, o.dy, 3 * t, 24 * t), m);
          c.drawRect(
            Rect.fromLTWH(o.dx + 24 * t, o.dy + 24 * t, 3 * t, 24 * t),
            m,
          );
        });
      case 'sand':
        c.drawRect(r, Paint()..color = const Color(0xFFF0C27A));
        tiles(18, (o) => dot(o, 9, 9, 1.2, const Color(0xFFD9A25A)));
      case 'mint':
        c.drawRect(r, Paint()..color = const Color(0xFFBFE9D9));
        tiles(40, (o) {
          dot(o, 10, 10, 4, const Color(0xFFDCF5EB));
          dot(o, 30, 30, 4, const Color(0xFFDCF5EB));
        });
      default: // sky: a top-to-bottom fade
        c.drawRect(
          r,
          Paint()
            ..shader = ui.Gradient.linear(r.topCenter, r.bottomCenter, const [
              Color(0xFF9FD8FF),
              Color(0xFFE4F5FF),
            ]),
        );
    }
    c.restore();
  }

  /// The watercolour behind everything: soft blobs of colour on paper.
  /// [blobs]: (x, y, radius, colour).
  void wash(Rect all, List<(double, double, double, int)> blobs) {
    c.drawRect(all, Paint()..color = Look.bg);
    for (final (x, y, r, col) in blobs) {
      final color = Color(col);
      c.drawCircle(
        Offset(x, y),
        r,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(x, y),
            r,
            [
              color.withValues(alpha: 0.75),
              color.withValues(alpha: 0.45),
              color.withValues(alpha: 0),
            ],
            const [0, 0.45, 1],
          ),
      );
    }
  }

  /// The checkered picture frame.
  void checker(Rect r, Color a, Color b) {
    box(r, a, Look.line, 5 * u, 12 * u);
    final inner = r.deflate(5 * u);
    c.save();
    c.clipRRect(RRect.fromRectAndRadius(inner, Radius.circular(9 * u)));
    final s = 28 * u;
    final p = Paint()..color = b;
    var row = 0;
    for (var y = inner.top; y < inner.bottom; y += s, row++) {
      for (
        var x = inner.left + (row.isOdd ? s : 0);
        x < inner.right;
        x += s * 2
      ) {
        c.drawRect(Rect.fromLTWH(x, y, s, s), p);
      }
    }
    c.restore();
    box(inner, a, Look.white, 3 * u, 9 * u, center: false);
  }

  /// The gold tag ("PKMN DATA"). [fs] is its text size.
  void label(String s, Offset at, {double fs = 20}) {
    final k = fs / 20;
    final w = width(s, Face.title, fs) + 26 * k;
    box(
      Rect.fromLTWH(at.dx, at.dy, w, 34 * k),
      Look.label,
      Look.labelEdge,
      3 * u,
      6 * u,
    );
    say(s, at + Offset(13 * k, 25 * k), Face.title, fs, Look.white);
  }

  /// A coloured chip ("WATER"); returns its width.
  double chip(
    String s,
    Offset at,
    Color fill, {
    double fs = 22,
    Color ink = Look.white,
  }) {
    final k = fs / 22;
    // a leading "★ " is drawn (the font has no star)
    final star = s.startsWith('★ ');
    final t = star ? s.substring(2) : s;
    final sw = star ? fs * 1.05 : 0.0;
    final w = width(t, Face.title, fs) + 28 * k + sw;
    box(Rect.fromLTWH(at.dx, at.dy, w, fs + 16 * k), fill, fill, 0, 8 * k);
    if (star) {
      this.star(
        at + Offset(14 * k + fs * 0.4, (fs + 16 * k) / 2),
        fs * 0.48,
        ink,
      );
    }
    say(t, at + Offset(14 * k + sw, fs + 6 * k), Face.title, fs, ink);
    return w;
  }

  /// A tag on a panel's top edge ("Box 2"), white-edged.
  void tag(String s, Offset at, Color fill, {double fs = 18, double maxW = 0}) {
    final k = fs / 18;
    final tw = math.min(
      width(s, Face.title, fs),
      maxW > 0 ? maxW - 26 * k : double.infinity,
    );
    final w = tw + 26 * k;
    box(
      Rect.fromLTWH(at.dx, at.dy, w, fs + 14 * k),
      fill,
      Look.white,
      3 * u,
      6 * u,
    );
    say(
      s,
      at + Offset(13 * k, fs + 4 * k),
      Face.title,
      fs,
      Look.white,
      maxW: tw + 1,
    );
  }

  /// A button hint: white pill, the pad's coloured letter, the action.
  /// Returns its rect. [h] is its height (58 on the PC).
  Rect button(
    String key,
    String what,
    Offset at, {
    double w = 0,
    double h = 58,
    bool fixed = false,
    double? fs,
  }) {
    final k = h / 58;
    final f = fs ?? 24 * k;
    final bw = fixed ? w : math.max(w, width(what, Face.title, f) + 84 * k);
    final r = Rect.fromLTWH(at.dx, at.dy, bw, h);
    box(r.shift(Offset(0, 4 * k)), Look.line, Look.line, 0, 12 * k);
    box(r, Look.white, Look.line, 4 * k, 12 * k);
    c.drawCircle(
      at + Offset(34 * k, 29 * k),
      17 * k,
      Paint()..color = Look.buttons[key] ?? Look.line,
    );
    say(
      key,
      at + Offset(34 * k, 37 * k),
      Face.title,
      22 * k,
      Look.white,
      align: 1,
    );
    say(
      what,
      at + Offset(62 * k, 29 * k + f * 0.37),
      Face.title,
      f,
      Look.ink,
      maxW: bw - 70 * k,
    );
    return r;
  }

  /// The box cursor: gold, navy-edged; dashed while carrying something.
  void cursor(Rect r, bool dashed) {
    box(r.inflate(4 * u), Look.white, Look.line, 3 * u, 16 * u, center: false);
    if (!dashed) {
      box(r, Look.white, Look.gold, 5 * u, 14 * u, center: false);
      return;
    }
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(r.deflate(2.5 * u), Radius.circular(12 * u)),
      );
    final paint = Paint()
      ..color = Look.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5 * u;
    for (final m in path.computeMetrics()) {
      final dash = 12 * u;
      for (var d = 0.0; d < m.length; d += dash * 2) {
        c.drawPath(m.extractPath(d, math.min(d + dash, m.length)), paint);
      }
    }
  }

  /// A sprite, nearest-neighbour, filling [dst].
  void sprite(ui.Image img, Rect dst, {Color? tint}) {
    final p = Paint()..filterQuality = FilterQuality.none;
    if (tint != null) {
      p.colorFilter = ColorFilter.mode(tint, BlendMode.modulate);
    }
    c.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      dst,
      p,
    );
  }

  /// The see-through ball a carried Pokémon rides in.
  void glassBall(
    Offset at,
    double rad,
    ui.Image? img,
    double tilt, {
    bool egg = false,
  }) {
    final lw = Paint()
      ..color = Look.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5 * u;
    c.save();
    c.translate(at.dx, at.dy);
    c.rotate(tilt);
    c.drawCircle(Offset.zero, rad + 2 * u, Paint()..color = Look.line);
    c.drawCircle(
      Offset.zero,
      rad - 3 * u,
      Paint()..color = const Color(0xB3EDF7FF),
    );
    c.drawRect(
      Rect.fromLTWH(-rad + 3 * u, -3 * u, rad * 2 - 6 * u, 6 * u),
      Paint()..color = Look.line.withValues(alpha: 0.25),
    );
    c.rotate(-tilt); // the Pokémon stays upright
    if (egg) {
      this.egg(Offset.zero, rad * 0.85);
    } else if (img != null) {
      final s = rad * 1.7;
      sprite(img, Rect.fromLTWH(-s / 2, -s / 2 - 4 * u, s, s));
    }
    c.rotate(tilt);
    c.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: rad - 10 * u),
      math.pi * 1.12,
      math.pi * 0.33,
      false,
      Paint()
        ..color = const Color(0xE6FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6 * u,
    );
    c.drawCircle(Offset(0, rad - 16 * u), 9 * u, Paint()..color = Look.line);
    c.drawCircle(Offset(0, rad - 16 * u), 5 * u, Paint()..color = Look.white);
    c.drawCircle(Offset.zero, rad, lw);
    c.restore();
  }

  /// ♂ / ♀, drawn (fonts can turn the signs into emoji).
  void genderMark(Offset at, bool male, {double s = 1}) {
    final col = male ? const Color(0xFF4A7BD8) : const Color(0xFFF0609A);
    final p = Paint()
      ..color = col
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5 * s
      ..strokeCap = StrokeCap.round;
    c.drawCircle(at, 9 * s, p);
    if (male) {
      final tip = at + Offset(15 * s, -15 * s);
      c.drawLine(at + Offset(6.4 * s, -6.4 * s), tip, p);
      c.drawLine(tip, tip + Offset(-8 * s, 0), p);
      c.drawLine(tip, tip + Offset(0, 8 * s), p);
    } else {
      c.drawLine(at + Offset(0, 9 * s), at + Offset(0, 22 * s), p);
      c.drawLine(at + Offset(-6 * s, 16 * s), at + Offset(6 * s, 16 * s), p);
    }
  }

  /// A five-point star, drawn.
  void star(Offset at, double r, Color col) {
    Path pts(Offset o) {
      final path = Path();
      for (var i = 0; i < 10; i++) {
        final a = -math.pi / 2 + i * math.pi / 5;
        final rr = i.isEven ? r : r * 0.45;
        final pt = at + o + Offset(math.cos(a) * rr, math.sin(a) * rr);
        i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
      }
      return path..close();
    }

    final sh = r / 10;
    c.drawPath(pts(Offset(sh, sh)), Paint()..color = Look.line);
    c.drawPath(pts(Offset.zero), Paint()..color = col);
  }

  /// An egg, drawn: a cream oval with green spots.
  void egg(Offset at, double size) {
    final path = Path();
    for (var i = 0; i < 32; i++) {
      final a = math.pi * 2 * i / 32;
      final y = math.sin(a);
      final pt =
          at + Offset(math.cos(a) * size * (0.42 + 0.06 * y), y * size * 0.55);
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    c.drawPath(path, Paint()..color = const Color(0xFFF4F1DC));
    final g = Paint()..color = const Color(0xFF7CC76B);
    c.drawCircle(at + Offset(-size * 0.14, -size * 0.12), size * 0.09, g);
    c.drawCircle(at + Offset(size * 0.16, size * 0.08), size * 0.1, g);
    c.drawCircle(at + Offset(-size * 0.04, size * 0.3), size * 0.07, g);
    c.drawPath(
      path,
      Paint()
        ..color = Look.line
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, size / 40),
    );
  }

  /// A little Poké Ball (where a picture can't be had): the item sprite when
  /// it's loaded, else drawn.
  void miniBall(Offset at, double r, ui.Image? ball) {
    if (ball != null) {
      final s = r * 2.6;
      sprite(ball, Rect.fromCenter(center: at, width: s, height: s));
      return;
    }
    c.drawCircle(at, r + 2 * u, Paint()..color = Look.line);
    c.drawCircle(at, r, Paint()..color = Look.white);
    c.drawArc(
      Rect.fromCircle(center: at, radius: r),
      math.pi,
      math.pi,
      true,
      Paint()..color = Look.red,
    );
    c.drawLine(
      at - Offset(r, 0),
      at + Offset(r, 0),
      Paint()
        ..color = Look.line
        ..strokeWidth = 3 * u,
    );
    c.drawCircle(at, r * 0.3, Paint()..color = Look.line);
    c.drawCircle(at, r * 0.18, Paint()..color = Look.white);
  }

  /// A solid triangle pointing left (-1) or right (1).
  void arrow(Offset at, int dir, {double s = 18, Color col = Look.ink}) {
    final path = Path()
      ..moveTo(at.dx + s * 0.6 * dir, at.dy)
      ..lineTo(at.dx - s * 0.6 * dir, at.dy - s)
      ..lineTo(at.dx - s * 0.6 * dir, at.dy + s)
      ..close();
    c.drawPath(path, Paint()..color = col);
  }

  /// A solid triangle pointing up (-1) or down (1).
  void arrowV(Offset at, int dir, {double s = 18, Color col = Look.ink}) {
    final path = Path()
      ..moveTo(at.dx, at.dy + s * 0.6 * dir)
      ..lineTo(at.dx - s, at.dy - s * 0.6 * dir)
      ..lineTo(at.dx + s, at.dy - s * 0.6 * dir)
      ..close();
    c.drawPath(path, Paint()..color = col);
  }
}
