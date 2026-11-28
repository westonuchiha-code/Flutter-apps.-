import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../model/controls.dart';
import '../model/session.dart';
import 'layout.dart';

/// Shared drawing pieces for the controller drawings: buttons that light
/// when pressed and get a tick once tested, sticks with their position,
/// gate and deadzone, d-pads, triggers.
class PadPainter {
  PadPainter(this.canvas, this.state, this.session, this.palette);

  final Canvas canvas;
  final PadState state;
  final TestSession session;
  final PadPalette palette;

  LayoutPart? part(String id) {
    for (final p in session.parts) {
      if (p.id == id) return p;
    }
    return null;
  }

  bool lit(String id) => part(id)?.active(state) ?? false;
  bool checked(String id) => session.checked.contains(id);

  void text(
    String s,
    Offset center, {
    double size = 16,
    Color? color,
    FontWeight weight = FontWeight.w600,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontSize: size,
          color: color ?? palette.ink,
          fontWeight: weight,
          fontFamily: palette.fontFamily,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  void glow(Path shape) {
    canvas.drawPath(
      shape,
      Paint()
        ..color = palette.lit.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
  }

  /// The small "tested" tick at [at].
  void tick(Offset at, {double r = 8}) {
    canvas.drawCircle(at, r, Paint()..color = palette.checked);
    final path = Path()
      ..moveTo(at.dx - r * 0.45, at.dy)
      ..lineTo(at.dx - r * 0.1, at.dy + r * 0.38)
      ..lineTo(at.dx + r * 0.5, at.dy - r * 0.38);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.3
        ..strokeCap = StrokeCap.round,
    );
  }

  /// A part shaped like [shape]: [fill] normally, the lit colour while
  /// pressed, a tick at [tickAt] once tested.
  void shapePart(
    String id,
    Path shape, {
    required Color fill,
    Color? edge,
    String? label,
    Offset? labelAt,
    Color? labelColor,
    double labelSize = 18,
    Offset? tickAt,
  }) {
    final on = lit(id);
    if (on) glow(shape);
    canvas.drawPath(shape, Paint()..color = on ? palette.lit : fill);
    if (edge != null) {
      canvas.drawPath(
        shape,
        Paint()
          ..color = edge
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    if (label != null) {
      text(
        label,
        labelAt ?? shape.getBounds().center,
        size: labelSize,
        color: on ? const Color(0xFF0B1A26) : labelColor,
      );
    }
    if (checked(id)) tick(tickAt ?? shape.getBounds().topRight);
  }

  void roundButton(
    String id,
    Offset c,
    double r, {
    required Color fill,
    Color? edge,
    String? label,
    Color? labelColor,
    double? labelSize,
  }) {
    if (part(id) == null) return;
    shapePart(
      id,
      Path()..addOval(Rect.fromCircle(center: c, radius: r)),
      fill: fill,
      edge: edge,
      label: label,
      labelColor: labelColor,
      labelSize: labelSize ?? r * 0.95,
      tickAt: c + Offset(r * 0.8, -r * 0.8),
    );
  }

  /// A stick: its well, gate (how far it has reached), deadzone ring and
  /// cap at the live position; [clickId] lights the cap's rim.
  void stick(
    String id,
    String? clickId,
    Offset c, {
    required double well,
    required double cap,
    required Color wellColor,
    required Color capColor,
    Color? capEdge,
  }) {
    final p = part(id);
    if (p == null) return;
    final travel = well - cap * 0.55;
    canvas.drawCircle(c, well, Paint()..color = wellColor);
    final st = session.sticks[id];
    final dz = st?.suggestedDeadzone;
    if (dz != null) {
      canvas.drawCircle(
        c,
        math.max(2, dz * travel),
        Paint()
          ..color = const Color(0xFFFFB300)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    final (x, y) = p.stick(state);
    final at = c + Offset(x, y) * travel;
    final moved = p.active(state);
    final clicked = clickId != null && lit(clickId);
    final capPath = Path()..addOval(Rect.fromCircle(center: at, radius: cap));
    if (moved || clicked) glow(capPath);
    canvas.drawPath(capPath, Paint()..color = clicked ? palette.lit : capColor);
    canvas.drawCircle(
      at,
      cap,
      Paint()
        ..color = moved ? palette.lit : (capEdge ?? capColor)
        ..style = PaintingStyle.stroke
        ..strokeWidth = moved ? 5 : 3,
    );
    // Thumb dimple.
    canvas.drawCircle(
      at,
      cap * 0.62,
      Paint()
        ..color = const Color(0x22000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Gate: the outline of the furthest it has gone each way.
    if (st != null && st.gate.any((g) => g > 0)) {
      // Only the directions it has been pushed (no spokes to the centre).
      final gate = Path();
      var first = true;
      for (var i = 0; i <= StickStats.sectors; i++) {
        final k = i % StickStats.sectors;
        if (st.gate[k] <= 0) continue;
        final a = (k + 0.5) / StickStats.sectors * 2 * math.pi - math.pi;
        final o = c + Offset(math.cos(a), math.sin(a)) * (st.gate[k] * travel);
        first ? gate.moveTo(o.dx, o.dy) : gate.lineTo(o.dx, o.dy);
        first = false;
      }
      canvas.drawPath(
        gate,
        Paint()
          ..color = palette.lit.withValues(alpha: 0.75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    if (checked(id)) tick(c + Offset(-well * 0.75, -well * 0.75));
    if (clickId != null && checked(clickId)) {
      tick(c + Offset(well * 0.75, -well * 0.75));
    }
  }

  /// A d-pad (plus shape) at [c]; each arm lights on its own.
  void dpad(
    Offset c,
    double size, {
    required Color fill,
    Color? edge,
    String up = 'up',
    String down = 'down',
    String left = 'left',
    String right = 'right',
  }) {
    final w = size * 0.36, h = size / 2;
    Path arm(double dx, double dy) {
      // An arm from the centre square out to [dx, dy].
      final r = dx == 0
          ? Rect.fromCenter(
              center: c + Offset(0, dy * (h + w / 2) / 2),
              width: w,
              height: h - w / 2 + 2,
            )
          : Rect.fromCenter(
              center: c + Offset(dx * (h + w / 2) / 2, 0),
              width: h - w / 2 + 2,
              height: w,
            );
      return Path()
        ..addRRect(RRect.fromRectAndRadius(r, Radius.circular(w * 0.18)));
    }

    final centre = Path()
      ..addRect(Rect.fromCenter(center: c, width: w, height: w));
    canvas.drawPath(centre, Paint()..color = fill);
    for (final (id, dx, dy) in [
      (up, 0.0, -1.0),
      (down, 0.0, 1.0),
      (left, -1.0, 0.0),
      (right, 1.0, 0.0),
    ]) {
      if (part(id) == null) continue;
      shapePart(
        id,
        arm(dx, dy),
        fill: fill,
        tickAt: c + Offset(dx, dy) * (h + 10),
      );
    }
    if (edge != null) {
      final all = Path()
        ..addRect(Rect.fromCenter(center: c, width: w, height: size))
        ..addRect(Rect.fromCenter(center: c, width: size, height: w));
      canvas.drawPath(
        all,
        Paint()
          ..color = edge
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    // Arrow marks.
    final mark = Paint()..color = const Color(0x55000000);
    for (final (dx, dy) in [(0.0, -1.0), (0.0, 1.0), (-1.0, 0.0), (1.0, 0.0)]) {
      canvas.drawCircle(c + Offset(dx, dy) * (h * 0.66), w * 0.1, mark);
    }
  }

  /// How far a trigger is pulled, as a bar under [rect].
  void triggerBar(String id, Rect rect) {
    final p = part(id);
    if (p == null) return;
    final v = p.value(state);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()..color = palette.ink.withValues(alpha: 0.15),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(rect.left, rect.top, rect.width * v, rect.height),
        const Radius.circular(4),
      ),
      Paint()..color = palette.lit,
    );
  }
}
