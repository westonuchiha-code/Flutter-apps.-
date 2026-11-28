import 'package:material_ui/material_ui.dart';

import '../layouts/layout.dart';
import '../model/controls.dart';
import '../model/session.dart';

/// Colours for the drawings, from the theme.
PadPalette padPalette(BuildContext context, {String variant = ''}) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  return PadPalette(
    fontFamily: theme.textTheme.bodyMedium?.fontFamily,
    lit: const Color(0xFF29B6F6),
    checked: const Color(0xFF2E9E4F),
    ink: cs.onSurface,
    background: cs.surface,
    variant: variant,
  );
}

/// A controller drawing, scaled to fit (keeping its shape), repainting
/// whenever [repaint] ticks.
class PadCanvas extends StatelessWidget {
  const PadCanvas({
    super.key,
    required this.layout,
    required this.info,
    required this.state,
    required this.session,
    required this.repaint,
    required this.palette,
  });

  final ControllerLayout layout;
  final ControllerInfo info;
  final PadState state;
  final TestSession session;
  final Listenable repaint;
  final PadPalette palette;

  @override
  Widget build(BuildContext context) {
    final ds = layout.designSize(info);
    return Semantics(
      label: '${layout.title} drawing',
      child: AspectRatio(
        aspectRatio: ds.width / ds.height,
        child: CustomPaint(
          painter: _PadPainter(layout, info, state, session, palette, repaint),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _PadPainter extends CustomPainter {
  _PadPainter(
    this.layout,
    this.info,
    this.state,
    this.session,
    this.palette,
    Listenable repaint,
  ) : super(repaint: repaint);

  final ControllerLayout layout;
  final ControllerInfo info;
  final PadState state;
  final TestSession session;
  final PadPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final ds = layout.designSize(info);
    final scale = (size.width / ds.width) < (size.height / ds.height)
        ? size.width / ds.width
        : size.height / ds.height;
    canvas.save();
    canvas.translate(
      (size.width - ds.width * scale) / 2,
      (size.height - ds.height * scale) / 2,
    );
    canvas.scale(scale);
    layout.paint(canvas, info, state, session, palette);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PadPainter old) =>
      old.layout != layout ||
      old.info != info ||
      old.state != state ||
      old.session != session ||
      old.palette.ink != palette.ink ||
      old.palette.variant != palette.variant;
}
