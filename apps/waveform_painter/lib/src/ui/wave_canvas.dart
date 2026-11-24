import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../controller.dart';

/// Draw the wave with a finger or mouse. Pen: freehand. Line: drag from
/// one point to another.
class WaveCanvas extends StatefulWidget {
  const WaveCanvas({super.key, required this.c});

  final PainterController c;

  @override
  State<WaveCanvas> createState() => _WaveCanvasState();
}

class _WaveCanvasState extends State<WaveCanvas> {
  Offset? _last; // wave coords: x 0..1, y -1..1
  Offset? _lineStart;
  Offset? _lineEnd;
  Float32List? _before;

  Offset _toWave(Offset p, Size s) => Offset(
    (p.dx / s.width).clamp(0.0, 0.9999),
    (1 - 2 * p.dy / s.height).clamp(-1.0, 1.0),
  );

  void _down(Offset p, Size s) {
    final c = widget.c;
    c.checkpoint();
    final w = _toWave(p, s);
    if (c.tool == DrawTool.pen) {
      c.stroke(w.dx, w.dy, w.dx, w.dy);
      _last = w;
    } else {
      _before = Float32List.fromList(c.wave);
      _lineStart = w;
      _lineEnd = w;
    }
  }

  void _move(Offset p, Size s) {
    final c = widget.c;
    final w = _toWave(p, s);
    if (c.tool == DrawTool.pen) {
      final l = _last ?? w;
      c.stroke(l.dx, l.dy, w.dx, w.dy);
      _last = w;
    } else if (_lineStart != null) {
      // Preview: restore, then draw the straight line.
      c.wave.setAll(0, _before!);
      _lineEnd = w;
      c.stroke(_lineStart!.dx, _lineStart!.dy, w.dx, w.dy);
    }
  }

  void _up() {
    _last = null;
    _lineStart = null;
    _lineEnd = null;
    _before = null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        return Listener(
          onPointerDown: (e) => _down(e.localPosition, size),
          onPointerMove: (e) => _move(e.localPosition, size),
          onPointerUp: (_) => _up(),
          onPointerCancel: (_) => _up(),
          child: ListenableBuilder(
            listenable: widget.c,
            builder: (context, _) => CustomPaint(
              size: size,
              painter: _WavePainter(
                wave: widget.c.wave,
                others: [
                  for (var i = 0; i < widget.c.waves.length; i++)
                    if (i != widget.c.selected) widget.c.waves[i],
                ],
                line: scheme.primary,
                ghost: scheme.outlineVariant,
                grid: scheme.surfaceContainerHighest,
                background: scheme.surfaceContainer,
                guide: _lineEnd == null ? null : (_lineStart!, _lineEnd!),
                version: widget.c.wave.hashCode ^ _lineEnd.hashCode,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.wave,
    required this.others,
    required this.line,
    required this.ghost,
    required this.grid,
    required this.background,
    required this.guide,
    required this.version,
  });

  final Float32List wave;
  final List<Float32List> others;
  final Color line, ghost, grid, background;
  final (Offset, Offset)? guide;
  final int version;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(12),
    );
    canvas.drawRRect(r, Paint()..color = background);
    canvas.save();
    canvas.clipRRect(r);
    final gp = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var k = 1; k < 8; k++) {
      final x = size.width * k / 8;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gp);
    }
    for (final f in [0.25, 0.5, 0.75]) {
      canvas.drawLine(
        Offset(0, size.height * f),
        Offset(size.width, size.height * f),
        gp..strokeWidth = f == 0.5 ? 2 : 1,
      );
    }
    Path pathOf(Float32List w) {
      final p = Path();
      for (var i = 0; i < w.length; i++) {
        final x = (i + 0.5) / w.length * size.width;
        final y = (1 - w[i]) / 2 * size.height;
        i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
      }
      return p;
    }

    final ghostPaint = Paint()
      ..color = ghost
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final o in others) {
      canvas.drawPath(pathOf(o), ghostPaint);
    }
    // Fill under the wave, then the line.
    final fill = pathOf(wave)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(0, size.height / 2)
      ..close();
    canvas.drawPath(fill, Paint()..color = line.withValues(alpha: 0.18));
    canvas.drawPath(
      pathOf(wave),
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WavePainter old) => true;
}
