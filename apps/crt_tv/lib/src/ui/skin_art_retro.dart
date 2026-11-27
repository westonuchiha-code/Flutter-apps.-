import 'dart:math';
import 'dart:ui' show PointMode;

import 'package:material_ui/material_ui.dart';

import 'skin_art.dart';

/// The painted cabinets for the retro sets: real kinds of television from
/// the 80s and 90s. Same rules as the themed ones in skin_art.dart.

// -----------------------------------------------------------------------------
// 1984 boombox TV: brushed silver, black bands, chrome-ringed speakers.

void _driver(Canvas canvas, Offset centre, double r) {
  canvas.drawCircle(
    centre.translate(0, r * 0.06),
    r * 1.03,
    Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.1),
  );
  final ring = Rect.fromCircle(center: centre, radius: r);
  canvas.drawCircle(
    centre,
    r,
    Paint()
      ..shader = const SweepGradient(
        colors: [
          Color(0xFFFFFFFF),
          Color(0xFF8D939B),
          Color(0xFFE9ECEF),
          Color(0xFF6F757D),
          Color(0xFFF4F6F8),
          Color(0xFF8D939B),
          Color(0xFFFFFFFF),
        ],
      ).createShader(ring),
  );
  canvas.drawCircle(
    centre,
    r * 0.86,
    Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFF3C3C40), Color(0xFF0B0B0C)],
      ).createShader(ring),
  );
  for (final at in [0.72, 0.58, 0.44]) {
    canvas.drawCircle(
      centre,
      r * at,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.0, r * 0.025)
        ..color = Colors.white.withValues(alpha: 0.1),
    );
  }
  canvas.drawCircle(
    centre,
    r * 0.27,
    Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.3, -0.4),
        colors: [Color(0xFF6A6B70), Color(0xFF17171A)],
      ).createShader(Rect.fromCircle(center: centre, radius: r * 0.27)),
  );
  for (var i = 0; i < 4; i++) {
    final a = pi / 4 + i * pi / 2;
    canvas.drawCircle(
      centre + Offset(cos(a), sin(a)) * r * 0.93,
      r * 0.035,
      Paint()..color = const Color(0xFF2A2C30),
    );
  }
}

void paintBoombox(
  Canvas canvas,
  Size size,
  Rect? screen,
  double bezel,
  bool dressed,
) {
  final rect = Offset.zero & size;
  final u = size.height / 100;
  canvas.drawRect(
    rect,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFD9DCE0), Color(0xFFA9ADB3), Color(0xFF8B8F96)],
      ).createShader(rect),
  );
  final brush = Random(84);
  final line = Paint()..strokeWidth = 1;
  for (var y = 0.0; y < size.height; y += 1.6) {
    line.color = (brush.nextBool() ? Colors.white : Colors.black).withValues(
      alpha: brush.nextDouble() * 0.07,
    );
    canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
  }
  // Black bands top and bottom, with a red pinstripe inside each.
  for (final band in [
    Rect.fromLTWH(0, 0, size.width, size.height * 0.052),
    Rect.fromLTWH(0, size.height * 0.948, size.width, size.height * 0.052),
  ]) {
    canvas.drawRect(
      band,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2A2B2E), Color(0xFF0E0E10)],
        ).createShader(band),
    );
  }
  final stripe = Paint()
    ..color = const Color(0xFFE5231B)
    ..strokeWidth = u * 0.4;
  canvas.drawLine(
    Offset(0, size.height * 0.064),
    Offset(size.width, size.height * 0.064),
    stripe,
  );
  canvas.drawLine(
    Offset(0, size.height * 0.936),
    Offset(size.width, size.height * 0.936),
    stripe,
  );
  if (screen == null) return;

  final frameRect = screen.inflate(bezel);
  final pillar = frameRect.left;
  final frame = RRect.fromRectAndRadius(
    frameRect,
    Radius.circular(bezel * 0.5),
  );
  artShadow(canvas, Path()..addRRect(frame.inflate(bezel * 0.1)), bezel * 0.4);
  canvas.drawRRect(
    frame,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF303135), Color(0xFF0B0B0C)],
      ).createShader(frameRect),
  );
  canvas.drawRRect(
    frame.deflate(1),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFFFFF), Color(0xFF7C828A), Color(0xFFE2E5E8)],
      ).createShader(frameRect),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      screen.inflate(bezel * 0.12),
      Radius.circular(bezel * 0.35),
    ),
    Paint()..color = const Color(0xFF050505),
  );
  artText(
    canvas,
    'STEREO VISION',
    Offset(screen.center.dx, frameRect.bottom - bezel * 0.4),
    bezel * 0.3,
    const Color(0xFFD9DCE0),
    spacing: bezel * 0.16,
  );
  if (!dressed) return;

  final cx = pillar / 2;
  _driver(canvas, Offset(cx, size.height * 0.2), pillar * 0.19);
  _driver(canvas, Offset(cx, size.height * 0.59), pillar * 0.37);
  artText(
    canvas,
    'BASS REFLEX',
    Offset(cx, size.height * 0.885),
    u * 1.6,
    const Color(0xFF2A2D31),
    spacing: u * 0.35,
  );

  final rx = frameRect.right;
  _driver(canvas, Offset(rx + pillar * 0.5, size.height * 0.165), pillar * 0.2);
  // LED level meters.
  final meters = Rect.fromLTWH(
    rx + pillar * 0.18,
    size.height * 0.3,
    pillar * 0.64,
    size.height * 0.1,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(meters, Radius.circular(u * 0.6)),
    Paint()..color = const Color(0xFF0C0D0F),
  );
  const levels = [3, 5, 4, 6, 2, 4, 5, 3];
  final cellW = meters.width / (levels.length + 1);
  final cellH = meters.height / 7.5;
  for (var column = 0; column < levels.length; column++) {
    for (var segment = 0; segment < 6; segment++) {
      final lit = segment < levels[column];
      final colour = segment < 3
          ? const Color(0xFF37E66B)
          : (segment < 5 ? const Color(0xFFFFD23F) : const Color(0xFFFF4136));
      canvas.drawRect(
        Rect.fromLTWH(
          meters.left + cellW * (column + 0.6),
          meters.bottom - cellH * (segment + 1.5),
          cellW * 0.72,
          cellH * 0.66,
        ),
        Paint()..color = lit ? colour : const Color(0xFF26292D),
      );
    }
  }
}

// -----------------------------------------------------------------------------
// 1987 sport portable: glossy red plastic, antenna, yellow trim.

void paintPortable(
  Canvas canvas,
  Size size,
  Rect? screen,
  double bezel,
  bool dressed,
) {
  final rect = Offset.zero & size;
  final u = size.height / 100;
  canvas.drawRect(
    rect,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFF03226), Color(0xFFC81C12), Color(0xFF9E100A)],
      ).createShader(rect),
  );
  // Gloss: a soft bloom up top and a hard reflection streak.
  canvas.drawOval(
    Rect.fromLTWH(
      -size.width * 0.15,
      -size.height * 0.5,
      size.width * 0.8,
      size.height * 0.85,
    ),
    Paint()
      ..color = Colors.white.withValues(alpha: 0.2)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * 7),
  );
  canvas.drawPath(
    Path()
      ..moveTo(size.width * 0.02, 0)
      ..lineTo(size.width * 0.075, 0)
      ..lineTo(size.width * 0.01, size.height * 0.5)
      ..lineTo(0, size.height * 0.5)
      ..lineTo(0, size.height * 0.16)
      ..close(),
    Paint()..color = Colors.white.withValues(alpha: 0.13),
  );
  const yellow = Color(0xFFFFD23F);
  canvas.drawLine(
    Offset(0, size.height * 0.925),
    Offset(size.width, size.height * 0.925),
    Paint()
      ..color = yellow
      ..strokeWidth = u * 1.0,
  );
  canvas.drawLine(
    Offset(0, size.height * 0.948),
    Offset(size.width, size.height * 0.948),
    Paint()
      ..color = yellow
      ..strokeWidth = u * 0.35,
  );
  if (screen == null) return;

  final frameRect = screen.inflate(bezel);
  final pillar = frameRect.left;
  final frame = RRect.fromRectAndRadius(
    frameRect,
    Radius.circular(bezel * 1.3),
  );
  artShadow(
    canvas,
    Path()..addRRect(frame.inflate(bezel * 0.06)),
    bezel * 0.35,
  );
  canvas.drawRRect(
    frame,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF333336), Color(0xFF111113)],
      ).createShader(frameRect),
  );
  canvas.drawRRect(
    frame.deflate(1),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: 0.22),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      screen.inflate(bezel * 0.42),
      Radius.circular(bezel * 0.95),
    ),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.5, u * 0.3)
      ..color = const Color(0xFF5B5C61),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      screen.inflate(bezel * 0.1),
      Radius.circular(bezel * 0.6),
    ),
    Paint()..color = const Color(0xFF050505),
  );
  artText(
    canvas,
    'COLOR PORTABLE',
    Offset(screen.center.dx, frameRect.bottom - bezel * 0.27),
    bezel * 0.26,
    Colors.white.withValues(alpha: 0.8),
    spacing: bezel * 0.14,
  );
  if (!dressed) return;

  final cx = pillar / 2;
  // Telescoping antenna, in three sections that thin towards the tip.
  final base = Offset(cx * 1.5, size.height * 0.37);
  final tip = Offset(cx * 0.45, size.height * 0.045);
  for (final (from, to, width) in [
    (0.0, 0.4, 1.0),
    (0.4, 0.72, 0.7),
    (0.72, 1.0, 0.45),
  ]) {
    final a = Offset.lerp(base, tip, from)!;
    final b = Offset.lerp(base, tip, to)!;
    canvas.drawLine(
      a.translate(u * 0.25, u * 0.25),
      b.translate(u * 0.25, u * 0.25),
      Paint()
        ..strokeWidth = u * width
        ..strokeCap = StrokeCap.round
        ..color = Colors.black.withValues(alpha: 0.3),
    );
    canvas.drawLine(
      a,
      b,
      Paint()
        ..strokeWidth = u * width
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFD5D9DD),
    );
    canvas.drawLine(
      a.translate(-u * width * 0.2, 0),
      b.translate(-u * width * 0.2, 0),
      Paint()
        ..strokeWidth = max(1.0, u * width * 0.25)
        ..strokeCap = StrokeCap.round
        ..color = Colors.white,
    );
  }
  canvas.drawCircle(tip, u * 0.85, Paint()..color = const Color(0xFFE9ECEF));
  canvas.drawCircle(base, u * 1.6, Paint()..color = const Color(0xFF1B1B1D));
  canvas.drawCircle(base, u * 0.8, Paint()..color = const Color(0xFFB9BEC4));

  // Speaker: moulded vertical slots.
  for (var i = 0; i < 6; i++) {
    final slot = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        cx - pillar * 0.3 + i * pillar * 0.108,
        size.height * 0.48,
        pillar * 0.055,
        size.height * 0.3,
      ),
      Radius.circular(pillar * 0.03),
    );
    canvas.drawRRect(slot, Paint()..color = const Color(0xFF5E0805));
    canvas.drawRRect(
      slot.shift(Offset(pillar * 0.012, 0)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.16),
    );
  }
  artText(
    canvas,
    'SPORT',
    Offset(cx + u * 0.3, size.height * 0.855 + u * 0.3),
    u * 3.4,
    Colors.black.withValues(alpha: 0.45),
    angle: -0.08,
    italic: true,
    spacing: u * 0.5,
  );
  artText(
    canvas,
    'SPORT',
    Offset(cx, size.height * 0.855),
    u * 3.4,
    yellow,
    angle: -0.08,
    italic: true,
    spacing: u * 0.5,
  );

  // Right, above the dials: a little colour-bar badge.
  final rx = frameRect.right;
  const bars = [
    Color(0xFFFFD23F),
    Color(0xFFFF8A3D),
    Color(0xFF37C66B),
    Color(0xFF2D7FF9),
    Color(0xFF7B4DFF),
  ];
  final left = rx + pillar * 0.5 - u * 3.2;
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(left - u * 0.6, size.height * 0.05, u * 7.6, u * 4.2),
      Radius.circular(u * 0.5),
    ),
    Paint()..color = const Color(0xFF151517),
  );
  for (var i = 0; i < bars.length; i++) {
    canvas.drawRect(
      Rect.fromLTWH(
        left + i * u * 1.28,
        size.height * 0.05 + u * 0.6,
        u * 1.0,
        u * 3.0,
      ),
      Paint()..color = bars[i],
    );
  }
  artText(
    canvas,
    'COLOR',
    Offset(rx + pillar * 0.5, size.height * 0.05 + u * 5.6),
    u * 1.5,
    Colors.white.withValues(alpha: 0.85),
    spacing: u * 0.4,
  );
}

// -----------------------------------------------------------------------------
// 1993 TV/VCR combo: black plastic with the tape deck under the screen.

/// Where the VCR's clock window sits in the chin under the screen.
Rect comboClockRect(Rect chin) => Rect.fromLTWH(
  chin.left + chin.width * 0.73,
  chin.top + chin.height * 0.29,
  chin.width * 0.17,
  chin.height * 0.42,
);

void _slats(Canvas canvas, Rect area, double u) {
  for (var y = area.top; y < area.bottom; y += u * 1.15) {
    canvas.drawLine(
      Offset(area.left, y),
      Offset(area.right, y),
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = max(1.5, u * 0.42)
        ..color = Colors.black.withValues(alpha: 0.8),
    );
    canvas.drawLine(
      Offset(area.left, y + u * 0.36),
      Offset(area.right, y + u * 0.36),
      Paint()
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.09),
    );
  }
}

void paintCombo(
  Canvas canvas,
  Size size,
  Rect? screen,
  double bezel,
  bool dressed,
  Rect? chin,
) {
  final rect = Offset.zero & size;
  final u = size.height / 100;
  canvas.drawRect(
    rect,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF303033), Color(0xFF151517)],
      ).createShader(rect),
  );
  final grain = Random(93);
  final light = <Offset>[];
  final dark = <Offset>[];
  for (
    var i = 0;
    i < (size.width * size.height / 600).round().clamp(200, 7000);
    i++
  ) {
    (grain.nextBool() ? light : dark).add(
      Offset(grain.nextDouble() * size.width, grain.nextDouble() * size.height),
    );
  }
  final speck = Paint()
    ..strokeWidth = 1.2
    ..strokeCap = StrokeCap.round;
  canvas.drawPoints(
    PointMode.points,
    light,
    speck..color = Colors.white.withValues(alpha: 0.06),
  );
  canvas.drawPoints(
    PointMode.points,
    dark,
    speck..color = Colors.black.withValues(alpha: 0.14),
  );
  if (screen == null) return;

  final frameRect = screen.inflate(bezel);
  final pillar = frameRect.left;
  final frame = RRect.fromRectAndRadius(frameRect, Radius.circular(bezel));
  artShadow(
    canvas,
    Path()..addRRect(frame.inflate(bezel * 0.08)),
    bezel * 0.35,
  );
  canvas.drawRRect(
    frame,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF3F4044), Color(0xFF1E1F22)],
      ).createShader(frameRect),
  );
  canvas.drawRRect(
    frame.deflate(0.75),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.25),
          Colors.black.withValues(alpha: 0.35),
        ],
      ).createShader(frameRect),
  );
  final slope = screen.inflate(bezel * 0.45);
  canvas.drawRRect(
    RRect.fromRectAndRadius(slope, Radius.circular(bezel * 0.8)),
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF08080A), Color(0xFF141417), Color(0xFF28292D)],
      ).createShader(slope),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      screen.inflate(bezel * 0.07),
      Radius.circular(bezel * 0.5),
    ),
    Paint()..color = const Color(0xFF050505),
  );

  if (chin != null && chin.height > 8) {
    const print = Color(0xFFB9BABF);
    // Tape slot with its flap.
    final slot = Rect.fromCenter(
      center: Offset(chin.left + chin.width * 0.465, chin.center.dy),
      width: chin.width * 0.38,
      height: chin.height * 0.4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(slot.inflate(u * 0.35), Radius.circular(u * 0.7)),
      Paint()..color = const Color(0xFF3A3B3F),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(slot, Radius.circular(u * 0.5)),
      Paint()..color = const Color(0xFF030303),
    );
    final flap = Rect.fromLTRB(
      slot.left,
      slot.top,
      slot.right,
      slot.top + slot.height * 0.72,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(flap, Radius.circular(u * 0.5)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF26262A), Color(0xFF0F0F11)],
        ).createShader(flap),
    );
    canvas.drawLine(
      flap.topLeft.translate(u, u * 0.3),
      flap.topRight.translate(-u, u * 0.3),
      Paint()
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.2),
    );
    artText(
      canvas,
      'VIDEO CASSETTE',
      Offset(slot.center.dx, flap.center.dy),
      chin.height * 0.13,
      print.withValues(alpha: 0.55),
      spacing: chin.height * 0.05,
    );

    // Transport keys.
    const symbols = ['◄◄', '►', '►►', '■', '▲'];
    final keyW = chin.width * 0.036;
    for (var i = 0; i < symbols.length; i++) {
      final key = Rect.fromLTWH(
        chin.left + chin.width * 0.025 + i * keyW * 1.18,
        chin.center.dy - chin.height * 0.16,
        keyW,
        chin.height * 0.32,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(key, Radius.circular(u * 0.3)),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF55565B), Color(0xFF2B2C30)],
          ).createShader(key),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(key, Radius.circular(u * 0.3)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.black.withValues(alpha: 0.7),
      );
      artText(canvas, symbols[i], key.center, chin.height * 0.15, print);
    }

    // The clock's window; the blinking digits are drawn on top of it.
    final clock = comboClockRect(chin);
    canvas.drawRRect(
      RRect.fromRectAndRadius(clock.inflate(u * 0.3), Radius.circular(u * 0.5)),
      Paint()..color = const Color(0xFF3A3B3F),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(clock, Radius.circular(u * 0.35)),
      Paint()..color = const Color(0xFF020504),
    );
    final led = Offset(clock.right + chin.width * 0.035, clock.center.dy);
    canvas.drawCircle(
      led,
      chin.height * 0.06,
      Paint()..color = const Color(0xFF5A0F0B),
    );
    artText(
      canvas,
      'REC',
      led.translate(0, chin.height * 0.22),
      chin.height * 0.11,
      print.withValues(alpha: 0.6),
    );
  }
  if (!dressed) return;

  final cx = pillar / 2;
  _slats(
    canvas,
    Rect.fromCenter(
      center: Offset(cx, size.height * 0.46),
      width: pillar * 0.56,
      height: size.height * 0.5,
    ),
    u,
  );
  final badge = Rect.fromCenter(
    center: Offset(cx, size.height * 0.84),
    width: pillar * 0.42,
    height: u * 3,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(badge, Radius.circular(u * 0.4)),
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFE6E8EB), Color(0xFF8E939A)],
      ).createShader(badge),
  );
  artText(
    canvas,
    'HI-FI',
    badge.center,
    u * 1.8,
    const Color(0xFF1B1C1F),
    spacing: u * 0.4,
  );
  _slats(
    canvas,
    Rect.fromLTWH(
      frameRect.right + pillar * 0.22,
      size.height * 0.08,
      pillar * 0.56,
      size.height * 0.29,
    ),
    u,
  );
}

// -----------------------------------------------------------------------------
// 1998 see-through: translucent purple plastic with the works on show.

void _screw(Canvas canvas, Offset at, double r) {
  canvas.drawCircle(at, r, Paint()..color = const Color(0xFFB9BEC4));
  canvas.drawCircle(
    at.translate(-r * 0.25, -r * 0.3),
    r * 0.4,
    Paint()..color = Colors.white.withValues(alpha: 0.6),
  );
  final slot = Paint()
    ..strokeWidth = max(1.0, r * 0.28)
    ..color = const Color(0xFF3A3D42);
  canvas.drawLine(at.translate(-r * 0.6, 0), at.translate(r * 0.6, 0), slot);
  canvas.drawLine(at.translate(0, -r * 0.6), at.translate(0, r * 0.6), slot);
}

/// A circuit board and its parts, filling [area]. [cone] adds a speaker.
void _innards(
  Canvas canvas,
  Rect area,
  Random random,
  double u, {
  required bool cone,
  double fill = 1,
}) {
  if (area.width < u * 8) return;
  final board = RRect.fromRectAndRadius(
    area.deflate(u * 1.2),
    Radius.circular(u),
  );
  canvas.drawRRect(board, Paint()..color = const Color(0xFF1C7443));
  canvas.save();
  canvas.clipRRect(board);
  // Copper traces with solder points.
  final trace = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = max(1.0, u * 0.22)
    ..color = const Color(0xFF55C487).withValues(alpha: 0.75);
  for (var i = 0; i < (area.height / u * 0.7).round(); i++) {
    var p = Offset(
      area.left + random.nextDouble() * area.width,
      area.top + random.nextDouble() * area.height,
    );
    final path = Path()..moveTo(p.dx, p.dy);
    for (var s = 0; s < 3; s++) {
      p += s.isEven
          ? Offset((random.nextDouble() - 0.5) * u * 14, 0)
          : Offset(0, (random.nextDouble() - 0.5) * u * 14);
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, trace);
    canvas.drawCircle(p, u * 0.4, Paint()..color = const Color(0xFFD8DDE2));
  }

  final speaker = Offset(area.center.dx, area.top + area.height * 0.5);
  final speakerR = area.width * 0.32;
  final bottom = area.top + area.height * fill;
  var y = area.top + u * 4;
  while (y < bottom - u * 5) {
    final x = area.left + area.width * (0.3 + random.nextDouble() * 0.4);
    final at = Offset(x, y);
    final inSpeaker = cone && (y - speaker.dy).abs() < speakerR + u * 4;
    final kind = random.nextInt(5);
    var height = u * 6;
    if (inSpeaker) {
      height = u * 3;
    } else if (kind == 0) {
      // A chip with legs down both long sides.
      final body = Rect.fromCenter(
        center: at,
        width: area.width * 0.46,
        height: u * 4.2,
      );
      for (var leg = body.left + u * 0.5; leg < body.right; leg += u * 1.1) {
        canvas.drawRect(
          Rect.fromLTWH(
            leg,
            body.top - u * 0.6,
            u * 0.45,
            body.height + u * 1.2,
          ),
          Paint()..color = const Color(0xFFC9CED3),
        );
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(body, Radius.circular(u * 0.3)),
        Paint()..color = const Color(0xFF151518),
      );
      canvas.drawCircle(
        body.centerLeft.translate(u * 0.9, 0),
        u * 0.35,
        Paint()..color = const Color(0xFF3A3A3F),
      );
      artText(
        canvas,
        'CX${1000 + random.nextInt(8999)}',
        body.center.translate(u * 0.6, 0),
        u * 1.2,
        Colors.white.withValues(alpha: 0.55),
      );
      height = u * 8;
    } else if (kind == 1) {
      // A pair of can capacitors seen from above.
      for (final dx in [-1.0, 1.0]) {
        final c = at.translate(dx * u * 2.6, 0);
        final r = u * (1.5 + random.nextDouble() * 0.6);
        canvas.drawCircle(
          c.translate(u * 0.3, u * 0.4),
          r,
          Paint()..color = Colors.black.withValues(alpha: 0.4),
        );
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..color = dx < 0
                ? const Color(0xFF2B55C9)
                : const Color(0xFF1A1A1D),
        );
        canvas.drawCircle(
          c,
          r * 0.72,
          Paint()..color = const Color(0xFFC9CED3),
        );
        canvas.drawLine(
          c.translate(-r * 0.5, 0),
          c.translate(r * 0.5, 0),
          Paint()
            ..strokeWidth = 1
            ..color = const Color(0xFF6C737B),
        );
      }
      height = u * 6.5;
    } else if (kind == 2) {
      // A row of resistors with colour bands.
      for (var i = -1; i <= 1; i++) {
        final body = Rect.fromCenter(
          center: at.translate(i * u * 3.4, 0),
          width: u * 2.6,
          height: u * 1.0,
        );
        canvas.drawLine(
          body.centerLeft.translate(-u * 0.5, 0),
          body.centerRight.translate(u * 0.5, 0),
          Paint()
            ..strokeWidth = 1
            ..color = const Color(0xFFC9CED3),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(body, Radius.circular(u * 0.4)),
          Paint()..color = const Color(0xFFD8B27A),
        );
        const bands = [Color(0xFF7A3B16), Color(0xFFE5231B), Color(0xFFFFD23F)];
        for (var b = 0; b < 3; b++) {
          canvas.drawRect(
            Rect.fromLTWH(
              body.left + u * (0.5 + b * 0.6),
              body.top,
              u * 0.28,
              body.height,
            ),
            Paint()..color = bands[(b + i + 3) % 3],
          );
        }
      }
      height = u * 4;
    } else if (kind == 3) {
      // A wound coil.
      final body = Rect.fromCenter(center: at, width: u * 6, height: u * 3.6);
      canvas.drawRRect(
        RRect.fromRectAndRadius(body, Radius.circular(u * 0.8)),
        Paint()..color = const Color(0xFFC2701F),
      );
      for (var w = body.left + u * 0.5; w < body.right; w += u * 0.55) {
        canvas.drawLine(
          Offset(w, body.top + u * 0.2),
          Offset(w, body.bottom - u * 0.2),
          Paint()
            ..strokeWidth = 1
            ..color = const Color(0xFF7A3F0E),
        );
      }
      height = u * 6.5;
    } else {
      // A ribbon cable crossing the board.
      for (var w = 0; w < 7; w++) {
        canvas.drawLine(
          Offset(area.left, y + w * u * 0.5),
          Offset(area.right, y + u * 2 + w * u * 0.5),
          Paint()
            ..strokeWidth = max(1.0, u * 0.3)
            ..color = w == 0
                ? const Color(0xFFE5231B)
                : const Color(0xFFBFC4CA),
        );
      }
      height = u * 7;
    }
    y += height;
  }

  if (cone) {
    // The speaker from behind its grille: frame, paper cone, magnet, wires.
    canvas.drawCircle(
      speaker,
      speakerR,
      Paint()..color = const Color(0xFF2C2D31),
    );
    canvas.drawCircle(
      speaker,
      speakerR * 0.9,
      Paint()
        ..shader =
            const RadialGradient(colors: [Color(0xFF8C8C92), Color(0xFF3A3A3F)])
                .createShader(
                  Rect.fromCircle(center: speaker, radius: speakerR * 0.9),
                ),
    );
    for (final at in [0.7, 0.5]) {
      canvas.drawCircle(
        speaker,
        speakerR * at,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.black.withValues(alpha: 0.3),
      );
    }
    canvas.drawCircle(
      speaker,
      speakerR * 0.32,
      Paint()..color = const Color(0xFFC9CED3),
    );
    canvas.drawCircle(
      speaker,
      speakerR * 0.2,
      Paint()..color = const Color(0xFF6C737B),
    );
    for (final (colour, side) in [
      (const Color(0xFFE5231B), -1.0),
      (const Color(0xFF151518), 1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(
            speaker.dx + side * speakerR * 0.2,
            speaker.dy + speakerR * 0.25,
          )
          ..quadraticBezierTo(
            speaker.dx + side * speakerR * 1.1,
            speaker.dy + speakerR * 1.2,
            speaker.dx + side * speakerR * 0.4,
            speaker.dy + speakerR * 1.9,
          ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(1.5, u * 0.4)
          ..color = colour,
      );
    }
  }
  canvas.restore();
}

void paintClear(
  Canvas canvas,
  Size size,
  Rect? screen,
  double bezel,
  bool dressed,
) {
  final rect = Offset.zero & size;
  final u = size.height / 100;
  canvas.drawRect(rect, Paint()..color = const Color(0xFF1A1130));

  final frameRect = screen?.inflate(bezel);
  if (frameRect != null && dressed) {
    final pillar = frameRect.left;
    _innards(
      canvas,
      Rect.fromLTRB(0, 0, pillar, size.height),
      Random(98),
      u,
      cone: true,
    );
    // Parts only above the buttons on the right.
    _innards(
      canvas,
      Rect.fromLTRB(frameRect.right, 0, size.width, size.height),
      Random(99),
      u,
      cone: false,
      fill: 0.42,
    );
  }
  // The plastic itself: a purple tint, lighter where the light falls.
  canvas.drawRect(
    rect,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0x4D9B6BFF), Color(0x426A35D8), Color(0x5C4A1FA8)],
      ).createShader(rect),
  );
  for (final (start, width) in [(0.03, 0.03), (0.075, 0.012), (0.93, 0.02)]) {
    canvas.drawPath(
      Path()
        ..moveTo(size.width * start, 0)
        ..lineTo(size.width * (start + width), 0)
        ..lineTo(size.width * (start + width - 0.05), size.height)
        ..lineTo(size.width * (start - 0.05), size.height)
        ..close(),
      Paint()..color = Colors.white.withValues(alpha: 0.11),
    );
  }
  if (screen == null || frameRect == null) return;

  if (dressed) {
    // A smoked panel behind the buttons, so their labels stay readable.
    final pillar = frameRect.left;
    final plate = RRect.fromRectAndRadius(
      Rect.fromLTRB(
        frameRect.right + pillar * 0.1,
        size.height * 0.41,
        size.width - pillar * 0.1,
        size.height * 0.965,
      ),
      Radius.circular(u * 1.4),
    );
    canvas.drawRRect(plate, Paint()..color = const Color(0xB3190B45));
    canvas.drawRRect(
      plate,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.25),
    );
  }

  final frame = RRect.fromRectAndRadius(frameRect, Radius.circular(bezel));
  artShadow(canvas, Path()..addRRect(frame.inflate(bezel * 0.06)), bezel * 0.4);
  canvas.drawRRect(
    frame,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xF2A07BFF), Color(0xF26A3BDB), Color(0xF2431C9E)],
      ).createShader(frameRect),
  );
  canvas.drawRRect(
    frame.deflate(1),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.6),
          Colors.white.withValues(alpha: 0.05),
        ],
      ).createShader(frameRect),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      screen.inflate(bezel * 0.36),
      Radius.circular(bezel * 0.75),
    ),
    Paint()..color = const Color(0xFF2B1470),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      screen.inflate(bezel * 0.1),
      Radius.circular(bezel * 0.5),
    ),
    Paint()..color = const Color(0xFF05030B),
  );
  final r = max(2.0, bezel * 0.15);
  final inset = bezel * 0.5;
  for (final corner in [
    Offset(frameRect.left + inset, frameRect.top + inset),
    Offset(frameRect.right - inset, frameRect.top + inset),
    Offset(frameRect.left + inset, frameRect.bottom - inset),
    Offset(frameRect.right - inset, frameRect.bottom - inset),
  ]) {
    _screw(canvas, corner, r);
  }
  artText(
    canvas,
    'clear-tech',
    Offset(screen.center.dx, frameRect.bottom - bezel * 0.3),
    bezel * 0.34,
    Colors.white.withValues(alpha: 0.85),
    italic: true,
    spacing: bezel * 0.06,
  );
}
