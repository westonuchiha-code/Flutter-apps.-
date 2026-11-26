/// The gold round a favorite: a soft halo, twinkles circling it and a small
/// star in the corner (ported from the PC's FavoriteSparkle.gd). It's
/// painted under [FavoriteSparkle.child], so it never covers the save's art.
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'look.dart';

class FavoriteSparkle extends StatefulWidget {
  const FavoriteSparkle({
    super.key,
    this.size = 96,
    this.child,
    this.dimmed = false,
    this.animate = true,
  });

  /// The icon's square; the halo and twinkles reach a little past it.
  final double size;
  final Widget? child;
  final bool dimmed;
  final bool animate;

  static const gold = Color(0xFFFFD54A);
  static const pale = Color(0xFFFFF6C8);
  static const deep = Color(0xFF8A5A00);

  @override
  State<FavoriteSparkle> createState() => _FavoriteSparkleState();
}

class _FavoriteSparkleState extends State<FavoriteSparkle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _time = AnimationController(
    vsync: this,
    // Long enough that the loop is never seen.
    duration: const Duration(minutes: 10),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _time.repeat();
  }

  @override
  void didUpdateWidget(FavoriteSparkle old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_time.isAnimating) {
      _time.repeat();
    } else if (!widget.animate) {
      _time.stop();
    }
  }

  @override
  void dispose() {
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size,
    child: CustomPaint(
      painter: _SparklePainter(_time, widget.dimmed),
      child: widget.child,
    ),
  );
}

class _SparklePainter extends CustomPainter {
  _SparklePainter(this.time, this.dimmed) : super(repaint: time);

  final AnimationController time;
  final bool dimmed;

  static const twinkles = 9;
  static const drift = 0.22; // radians a second round the icon
  static const blink = 2.3;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value * 600;
    final alpha = dimmed ? 0.35 : 1.0;
    final mid = size.center(Offset.zero);
    final side = math.min(size.width, size.height);
    final breath = 0.5 + 0.5 * math.sin(t * 1.7);
    final halo = side * 1.34;
    Look.glow(
      canvas,
      Rect.fromCenter(center: mid, width: halo, height: halo),
      tint: FavoriteSparkle.gold,
      alpha: (0.62 + 0.18 * breath) * alpha,
    );
    // Just outside where an icon reaches.
    final around = Offset(side * 0.58, side * 0.5);
    for (var k = 0; k < twinkles; k++) {
      final turn = 2 * math.pi * k / twinkles + t * drift;
      final out = 1 + 0.1 * math.sin(k * 2.1);
      final at =
          mid +
          Offset(
            math.cos(turn) * around.dx * out,
            math.sin(turn) * around.dy * out,
          );
      final shine = 0.5 + 0.5 * math.sin(t * blink + k * 2.4);
      final c = Color.lerp(FavoriteSparkle.gold, FavoriteSparkle.pale, shine)!;
      _twinkle(
        canvas,
        at,
        side * (0.035 + 0.05 * shine),
        c.withValues(alpha: (0.35 + 0.65 * shine) * alpha),
      );
    }
    _star(
      canvas,
      Offset(mid.dx + around.dx * 0.98, mid.dy - around.dy * 0.9),
      side * 0.1,
      alpha,
    );
  }

  void _twinkle(Canvas canvas, Offset at, double size, Color col) {
    final w = size * 0.22;
    final path = Path()
      ..moveTo(at.dx, at.dy - size)
      ..lineTo(at.dx + w, at.dy - w)
      ..lineTo(at.dx + size, at.dy)
      ..lineTo(at.dx + w, at.dy + w)
      ..lineTo(at.dx, at.dy + size)
      ..lineTo(at.dx - w, at.dy + w)
      ..lineTo(at.dx - size, at.dy)
      ..lineTo(at.dx - w, at.dy - w)
      ..close();
    canvas.drawPath(path, Paint()..color = col);
  }

  void _star(Canvas canvas, Offset at, double size, double alpha) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? size : size * 0.46;
      final turn = -math.pi / 2 + math.pi * i / 5;
      final p = at + Offset(math.cos(turn) * r, math.sin(turn) * r);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()..color = FavoriteSparkle.gold.withValues(alpha: alpha),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(size * 0.12, 1.5)
        ..strokeJoin = StrokeJoin.round
        ..color = FavoriteSparkle.deep.withValues(alpha: alpha),
    );
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.dimmed != dimmed;
}
