import 'dart:math' as math;

import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../model/controls.dart';
import '../model/session.dart';
import 'layout.dart';
import 'paint_kit.dart';

/// The Wii U Pro Controller (RVL-CNT-01-UC), drawn from the front: both
/// sticks high and wide apart, the d-pad below and inside the left stick,
/// A/B/X/Y below and inside the right stick in Nintendo's diamond (X top,
/// A right, B bottom, Y left), −, HOME and + in a row between the sticks
/// with POWER under HOME, the four player lights on the bottom edge,
/// BATTERY light and the Wii U logo at the top, L/R wrapping the top
/// corners with ZL/ZR peeking over them. White or black body.
///
/// The outline and every control's place come from Nintendo's straight-on
/// photo of the black controller, traced by `tool/trace_outline.dart`
/// (threshold, outer contour, mirrored and averaged halves, Douglas–Peucker)
/// and pasted below; the body is a smooth curve through those points.
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
  Size designSize(ControllerInfo info) => const Size(1000, 740);

  // ---- from tool/trace_outline.dart (design units, 1000 wide) ----
  /// The body's right half, clockwise from the top centre to the bottom
  /// centre (traced; the left half is its mirror).
  static const bodyRight = <Offset>[
    Offset(500.0, 117.9),
    Offset(526.5, 117.8),
    Offset(593.4, 112.7),
    Offset(633.2, 106.1),
    Offset(678.2, 94.5),
    Offset(693.9, 93.6),
    Offset(741.7, 96.5),
    Offset(798.5, 103.7),
    Offset(841.7, 112.7),
    Offset(856.4, 117.8),
    Offset(863.0, 121.7),
    Offset(881.4, 145.2),
    Offset(891.3, 159.7),
    Offset(905.7, 188.2),
    Offset(922.9, 234.2),
    Offset(939.7, 293.6),
    Offset(953.6, 359.6),
    Offset(966.2, 439.3),
    Offset(973.0, 513.5),
    Offset(976.0, 581.3),
    Offset(974.1, 649.6),
    Offset(969.9, 666.4),
    Offset(963.2, 679.6),
    Offset(957.1, 687.6),
    Offset(949.7, 694.4),
    Offset(932.7, 704.6),
    Offset(913.6, 709.9),
    Offset(903.4, 710.7),
    Offset(893.1, 709.9),
    Offset(874.0, 704.7),
    Offset(865.3, 700.2),
    Offset(855.0, 693.0),
    Offset(843.4, 682.5),
    Offset(803.1, 641.3),
    Offset(745.3, 586.4),
    Offset(717.2, 564.4),
    Offset(687.3, 546.8),
    Offset(671.6, 539.9),
    Offset(652.9, 533.6),
    Offset(638.6, 529.7),
    Offset(614.0, 525.1),
    Offset(575.9, 520.9),
    Offset(500.0, 518.2),
  ];

  /// The R button's hump above the body, inner end to outer end (L is
  /// its mirror).
  static const shoulderRight = <Offset>[
    Offset(676.4, 94.9),
    Offset(690.4, 90.5),
    Offset(709.2, 79.5),
    Offset(726.0, 75.0),
    Offset(758.8, 71.1),
    Offset(786.6, 73.7),
    Offset(801.3, 80.0),
    Offset(822.2, 87.0),
    Offset(851.1, 100.6),
    Offset(857.7, 107.4),
    Offset(864.3, 123.1),
  ];

  static const leftStick = Offset(219.9, 221.6);
  static const rightStick = Offset(780.1, 221.6);
  static const stickCap = 51.7;
  static const stickRing = 75.7;
  static const stickDish = 36.4;
  static const dpadAt = Offset(323.5, 378.4);
  static const dpadSize = 134.1;
  static const dpadArm = 40.2;
  static const faceAt = Offset(676.5, 378.4);
  static const faceGap = 63.2;
  static const faceButton = 27.3;
  static const minusAt = Offset(421.5, 267.3);
  static const plusAt = Offset(578.5, 267.3);
  static const homeAt = Offset(500.0, 270.2);
  static const powerAt = Offset(500.0, 382.2);
  static const smallButton = 18.4;
  static const homeButton = 19.9;
  static const powerButton = 19.2;
  static const smallLabelY = 304.2;
  static const powerLabelY = 416.7;
  static const batteryLabelAt = Offset(500.0, 132.3);
  static const batteryLedAt = Offset(500.0, 152.4);
  static const logoAt = Offset(500.0, 207.9);
  static const logoHeight = 30.6;
  static const ledsAt = Offset(500.0, 498.1);
  static const ledGap = 38.3;
  // ---- end of traced numbers ----

  static Offset _mirror(Offset o) => Offset(1000 - o.dx, o.dy);

  /// The body's outline: a smooth closed curve through the traced points.
  static Path body() {
    final left = [
      for (final p in bodyRight.reversed.skip(1).take(bodyRight.length - 2))
        _mirror(p),
    ];
    return smoothPath([...bodyRight, ...left]);
  }

  /// A shoulder button: the traced hump, closed well under the body's top
  /// edge (the body is drawn over the lower part).
  static Path shoulder({required bool right}) {
    final hump = right ? shoulderRight : shoulderRight.map(_mirror).toList();
    final path = smoothPath(hump, closed: false);
    final out = hump.last, inner = hump.first;
    return path
      ..lineTo(out.dx + (right ? -4 : 4), out.dy + 60)
      ..lineTo(inner.dx, inner.dy + 60)
      ..close();
  }

  /// ZL/ZR: tabs on the back, peeking over L/R.
  static RRect zTab({required bool right}) {
    final r = RRect.fromLTRBR(722, 34, 800, 110, const Radius.circular(22));
    return right ? r : r.shift(Offset(1000 - r.left - r.right, 0));
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
    final bodyFill = black ? const Color(0xFF1A1B1F) : const Color(0xFFF5F5F7);
    final bodyEdge = black ? const Color(0xFF050506) : const Color(0xFFB4B6BE);
    final bodyShade = black ? const Color(0xFF000000) : const Color(0xFFA4A6B0);
    final bevel = black ? const Color(0xFF3B3C43) : const Color(0xFFD6D7DD);
    final topFace = black ? const Color(0xFF26272D) : const Color(0xFFFFFFFF);
    final shoulderFill = black
        ? const Color(0xFF2A2B31)
        : const Color(0xFFE9EAEE);
    final zFill = black ? const Color(0xFF16161A) : const Color(0xFFDADBE0);
    final btn = black ? const Color(0xFF2A2B31) : const Color(0xFFFAFAFB);
    final btnEdge = black ? const Color(0xFF55565F) : const Color(0xFFA9ABB4);
    final btnInk = black ? const Color(0xFFD5D6DC) : const Color(0xFF8A8C95);
    final print = black ? const Color(0xFFC4C5CC) : const Color(0xFF9A9CA5);
    final logo = black ? const Color(0xFFF2F2F4) : const Color(0xFF8D8F98);
    final shadow = black ? const Color(0x99000000) : const Color(0x33000000);
    final ring = black ? const Color(0xFF222328) : const Color(0xFFF0F0F3);
    final well = black ? const Color(0xFF0C0C0F) : const Color(0xFFDCDDE2);
    final cap = black ? const Color(0xFF2E2F36) : const Color(0xFFF8F8FA);
    final stem = black ? const Color(0xFF17171B) : const Color(0xFFC9CAD1);
    final pp = PadPainter(canvas, state, session, palette);

    // ZL / ZR on the back peek over L / R, which wrap the top corners;
    // the body goes over the lower part of both.
    for (final (id, label, right) in [
      ('zl', 'ZL', false),
      ('zr', 'ZR', true),
    ]) {
      final tab = zTab(right: right);
      pp.shapePart(
        id,
        Path()..addRRect(tab),
        fill: zFill,
        edge: bodyEdge,
        label: label,
        labelAt: Offset(tab.center.dx, 52),
        labelColor: btnInk,
        labelSize: 18,
        tickAt: Offset(right ? tab.right : tab.left, 38),
      );
    }
    for (final (id, label, right) in [('l', 'L', false), ('r', 'R', true)]) {
      final s = shoulderRight;
      final mid = Offset(right ? 790 : 210, (s[4].dy + s[6].dy) / 2 + 14);
      pp.shapePart(
        id,
        shoulder(right: right),
        fill: shoulderFill,
        edge: bodyEdge,
        label: label,
        labelAt: mid,
        labelColor: btnInk,
        labelSize: 16,
        tickAt: right ? _mirror(const Offset(140, 96)) : const Offset(140, 96),
      );
    }

    final shape = body();
    canvas.drawShadow(shape, const Color(0xFF000000), 12, false);
    canvas.drawPath(shape, Paint()..color = bodyFill);
    canvas.save();
    canvas.clipPath(shape);
    // The top face catches the light along the top edge; the bottom face
    // (a bevel round the arch and the grip tips) shows as a band.
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        shape,
        shape.shift(const Offset(0, 16)),
      ),
      Paint()..color = topFace.withValues(alpha: black ? 0.9 : 1),
    );
    canvas.drawRect(
      const Rect.fromLTRB(0, 100, 1000, 330),
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 110),
          const Offset(0, 330),
          [Color(black ? 0x14FFFFFF : 0x80FFFFFF), const Color(0x00FFFFFF)],
        ),
    );
    canvas.drawRect(
      const Rect.fromLTRB(0, 450, 1000, 720),
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 450),
          const Offset(0, 720),
          [
            bodyShade.withValues(alpha: 0),
            bodyShade.withValues(alpha: black ? 0.45 : 0.22),
          ],
        ),
    );
    final bottomFace = Path.combine(
      PathOperation.difference,
      shape,
      shape.shift(const Offset(0, -26)),
    );
    canvas.drawPath(bottomFace, Paint()..color = bevel);
    canvas.drawPath(
      shape,
      Paint()
        ..color = bodyShade.withValues(alpha: black ? 0.6 : 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.restore();
    canvas.drawPath(
      shape,
      Paint()
        ..color = bodyEdge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    // The charging port's slot on the top edge.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(500, bodyRight.first.dy + 3),
          width: 46,
          height: 6,
        ),
        const Radius.circular(3),
      ),
      Paint()
        ..color = black ? const Color(0xFF050506) : const Color(0xFF3A3B40),
    );

    // BATTERY with its light, and the logo.
    pp.text(
      'BATTERY',
      batteryLabelAt + const Offset(0, 4),
      size: 11,
      color: print,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: batteryLedAt, width: 8, height: 6),
        const Radius.circular(1.5),
      ),
      Paint()
        ..color = black ? const Color(0xFF4A1E1E) : const Color(0xFF5A2A2A),
    );
    _logo(canvas, pp, logoAt, logoHeight, logo, black ? bodyFill : bodyFill);

    // The sticks: a raised ring round each base, a tall stem, a big cap
    // with a dished top.
    for (final (id, click, c) in [
      ('ls', 'l3', leftStick),
      ('rs', 'r3', rightStick),
    ]) {
      canvas.drawCircle(
        c + const Offset(0, 4),
        stickRing,
        Paint()
          ..color = shadow
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawCircle(c, stickRing, Paint()..color = ring);
      canvas.drawCircle(
        c,
        stickRing,
        Paint()
          ..shader = ui.Gradient.linear(
            c - const Offset(0, stickRing),
            c + const Offset(0, stickRing),
            black
                ? const [Color(0x40FFFFFF), Color(0x00FFFFFF)]
                : const [Color(0x00000000), Color(0x22000000)],
          ),
      );
      canvas.drawCircle(
        c,
        stickRing,
        Paint()
          ..color = btnEdge
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
      pp.stick(
        id,
        click,
        c,
        well: stickRing - 10,
        cap: stickCap,
        wellColor: well,
        capColor: cap,
        capEdge: btnEdge,
        stem: 20,
        stemColor: stem,
      );
    }

    // D-pad: a plus sitting in a shallow recess, a groove per arm.
    final arms = Path.combine(
      PathOperation.union,
      Path()..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: dpadAt, width: dpadArm, height: dpadSize),
          const Radius.circular(7),
        ),
      ),
      Path()..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: dpadAt, width: dpadSize, height: dpadArm),
          const Radius.circular(7),
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
      markColor: btnInk.withValues(alpha: 0.8),
      armRatio: dpadArm / dpadSize,
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
      raised(c, faceButton);
      pp.roundButton(
        id,
        c,
        faceButton,
        fill: btn,
        edge: btnEdge,
        label: label,
        labelColor: btnInk,
        labelSize: 24,
      );
    }

    // − HOME + in a row, labelled SELECT / HOME / START; POWER below.
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
        labelSize: 24,
      );
    }
    raised(homeAt, homeButton);
    pp.roundButton('home', homeAt, homeButton, fill: btn, edge: btnEdge);
    _house(canvas, homeAt, pp.lit('home') ? const Color(0xFF0B1A26) : btnInk);
    for (final (label, x) in [
      ('SELECT', minusAt.dx),
      ('HOME', homeAt.dx),
      ('START', plusAt.dx),
    ]) {
      pp.text(label, Offset(x, smallLabelY), size: 12, color: print);
    }
    // POWER can't be read by any program: drawn, not tested.
    raised(powerAt, powerButton);
    canvas.drawCircle(powerAt, powerButton, Paint()..color = btn);
    canvas.drawCircle(
      powerAt,
      powerButton,
      Paint()
        ..color = btnEdge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    _power(canvas, powerAt, const Color(0xFFD2343A));
    pp.text('POWER', Offset(powerAt.dx, powerLabelY), size: 12, color: print);

    // The four player lights on the bottom face, player 1 lit, each with
    // its count of pips under it.
    for (var i = 0; i < 4; i++) {
      final c = ledsAt + Offset((i - 1.5) * ledGap, 0);
      final r = Rect.fromCenter(center: c, width: 9, height: 8);
      if (i == 0) {
        canvas.drawRect(
          r.inflate(4),
          Paint()
            ..color = const Color(0x664FC3F7)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
      }
      canvas.drawRect(
        r,
        Paint()
          ..color = i == 0
              ? const Color(0xFF3FA9F5)
              : (black ? const Color(0xFF0A0A0C) : const Color(0xFF45474E)),
      );
      for (var k = 0; k <= i; k++) {
        canvas.drawCircle(
          c + Offset((k - i / 2) * 4.5, 10),
          1.2,
          Paint()..color = print,
        );
      }
    }
  }

  /// "Wii" with the boxed "U" after it.
  static void _logo(
    Canvas canvas,
    PadPainter pp,
    Offset c,
    double h,
    Color ink,
    Color cutout,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: 'Wii',
        style: TextStyle(
          fontSize: h * 1.3,
          color: ink,
          fontWeight: FontWeight.w800,
          fontFamily: pp.palette.fontFamily,
          height: 1,
          letterSpacing: -1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final box = h * 0.95, gap = h * 0.12;
    final total = tp.width + gap + box;
    final x0 = c.dx - total / 2;
    tp.paint(canvas, Offset(x0, c.dy - tp.height / 2));
    final r = Rect.fromLTWH(x0 + tp.width + gap, c.dy - h * 0.6, box, box);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, Radius.circular(box * 0.2)),
      Paint()..color = ink,
    );
    // The U: a rounded cup cut out of the box.
    final u = Path()
      ..moveTo(r.left + box * 0.27, r.top + box * 0.2)
      ..lineTo(r.left + box * 0.27, r.top + box * 0.55)
      ..arcToPoint(
        Offset(r.right - box * 0.27, r.top + box * 0.55),
        radius: Radius.circular(box * 0.23),
        clockwise: false,
      )
      ..lineTo(r.right - box * 0.27, r.top + box * 0.2);
    canvas.drawPath(
      u,
      Paint()
        ..color = cutout
        ..style = PaintingStyle.stroke
        ..strokeWidth = box * 0.15
        ..strokeCap = StrokeCap.round,
    );
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
      ..moveTo(c.dx, c.dy - 10)
      ..lineTo(c.dx + 10, c.dy - 1)
      ..lineTo(c.dx + 6.5, c.dy - 1)
      ..lineTo(c.dx + 6.5, c.dy + 8)
      ..lineTo(c.dx - 6.5, c.dy + 8)
      ..lineTo(c.dx - 6.5, c.dy - 1)
      ..lineTo(c.dx - 10, c.dy - 1)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }
}
