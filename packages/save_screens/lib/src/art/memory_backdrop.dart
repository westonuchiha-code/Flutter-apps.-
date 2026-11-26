/// The Paint & Polygons background: periwinkle light in the middle fading
/// to deep navy, a faint grid, and (on an opened save) a wash of the four
/// corner colours that save carries. A painter port of the PC's
/// shaders/memory_back.gdshader.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:save_kit/save_kit.dart';

import 'look.dart';

class MemoryBackdrop extends StatelessWidget {
  const MemoryBackdrop({super.key, this.child, this.tint, this.tintAmount = 0});

  final Widget? child;

  /// Four corner colours: top-left, top-right, bottom-left, bottom-right.
  final List<Color>? tint;

  /// How much of [tint] shows (a PS2 save's own backAlpha).
  final double tintAmount;

  /// How much of a save's colours show at its full backAlpha (the PC's
  /// OWN_STRENGTH).
  static const ownStrength = 0.5;

  /// A save's corner colours (brightened 1.5×, like the PC) and strength,
  /// for [tint] / [tintAmount] (null when it has none).
  static ({List<Color> tint, double amount})? tintOf(CardSave? s) {
    if (s == null || s.backColors.length < 4 || s.backAlpha <= 0) return null;
    return (
      tint: [
        for (final c in s.backColors.take(4))
          Look.rgb(Rgb(c.r * 1.5, c.g * 1.5, c.b * 1.5)),
      ],
      amount: ownStrength * s.backAlpha,
    );
  }

  /// [MemoryBackdrop] washed with [save]'s colours, easing in and out.
  static Widget forSave(CardSave? save, {Key? key, Widget? child}) {
    final t = tintOf(save);
    return TweenAnimationBuilder<double>(
      key: key,
      tween: Tween(end: t?.amount ?? 0),
      duration: const Duration(milliseconds: 350),
      builder: (_, a, c) =>
          MemoryBackdrop(tint: t?.tint ?? _lastTint, tintAmount: a, child: c),
      child: child,
    );
  }

  static const _lastTint = <Color>[
    Color(0xFF000000),
    Color(0xFF000000),
    Color(0xFF000000),
    Color(0xFF000000),
  ];

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: BackdropPainter(tint: tint, amount: tintAmount),
    child: child ?? const SizedBox.expand(),
  );
}

class BackdropPainter extends CustomPainter {
  BackdropPainter({this.tint, this.amount = 0});

  final List<Color>? tint;
  final double amount;

  static const core = Color.from(
    alpha: 1,
    red: 0.537,
    green: 0.549,
    blue: 0.941,
  );
  static const mid = Color.from(
    alpha: 1,
    red: 0.349,
    green: 0.349,
    blue: 0.800,
  );
  static const edge = Color.from(
    alpha: 1,
    red: 0.153,
    green: 0.161,
    blue: 0.533,
  );
  static const dark = Color.from(
    alpha: 1,
    red: 0.027,
    green: 0.031,
    blue: 0.184,
  );
  static const gridLine = Color.from(alpha: 1, red: 0.84, green: 0.86, blue: 1);

  /// The PC's grid cell at 1080 lines.
  static const cell = 46.0;

  static double _smooth(double a, double b, double x) {
    final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  /// The shader's colour at elliptical distance [d].
  static Color colorAt(double d) {
    var c = Color.lerp(core, mid, _smooth(0, 0.34, d))!;
    c = Color.lerp(c, edge, _smooth(0.30, 0.68, d))!;
    return Color.lerp(c, dark, _smooth(0.62, 1.02, d))!;
  }

  static final _stops = [for (var i = 0; i <= 32; i++) i / 32 * 1.1];
  static final _colors = [for (final d in _stops) colorAt(d)];
  static final _fadeStops = [for (var i = 0; i <= 16; i++) i / 16];
  static final _fade = [
    for (final d in _fadeStops)
      gridLine.withValues(alpha: 0.15 * (1 - _smooth(0.1, 1, d))),
  ];

  /// A radial gradient stretched into an ellipse with radii [rx], [ry].
  static ui.Gradient _ellipse(
    Offset c,
    double rx,
    double ry,
    List<Color> colors,
    List<double> stops,
  ) => ui.Gradient.radial(
    Offset.zero,
    1,
    colors,
    [for (final s in stops) s / stops.last],
    TileMode.clamp,
    Float64List.fromList([
      rx,
      0,
      0,
      0,
      0,
      ry,
      0,
      0,
      0,
      0,
      1,
      0,
      c.dx,
      c.dy,
      0,
      1,
    ]),
  );

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final w = size.width, h = size.height;
    canvas.drawRect(r, Paint()..color = dark);
    // d = |(uv - (0.5, 0.48)) / (0.76, 0.88)|; the gradient runs to 1.1.
    canvas.drawRect(
      r,
      Paint()
        ..shader = _ellipse(
          Offset(w * 0.5, h * 0.48),
          w * 0.76 * 1.1,
          h * 0.88 * 1.1,
          _colors,
          _stops,
        ),
    );
    final t = tint;
    if (t != null && t.length >= 4 && amount > 0) {
      // A bilinear wash: four triangles meeting at the averaged middle.
      final a = amount.clamp(0.0, 1.0);
      final m = Color.from(
        alpha: 1,
        red: (t[0].r + t[1].r + t[2].r + t[3].r) / 4,
        green: (t[0].g + t[1].g + t[2].g + t[3].g) / 4,
        blue: (t[0].b + t[1].b + t[2].b + t[3].b) / 4,
      );
      final tl = r.topLeft, tr = r.topRight, bl = r.bottomLeft;
      final br = r.bottomRight, c = r.center;
      final pts = [tl, tr, c, tr, br, c, br, bl, c, bl, tl, c];
      final cols = [
        t[0], t[1], m, t[1], t[3], m, t[3], t[2], m, t[2], t[0], m, //
      ];
      canvas.drawVertices(
        ui.Vertices(
          ui.VertexMode.triangles,
          pts,
          colors: [for (final c in cols) c.withValues(alpha: a)],
        ),
        BlendMode.dst,
        Paint(),
      );
    }
    // The grid: 2 px lines every 46 px of a 1080-line screen, fading out
    // toward the edges; never so fine it turns to a haze on a phone.
    final k = h / 1080;
    final step = (cell * k).clamp(22.0, 80.0);
    final line = (2 * k).clamp(1.0, 3.0);
    final paint = Paint()
      ..shader = _ellipse(
        Offset(w * 0.5, h * 0.5),
        w * 0.62,
        h * 0.66,
        _fade,
        _fadeStops,
      );
    final path = Path();
    for (var x = 0.0; x < w; x += step) {
      path.addRect(Rect.fromLTWH(x, 0, line, h));
    }
    for (var y = 0.0; y < h; y += step) {
      path.addRect(Rect.fromLTWH(0, y, w, line));
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(BackdropPainter old) =>
      old.amount != amount || !listEquals(old.tint, tint);
}
