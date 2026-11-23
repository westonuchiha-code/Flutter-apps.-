import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// Oscilloscope of the synth output, drawn like a retro LCD.
class ScopeView extends StatelessWidget {
  const ScopeView({super.key, required this.data});

  final ValueListenable<Float32List?> data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ColoredBox(
        color: const Color(0xFF0F1A12),
        child: ValueListenableBuilder(
          valueListenable: data,
          builder: (context, samples, _) => CustomPaint(
            painter: _ScopePainter(samples, scheme.primary),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _ScopePainter extends CustomPainter {
  _ScopePainter(this.samples, this.color);

  final Float32List? samples;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFF1F3324)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      grid,
    );
    final s = samples;
    if (s == null || s.isEmpty) return;
    // Start at a rising zero crossing so the wave stands still.
    var start = 0;
    for (var i = 1; i < s.length ~/ 2; i++) {
      if (s[i - 1] <= 0 && s[i] > 0) {
        start = i;
        break;
      }
    }
    final count = s.length - start < 256 ? s.length - start : 256;
    final path = Path();
    for (var i = 0; i < count; i++) {
      final x = i / (count - 1) * size.width;
      final y = size.height / 2 - s[start + i] * size.height * 0.45;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF7CFC9A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_ScopePainter old) => !identical(old.samples, samples);
}
