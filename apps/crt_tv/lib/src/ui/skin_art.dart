import 'dart:math';
import 'dart:ui' show PointMode;

import 'package:material_ui/material_ui.dart';

/// The painted cabinets for the themed skins. Each takes the whole window,
/// the screen's rectangle (null when only a panel of material is wanted),
/// the bezel width, and whether the side pillars are wide enough to dress.
///
/// Everything is drawn from seeded random numbers, so a cabinet looks the
/// same every time, and sized from the window height so it scales cleanly.

void artText(
  Canvas canvas,
  String text,
  Offset center,
  double size,
  Color color, {
  double angle = 0,
  double spacing = 0,
  bool italic = false,
  String family = 'monospace',
  List<String> fallback = const ['Consolas', 'Courier New', 'DejaVu Sans Mono', 'Menlo'],
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: size,
        fontWeight: FontWeight.w800,
        letterSpacing: spacing,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        fontFamily: family,
        fontFamilyFallback: fallback,
        height: 1,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.rotate(angle);
  painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
  canvas.restore();
}

Path _chamfered(Rect r, double c) => Path()
  ..moveTo(r.left + c, r.top)
  ..lineTo(r.right - c, r.top)
  ..lineTo(r.right, r.top + c)
  ..lineTo(r.right, r.bottom - c)
  ..lineTo(r.right - c, r.bottom)
  ..lineTo(r.left + c, r.bottom)
  ..lineTo(r.left, r.bottom - c)
  ..lineTo(r.left, r.top + c)
  ..close();

void artShadow(Canvas canvas, Path shape, double blur) {
  canvas.drawPath(
    shape,
    Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
  );
}

// -----------------------------------------------------------------------------
// Cyberpunk: black-violet shell, circuit traces, neon cyan and magenta edges.

const _cyan = Color(0xFF39F3FF);
const _magenta = Color(0xFFFF3DD4);

void paintCyberpunk(Canvas canvas, Size size, Rect? screen, double bezel, bool dressed) {
  final rect = Offset.zero & size;
  final u = size.height / 100;
  canvas.drawRect(
    rect,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1C1433), Color(0xFF0A0812), Color(0xFF160B24)],
      ).createShader(rect),
  );
  final grid = Paint()
    ..color = _cyan.withValues(alpha: 0.045)
    ..strokeWidth = 1;
  for (var x = 0.0; x < size.width; x += u * 3) {
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
  }
  for (var y = 0.0; y < size.height; y += u * 3) {
    canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
  }
  if (screen == null) return;

  final frameRect = screen.inflate(bezel);
  final pillar = frameRect.left;
  _traces(canvas, Rect.fromLTRB(0, 0, pillar, size.height), Random(7), u);
  _traces(canvas, Rect.fromLTRB(frameRect.right, 0, size.width, size.height), Random(21), u);

  final frame = _chamfered(frameRect, bezel * 0.85);
  artShadow(canvas, frame, bezel * 0.5);
  canvas.drawPath(
    frame,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF2A2638), Color(0xFF12101A)],
      ).createShader(frameRect),
  );
  // Neon tube round the outside: a wide soft glow under a thin bright line.
  canvas.drawPath(
    frame,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = u * 1.1
      ..color = _cyan.withValues(alpha: 0.5)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * 1.3),
  );
  canvas.drawPath(
    frame,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.5, u * 0.24)
      ..color = _cyan,
  );
  final inner = RRect.fromRectAndRadius(screen.inflate(bezel * 0.2), Radius.circular(bezel * 0.45));
  canvas.drawRRect(
    inner,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = u * 0.8
      ..color = _magenta.withValues(alpha: 0.55)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * 0.9),
  );
  canvas.drawRRect(
    inner,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.2, u * 0.18)
      ..color = _magenta,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(screen.inflate(bezel * 0.1), Radius.circular(bezel * 0.4)),
    Paint()..color = const Color(0xFF050409),
  );
  artText(
    canvas,
    'NEON//VISION',
    Offset(screen.center.dx, frameRect.bottom - bezel * 0.36),
    bezel * 0.3,
    _cyan.withValues(alpha: 0.9),
    spacing: bezel * 0.12,
  );
  if (!dressed) return;

  // Left pillar: warning mark, glowing vent, barcode.
  final cx = pillar / 2;
  final mark = Path()
    ..moveTo(cx, size.height * 0.085)
    ..lineTo(cx + u * 3.4, size.height * 0.085 + u * 5.6)
    ..lineTo(cx - u * 3.4, size.height * 0.085 + u * 5.6)
    ..close();
  canvas.drawPath(
    mark,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.5, u * 0.3)
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFFFFE14D),
  );
  artText(canvas, '!', Offset(cx, size.height * 0.085 + u * 3.7), u * 3.2, const Color(0xFFFFE14D));
  artText(canvas, 'SYS-2049', Offset(cx, size.height * 0.2), u * 1.7, _cyan.withValues(alpha: 0.85), spacing: u * 0.25);

  final vent = Rect.fromCenter(center: Offset(cx, size.height * 0.52), width: pillar * 0.62, height: size.height * 0.46);
  canvas.drawRRect(
    RRect.fromRectAndRadius(vent.inflate(u), Radius.circular(u)),
    Paint()..color = const Color(0xFF07060C),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(vent.inflate(u), Radius.circular(u)),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = _magenta.withValues(alpha: 0.5),
  );
  for (var y = vent.top + u; y < vent.bottom - u * 0.5; y += u * 2.3) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(vent.left, y, vent.width, u * 1.1), Radius.circular(u * 0.4)),
      Paint()..color = const Color(0xFF1B1826),
    );
    canvas.drawLine(
      Offset(vent.left + u * 0.5, y + u * 1.45),
      Offset(vent.right - u * 0.5, y + u * 1.45),
      Paint()
        ..strokeWidth = max(1.0, u * 0.22)
        ..color = _magenta.withValues(alpha: 0.75)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * 0.3),
    );
  }

  final bars = Random(3);
  var x = cx - pillar * 0.28;
  while (x < cx + pillar * 0.28) {
    final w = u * (0.18 + bars.nextDouble() * 0.5);
    canvas.drawRect(
      Rect.fromLTWH(x, size.height * 0.845, w, u * 3.4),
      Paint()..color = Colors.white.withValues(alpha: 0.75),
    );
    x += w + u * (0.18 + bars.nextDouble() * 0.4);
  }
  artText(canvas, '0451-TV', Offset(cx, size.height * 0.905), u * 1.5, Colors.white.withValues(alpha: 0.6), spacing: u * 0.2);

  // Right pillar, above the buttons: a round-holed speaker with a cyan rim.
  final speaker = Rect.fromLTWH(frameRect.right + pillar * 0.19, size.height * 0.075, pillar * 0.62, size.height * 0.29);
  final plate = RRect.fromRectAndRadius(speaker, Radius.circular(u * 1.2));
  canvas.drawRRect(plate, Paint()..color = const Color(0xFF07060C));
  final holes = <Offset>[];
  final gap = max(4.0, speaker.width / 9);
  var row = 0;
  for (var y = speaker.top + gap; y <= speaker.bottom - gap * 0.8; y += gap * 0.87, row++) {
    for (var hx = speaker.left + gap + (row.isOdd ? gap / 2 : 0); hx <= speaker.right - gap * 0.8; hx += gap) {
      holes.add(Offset(hx, y));
    }
  }
  canvas.drawPoints(
    PointMode.points,
    holes,
    Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = gap * 0.5
      ..color = const Color(0xFF2B2740),
  );
  canvas.drawRRect(
    plate,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.2, u * 0.2)
      ..color = _cyan.withValues(alpha: 0.85),
  );
  artText(canvas, 'AUDIO', Offset(speaker.center.dx, speaker.bottom + u * 2), u * 1.5, _cyan.withValues(alpha: 0.7), spacing: u * 0.4);
}

/// Circuit-board traces: runs of straight and 45 degree lines ending in pads.
void _traces(Canvas canvas, Rect area, Random random, double u) {
  const directions = [
    Offset(1, 0), Offset(0, 1), Offset(-1, 0), Offset(0, -1),
    Offset(0.7, 0.7), Offset(-0.7, 0.7), Offset(0.7, -0.7), Offset(-0.7, -0.7),
  ];
  canvas.save();
  canvas.clipRect(area);
  final count = (area.width * area.height / (u * u * 120)).round().clamp(6, 60);
  for (var i = 0; i < count; i++) {
    final color = (random.nextInt(5) == 0 ? _magenta : _cyan).withValues(alpha: 0.16 + random.nextDouble() * 0.16);
    var point = Offset(
      area.left + random.nextDouble() * area.width,
      area.top + random.nextDouble() * area.height,
    );
    final path = Path()..moveTo(point.dx, point.dy);
    var heading = random.nextInt(4);
    for (var segment = 0; segment < 3 + random.nextInt(3); segment++) {
      point += directions[heading] * (u * (2.5 + random.nextDouble() * 7));
      path.lineTo(point.dx, point.dy);
      heading = random.nextBool() ? random.nextInt(4) : 4 + random.nextInt(4);
    }
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.0, u * 0.16)
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    canvas.drawPath(path, line);
    canvas.drawCircle(point, u * 0.45, line);
  }
  canvas.restore();
}

// -----------------------------------------------------------------------------
// Wasteland: salvaged olive steel, rust, rivets, hazard stripes, stencils.

void _rivet(Canvas canvas, Offset at, double r) {
  canvas.drawCircle(at.translate(r * 0.25, r * 0.35), r * 1.1, Paint()..color = Colors.black.withValues(alpha: 0.45));
  canvas.drawCircle(at, r, Paint()..color = const Color(0xFF6E6C5C));
  canvas.drawCircle(at.translate(-r * 0.3, -r * 0.35), r * 0.38, Paint()..color = Colors.white.withValues(alpha: 0.4));
}

void paintWasteland(Canvas canvas, Size size, Rect? screen, double bezel, bool dressed) {
  final rect = Offset.zero & size;
  final u = size.height / 100;
  canvas.drawRect(
    rect,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF62603F), Color(0xFF3B3A27)],
      ).createShader(rect),
  );

  final random = Random(13);
  // Rust: clusters of soft blots, thicker towards the edges.
  final rust = Paint()..maskFilter = MaskFilter.blur(BlurStyle.normal, u * 0.6);
  final patches = (size.width * size.height / (u * u * 95)).round().clamp(20, 220);
  for (var i = 0; i < patches; i++) {
    var x = random.nextDouble();
    var y = random.nextDouble();
    // Pull two thirds of them out to the rim, where water sits.
    if (random.nextInt(3) != 0) {
      if (random.nextBool()) {
        x = x < 0.5 ? x * 0.18 : 1 - (1 - x) * 0.18;
      } else {
        y = y < 0.5 ? y * 0.18 : 1 - (1 - y) * 0.18;
      }
    }
    final centre = Offset(x * size.width, y * size.height);
    for (var blot = 0; blot < 5 + random.nextInt(8); blot++) {
      rust.color = Color.lerp(const Color(0xFF5C2A0E), const Color(0xFFB0602A), random.nextDouble())!
          .withValues(alpha: 0.10 + random.nextDouble() * 0.2);
      canvas.drawCircle(
        centre + Offset((random.nextDouble() - 0.5) * u * 6, (random.nextDouble() - 0.5) * u * 6),
        u * (0.5 + random.nextDouble() * 2.4),
        rust,
      );
    }
  }
  // Grime running down from the top, then scratches down to bare metal.
  for (var i = 0; i < (size.width / (u * 6)).round(); i++) {
    final x = random.nextDouble() * size.width;
    final top = random.nextDouble() * size.height * 0.5;
    canvas.drawLine(
      Offset(x, top),
      Offset(x + u * (random.nextDouble() - 0.5), top + u * (6 + random.nextDouble() * 22)),
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = u * (0.4 + random.nextDouble() * 0.9)
        ..color = Colors.black.withValues(alpha: 0.07 + random.nextDouble() * 0.08),
    );
  }
  for (var i = 0; i < (size.width * size.height / (u * u * 140)).round(); i++) {
    final from = Offset(random.nextDouble() * size.width, random.nextDouble() * size.height);
    final angle = random.nextDouble() * pi;
    final length = u * (0.8 + random.nextDouble() * 5);
    canvas.drawLine(
      from,
      from + Offset(cos(angle), sin(angle)) * length,
      Paint()
        ..strokeWidth = 1
        ..color = const Color(0xFFEDE6C4).withValues(alpha: 0.08 + random.nextDouble() * 0.16),
    );
  }
  if (screen == null) return;

  final frameRect = screen.inflate(bezel);
  final pillar = frameRect.left;
  // Panel seams and edge rivets on both pillars.
  for (final seam in [0.335, 0.72]) {
    final y = size.height * seam;
    for (final span in [(0.0, pillar), (frameRect.right, size.width)]) {
      canvas.drawLine(Offset(span.$1, y), Offset(span.$2, y), Paint()
        ..strokeWidth = max(1.5, u * 0.3)
        ..color = Colors.black.withValues(alpha: 0.5));
      canvas.drawLine(Offset(span.$1, y + u * 0.3), Offset(span.$2, y + u * 0.3), Paint()
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.12));
    }
  }
  if (pillar > u * 8) {
    for (var y = u * 4; y < size.height - u * 2; y += u * 8) {
      _rivet(canvas, Offset(u * 1.8, y), u * 0.55);
      _rivet(canvas, Offset(size.width - u * 1.8, y), u * 0.55);
    }
  }

  final frame = RRect.fromRectAndRadius(frameRect, Radius.circular(bezel * 0.35));
  artShadow(canvas, Path()..addRRect(frame.inflate(bezel * 0.1)), bezel * 0.45);
  canvas.drawRRect(
    frame,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF55554C), Color(0xFF2C2C27)],
      ).createShader(frameRect),
  );
  canvas.drawRRect(
    frame.deflate(1),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white.withValues(alpha: 0.3), Colors.black.withValues(alpha: 0.5)],
      ).createShader(frameRect),
  );

  // Worn hazard stripes on the strip under the glass.
  final band = Rect.fromLTRB(screen.left, screen.bottom + bezel * 0.34, screen.right, frameRect.bottom - bezel * 0.16);
  canvas.save();
  canvas.clipRect(band);
  canvas.drawRect(band, Paint()..color = const Color(0xFFD9A915));
  final stripe = Paint()
    ..color = const Color(0xFF16150F)
    ..strokeWidth = u * 1.6;
  for (var x = band.left - band.height; x < band.right + band.height; x += u * 3.6) {
    canvas.drawLine(Offset(x, band.bottom + u), Offset(x + band.height + u * 2, band.top - u), stripe);
  }
  final wear = Random(5);
  for (var i = 0; i < (band.width / u * 0.9).round(); i++) {
    canvas.drawCircle(
      Offset(band.left + wear.nextDouble() * band.width, band.top + wear.nextDouble() * band.height),
      u * (0.1 + wear.nextDouble() * 0.4),
      Paint()..color = const Color(0xFF3A3A33).withValues(alpha: 0.6),
    );
  }
  canvas.restore();

  canvas.drawRRect(
    RRect.fromRectAndRadius(screen.inflate(bezel * 0.12), Radius.circular(bezel * 0.3)),
    Paint()..color = const Color(0xFF0B0B08),
  );
  final r = max(2.0, bezel * 0.13);
  final inset = bezel * 0.42;
  for (final corner in [
    Offset(frameRect.left + inset, frameRect.top + inset),
    Offset(frameRect.right - inset, frameRect.top + inset),
    Offset(frameRect.left + inset, frameRect.bottom - inset),
    Offset(frameRect.right - inset, frameRect.bottom - inset),
    Offset(frameRect.center.dx, frameRect.top + inset * 0.9),
    Offset(frameRect.left + inset * 0.9, frameRect.center.dy),
    Offset(frameRect.right - inset * 0.9, frameRect.center.dy),
  ]) {
    _rivet(canvas, corner, r);
  }
  if (!dressed) return;

  // Left pillar: a bolted speaker plate with punched holes, and stencilling.
  final cx = pillar / 2;
  final centre = Offset(cx, size.height * 0.42);
  final radius = pillar * 0.3;
  final plate = RRect.fromRectAndRadius(Rect.fromCircle(center: centre, radius: radius * 1.28), Radius.circular(u * 0.8));
  canvas.drawRRect(plate.shift(Offset(u * 0.3, u * 0.4)), Paint()..color = Colors.black.withValues(alpha: 0.45));
  canvas.drawRRect(plate, Paint()..color = const Color(0xFF4A4937));
  canvas.drawRRect(plate, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = Colors.black.withValues(alpha: 0.6));
  canvas.drawCircle(centre, radius, Paint()..color = const Color(0xFF14140F));
  final hole = Paint()..color = const Color(0xFF4A4937);
  for (var ring = 1; ring <= 4; ring++) {
    final distance = radius * ring / 4.6;
    final holes = ring * 7;
    for (var i = 0; i < holes; i++) {
      final a = i / holes * pi * 2 + ring * 0.4;
      canvas.drawCircle(centre + Offset(cos(a), sin(a)) * distance, radius * 0.055, hole);
    }
  }
  canvas.drawCircle(centre, radius * 0.07, hole);
  for (final dx in [-1.0, 1.0]) {
    for (final dy in [-1.0, 1.0]) {
      _rivet(canvas, centre + Offset(dx, dy) * radius * 1.08, u * 0.6);
    }
  }
  const stencil = Color(0xFFE8DFB6);
  artText(canvas, 'UNIT 13', Offset(cx, size.height * 0.79), u * 3.3, stencil.withValues(alpha: 0.62), angle: -0.06, spacing: u * 0.5);
  artText(canvas, 'SALVAGE', Offset(cx, size.height * 0.845), u * 1.8, stencil.withValues(alpha: 0.5), angle: -0.06, spacing: u * 0.6);

  // Right pillar, above the buttons: a strip of tape and a scratched tally.
  canvas.save();
  canvas.translate(frameRect.right + pillar * 0.5, size.height * 0.17);
  canvas.rotate(-0.13);
  final tape = Rect.fromCenter(center: Offset.zero, width: pillar * 0.78, height: u * 5.2);
  canvas.drawRect(tape.shift(Offset(u * 0.2, u * 0.3)), Paint()..color = Colors.black.withValues(alpha: 0.35));
  canvas.drawRect(tape, Paint()..color = const Color(0xFF9A9A92));
  for (var y = tape.top + u * 0.5; y < tape.bottom; y += u * 0.55) {
    canvas.drawLine(Offset(tape.left, y), Offset(tape.right, y), Paint()
      ..strokeWidth = 1
      ..color = Colors.black.withValues(alpha: 0.1));
  }
  artText(canvas, 'DO NOT FIX', Offset.zero, u * 2.1, const Color(0xFF1B1B17).withValues(alpha: 0.85), spacing: u * 0.2);
  canvas.restore();

  final tally = Paint()
    ..strokeCap = StrokeCap.round
    ..strokeWidth = max(1.5, u * 0.28)
    ..color = stencil.withValues(alpha: 0.6);
  final tx = frameRect.right + pillar * 0.3;
  final ty = size.height * 0.29;
  for (var i = 0; i < 4; i++) {
    canvas.drawLine(Offset(tx + i * u * 1.5, ty), Offset(tx + i * u * 1.5 + u * 0.3, ty + u * 5), tally);
  }
  canvas.drawLine(Offset(tx - u, ty + u * 4), Offset(tx + u * 5.6, ty + u * 1), tally);
}

// -----------------------------------------------------------------------------
// Atomic: 1960s space-age cream, chrome ring, teal sweep, starbursts.

const _teal = Color(0xFF2FA8A0);
const _orange = Color(0xFFFF7A1A);

void _starburst(Canvas canvas, Offset centre, double length, Color color) {
  final fill = Paint()..color = color;
  for (var i = 0; i < 8; i++) {
    final a = i * pi / 4;
    final direction = Offset(cos(a), sin(a));
    final across = Offset(-direction.dy, direction.dx);
    final reach = i.isEven ? length : length * 0.52;
    canvas.drawPath(
      Path()
        ..moveTo(centre.dx + across.dx * reach * 0.1, centre.dy + across.dy * reach * 0.1)
        ..lineTo(centre.dx + direction.dx * reach, centre.dy + direction.dy * reach)
        ..lineTo(centre.dx - across.dx * reach * 0.1, centre.dy - across.dy * reach * 0.1)
        ..close(),
      fill,
    );
  }
  canvas.drawCircle(centre, length * 0.14, Paint()..color = const Color(0xFFFFF6E0));
  canvas.drawCircle(centre, length * 0.14, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = max(1.0, length * 0.03)
    ..color = color);
}

void paintAtomic(Canvas canvas, Size size, Rect? screen, double bezel, bool dressed) {
  final rect = Offset.zero & size;
  final u = size.height / 100;
  canvas.drawRect(
    rect,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFF6EEDB), Color(0xFFE2D3AE)],
      ).createShader(rect),
  );
  // A two-tone sweep across the bottom, with a pinstripe riding above it.
  Path sweep(double lift) => Path()
    ..moveTo(0, size.height * 0.82 - lift)
    ..quadraticBezierTo(size.width * 0.5, size.height * 0.62 - lift, size.width, size.height * 0.96 - lift);
  final lower = sweep(0)
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..close();
  canvas.drawPath(
    lower,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF3BB8AF), Color(0xFF1B837C)],
      ).createShader(Rect.fromLTRB(0, size.height * 0.5, size.width, size.height)),
  );
  canvas.drawPath(sweep(u * 1.6), Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = u * 0.55
    ..color = _orange);
  canvas.drawPath(sweep(u * 2.9), Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = u * 0.22
    ..color = const Color(0xFF17524E));
  // Gloss: a soft highlight falling across the top left.
  canvas.drawOval(
    Rect.fromLTWH(-size.width * 0.2, -size.height * 0.55, size.width * 0.9, size.height * 0.9),
    Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * 6),
  );
  if (screen == null) return;

  final frameRect = screen.inflate(bezel);
  final pillar = frameRect.left;
  final frame = RRect.fromRectAndRadius(frameRect, Radius.circular(bezel * 2.0));
  canvas.drawRRect(
    frame.inflate(bezel * 0.08),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, bezel * 0.4),
  );
  // Chrome: bands of light and dark, like a bumper.
  canvas.drawRRect(
    frame,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFFFFF), Color(0xFFB4BAC1), Color(0xFFF2F4F6), Color(0xFF858C95), Color(0xFFDDE1E5)],
        stops: [0.0, 0.3, 0.52, 0.8, 1.0],
      ).createShader(frameRect),
  );
  canvas.drawRRect(frame, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2
    ..color = const Color(0xFF6C737B));
  final insetRect = screen.inflate(bezel * 0.5);
  canvas.drawRRect(
    RRect.fromRectAndRadius(insetRect, Radius.circular(bezel * 1.45)),
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF134E4A), Color(0xFF2A938B)],
      ).createShader(insetRect),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(screen.inflate(bezel * 0.1), Radius.circular(bezel * 0.9)),
    Paint()..color = const Color(0xFF07100F),
  );
  artText(
    canvas,
    'Astro-Vision',
    Offset(screen.center.dx, frameRect.bottom - bezel * 0.25),
    bezel * 0.34,
    const Color(0xFF2D343B),
    italic: true,
    family: 'Georgia',
    fallback: const ['Times New Roman', 'DejaVu Serif', 'serif'],
  );
  if (!dressed) return;

  final cx = pillar / 2;
  _starburst(canvas, Offset(cx * 0.92, size.height * 0.15), u * 7.5, _orange);
  _starburst(canvas, Offset(cx * 1.45, size.height * 0.29), u * 4.2, _teal);
  _starburst(canvas, Offset(cx * 0.55, size.height * 0.33), u * 3.0, const Color(0xFFE0A526));
  // Speaker: a stack of chrome fins.
  for (var i = 0; i < 6; i++) {
    final fin = Rect.fromCenter(
      center: Offset(cx, size.height * 0.45 + i * u * 3.3),
      width: pillar * 0.58,
      height: u * 1.7,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(fin.shift(Offset(0, u * 0.45)), Radius.circular(u)),
      Paint()..color = Colors.black.withValues(alpha: 0.28),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(fin, Radius.circular(u)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFFFF), Color(0xFF9AA1A9), Color(0xFFE4E7EA)],
        ).createShader(fin),
    );
  }
  final rx = frameRect.right;
  _starburst(canvas, Offset(rx + pillar * 0.24, size.height * 0.085), u * 2.6, const Color(0xFFE0A526));
  _starburst(canvas, Offset(rx + pillar * 0.76, size.height * 0.07), u * 4.0, _orange);
}

// -----------------------------------------------------------------------------
// Memphis: late-80s postmodern. Mint shell, loud shapes, hard black shadows.

const _ink = Color(0xFF111111);
const memphisColours = [
  Color(0xFFFF4FA3),
  Color(0xFFFFD23F),
  Color(0xFF7B4DFF),
  Color(0xFFFF8A3D),
  Color(0xFF2D7FF9),
];

void _memphisShapes(Canvas canvas, Rect area, Random random, double u, {Offset? avoid, double avoidRadius = 0}) {
  if (area.width < u * 6 || area.height < u * 6) return;
  final columns = max(1, (area.width / (u * 9)).floor());
  final cell = area.width / columns;
  final rows = (area.height / cell).floor();
  final outline = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = max(1.5, u * 0.4)
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round
    ..color = _ink;
  for (var row = 0; row < rows; row++) {
    for (var column = 0; column < columns; column++) {
      final kind = random.nextInt(7);
      final centre = Offset(
        area.left + (column + 0.5 + (random.nextDouble() - 0.5) * 0.3) * cell,
        area.top + (row + 0.5 + (random.nextDouble() - 0.5) * 0.3) * cell,
      );
      final s = cell * (0.22 + random.nextDouble() * 0.1);
      final colour = memphisColours[random.nextInt(memphisColours.length)];
      final turn = random.nextDouble() * pi;
      if (kind == 6 || (avoid != null && (centre - avoid).distance < avoidRadius)) continue;
      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.rotate(turn);
      switch (kind) {
        case 0: // Squiggle.
          final path = Path()..moveTo(-s * 1.2, 0);
          for (var i = 0; i < 4; i++) {
            path.lineTo(-s * 1.2 + (i + 0.5) * s * 0.6, i.isEven ? -s * 0.45 : s * 0.45);
          }
          path.lineTo(s * 1.2, 0);
          canvas.drawPath(path, outline);
        case 1: // Triangle.
          final path = Path()
            ..moveTo(0, -s)
            ..lineTo(s * 0.9, s * 0.7)
            ..lineTo(-s * 0.9, s * 0.7)
            ..close();
          canvas.drawPath(path.shift(Offset(u * 0.5, u * 0.5)), Paint()..color = _ink);
          canvas.drawPath(path, Paint()..color = colour);
          canvas.drawPath(path, outline);
        case 2: // Ring.
          canvas.drawCircle(Offset.zero, s * 0.8, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.34
            ..color = colour);
          canvas.drawCircle(Offset.zero, s * 0.97, outline);
          canvas.drawCircle(Offset.zero, s * 0.63, outline);
        case 3: // Dot grid.
          for (var i = -1; i <= 1; i++) {
            for (var j = -1; j <= 1; j++) {
              canvas.drawCircle(Offset(i * s * 0.62, j * s * 0.62), s * 0.15, Paint()..color = _ink);
            }
          }
        case 4: // Confetti bar.
          final bar = RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: s * 2.2, height: s * 0.55),
            Radius.circular(s * 0.28),
          );
          canvas.drawRRect(bar, Paint()..color = colour);
          canvas.drawRRect(bar, outline);
        default: // Half circle.
          final half = Path()
            ..addArc(Rect.fromCircle(center: Offset.zero, radius: s), 0, pi)
            ..close();
          canvas.drawPath(half.shift(Offset(u * 0.5, u * 0.5)), Paint()..color = _ink);
          canvas.drawPath(half, Paint()..color = colour);
          canvas.drawPath(half, outline);
      }
      canvas.restore();
    }
  }
}

void paintMemphis(Canvas canvas, Size size, Rect? screen, double bezel, bool dressed) {
  final rect = Offset.zero & size;
  final u = size.height / 100;
  canvas.drawRect(
    rect,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF9BE8DA), Color(0xFF67CDBF)],
      ).createShader(rect),
  );
  // A faint dot screen, like printed card.
  final dots = <Offset>[];
  for (var y = u; y < size.height; y += u * 2.2) {
    for (var x = u; x < size.width; x += u * 2.2) {
      dots.add(Offset(x, y));
    }
  }
  canvas.drawPoints(
    PointMode.points,
    dots,
    Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = u * 0.35
      ..color = Colors.white.withValues(alpha: 0.28),
  );
  if (screen == null) return;

  final frameRect = screen.inflate(bezel);
  final pillar = frameRect.left;
  final speakerCentre = Offset(pillar / 2, size.height * 0.5);
  final speakerRadius = pillar * 0.3;
  if (dressed) {
    _memphisShapes(
      canvas,
      Rect.fromLTRB(u, u, pillar - u, size.height - u),
      Random(84),
      u,
      avoid: speakerCentre,
      avoidRadius: speakerRadius * 1.55,
    );
    // Only above the buttons on the right, so the controls stay readable.
    _memphisShapes(canvas, Rect.fromLTRB(frameRect.right + u, u, size.width - u, size.height * 0.4), Random(91), u);
    final plate = RRect.fromRectAndRadius(
      Rect.fromLTRB(frameRect.right + pillar * 0.09, size.height * 0.405, size.width - pillar * 0.09, size.height * 0.968),
      Radius.circular(u * 1.6),
    );
    canvas.drawRRect(plate.shift(Offset(u * 0.9, u * 0.9)), Paint()..color = _ink);
    canvas.drawRRect(plate, Paint()..color = const Color(0xFFFFFBF0));
    canvas.drawRRect(plate, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(2.0, u * 0.42)
      ..color = _ink);
  }

  final frame = RRect.fromRectAndRadius(frameRect, Radius.circular(bezel * 0.7));
  canvas.drawRRect(frame.shift(Offset(u * 1.3, u * 1.3)), Paint()..color = memphisColours[0]);
  canvas.drawRRect(frame, Paint()..color = memphisColours[1]);
  // Terrazzo chips scattered round the frame.
  canvas.save();
  canvas.clipRRect(frame);
  final chips = Random(40);
  for (var i = 0; i < ((frameRect.width + frameRect.height) / u * 0.6).round(); i++) {
    // Keep to the ring: pick a side, then a spot along it.
    final along = chips.nextDouble();
    final depth = (0.15 + chips.nextDouble() * 0.6) * bezel;
    final at = switch (chips.nextInt(4)) {
      0 => Offset(frameRect.left + along * frameRect.width, frameRect.top + depth),
      1 => Offset(frameRect.left + along * frameRect.width, frameRect.bottom - depth),
      2 => Offset(frameRect.left + depth, frameRect.top + along * frameRect.height),
      _ => Offset(frameRect.right - depth, frameRect.top + along * frameRect.height),
    };
    final s = u * (0.35 + chips.nextDouble() * 0.6);
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(chips.nextDouble() * pi);
    final chip = Paint()
      ..color = [_ink, memphisColours[0], memphisColours[2], memphisColours[4]][chips.nextInt(4)];
    if (chips.nextBool()) {
      canvas.drawPath(
        Path()
          ..moveTo(0, -s)
          ..lineTo(s, s * 0.8)
          ..lineTo(-s, s * 0.8)
          ..close(),
        chip,
      );
    } else {
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: s * 2, height: s * 0.9), chip);
    }
    canvas.restore();
  }
  canvas.restore();
  canvas.drawRRect(frame, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = max(2.0, u * 0.5)
    ..color = _ink);
  canvas.drawRRect(
    RRect.fromRectAndRadius(screen.inflate(bezel * 0.2), Radius.circular(bezel * 0.4)),
    Paint()..color = _ink,
  );
  if (!dressed) return;

  // Speaker: a pink disc of polka dots.
  canvas.drawCircle(speakerCentre.translate(u * 0.9, u * 0.9), speakerRadius, Paint()..color = _ink);
  canvas.drawCircle(speakerCentre, speakerRadius, Paint()..color = memphisColours[0]);
  canvas.save();
  canvas.clipPath(Path()..addOval(Rect.fromCircle(center: speakerCentre, radius: speakerRadius * 0.9)));
  final step = speakerRadius / 3.2;
  var row = 0;
  for (var y = speakerCentre.dy - speakerRadius; y <= speakerCentre.dy + speakerRadius; y += step * 0.87, row++) {
    for (var x = speakerCentre.dx - speakerRadius + (row.isOdd ? step / 2 : 0); x <= speakerCentre.dx + speakerRadius; x += step) {
      canvas.drawCircle(Offset(x, y), step * 0.26, Paint()..color = _ink);
    }
  }
  canvas.restore();
  canvas.drawCircle(speakerCentre, speakerRadius, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = max(2.0, u * 0.45)
    ..color = _ink);
}
