import 'dart:math' as math;
import 'dart:typed_data';

import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../model/controls.dart';
import '../model/session.dart';
import 'layout.dart';
import 'paint_kit.dart';

/// The Wii U Pro Controller (RVL-CNT-01-UC), drawn from the front as it
/// is: both sticks high and wide apart on top, the d-pad below and inside
/// the left stick, A/B/X/Y below and inside the right stick in Nintendo's
/// diamond (X top, A right, B bottom, Y left), −, HOME and + across the
/// middle with POWER under HOME, the four player lights at the bottom,
/// L/R on the top edge with ZL/ZR behind them. White or black body.
///
/// Through SDL's Wii driver the buttons are positional, so Nintendo's A
/// (right) is SDL's east, B (bottom) south, X (top) north, Y (left) west.
/// ZL/ZR are digital but SDL reports them as full-scale trigger axes.
class WiiUProLayout extends ControllerLayout {
  const WiiUProLayout();

  @override
  String get id => 'wii_u_pro';

  @override
  String get title => 'Wii U Pro Controller';

  @override
  bool matches(ControllerInfo info) => mappedWiiUPro(info);

  static const _parts = [
    LayoutPart.button('a', 'A', GButton.east),
    LayoutPart.button('b', 'B', GButton.south),
    LayoutPart.button('x', 'X', GButton.north),
    LayoutPart.button('y', 'Y', GButton.west),
    LayoutPart.button('up', 'D-pad ↑', GButton.dpadUp),
    LayoutPart.button('down', 'D-pad ↓', GButton.dpadDown),
    LayoutPart.button('left', 'D-pad ←', GButton.dpadLeft),
    LayoutPart.button('right', 'D-pad →', GButton.dpadRight),
    LayoutPart.button('l', 'L', GButton.leftShoulder),
    LayoutPart.button('r', 'R', GButton.rightShoulder),
    LayoutPart.trigger('zl', 'ZL', GAxis.leftTrigger),
    LayoutPart.trigger('zr', 'ZR', GAxis.rightTrigger),
    LayoutPart.button('minus', '−', GButton.back),
    LayoutPart.button('plus', '+', GButton.start),
    LayoutPart.button('home', 'HOME', GButton.guide),
    LayoutPart.stick('ls', 'Left stick', GAxis.leftX, GAxis.leftY),
    LayoutPart.button('l3', 'Left stick click', GButton.leftStick),
    LayoutPart.stick('rs', 'Right stick', GAxis.rightX, GAxis.rightY),
    LayoutPart.button('r3', 'Right stick click', GButton.rightStick),
  ];

  @override
  List<LayoutPart> parts(ControllerInfo info) => _parts;

  @override
  Size designSize(ControllerInfo info) => const Size(1000, 600);

  // Where things are (design units).
  static const leftStick = Offset(282, 222);
  static const rightStick = Offset(718, 222);
  static const dpadAt = Offset(372, 352);
  static const faceAt = Offset(628, 352);
  static const faceGap = 46.0;

  /// The body's outline: a wide top, two long grips.
  static Path body() {
    final main = Path()
      ..addRRect(
        RRect.fromLTRBR(118, 104, 882, 420, const Radius.circular(130)),
      );
    Path grip(Offset c, double angle) {
      final m = Float64List.fromList([
        math.cos(angle), math.sin(angle), 0, 0, //
        -math.sin(angle), math.cos(angle), 0, 0,
        0, 0, 1, 0,
        c.dx, c.dy, 0, 1,
      ]);
      return (Path()..addOval(
            Rect.fromCenter(center: Offset.zero, width: 230, height: 300),
          ))
          .transform(m);
    }

    var out = Path.combine(
      PathOperation.union,
      main,
      grip(const Offset(232, 400), 0.4),
    );
    out = Path.combine(
      PathOperation.union,
      out,
      grip(const Offset(768, 400), -0.4),
    );
    return out;
  }

  @override
  void paint(
    Canvas canvas,
    ControllerInfo info,
    PadState state,
    TestSession session,
    PadPalette palette,
  ) {
    final black = palette.variant == 'black';
    final bodyFill = black ? const Color(0xFF1E1F24) : const Color(0xFFF1F1F3);
    final bodyEdge = black ? const Color(0xFF0A0A0C) : const Color(0xFFB9BAC2);
    final shoulder = black ? const Color(0xFF2A2B31) : const Color(0xFFDCDDE2);
    final zFill = black ? const Color(0xFF16161A) : const Color(0xFFC9CAD1);
    final btn = black ? const Color(0xFF2E2F36) : const Color(0xFFE2E3E8);
    final btnEdge = black ? const Color(0xFF4A4B54) : const Color(0xFFA9AAB3);
    final btnInk = black ? const Color(0xFFD9DAE0) : const Color(0xFF4A4B54);
    final well = black ? const Color(0xFF0E0E11) : const Color(0xFFC3C4CC);
    final cap = black ? const Color(0xFF303138) : const Color(0xFFE9E9EE);
    final pp = PadPainter(canvas, state, session, palette);

    // ZL / ZR (furthest back), then L / R, then the body over them.
    RRect pill(double l, double t, double r, double b) =>
        RRect.fromLTRBR(l, t, r, b, const Radius.circular(22));
    pp.shapePart(
      'zl',
      Path()..addRRect(pill(176, 40, 352, 110)),
      fill: zFill,
      edge: bodyEdge,
      label: 'ZL',
      labelAt: const Offset(264, 58),
      labelColor: btnInk,
      tickAt: const Offset(176, 46),
    );
    pp.shapePart(
      'zr',
      Path()..addRRect(pill(648, 40, 824, 110)),
      fill: zFill,
      edge: bodyEdge,
      label: 'ZR',
      labelAt: const Offset(736, 58),
      labelColor: btnInk,
      tickAt: const Offset(824, 46),
    );
    pp.shapePart(
      'l',
      Path()..addRRect(pill(150, 78, 380, 134)),
      fill: shoulder,
      edge: bodyEdge,
      label: 'L',
      labelAt: const Offset(262, 92),
      labelColor: btnInk,
      tickAt: const Offset(150, 92),
    );
    pp.shapePart(
      'r',
      Path()..addRRect(pill(620, 78, 850, 134)),
      fill: shoulder,
      edge: bodyEdge,
      label: 'R',
      labelAt: const Offset(738, 92),
      labelColor: btnInk,
      tickAt: const Offset(850, 92),
    );

    final shape = body();
    canvas.drawShadow(shape, const Color(0xFF000000), 10, false);
    canvas.drawPath(shape, Paint()..color = bodyFill);
    // A soft highlight across the top, like the glossy plastic.
    canvas.save();
    canvas.clipPath(shape);
    canvas.drawRect(
      const Rect.fromLTRB(0, 100, 1000, 300),
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 100),
          const Offset(0, 300),
          [Color(black ? 0x18FFFFFF : 0x60FFFFFF), const Color(0x00FFFFFF)],
        ),
    );
    canvas.restore();
    canvas.drawPath(
      shape,
      Paint()
        ..color = bodyEdge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    pp.stick(
      'ls',
      'l3',
      leftStick,
      well: 74,
      cap: 48,
      wellColor: well,
      capColor: cap,
      capEdge: btnEdge,
    );
    pp.stick(
      'rs',
      'r3',
      rightStick,
      well: 74,
      cap: 48,
      wellColor: well,
      capColor: cap,
      capEdge: btnEdge,
    );

    pp.dpad(dpadAt, 112, fill: btn, edge: btnEdge);

    for (final (id, label, dx, dy) in [
      ('x', 'X', 0.0, -1.0),
      ('a', 'A', 1.0, 0.0),
      ('b', 'B', 0.0, 1.0),
      ('y', 'Y', -1.0, 0.0),
    ]) {
      pp.roundButton(
        id,
        faceAt + Offset(dx, dy) * faceGap,
        25,
        fill: btn,
        edge: btnEdge,
        label: label,
        labelColor: btnInk,
        labelSize: 24,
      );
    }

    // − HOME + across the middle, POWER below HOME.
    pp.roundButton(
      'minus',
      const Offset(436, 226),
      15,
      fill: btn,
      edge: btnEdge,
      label: '−',
      labelColor: btnInk,
      labelSize: 22,
    );
    pp.roundButton(
      'plus',
      const Offset(564, 226),
      15,
      fill: btn,
      edge: btnEdge,
      label: '+',
      labelColor: btnInk,
      labelSize: 22,
    );
    pp.roundButton(
      'home',
      const Offset(500, 252),
      21,
      fill: btn,
      edge: btnEdge,
    );
    _house(canvas, const Offset(500, 252), pp.lit('home') ? bodyEdge : btnInk);
    pp.text('HOME', const Offset(500, 286), size: 11, color: btnInk);
    // POWER can't be read by any program: drawn, not tested.
    canvas.drawCircle(const Offset(500, 340), 12, Paint()..color = btn);
    canvas.drawCircle(
      const Offset(500, 340),
      12,
      Paint()
        ..color = btnEdge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    _power(canvas, const Offset(500, 340), btnInk);
    // The four player lights.
    for (var i = 0; i < 4; i++) {
      final r = Rect.fromCenter(
        center: Offset(470 + i * 20.0, 400),
        width: 10,
        height: 5,
      );
      canvas.drawRect(
        r,
        Paint()
          ..color = i == 0
              ? const Color(0xFF4FC3F7)
              : (black ? const Color(0xFF3A3B42) : const Color(0xFFC3C4CC)),
      );
    }
    pp.text('Wii U', const Offset(500, 168), size: 15, color: btnEdge);
  }

  static void _power(Canvas canvas, Offset c, Color color) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: 6),
      -math.pi / 2 + 0.6,
      2 * math.pi - 1.2,
      false,
      p,
    );
    canvas.drawLine(c - const Offset(0, 8), c - const Offset(0, 1), p);
  }

  static void _house(Canvas canvas, Offset c, Color color) {
    final p = Path()
      ..moveTo(c.dx, c.dy - 11)
      ..lineTo(c.dx + 11, c.dy - 1)
      ..lineTo(c.dx + 7, c.dy - 1)
      ..lineTo(c.dx + 7, c.dy + 9)
      ..lineTo(c.dx - 7, c.dy + 9)
      ..lineTo(c.dx - 7, c.dy - 1)
      ..lineTo(c.dx - 11, c.dy - 1)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }
}
