import 'package:material_ui/material_ui.dart';

import '../app/synth_controller.dart';
import 'style.dart';

const _names = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];
bool _isBlack(int midi) => const [1, 3, 6, 8, 10].contains(midi % 12);

/// Play surface: left→right = pitch (smooth), bottom→top = the Y control.
/// A key strip along the bottom shows where the notes are.
class TouchPad extends StatelessWidget {
  const TouchPad({super.key, required this.controller, required this.yLabel});

  final SynthController controller;
  final String yLabel;

  static const keyStrip = 28.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final h = c.maxHeight - keyStrip;
        Offset norm(Offset p) =>
            Offset(p.dx / c.maxWidth, (p.dy / h).clamp(0.0, 1.0));
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
                yLabel: yLabel,
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
    required this.yLabel,
  });

  final int low;
  final int octaves;
  final List<Offset?> fingers;
  final String yLabel;

  void _text(
    Canvas canvas,
    String s,
    Offset at, {
    Color color = Ui.dim,
    double size = 11,
    FontWeight weight = FontWeight.w500,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontFamily: 'Roboto',
          color: color,
          fontSize: size,
          fontWeight: weight,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final padH = size.height - TouchPad.keyStrip;
    canvas.drawRect(Offset.zero & size, Paint()..color = Ui.bg);
    final semis = octaves * 12;
    final step = size.width / semis;

    // Lane shading like a piano roll: black-key lanes slightly darker.
    for (var i = 0; i < semis; i++) {
      final midi = low + i;
      final x = i * step;
      if (_isBlack(midi)) {
        canvas.drawRect(
          Rect.fromLTWH(x, 0, step, padH),
          Paint()..color = const Color(0xFF0F1114),
        );
      }
      final isC = midi % 12 == 0;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, padH),
        Paint()
          ..color = isC ? const Color(0xFF3A4048) : const Color(0xFF1F2328)
          ..strokeWidth = 1,
      );
    }
    for (var i = 0; i < semis; i++) {
      final midi = low + i;
      if (midi % 12 == 0) {
        _text(canvas, 'C${midi ~/ 12 - 1}', Offset(i * step + 4, 6));
      }
    }
    // Y-axis caption.
    canvas
      ..save()
      ..translate(8, padH - 10)
      ..rotate(-1.5708);
    _text(canvas, '$yLabel  →', Offset.zero, size: 10);
    canvas.restore();

    // Key strip.
    final top = padH;
    canvas.drawRect(
      Rect.fromLTWH(0, top, size.width, TouchPad.keyStrip),
      Paint()..color = const Color(0xFFD9DCE0),
    );
    for (var i = 0; i < semis; i++) {
      final midi = low + i;
      final x = i * step;
      if (_isBlack(midi)) {
        canvas.drawRect(
          Rect.fromLTWH(x, top, step, TouchPad.keyStrip * 0.62),
          Paint()..color = const Color(0xFF202327),
        );
      }
      if (midi % 12 == 0 || midi % 12 == 5) {
        canvas.drawLine(
          Offset(x, top),
          Offset(x, size.height),
          Paint()..color = const Color(0xFF9AA0A8),
        );
      }
    }
    canvas.drawLine(
      Offset(0, top),
      Offset(size.width, top),
      Paint()..color = Ui.line,
    );

    // Fingers: thin pitch line, simple marker, note readout.
    for (var i = 0; i < fingers.length; i++) {
      final f = fingers[i];
      if (f == null) continue;
      final p = Offset(f.dx * size.width, f.dy * padH);
      canvas
        ..drawLine(
          Offset(p.dx, 0),
          Offset(p.dx, size.height),
          Paint()
            ..color = Ui.accent.withValues(alpha: 0.45)
            ..strokeWidth = 1.5,
        )
        ..drawCircle(p, 13, Paint()..color = Ui.accent)
        ..drawCircle(
          p,
          13,
          Paint()
            ..color = Ui.bg
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      final midi = low + f.dx * semis;
      final n = midi.round();
      final cents = ((midi - n) * 100).round();
      final label =
          '${_names[n % 12]}${n ~/ 12 - 1}${cents == 0
              ? ''
              : cents > 0
              ? ' +$cents'
              : ' $cents'}';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            fontFamily: 'Roboto',
            color: Ui.text,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final box = Rect.fromCenter(
        center: p.translate(0, -32),
        width: tp.width + 12,
        height: tp.height + 6,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(4)),
        Paint()..color = Ui.raised,
      );
      tp.paint(canvas, box.topLeft.translate(6, 3));
    }
  }

  @override
  bool shouldRepaint(_PadPainter old) => true;
}
