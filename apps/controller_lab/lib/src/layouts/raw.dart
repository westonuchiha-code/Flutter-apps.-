import 'package:flutter/painting.dart';

import '../model/controls.dart';
import '../model/session.dart';
import 'layout.dart';
import 'paint_kit.dart';

/// Any controller, as the raw joystick sees it: numbered buttons, hats
/// and axes. For pads SDL has no mapping for (odd Bluetooth pads,
/// adapters) and as the "raw" view of every pad.
class RawLayout extends ControllerLayout {
  const RawLayout();

  static const perRow = 8;
  static const _top = 40.0, _rowH = 104.0, _hatH = 150.0, _axisH = 64.0;

  @override
  String get id => 'raw';

  @override
  String get title => 'Raw joystick';

  @override
  bool matches(ControllerInfo info) => true;

  String _buttonLabel(ControllerInfo info, PadState? s, int i) =>
      s?.buttonNames?[i] ?? '${i + 1}';

  @override
  List<LayoutPart> parts(ControllerInfo info) => [
    for (var i = 0; i < info.buttonCount; i++)
      LayoutPart.rawButton('b$i', 'Button ${i + 1}', i),
    for (var h = 0; h < info.hatCount; h++)
      for (final (bit, dir) in [(1, '↑'), (4, '↓'), (8, '←'), (2, '→')])
        LayoutPart.hat('h$h.$bit', 'Hat ${h + 1} $dir', h, bit),
    for (var i = 0; i < info.axisCount; i++)
      LayoutPart.rawAxis('a$i', 'Axis ${i + 1}', i),
  ];

  int _rows(int n) => (n + perRow - 1) ~/ perRow;

  @override
  Size designSize(ControllerInfo info) => Size(
    1000,
    _top * 2 +
        _rows(info.buttonCount) * _rowH +
        (info.hatCount > 0 ? _hatH : 0) +
        ((info.axisCount + 1) ~/ 2) * _axisH +
        (info.buttonCount + info.hatCount + info.axisCount == 0 ? 120 : 0),
  );

  @override
  void paint(
    Canvas canvas,
    ControllerInfo info,
    PadState state,
    TestSession session,
    PadPalette palette,
  ) {
    final pp = PadPainter(canvas, state, session, palette);
    final btn = palette.ink.withValues(alpha: 0.16);
    if (info.buttonCount + info.hatCount + info.axisCount == 0) {
      pp.text(
        'No buttons or axes reported yet',
        const Offset(500, 100),
        size: 28,
      );
      return;
    }
    var y = _top;
    for (var i = 0; i < info.buttonCount; i++) {
      final row = i ~/ perRow, col = i % perRow;
      final c = Offset(
        500 + (col - (perRow - 1) / 2) * 118,
        y + row * _rowH + 40,
      );
      final label = _buttonLabel(info, state, i);
      pp.roundButton(
        'b$i',
        c,
        38,
        fill: btn,
        label: label.length > 4 ? label.replaceFirst('BUTTON_', '') : label,
        labelColor: palette.ink,
        labelSize: label.length > 3 ? 13 : 26,
      );
    }
    y += _rows(info.buttonCount) * _rowH;
    if (info.hatCount > 0) {
      for (var h = 0; h < info.hatCount; h++) {
        final c = Offset(
          500 + (h - (info.hatCount - 1) / 2) * 180,
          y + _hatH / 2,
        );
        pp.dpad(
          c,
          110,
          fill: btn,
          up: 'h$h.1',
          down: 'h$h.4',
          left: 'h$h.8',
          right: 'h$h.2',
        );
        pp.text('Hat ${h + 1}', c + const Offset(0, 68), size: 14);
      }
      y += _hatH;
    }
    for (var i = 0; i < info.axisCount; i++) {
      final col = i % 2, row = i ~/ 2;
      final rect = Rect.fromLTWH(
        130.0 + col * 450,
        y + row * _axisH + 18,
        330,
        28,
      );
      final v = state.axes.length > i ? state.axes[i] / 32767 : 0.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        Paint()..color = btn,
      );
      final mid = rect.center.dx;
      final end = mid + v.clamp(-1.0, 1.0) * rect.width / 2;
      canvas.drawRRect(
        RRect.fromLTRBR(
          v < 0 ? end : mid,
          rect.top,
          v < 0 ? mid : end,
          rect.bottom,
          const Radius.circular(6),
        ),
        Paint()..color = palette.lit,
      );
      canvas.drawLine(
        Offset(mid, rect.top - 4),
        Offset(mid, rect.bottom + 4),
        Paint()
          ..color = palette.ink
          ..strokeWidth = 2,
      );
      final st = session.axes['a$i'];
      if (st != null && st.min.isFinite) {
        final seen = Paint()
          ..color = palette.ink.withValues(alpha: 0.6)
          ..strokeWidth = 2;
        for (final e in [st.min, st.max]) {
          final x = mid + e.clamp(-1.0, 1.0) * rect.width / 2;
          canvas.drawLine(
            Offset(x, rect.top - 6),
            Offset(x, rect.bottom + 6),
            seen,
          );
        }
      }
      final name =
          state.axisNames?[i].replaceFirst('AXIS_', '') ?? 'Axis ${i + 1}';
      pp.text(name, Offset(rect.left - 58, rect.center.dy), size: 14);
      if (pp.checked('a$i')) pp.tick(Offset(rect.right + 16, rect.center.dy));
    }
  }
}
