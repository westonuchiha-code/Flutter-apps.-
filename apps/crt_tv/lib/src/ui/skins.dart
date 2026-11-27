import 'dart:math';
import 'dart:ui' show PointMode;

import 'package:material_ui/material_ui.dart';

import '../models.dart';
import 'skin_art.dart';
import 'skin_art_retro.dart';

/// Colors for each cabinet style.
class SkinColors {
  const SkinColors({
    required this.top,
    required this.bottom,
    required this.bezel,
    required this.grille,
    required this.text,
  });

  final Color top;
  final Color bottom;
  final Color bezel;
  final Color grille;
  final Color text;

  static SkinColors of(SkinStyle style) => switch (style) {
    SkinStyle.wood => const SkinColors(
      top: Color(0xFF6B4528),
      bottom: Color(0xFF3B2414),
      bezel: Color(0xFF16110D),
      grille: Color(0xFF1E140C),
      text: Color(0xFFE8D9B5),
    ),
    SkinStyle.black => const SkinColors(
      top: Color(0xFF2A2A2C),
      bottom: Color(0xFF0E0E10),
      bezel: Color(0xFF050505),
      grille: Color(0xFF000000),
      text: Color(0xFFBDBDBD),
    ),
    SkinStyle.silver => const SkinColors(
      top: Color(0xFFD5D6D8),
      bottom: Color(0xFF8C8E92),
      bezel: Color(0xFF2B2C2E),
      grille: Color(0xFF55575B),
      text: Color(0xFF26272A),
    ),
    SkinStyle.crt95 => const SkinColors(
      top: Color(0xFF3B3C41),
      bottom: Color(0xFF212226),
      bezel: Color(0xFF0B0B0D),
      grille: Color(0xFF131316),
      text: Color(0xFFB9BABF),
    ),
    SkinStyle.cyberpunk => const SkinColors(
      top: Color(0xFF1C1433),
      bottom: Color(0xFF0A0812),
      bezel: Color(0xFF050409),
      grille: Color(0xFF07060C),
      text: Color(0xFF8FF7FF),
    ),
    SkinStyle.wasteland => const SkinColors(
      top: Color(0xFF62603F),
      bottom: Color(0xFF3B3A27),
      bezel: Color(0xFF0B0B08),
      grille: Color(0xFF14140F),
      text: Color(0xFFE8DFB6),
    ),
    SkinStyle.atomic => const SkinColors(
      top: Color(0xFFF6EEDB),
      bottom: Color(0xFFE2D3AE),
      bezel: Color(0xFF07100F),
      grille: Color(0xFF9AA1A9),
      text: Color(0xFF17524E),
    ),
    SkinStyle.memphis => const SkinColors(
      top: Color(0xFF9BE8DA),
      bottom: Color(0xFF67CDBF),
      bezel: Color(0xFF111111),
      grille: Color(0xFFFF4FA3),
      text: Color(0xFF111111),
    ),
    SkinStyle.boombox => const SkinColors(
      top: Color(0xFFD9DCE0),
      bottom: Color(0xFF8B8F96),
      bezel: Color(0xFF050505),
      grille: Color(0xFF0B0B0C),
      text: Color(0xFF23262B),
    ),
    SkinStyle.portable => const SkinColors(
      top: Color(0xFFF03226),
      bottom: Color(0xFF9E100A),
      bezel: Color(0xFF050505),
      grille: Color(0xFF5E0805),
      text: Color(0xFFFFFFFF),
    ),
    SkinStyle.combo => const SkinColors(
      top: Color(0xFF303033),
      bottom: Color(0xFF151517),
      bezel: Color(0xFF050505),
      grille: Color(0xFF0B0B0C),
      text: Color(0xFFB9BABF),
    ),
    SkinStyle.clear => const SkinColors(
      top: Color(0xFF7B4FE0),
      bottom: Color(0xFF3A1890),
      bezel: Color(0xFF05030B),
      grille: Color(0xFF2B1470),
      text: Color(0xFFFFFFFF),
    ),
    SkinStyle.none => const SkinColors(
      top: Color(0xFF000000),
      bottom: Color(0xFF000000),
      bezel: Color(0xFF000000),
      grille: Color(0xFF111111),
      text: Color(0xFF9E9E9E),
    ),
  };
}

extension SkinStyleInfo on SkinStyle {
  String get label => switch (this) {
    SkinStyle.none => 'No cabinet',
    SkinStyle.wood => 'Wood console',
    SkinStyle.black => 'Black plastic',
    SkinStyle.silver => 'Silver',
    SkinStyle.crt95 => '1995 CRT',
    SkinStyle.cyberpunk => 'Cyberpunk',
    SkinStyle.wasteland => 'Wasteland',
    SkinStyle.atomic => 'Retro-Future',
    SkinStyle.memphis => 'Wacky Pomo',
    SkinStyle.boombox => '1984 Boombox',
    SkinStyle.portable => '1987 Sport Portable',
    SkinStyle.combo => '1993 TV/VCR',
    SkinStyle.clear => '1998 See-Through',
  };

  String get blurb => switch (this) {
    SkinStyle.none => 'Just the picture on black',
    SkinStyle.wood => 'Wood grain with big dials',
    SkinStyle.black => 'Plain black with big dials',
    SkinStyle.silver => 'Brushed silver with big dials',
    SkinStyle.crt95 => 'Charcoal plastic, side speakers, push buttons',
    SkinStyle.cyberpunk => 'Black shell, circuit traces, neon tubes',
    SkinStyle.wasteland => 'Salvaged steel, rust, rivets and hazard tape',
    SkinStyle.atomic => 'Space-age cream and chrome with starbursts',
    SkinStyle.memphis => 'Mint, squiggles and candy-coloured buttons',
    SkinStyle.boombox => 'Brushed silver, chrome speakers, LED meters',
    SkinStyle.portable => 'Glossy red with an antenna and yellow dials',
    SkinStyle.combo => 'Black plastic with a tape deck blinking 12:00',
    SkinStyle.clear => 'Translucent purple with the works showing',
  };
}

/// Where the 4:3 screen and the cabinet's side pillars sit in a wide window.
class CabinetLayout {
  const CabinetLayout._(
    this.screenRect,
    this.bezel,
    this.pillar,
    this.decorate,
    this.chin,
  );

  factory CabinetLayout.of(Size size, SkinStyle skin) {
    var outerH = size.height;
    if (outerH * 4 / 3 > size.width) outerH = size.width * 3 / 4;
    final bezel = switch (skin) {
      SkinStyle.none => 0.0,
      SkinStyle.crt95 => outerH * 0.05,
      SkinStyle.cyberpunk => outerH * 0.044,
      SkinStyle.wasteland => outerH * 0.056,
      SkinStyle.atomic => outerH * 0.066,
      SkinStyle.memphis => outerH * 0.05,
      SkinStyle.boombox => outerH * 0.04,
      SkinStyle.portable => outerH * 0.06,
      SkinStyle.combo => outerH * 0.045,
      SkinStyle.clear => outerH * 0.05,
      _ => outerH * 0.028,
    };
    // A TV/VCR has its tape deck in a strip under the screen, so the tube
    // sits higher and is a little smaller.
    final chinH = skin == SkinStyle.combo ? outerH * 0.15 : 0.0;
    final top = (size.height - outerH) / 2;
    final innerH = outerH - chinH - bezel * 2;
    final screenRect = Rect.fromCenter(
      center: Offset(size.width / 2, top + bezel + innerH / 2),
      width: innerH * 4 / 3,
      height: innerH,
    );
    final pillar = screenRect.left - bezel;
    final chin = chinH == 0
        ? null
        : Rect.fromLTRB(
            screenRect.left - bezel,
            screenRect.bottom + bezel,
            screenRect.right + bezel,
            top + outerH,
          );
    return CabinetLayout._(
      screenRect,
      bezel,
      pillar,
      skin != SkinStyle.none && pillar > 80,
      chin,
    );
  }

  /// The strip under the screen on cabinets that have one, else null.
  final Rect? chin;

  /// Where the TV/VCR's blinking clock goes, if this cabinet has one.
  Rect? get clock => chin == null ? null : comboClockRect(chin!);

  final Rect screenRect;
  final double bezel;

  /// Width of the cabinet left over on each side of the screen.
  final double pillar;

  /// Whether the pillars are wide enough for speakers and controls.
  final bool decorate;
}

/// Paints the TV cabinet around the screen: the material (wood, plastic or
/// silver), a dark bezel hugging the glass, and a speaker grille on the left.
class SkinPainter extends CustomPainter {
  SkinPainter({
    required this.style,
    this.screenRect,
    this.bezel = 0,
    this.speaker = false,
    this.chin,
  });

  final SkinStyle style;

  /// The strip under the screen, on cabinets that have one.
  final Rect? chin;

  /// Where the screen sits, or null when painting just a panel of material.
  final Rect? screenRect;
  final double bezel;
  final bool speaker;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final colors = SkinColors.of(style);
    if (style == SkinStyle.none) {
      canvas.drawRect(rect, Paint()..color = Colors.black);
      return;
    }
    if (style == SkinStyle.crt95) {
      _paint95(canvas, size, colors);
      return;
    }
    final themed = switch (style) {
      SkinStyle.cyberpunk => paintCyberpunk,
      SkinStyle.wasteland => paintWasteland,
      SkinStyle.atomic => paintAtomic,
      SkinStyle.memphis => paintMemphis,
      SkinStyle.boombox => paintBoombox,
      SkinStyle.portable => paintPortable,
      SkinStyle.clear => paintClear,
      _ => null,
    };
    if (themed != null) {
      themed(canvas, size, screenRect, bezel, speaker);
      return;
    }
    if (style == SkinStyle.combo) {
      paintCombo(canvas, size, screenRect, bezel, speaker, chin);
      return;
    }

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colors.top, colors.bottom],
        ).createShader(rect),
    );

    if (style == SkinStyle.wood) _paintWoodGrain(canvas, size);
    if (style == SkinStyle.silver) _paintBrushed(canvas, size);

    final screen = screenRect;
    if (screen != null && bezel > 0) {
      final outer = RRect.fromRectAndRadius(
        screen.inflate(bezel),
        Radius.circular(bezel * 1.6),
      );
      // Soft shadow, then the bezel, then a thin highlight on its edge.
      canvas.drawRRect(
        outer.inflate(bezel * 0.25),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.45)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, bezel * 0.6),
      );
      canvas.drawRRect(outer, Paint()..color = colors.bezel);
      canvas.drawRRect(
        outer,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(1.0, bezel * 0.08)
          ..color = Colors.white.withValues(alpha: 0.12),
      );

      if (speaker) {
        final pillar = screen.left - bezel;
        if (pillar > 40) {
          final width = pillar * 0.5;
          final height = screen.height * 0.5;
          final grille = Rect.fromCenter(
            center: Offset(pillar / 2, screen.center.dy),
            width: width,
            height: height,
          );
          _paintGrille(canvas, grille, colors);
        }
      }
    }
  }

  /// A mid-90s set: charcoal moulded plastic, a thick stepped bezel with a
  /// badge under the glass, and perforated speaker grilles at the sides.
  void _paint95(Canvas canvas, Size size, SkinColors colors) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colors.top, colors.bottom],
        ).createShader(rect),
    );
    _paintSpeckle(canvas, size);

    final screen = screenRect;
    if (screen == null || bezel <= 0) return;

    // The raised front frame around the tube.
    final frameRect = screen.inflate(bezel);
    final frame = RRect.fromRectAndRadius(
      frameRect,
      Radius.circular(bezel * 1.1),
    );
    canvas.drawRRect(
      frame.inflate(bezel * 0.12),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, bezel * 0.35),
    );
    canvas.drawRRect(
      frame,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF4A4B51), Color(0xFF2B2C31)],
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
            Colors.white.withValues(alpha: 0.28),
            Colors.black.withValues(alpha: 0.35),
          ],
        ).createShader(frameRect),
    );

    // The slope down to the glass: its top is in shadow, its bottom catches light.
    final slopeRect = screen.inflate(bezel * 0.46);
    canvas.drawRRect(
      RRect.fromRectAndRadius(slopeRect, Radius.circular(bezel * 0.85)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF09090B), Color(0xFF141417), Color(0xFF26272B)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(slopeRect),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        screen.inflate(bezel * 0.07),
        Radius.circular(bezel * 0.5),
      ),
      Paint()..color = colors.bezel,
    );

    // Badge on the strip under the glass.
    final strip = bezel * 0.54;
    final badge = TextPainter(
      text: TextSpan(
        text: 'CRT·TV',
        style: TextStyle(
          color: const Color(0xFFC9CACF).withValues(alpha: 0.85),
          fontSize: strip * 0.5,
          fontWeight: FontWeight.w800,
          letterSpacing: strip * 0.22,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    badge.paint(
      canvas,
      Offset(
        screen.center.dx - badge.width / 2,
        frameRect.bottom - strip / 2 - badge.height / 2,
      ),
    );

    if (!speaker) return;
    final pillar = frameRect.left;
    final grilleWidth = pillar * 0.58;
    _paintDotGrille(
      canvas,
      Rect.fromCenter(
        center: Offset(pillar / 2, screen.center.dy),
        width: grilleWidth,
        height: screen.height * 0.66,
      ),
      colors,
    );
    // The right speaker is shorter: the buttons sit underneath it.
    _paintDotGrille(
      canvas,
      Rect.fromLTWH(
        frameRect.right + (pillar - grilleWidth) / 2,
        screen.top + screen.height * 0.07,
        grilleWidth,
        screen.height * 0.3,
      ),
      colors,
    );
  }

  /// Fine grain so the plastic doesn't read as a flat colour.
  void _paintSpeckle(Canvas canvas, Size size) {
    final random = Random(95);
    final count = (size.width * size.height / 700).round().clamp(200, 6000);
    final lightDots = <Offset>[];
    final darkDots = <Offset>[];
    for (var i = 0; i < count; i++) {
      final p = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      (random.nextBool() ? lightDots : darkDots).add(p);
    }
    final paint = Paint()
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    canvas.drawPoints(
      PointMode.points,
      lightDots,
      paint..color = Colors.white.withValues(alpha: 0.05),
    );
    canvas.drawPoints(
      PointMode.points,
      darkDots,
      paint..color = Colors.black.withValues(alpha: 0.12),
    );
  }

  void _paintDotGrille(Canvas canvas, Rect area, SkinColors colors) {
    final panel = RRect.fromRectAndRadius(
      area,
      Radius.circular(area.width * 0.07),
    );
    canvas.drawRRect(
      panel,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colors.grille,
            Color.lerp(colors.grille, colors.bottom, 0.7)!,
          ],
        ).createShader(area),
    );
    canvas.drawRRect(
      panel,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.7),
            Colors.white.withValues(alpha: 0.16),
          ],
        ).createShader(area),
    );

    final gap = max(4.0, area.width / 13);
    final inset = gap * 0.9;
    final holes = <Offset>[];
    final glints = <Offset>[];
    var row = 0;
    for (
      var y = area.top + inset;
      y <= area.bottom - inset;
      y += gap * 0.87, row++
    ) {
      final shift = row.isOdd ? gap / 2 : 0.0;
      for (
        var x = area.left + inset + shift;
        x <= area.right - inset;
        x += gap
      ) {
        holes.add(Offset(x, y));
        glints.add(Offset(x, y + gap * 0.16));
      }
    }
    final dot = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = gap * 0.5;
    canvas.drawPoints(
      PointMode.points,
      glints,
      dot..color = Colors.white.withValues(alpha: 0.07),
    );
    canvas.drawPoints(
      PointMode.points,
      holes,
      dot..color = Colors.black.withValues(alpha: 0.85),
    );
  }

  void _paintWoodGrain(Canvas canvas, Size size) {
    final random = Random(42);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final lines = max(24, (size.height / 9).round());
    for (var i = 0; i < lines; i++) {
      final baseY = random.nextDouble() * size.height;
      final amplitude = 2 + random.nextDouble() * 7;
      final wavelength = 120 + random.nextDouble() * 260;
      final phase = random.nextDouble() * pi * 2;
      final dark = random.nextBool();
      paint
        ..strokeWidth = 0.6 + random.nextDouble() * 2.2
        ..color = (dark ? Colors.black : const Color(0xFFFFE0B0)).withValues(
          alpha: 0.05 + random.nextDouble() * 0.09,
        );
      final path = Path()..moveTo(0, baseY);
      for (var x = 0.0; x <= size.width; x += 12) {
        path.lineTo(
          x,
          baseY + sin(x / wavelength * pi * 2 + phase) * amplitude,
        );
      }
      canvas.drawPath(path, paint);
    }
  }

  void _paintBrushed(Canvas canvas, Size size) {
    final random = Random(7);
    final paint = Paint()..strokeWidth = 1;
    for (var y = 0.0; y < size.height; y += 2) {
      paint.color = (random.nextBool() ? Colors.white : Colors.black)
          .withValues(alpha: random.nextDouble() * 0.05);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _paintGrille(Canvas canvas, Rect area, SkinColors colors) {
    final panel = RRect.fromRectAndRadius(
      area,
      Radius.circular(area.width * 0.08),
    );
    canvas.drawRRect(
      panel,
      Paint()..color = colors.grille.withValues(alpha: 0.55),
    );
    final slot = Paint()
      ..color = Colors.black.withValues(alpha: 0.7)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = max(2.0, area.height / 70);
    final gap = max(6.0, area.height / 24);
    for (var y = area.top + gap; y < area.bottom - gap * 0.5; y += gap) {
      canvas.drawLine(
        Offset(area.left + area.width * 0.12, y),
        Offset(area.right - area.width * 0.12, y),
        slot,
      );
    }
  }

  @override
  bool shouldRepaint(SkinPainter oldDelegate) =>
      oldDelegate.style != style ||
      oldDelegate.screenRect != screenRect ||
      oldDelegate.bezel != bezel ||
      oldDelegate.speaker != speaker ||
      oldDelegate.chin != chin;
}

/// A round knob with ridges and a pointer, drawn to suit the cabinet.
class KnobPainter extends CustomPainter {
  KnobPainter({required this.angle, required this.style});

  /// Pointer angle in radians, 0 = straight up.
  final double angle;
  final SkinStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final look = DialLook.of(style);
    final light = look.darkRidges;
    final face = look.face;
    final edge = look.edge;

    canvas.drawCircle(
      center.translate(0, radius * 0.06),
      radius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.12),
    );
    canvas.drawCircle(center, radius, Paint()..color = edge);
    // Ridges around the rim.
    final ridge = Paint()
      ..color = (light ? Colors.black : Colors.white).withValues(alpha: 0.12)
      ..strokeWidth = max(1.0, radius * 0.04);
    for (var i = 0; i < 36; i++) {
      final a = i / 36 * pi * 2;
      final dir = Offset(sin(a), -cos(a));
      canvas.drawLine(
        center + dir * radius * 0.82,
        center + dir * radius * 0.98,
        ridge,
      );
    }
    canvas.drawCircle(
      center,
      radius * 0.8,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: [Color.lerp(face, Colors.white, 0.25)!, face],
        ).createShader(Rect.fromCircle(center: center, radius: radius * 0.8)),
    );
    final dir = Offset(sin(angle), -cos(angle));
    canvas.drawLine(
      center + dir * radius * 0.2,
      center + dir * radius * 0.72,
      Paint()
        ..color = look.pointer
        ..strokeWidth = max(2.0, radius * 0.1)
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(KnobPainter oldDelegate) =>
      oldDelegate.angle != angle || oldDelegate.style != style;
}

/// How a cabinet's push buttons look. Null for cabinets with dials.
class ButtonLook {
  const ButtonLook({
    required this.text,
    required this.icon,
    required this.up,
    required this.down,
    required this.border,
    this.borderWidth = 1,
    this.led = const Color(0xFFFF3B30),
    this.glow,
    this.rainbow,
    this.hardShadow = false,
    this.jacks = false,
    this.mono = false,
  });

  /// The small printed labels.
  final Color text;
  final Color icon;

  /// Top-to-bottom shading when up and when pressed.
  final List<Color> up;
  final List<Color> down;
  final Color border;
  final double borderWidth;
  final Color led;

  /// A coloured glow round each button (neon).
  final Color? glow;

  /// One flat colour per button instead of [up], cycling.
  final List<Color>? rainbow;

  /// A solid offset shadow instead of a soft one.
  final bool hardShadow;

  /// The decorative video and audio sockets under the buttons.
  final bool jacks;

  /// Labels in the blocky monospace face.
  final bool mono;

  static ButtonLook? of(SkinStyle style) => switch (style) {
    SkinStyle.crt95 => const ButtonLook(
      text: Color(0xFFB9BABF),
      icon: Color(0xFFB9BABF),
      up: [Color(0xFF5B5C62), Color(0xFF36373C)],
      down: [Color(0xFF2C2D31), Color(0xFF3A3B40)],
      border: Color(0xBF000000),
      jacks: true,
    ),
    SkinStyle.cyberpunk => const ButtonLook(
      text: Color(0xFF8FF7FF),
      icon: Color(0xFF8FF7FF),
      up: [Color(0xFF1F1B2E), Color(0xFF0E0C15)],
      down: [Color(0xFF0A0810), Color(0xFF16131F)],
      border: Color(0xFF39F3FF),
      borderWidth: 1.2,
      led: Color(0xFFFF3DD4),
      glow: Color(0xFF39F3FF),
      mono: true,
    ),
    SkinStyle.wasteland => const ButtonLook(
      text: Color(0xFFE8DFB6),
      icon: Color(0xFF1C1C16),
      up: [Color(0xFF8D8A74), Color(0xFF55533F)],
      down: [Color(0xFF4A4838), Color(0xFF636150)],
      border: Color(0xFF16150F),
      borderWidth: 1.6,
      led: Color(0xFFFFA020),
      mono: true,
    ),
    SkinStyle.boombox => const ButtonLook(
      text: Color(0xFF23262B),
      icon: Color(0xFF23262B),
      up: [Color(0xFFF4F5F7), Color(0xFFA9AEB5)],
      down: [Color(0xFF959AA1), Color(0xFFC6CACF)],
      border: Color(0xFF4A4E55),
    ),
    SkinStyle.combo => const ButtonLook(
      text: Color(0xFFB9BABF),
      icon: Color(0xFFB9BABF),
      up: [Color(0xFF4C4D52), Color(0xFF27282B)],
      down: [Color(0xFF1F2023), Color(0xFF303135)],
      border: Color(0xBF000000),
      jacks: true,
    ),
    SkinStyle.clear => const ButtonLook(
      text: Color(0xFFFFFFFF),
      icon: Color(0xFFFFFFFF),
      up: [Color(0xD9B79BFF), Color(0xD95B36C9)],
      down: [Color(0xD94A2AA8), Color(0xD97A5BE0)],
      border: Color(0xFF2B1470),
      borderWidth: 1.2,
      led: Color(0xFF7CFFB2),
    ),
    SkinStyle.memphis => const ButtonLook(
      text: Color(0xFF111111),
      icon: Color(0xFF111111),
      up: [Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
      down: [Color(0xFFDDDDDD), Color(0xFFDDDDDD)],
      border: Color(0xFF111111),
      borderWidth: 2,
      rainbow: memphisColours,
      hardShadow: true,
    ),
    _ => null,
  };
}

/// Colours of the on-screen menu, so it suits the cabinet round it.
class OsdPalette {
  const OsdPalette({
    required this.panel,
    required this.ink,
    required this.accent,
    required this.bar,
    required this.barInk,
  });

  final Color panel;
  final Color ink;

  /// Titles and notices.
  final Color accent;

  /// The highlighted line, and the text on it.
  final Color bar;
  final Color barInk;

  /// Blue with white and yellow, like a mid-90s set.
  static const classic = OsdPalette(
    panel: Color(0xF50E1A86),
    ink: Color(0xFFF2F2F2),
    accent: Color(0xFFFFE14D),
    bar: Color(0xFF39D5E6),
    barInk: Color(0xFF07103F),
  );

  static OsdPalette of(SkinStyle style) => switch (style) {
    SkinStyle.cyberpunk => const OsdPalette(
      panel: Color(0xF20A0814),
      ink: Color(0xFF8FF7FF),
      accent: Color(0xFFFF3DD4),
      bar: Color(0xFFFF3DD4),
      barInk: Color(0xFF14001A),
    ),
    SkinStyle.wasteland => const OsdPalette(
      panel: Color(0xF2140E02),
      ink: Color(0xFFFFB000),
      accent: Color(0xFFFFD866),
      bar: Color(0xFFFFB000),
      barInk: Color(0xFF1A0F00),
    ),
    SkinStyle.atomic => const OsdPalette(
      panel: Color(0xF20E5B57),
      ink: Color(0xFFFFF4DC),
      accent: Color(0xFFFFA43A),
      bar: Color(0xFFFFA43A),
      barInk: Color(0xFF3A1E00),
    ),
    SkinStyle.boombox => const OsdPalette(
      panel: Color(0xF20B0B0D),
      ink: Color(0xFFE9EBEE),
      accent: Color(0xFFFF4136),
      bar: Color(0xFFE5231B),
      barInk: Color(0xFFFFFFFF),
    ),
    SkinStyle.portable => const OsdPalette(
      panel: Color(0xF2B3140E),
      ink: Color(0xFFFFFFFF),
      accent: Color(0xFFFFD23F),
      bar: Color(0xFFFFD23F),
      barInk: Color(0xFF1A1A1C),
    ),
    SkinStyle.clear => const OsdPalette(
      panel: Color(0xF22B1470),
      ink: Color(0xFFFFFFFF),
      accent: Color(0xFF7CFFB2),
      bar: Color(0xFF7CFFB2),
      barInk: Color(0xFF1A0B45),
    ),
    SkinStyle.memphis => const OsdPalette(
      panel: Color(0xF2FF4FA3),
      ink: Color(0xFFFFFFFF),
      accent: Color(0xFFFFE04A),
      bar: Color(0xFFFFE04A),
      barInk: Color(0xFF111111),
    ),
    _ => classic,
  };
}

/// How a cabinet's dials, and the small buttons beside them, look.
class DialLook {
  const DialLook({
    required this.face,
    required this.edge,
    required this.pointer,
    this.darkRidges = false,
    this.button = const Color(0xFF1A1A1A),
    this.buttonBorder = const Color(0x3DFFFFFF),
    this.buttonIcon = const Color(0xB3FFFFFF),
  });

  final Color face;
  final Color edge;
  final Color pointer;

  /// Dark ridges on a pale rim, instead of pale ridges on a dark one.
  final bool darkRidges;
  final Color button;
  final Color buttonBorder;
  final Color buttonIcon;

  static DialLook of(SkinStyle style) => switch (style) {
    SkinStyle.silver => const DialLook(
      face: Color(0xFFE6E6E8),
      edge: Color(0xFF9A9A9E),
      pointer: Color(0xFFB00000),
      darkRidges: true,
    ),
    SkinStyle.atomic => const DialLook(
      face: Color(0xFF2FA8A0),
      edge: Color(0xFFC9CED3),
      pointer: Color(0xFFFF7A1A),
      darkRidges: true,
      button: Color(0xFF1F8F88),
      buttonBorder: Color(0xFF134E4A),
      buttonIcon: Color(0xFFFFF6E0),
    ),
    SkinStyle.portable => const DialLook(
      face: Color(0xFFFFD23F),
      edge: Color(0xFF1A1A1C),
      pointer: Color(0xFF1A1A1C),
      button: Color(0xFFFFD23F),
      buttonBorder: Color(0xFF1A1A1C),
      buttonIcon: Color(0xFF1A1A1C),
    ),
    _ => const DialLook(
      face: Color(0xFF2C2C2E),
      edge: Color(0xFF111111),
      pointer: Color(0xFFFFFFFF),
    ),
  };
}
