import 'package:material_ui/material_ui.dart';

/// Computer keys for one octave and a bit (like a piano: A=C, W=C#…).
const pianoKeys = 'AWSEDFTGYHUJK';

/// Multi-touch piano: [octaves] octaves starting at MIDI note [baseNote]
/// (a C). Sliding a finger across keys plays the keys it crosses.
class PianoKeyboard extends StatefulWidget {
  const PianoKeyboard({
    super.key,
    required this.baseNote,
    required this.isDown,
    required this.onNoteOn,
    required this.onNoteOff,
    this.repaint,
    this.octaves = 2,
  });

  final int baseNote;
  final bool Function(int note) isDown;
  final void Function(int note) onNoteOn;
  final void Function(int note) onNoteOff;

  /// Repaints the keys when this changes (e.g. the synth controller).
  final Listenable? repaint;
  final int octaves;

  @override
  State<PianoKeyboard> createState() => _PianoKeyboardState();
}

class _PianoKeyboardState extends State<PianoKeyboard> {
  final _pointerNote = <int, int>{};

  static const _blackAfter = {0, 1, 3, 4, 5}; // white index -> has black key

  int get _base => widget.baseNote;

  /// Note under [p], black keys first.
  int? _noteAt(Offset p, Size s) {
    final whites = widget.octaves * 7 + 1;
    final ww = s.width / whites;
    if (p.dy < s.height * 0.6) {
      for (var w = 0; w < whites - 1; w++) {
        if (!_blackAfter.contains(w % 7)) continue;
        final cx = (w + 1) * ww;
        if ((p.dx - cx).abs() < ww * 0.3) return _base + _whiteSemis(w) + 1;
      }
    }
    final w = (p.dx / ww).floor().clamp(0, whites - 1);
    return _base + _whiteSemis(w);
  }

  static int _whiteSemis(int w) =>
      (w ~/ 7) * 12 + const [0, 2, 4, 5, 7, 9, 11][w % 7];

  void _press(int pointer, Offset p, Size s) {
    final n = _noteAt(p, s);
    final old = _pointerNote[pointer];
    if (n == old) return;
    if (old != null) widget.onNoteOff(old);
    if (n != null) {
      _pointerNote[pointer] = n;
      widget.onNoteOn(n);
    }
  }

  void _release(int pointer) {
    final old = _pointerNote.remove(pointer);
    if (old != null) widget.onNoteOff(old);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        return Listener(
          onPointerDown: (e) => _press(e.pointer, e.localPosition, size),
          onPointerMove: (e) => _press(e.pointer, e.localPosition, size),
          onPointerUp: (e) => _release(e.pointer),
          onPointerCancel: (e) => _release(e.pointer),
          child: ListenableBuilder(
            listenable: widget.repaint ?? const AlwaysStoppedAnimation(0),
            builder: (context, _) => CustomPaint(
              size: size,
              painter: _KeysPainter(
                octaves: widget.octaves,
                base: _base,
                isDown: widget.isDown,
                // Real piano colours in both themes.
                white: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFFD5DADF)
                    : const Color(0xFFF7F8FA),
                black: const Color(0xFF16191D),
                lit: scheme.primary,
                border: scheme.outlineVariant,
                label: scheme.outline,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _KeysPainter extends CustomPainter {
  _KeysPainter({
    required this.octaves,
    required this.base,
    required this.isDown,
    required this.white,
    required this.black,
    required this.lit,
    required this.border,
    required this.label,
  });

  final int octaves, base;
  final bool Function(int note) isDown;
  final Color white, black, lit, border, label;

  @override
  void paint(Canvas canvas, Size size) {
    final whites = octaves * 7 + 1;
    final ww = size.width / whites;
    final bp = Paint()
      ..color = border
      ..style = PaintingStyle.stroke;
    for (var w = 0; w < whites; w++) {
      final note = base + _PianoKeyboardState._whiteSemis(w);
      final r = Rect.fromLTWH(w * ww, 0, ww, size.height).deflate(1);
      final rr = RRect.fromRectAndCorners(
        r,
        bottomLeft: const Radius.circular(6),
        bottomRight: const Radius.circular(6),
      );
      canvas.drawRRect(rr, Paint()..color = isDown(note) ? lit : white);
      canvas.drawRRect(rr, bp);
      if (w % 7 == 0) {
        final tp = TextPainter(
          text: TextSpan(
            text: 'C${note ~/ 12 - 1}',
            style: TextStyle(color: label, fontSize: 11),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(w * ww + (ww - tp.width) / 2, size.height - tp.height - 6),
        );
      }
    }
    for (var w = 0; w < whites - 1; w++) {
      if (!_PianoKeyboardState._blackAfter.contains(w % 7)) continue;
      final note = base + _PianoKeyboardState._whiteSemis(w) + 1;
      final r = Rect.fromCenter(
        center: Offset((w + 1) * ww, size.height * 0.3),
        width: ww * 0.6,
        height: size.height * 0.6,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(4)),
        Paint()..color = isDown(note) ? lit : black,
      );
    }
  }

  @override
  bool shouldRepaint(_KeysPainter old) => true;
}
