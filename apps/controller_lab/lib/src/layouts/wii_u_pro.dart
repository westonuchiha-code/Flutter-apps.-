import 'dart:math' as math;

import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../model/controls.dart';
import '../model/session.dart';
import 'layout.dart';
import 'paint_kit.dart';

/// The Wii U Pro Controller (RVL-CNT-01-UC), drawn from the front as it
/// is: both sticks high and wide apart on top, the d-pad below and inside
/// the left stick, A/B/X/Y below and inside the right stick in Nintendo's
/// diamond (X top, A right, B bottom, Y left), −, HOME and + in a row
/// across the top between the sticks with POWER under HOME, the four
/// player lights in slots on the bottom edge, L/R on the top edge with
/// ZL/ZR behind them, a straight-topped body with grips running down and
/// out. White (the owner's, without its paint) or black body.
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
  Size designSize(ControllerInfo info) => const Size(1000, 790);

  // Where things are (design units), measured off the owner's photos.
  static const leftStick = Offset(186, 268);
  static const rightStick = Offset(814, 268);
  static const dpadAt = Offset(302, 452);
  static const faceAt = Offset(690, 444);
  static const faceGap = 64.0;
  static const minusAt = Offset(418, 306);
  static const homeAt = Offset(500, 306);
  static const plusAt = Offset(582, 306);
  static const powerAt = Offset(500, 432);
  static const smallButton = 21.0;

  /// The right half of the outline, clockwise from the top centre, as
  /// cubic segments (two control points and an end each); the left half
  /// is its mirror. A nearly straight top that rises a little over the
  /// sticks, rounded top corners, straight outer sides and two grips that
  /// run down (and a touch out) to round tips, with the bottom edge
  /// arching up between them.
  static const _rightHalf = <List<Offset>>[
    [Offset(600, 120), Offset(700, 110), Offset(810, 110)],
    [Offset(885, 110), Offset(938, 128), Offset(950, 186)],
    [Offset(957, 260), Offset(960, 560), Offset(960, 662)],
    [Offset(960, 728), Offset(928, 756), Offset(890, 756)],
    [Offset(856, 756), Offset(838, 738), Offset(826, 708)],
    [Offset(800, 642), Offset(742, 590), Offset(672, 574)],
    [Offset(620, 562), Offset(562, 556), Offset(500, 556)],
  ];

  /// The body's outline.
  static Path body() {
    const top = Offset(500, 120);
    Offset mirror(Offset o) => Offset(1000 - o.dx, o.dy);
    final path = Path()..moveTo(top.dx, top.dy);
    for (final seg in _rightHalf) {
      path.cubicTo(
        seg[0].dx,
        seg[0].dy,
        seg[1].dx,
        seg[1].dy,
        seg[2].dx,
        seg[2].dy,
      );
    }
    // Back along the left half: each segment reversed and mirrored.
    for (var i = _rightHalf.length - 1; i >= 0; i--) {
      final seg = _rightHalf[i];
      final end = i == 0 ? top : _rightHalf[i - 1][2];
      final a = mirror(seg[1]), b = mirror(seg[0]), e = mirror(end);
      path.cubicTo(a.dx, a.dy, b.dx, b.dy, e.dx, e.dy);
    }
    return path..close();
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
    final bodyFill = black ? const Color(0xFF1E1F24) : const Color(0xFFF4F4F6);
    final bodyEdge = black ? const Color(0xFF050506) : const Color(0xFFAEB0B8);
    final bodyShade = black ? const Color(0xFF000000) : const Color(0xFF9EA0AA);
    final shoulder = black ? const Color(0xFF2A2B31) : const Color(0xFFE6E7EB);
    final zFill = black ? const Color(0xFF17171B) : const Color(0xFFD2D3D9);
    final btn = black ? const Color(0xFF2B2C33) : const Color(0xFFFAFAFB);
    final btnEdge = black ? const Color(0xFF4A4B54) : const Color(0xFFB3B5BD);
    final btnInk = black ? const Color(0xFFC9CAD2) : const Color(0xFF7A7C86);
    final shadow = black ? const Color(0x99000000) : const Color(0x33000000);
    final ring = black ? const Color(0xFF26272D) : const Color(0xFFEDEDF0);
    final well = black ? const Color(0xFF0E0E11) : const Color(0xFFD5D6DC);
    final cap = black ? const Color(0xFF303138) : const Color(0xFFF7F7F9);
    final stem = black ? const Color(0xFF1A1A1F) : const Color(0xFFC4C5CC);
    final pp = PadPainter(canvas, state, session, palette);

    // ZL / ZR on the back of the grips peek over L / R, which sit on the
    // top edge wrapping the corners; the body goes over both.
    pp.shapePart(
      'zl',
      Path()..addRRect(
        RRect.fromLTRBR(118, 40, 282, 110, const Radius.circular(20)),
      ),
      fill: zFill,
      edge: bodyEdge,
      label: 'ZL',
      labelAt: const Offset(200, 57),
      labelColor: btnInk,
      labelSize: 21,
      tickAt: const Offset(118, 46),
    );
    pp.shapePart(
      'zr',
      Path()..addRRect(
        RRect.fromLTRBR(718, 40, 882, 110, const Radius.circular(20)),
      ),
      fill: zFill,
      edge: bodyEdge,
      label: 'ZR',
      labelAt: const Offset(800, 57),
      labelColor: btnInk,
      labelSize: 21,
      tickAt: const Offset(882, 46),
    );
    pp.shapePart(
      'l',
      Path()..addRRect(
        RRect.fromLTRBAndCorners(
          52,
          74,
          296,
          190,
          topLeft: const Radius.circular(78),
          topRight: const Radius.circular(16),
          bottomLeft: const Radius.circular(16),
          bottomRight: const Radius.circular(16),
        ),
      ),
      fill: shoulder,
      edge: bodyEdge,
      label: 'L',
      labelAt: const Offset(196, 92),
      labelColor: btnInk,
      labelSize: 21,
      tickAt: const Offset(64, 104),
    );
    pp.shapePart(
      'r',
      Path()..addRRect(
        RRect.fromLTRBAndCorners(
          704,
          74,
          948,
          190,
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(78),
          bottomLeft: const Radius.circular(16),
          bottomRight: const Radius.circular(16),
        ),
      ),
      fill: shoulder,
      edge: bodyEdge,
      label: 'R',
      labelAt: const Offset(804, 92),
      labelColor: btnInk,
      labelSize: 21,
      tickAt: const Offset(936, 104),
    );

    final shape = body();
    canvas.drawShadow(shape, const Color(0xFF000000), 12, false);
    canvas.drawPath(shape, Paint()..color = bodyFill);
    canvas.save();
    canvas.clipPath(shape);
    // Glossy across the top, shading down the grips (they curve away).
    canvas.drawRect(
      const Rect.fromLTRB(0, 100, 1000, 330),
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 110),
          const Offset(0, 330),
          [Color(black ? 0x1CFFFFFF : 0x80FFFFFF), const Color(0x00FFFFFF)],
        ),
    );
    canvas.drawRect(
      const Rect.fromLTRB(0, 470, 1000, 760),
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 470),
          const Offset(0, 760),
          [
            bodyShade.withValues(alpha: 0),
            bodyShade.withValues(alpha: black ? 0.5 : 0.28),
          ],
        ),
    );
    // The bottom edge's bevel and the rim along the outer sides.
    canvas.drawPath(
      shape,
      Paint()
        ..color = bodyShade.withValues(alpha: black ? 0.6 : 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.restore();
    canvas.drawPath(
      shape,
      Paint()
        ..color = bodyEdge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // The sticks: a raised ring round each base, a tall stem, a big cap.
    for (final (id, click, c) in [
      ('ls', 'l3', leftStick),
      ('rs', 'r3', rightStick),
    ]) {
      canvas.drawCircle(
        c + const Offset(0, 4),
        86,
        Paint()
          ..color = shadow
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawCircle(c, 86, Paint()..color = ring);
      canvas.drawCircle(
        c,
        86,
        Paint()
          ..color = btnEdge
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      pp.stick(
        id,
        click,
        c,
        well: 70,
        cap: 54,
        wellColor: well,
        capColor: cap,
        capEdge: btnEdge,
        stem: 22,
        stemColor: stem,
      );
    }

    // D-pad: a chunky plus sitting in a shallow recess, a groove per arm.
    const dpadSize = 124.0;
    final arms = Path.combine(
      PathOperation.union,
      Path()..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: dpadAt, width: 46, height: dpadSize),
          const Radius.circular(8),
        ),
      ),
      Path()..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: dpadAt, width: dpadSize, height: 46),
          const Radius.circular(8),
        ),
      ),
    );
    canvas.drawPath(
      arms.shift(const Offset(0, 5)),
      Paint()
        ..color = shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawPath(arms.shift(const Offset(0, 3)), Paint()..color = btnEdge);
    pp.dpad(
      dpadAt,
      dpadSize,
      fill: btn,
      lineMarks: true,
      markColor: btnInk.withValues(alpha: 0.7),
    );
    canvas.drawPath(
      arms,
      Paint()
        ..color = btnEdge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    void raised(Offset c, double r) => canvas.drawCircle(
      c + Offset(0, r * 0.14),
      r * 1.04,
      Paint()
        ..color = shadow
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.12),
    );

    for (final (id, label, dx, dy) in [
      ('x', 'X', 0.0, -1.0),
      ('a', 'A', 1.0, 0.0),
      ('b', 'B', 0.0, 1.0),
      ('y', 'Y', -1.0, 0.0),
    ]) {
      final c = faceAt + Offset(dx, dy) * faceGap;
      raised(c, 31);
      pp.roundButton(
        id,
        c,
        31,
        fill: btn,
        edge: btnEdge,
        label: label,
        labelColor: btnInk,
        labelSize: 25,
      );
    }

    // − HOME + in a row across the top, POWER below HOME: all small.
    for (final (id, label, c) in [
      ('minus', '−', minusAt),
      ('plus', '+', plusAt),
    ]) {
      raised(c, smallButton);
      pp.roundButton(
        id,
        c,
        smallButton,
        fill: btn,
        edge: btnEdge,
        label: label,
        labelColor: btnInk,
        labelSize: 26,
      );
    }
    raised(homeAt, smallButton);
    pp.roundButton('home', homeAt, smallButton, fill: btn, edge: btnEdge);
    _house(canvas, homeAt, pp.lit('home') ? const Color(0xFF0B1A26) : btnInk);
    // POWER can't be read by any program: drawn, not tested.
    raised(powerAt, smallButton);
    canvas.drawCircle(powerAt, smallButton, Paint()..color = btn);
    canvas.drawCircle(
      powerAt,
      smallButton,
      Paint()
        ..color = btnEdge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    _power(canvas, powerAt, btnInk);

    // The four player lights: slots along the bottom edge, player 1 lit.
    for (var i = 0; i < 4; i++) {
      final r = Rect.fromCenter(
        center: Offset(440 + i * 40.0, 536),
        width: 11,
        height: 8,
      );
      canvas.drawRect(
        r,
        Paint()
          ..color = i == 0
              ? const Color(0xFF4FC3F7)
              : (black ? const Color(0xFF050506) : const Color(0xFF55575F)),
      );
    }
  }

  static void _power(Canvas canvas, Offset c, Color color) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: 8),
      -math.pi / 2 + 0.6,
      2 * math.pi - 1.2,
      false,
      p,
    );
    canvas.drawLine(c - const Offset(0, 11), c - const Offset(0, 2), p);
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
