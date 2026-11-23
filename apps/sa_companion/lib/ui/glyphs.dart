import 'package:material_ui/material_ui.dart';

import 'theme.dart';

const _faceColors = {
  'X': Color(0xFF6DA0FF),
  'O': Color(0xFFFF6B6B),
  'T': Color(0xFF58D68D),
  'S': Color(0xFFF08AC4),
};

const buttonNames = {
  'X': 'Cross',
  'O': 'Circle',
  'T': 'Triangle',
  'S': 'Square',
  'U': 'Up',
  'D': 'Down',
  'L': 'Left',
  'R': 'Right',
};

/// A PS2 controller button: face buttons and d-pad are drawn, shoulder
/// buttons (L1, L2, R1, R2) are labelled keycaps.
class ButtonGlyph extends StatelessWidget {
  const ButtonGlyph(this.token, {super.key, this.size = 29});

  final String token;
  final double size;

  @override
  Widget build(BuildContext context) {
    final label = buttonNames[token] ?? token;
    if (_faceColors.containsKey(token) || 'UDLR'.contains(token)) {
      return Semantics(
        label: label,
        child: CustomPaint(
          size: Size.square(size),
          painter: _GlyphPainter(token),
        ),
      );
    }
    final trigger = token.endsWith('2');
    return Semantics(
      label: label,
      child: Container(
        height: size * 0.86,
        constraints: BoxConstraints(minWidth: size * 1.25),
        padding: EdgeInsets.symmetric(horizontal: size * 0.12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: trigger
                ? const [Color(0xFF3A4540), Color(0xFF1B211E)]
                : const [Color(0xFF2A322F), Color(0xFF171C19)],
          ),
          border: Border.all(color: const Color(0xFF4A5651), width: 1.5),
          borderRadius: trigger
              ? const BorderRadius.vertical(
                  top: Radius.circular(5),
                  bottom: Radius.circular(12),
                )
              : const BorderRadius.vertical(
                  top: Radius.circular(9),
                  bottom: Radius.circular(5),
                ),
        ),
        // widthFactor 1: shrink-wrap instead of filling the row.
        child: Center(
          widthFactor: 1,
          child: Text(
            token,
            style: condensed(
              size: size * 0.5,
              color: const Color(0xFFE9ECE9),
              spacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.token);
  final String token;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 32);
    final face = _faceColors[token];
    if (face != null) {
      canvas.drawCircle(
        const Offset(16, 16),
        14.5,
        Paint()..color = const Color(0xFF0A0D0C),
      );
      canvas.drawCircle(
        const Offset(16, 16),
        14.5,
        Paint()
          ..color = const Color(0xFF46524D)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      final p = Paint()
        ..color = face
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.7
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      switch (token) {
        case 'O':
          canvas.drawCircle(const Offset(16, 16), 7.4, p);
        case 'X':
          canvas
            ..drawLine(const Offset(9.5, 9.5), const Offset(22.5, 22.5), p)
            ..drawLine(const Offset(22.5, 9.5), const Offset(9.5, 22.5), p);
        case 'T':
          canvas.drawPath(
            Path()
              ..moveTo(16, 8.2)
              ..lineTo(24, 22.2)
              ..lineTo(8, 22.2)
              ..close(),
            p,
          );
        default:
          canvas.drawRect(const Rect.fromLTWH(9, 9, 14, 14), p);
      }
      return;
    }
    // D-pad cross with the pressed arm highlighted.
    final cross = Path()
      ..moveTo(11, 3)
      ..lineTo(21, 3)
      ..lineTo(21, 11)
      ..lineTo(29, 11)
      ..lineTo(29, 21)
      ..lineTo(21, 21)
      ..lineTo(21, 29)
      ..lineTo(11, 29)
      ..lineTo(11, 21)
      ..lineTo(3, 21)
      ..lineTo(3, 11)
      ..lineTo(11, 11)
      ..close();
    canvas
      ..drawPath(cross, Paint()..color = const Color(0xFF1B221F))
      ..drawPath(
        cross,
        Paint()
          ..color = const Color(0xFF4D5A54)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeJoin = StrokeJoin.round,
      );
    final arm = switch (token) {
      'U' => const Rect.fromLTWH(11, 3, 10, 8),
      'D' => const Rect.fromLTWH(11, 21, 10, 8),
      'L' => const Rect.fromLTWH(3, 11, 8, 10),
      _ => const Rect.fromLTWH(21, 11, 8, 10),
    };
    canvas.drawRect(arm, Paint()..color = SaColors.ink);
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.token != token;
}

/// A whole cheat sequence as a wrapping row of glyphs.
class ButtonSequence extends StatelessWidget {
  const ButtonSequence(this.buttons, {super.key, this.size = 29});

  final List<String> buttons;
  final double size;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 5,
    runSpacing: 5,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [for (final b in buttons) ButtonGlyph(b, size: size)],
  );
}
