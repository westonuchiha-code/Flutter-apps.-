import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../models.dart';

/// Scanlines, glass glare and dark corners laid over the picture, so any
/// video looks like it's on a tube TV. It never blocks taps.
class CrtOverlay extends StatelessWidget {
  const CrtOverlay({super.key, required this.effect});

  final CrtEffect effect;

  @override
  Widget build(BuildContext context) {
    if (effect == CrtEffect.off) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(painter: _CrtPainter(effect), size: Size.infinite),
      ),
    );
  }
}

/// Corner rounding for the screen glass, as a fraction of its height.
double screenCornerRadius(CrtEffect effect, double screenHeight) => switch (effect) {
      CrtEffect.off => 0.0,
      CrtEffect.subtle => screenHeight * 0.035,
      CrtEffect.strong => screenHeight * 0.07,
    };

class _CrtPainter extends CustomPainter {
  _CrtPainter(this.effect);

  final CrtEffect effect;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final strong = effect == CrtEffect.strong;
    final rect = Offset.zero & size;

    // Scanlines: about 300 (subtle) or 240 (strong) dark lines top to bottom,
    // whatever the window size, like a standard-definition picture.
    final spacing = max(2.0, size.height / (strong ? 240 : 300));
    final thickness = spacing * (strong ? 0.5 : 0.4);
    final linePaint = Paint()..color = Colors.black.withValues(alpha: strong ? 0.32 : 0.18);
    for (var y = 0.0; y < size.height; y += spacing) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, thickness), linePaint);
    }

    // Strong only: a faint red-green-blue stripe mask, like phosphor stripes.
    if (strong) {
      final stripe = max(3.0, size.width / 420);
      final colors = [
        const Color(0xFFFF0000).withValues(alpha: 0.045),
        const Color(0xFF00FF00).withValues(alpha: 0.03),
        const Color(0xFF0000FF).withValues(alpha: 0.045),
      ];
      var i = 0;
      for (var x = 0.0; x < size.width; x += stripe / 3) {
        canvas.drawRect(
          Rect.fromLTWH(x, 0, stripe / 3, size.height),
          Paint()..color = colors[i % 3],
        );
        i++;
      }
    }

    // Darker corners, like the edges of a curved tube.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 0.8,
          colors: [
            Colors.black.withValues(alpha: 0.0),
            Colors.black.withValues(alpha: 0.0),
            Colors.black.withValues(alpha: strong ? 0.6 : 0.38),
          ],
          stops: const [0.0, 0.62, 1.0],
        ).createShader(rect),
    );

    // A soft reflection on the glass, top left.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.center,
          colors: [
            Colors.white.withValues(alpha: strong ? 0.09 : 0.06),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_CrtPainter oldDelegate) => oldDelegate.effect != effect;
}
