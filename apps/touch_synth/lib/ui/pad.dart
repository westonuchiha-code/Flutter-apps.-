import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../app/synth_controller.dart';

const _noteNames = [
  'C',
  'C♯',
  'D',
  'D♯',
  'E',
  'F',
  'F♯',
  'G',
  'G♯',
  'A',
  'A♯',
  'B',
];
const fingerColors = [
  Color(0xFF39E0FF),
  Color(0xFFFF3DF2),
  Color(0xFFB6FF3A),
  Color(0xFFFFB13B),
  Color(0xFFFF4F5A),
  Color(0xFF9A7CFF),
];

/// The play surface: left→right = pitch (smooth), bottom→top = filter/volume.
/// Every finger is its own voice.
class TouchPad extends StatelessWidget {
  const TouchPad({super.key, required this.controller});

  final SynthController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        Offset norm(Offset p) => Offset(p.dx / c.maxWidth, p.dy / c.maxHeight);
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) =>
              controller.fingerDown(e.pointer, norm(e.localPosition)),
          onPointerMove: (e) =>
              controller.fingerMove(e.pointer, norm(e.localPosition)),
          onPointerUp: (e) => controller.fingerUp(e.pointer),
          onPointerCancel: (e) => controller.fingerUp(e.pointer),
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => CustomPaint(
              size: c.biggest,
              painter: _PadPainter(
                low: controller.lowNote,
                octaves: controller.octaves,
                fingers: List.of(controller.fingers),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PadPainter extends CustomPainter {
  _PadPainter({
    required this.low,
    required this.octaves,
    required this.fingers,
  });

  final int low;
  final int octaves;
  final List<Offset?> fingers;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A1030), Color(0xFF0A0A12)],
        ).createShader(rect),
    );
    // Note guide lines: C bright, natural notes medium, sharps faint.
    final semis = octaves * 12;
    for (var i = 0; i <= semis; i++) {
      final midi = low + i;
      final x = i / semis * size.width;
      final pc = midi % 12;
      final isC = pc == 0;
      final sharp = const [1, 3, 6, 8, 10].contains(pc);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = isC
              ? const Color(0x9939E0FF)
              : sharp
              ? const Color(0x14FFFFFF)
              : const Color(0x33FFFFFF)
          ..strokeWidth = isC ? 2 : 1,
      );
      if (!sharp) {
        final tp = TextPainter(
          text: TextSpan(
            text: isC ? '${_noteNames[pc]}${midi ~/ 12 - 1}' : _noteNames[pc],
            style: TextStyle(
              fontSize: isC ? 12 : 10,
              color: isC ? const Color(0xCC39E0FF) : const Color(0x66FFFFFF),
              fontWeight: isC ? FontWeight.w800 : FontWeight.w400,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + 3, size.height - tp.height - 4));
      }
    }
    // Horizontal hint lines for the Y axis.
    for (var j = 1; j < 4; j++) {
      final y = size.height * j / 4;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()..color = const Color(0x0FFFFFFF),
      );
    }
    // Fingers.
    for (var i = 0; i < fingers.length; i++) {
      final f = fingers[i];
      if (f == null) continue;
      final p = Offset(f.dx * size.width, f.dy * size.height);
      final color = fingerColors[i % fingerColors.length];
      canvas
        ..drawLine(
          Offset(p.dx, 0),
          Offset(p.dx, size.height),
          Paint()
            ..color = color.withValues(alpha: 0.35)
            ..strokeWidth = 2,
        )
        ..drawCircle(
          p,
          46,
          Paint()
            ..shader = RadialGradient(
              colors: [
                color.withValues(alpha: 0.55),
                color.withValues(alpha: 0),
              ],
            ).createShader(Rect.fromCircle(center: p, radius: 46)),
        )
        ..drawCircle(
          p,
          18,
          Paint()
            ..color = color.withValues(alpha: 0.9)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      final midi = low + f.dx * octaves * 12;
      final n = midi.round();
      final cents = ((midi - n) * 100).round();
      final tp = TextPainter(
        text: TextSpan(
          text:
              '${_noteNames[n % 12]}${n ~/ 12 - 1}${cents == 0
                  ? ''
                  : cents > 0
                  ? ' +$cents'
                  : ' $cents'}',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, p.translate(-tp.width / 2, -44));
    }
  }

  @override
  bool shouldRepaint(_PadPainter old) => true;
}

/// For tests and debugging.
double padX(int low, int octaves, double midi) => (midi - low) / (octaves * 12);

double centsBetween(double a, double b) => 1200 * math.log(b / a) / math.ln2;
