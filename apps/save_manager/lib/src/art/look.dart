/// Paint & Polygons: the save manager's colours and small shared pieces
/// (ported from the PC's MemoryCardLook.gd).
library;

import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:save_kit/save_kit.dart';

abstract final class Look {
  static const ink = Color(0xFF111111);
  static const yellow = Color(0xFFFFE23A);
  static const warn = Color(0xFFFFD43A);
  static const cyan = Color(0xFF22D3EE);
  static const label = Color(0xFFA9B0FB);
  static const soft = Color(0xFFD4D7FF);
  static const edge = Color(0xFF7278E8);
  static const panel = Color(0xD9070838);
  static const chip = Color(0xFF15175E);
  static const danger = Color(0xFFFF8095);
  static const blockOff = Color(0xFF2A2D83);
  static const good = Color(0xFF54F08C);

  /// The heavy font the outlined words and card labels use (null = the
  /// app's own; the PC uses Arial Black).
  static String? fontFamily;

  static Color rgb(Rgb c) => Color.from(
    alpha: c.a.clamp(0.0, 1.0),
    red: c.r.clamp(0.0, 1.0),
    green: c.g.clamp(0.0, 1.0),
    blue: c.b.clamp(0.0, 1.0),
  );

  /// A console's colour from [CardSystems.info] ('shell', 'edge', 'label',
  /// 'ink', 'badge').
  static Color system(String system, String key) =>
      rgb(CardSystems.color(system, key));

  /// The PC's soft white glow (a radial texture) over [r], times [tint].
  static void glow(
    Canvas canvas,
    Rect r, {
    Color tint = const Color(0xFFFFFFFF),
    double alpha = 1,
  }) {
    Color mul(double cr, double cg, double cb, double a) => Color.from(
      alpha: (a * tint.a * alpha).clamp(0.0, 1.0),
      red: cr * tint.r,
      green: cg * tint.g,
      blue: cb * tint.b,
    );
    final m = Matrix4.identity()
      ..translateByDouble(r.center.dx, r.center.dy, 0, 1)
      ..scaleByDouble(r.width * 0.5, r.height * 0.5, 1, 1);
    canvas.drawRect(
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset.zero,
          1,
          [mul(1, 1, 1, 0.93), mul(0.87, 0.89, 1, 0.53), mul(1, 1, 1, 0)],
          [0, 0.42, 0.95],
          TileMode.clamp,
          m.storage,
        ),
    );
  }
}

/// White (or yellow) heavy words with the PC's thick black outline and
/// drop shadow (MemoryCardLook.outlined).
class OutlinedText extends StatelessWidget {
  const OutlinedText(
    this.text, {
    super.key,
    this.size = 32,
    this.color = Colors.white,
  });

  final String text;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    TextStyle style(Paint? p, Color? c) => TextStyle(
      fontSize: size,
      fontFamily: Look.fontFamily,
      fontWeight: FontWeight.w900,
      height: 1.1,
      letterSpacing: size * 0.01,
      foreground: p,
      color: c,
    );
    Paint stroke(Color c, double w) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeJoin = StrokeJoin.round
      ..color = c;
    // The PC draws at 1080p with 6-7 px outlines on ~34 px words.
    final w = size * 0.2;
    final shadow = Offset(size * 0.09, size * 0.11);
    Widget line(TextStyle s) =>
        Text(text, maxLines: 1, softWrap: false, style: s);
    return Stack(
      children: [
        Transform.translate(
          offset: shadow,
          child: line(style(stroke(Colors.black, w * 0.86), null)),
        ),
        line(style(stroke(Look.ink, w), null)),
        line(style(null, color)),
      ],
    );
  }
}
