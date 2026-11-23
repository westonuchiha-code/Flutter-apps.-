import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

/// Max peak of [peaks] in [from, to) (indices clamped).
double peakIn(Float32List peaks, int from, int to) {
  var m = 0.0;
  final a = from.clamp(0, peaks.length);
  final b = to.clamp(a, peaks.length);
  for (var i = a; i < b; i++) {
    if (peaks[i] > m) m = peaks[i];
  }
  return m;
}

/// Waveform with optional trim handles, markers and playhead.
///
/// In [live] mode it shows the last [liveSeconds] and scrolls.
class WaveformView extends StatefulWidget {
  const WaveformView({
    super.key,
    required this.peaks,
    this.peaksPerSecond = 100,
    this.live = false,
    this.liveSeconds = 8,
    this.markers = const [],
    this.trimStart,
    this.trimEnd,
    this.onTrimChanged,
    this.position,
    this.onSeek,
  });

  final Float32List peaks;
  final int peaksPerSecond;
  final bool live;
  final double liveSeconds;
  final List<double> markers;
  final double? trimStart;
  final double? trimEnd;
  final void Function(double start, double end)? onTrimChanged;
  final double? position;
  final void Function(double seconds)? onSeek;

  @override
  State<WaveformView> createState() => _WaveformViewState();
}

enum _Drag { none, start, end, seek }

class _WaveformViewState extends State<WaveformView> {
  _Drag _drag = _Drag.none;

  double get _total => widget.peaks.length / widget.peaksPerSecond;

  double _toSeconds(double x, double width) =>
      (x / width * _total).clamp(0, _total).toDouble();

  void _begin(Offset p, double width) {
    final s = widget.trimStart, e = widget.trimEnd;
    if (widget.onTrimChanged != null && s != null && e != null && _total > 0) {
      final xs = s / _total * width, xe = e / _total * width;
      final ds = (p.dx - xs).abs(), de = (p.dx - xe).abs();
      if (math.min(ds, de) < 28) {
        _drag = ds <= de ? _Drag.start : _Drag.end;
        return;
      }
    }
    _drag = widget.onSeek == null ? _Drag.none : _Drag.seek;
    _update(p, width);
  }

  void _update(Offset p, double width) {
    final t = _toSeconds(p.dx, width);
    final s = widget.trimStart ?? 0, e = widget.trimEnd ?? _total;
    const minLen = 0.05;
    switch (_drag) {
      case _Drag.start:
        widget.onTrimChanged!(math.min(t, e - minLen).clamp(0, _total), e);
      case _Drag.end:
        widget.onTrimChanged!(s, math.max(t, s + minLen).clamp(0, _total));
      case _Drag.seek:
        widget.onSeek!(t);
      case _Drag.none:
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        final painter = _WavePainter(
          peaks: widget.peaks,
          peaksPerSecond: widget.peaksPerSecond,
          live: widget.live,
          liveSeconds: widget.liveSeconds,
          markers: widget.markers,
          trimStart: widget.trimStart,
          trimEnd: widget.trimEnd,
          position: widget.position,
          wave: scheme.primary,
          dim: scheme.outlineVariant,
          marker: scheme.tertiary,
          head: scheme.onSurface,
          handle: scheme.secondary,
          background: scheme.surfaceContainerHighest,
        );
        final paint = CustomPaint(painter: painter, size: Size.infinite);
        if (widget.live) return paint;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) {
            _begin(d.localPosition, c.maxWidth);
            _drag = _Drag.none;
          },
          onHorizontalDragStart: (d) => _begin(d.localPosition, c.maxWidth),
          onHorizontalDragUpdate: (d) => _update(d.localPosition, c.maxWidth),
          onHorizontalDragEnd: (_) => _drag = _Drag.none,
          child: paint,
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.peaks,
    required this.peaksPerSecond,
    required this.live,
    required this.liveSeconds,
    required this.markers,
    required this.trimStart,
    required this.trimEnd,
    required this.position,
    required this.wave,
    required this.dim,
    required this.marker,
    required this.head,
    required this.handle,
    required this.background,
  }) : _length = peaks.length;

  final Float32List peaks;
  final int _length;
  final int peaksPerSecond;
  final bool live;
  final double liveSeconds;
  final List<double> markers;
  final double? trimStart, trimEnd, position;
  final Color wave, dim, marker, head, handle, background;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(8),
    );
    canvas.drawRRect(r, Paint()..color = background);
    canvas.save();
    canvas.clipRRect(r);
    final mid = size.height / 2;
    final w = size.width;
    // Visible window, in peak indices.
    final double first, span;
    if (live) {
      span = liveSeconds * peaksPerSecond;
      first = math.max(0, _length - span);
    } else {
      first = 0;
      span = math.max(1, _length).toDouble();
    }
    double xOf(double seconds) => (seconds * peaksPerSecond - first) / span * w;

    final ts = trimStart, te = trimEnd;
    final p = Paint()..strokeWidth = 1;
    final cols = w.floor();
    for (var x = 0; x < cols; x++) {
      final a = (first + x / w * span).floor();
      final b = math.max(a + 1, (first + (x + 1) / w * span).floor());
      if (a >= _length) break;
      final v = math.sqrt(peakIn(peaks, a, b)); // easier to see quiet parts
      final h = math.max(0.5, v * (mid - 2));
      final t = a / peaksPerSecond;
      final inside = ts == null || te == null || (t >= ts && t <= te);
      p.color = inside ? wave : dim;
      canvas.drawLine(Offset(x + 0.5, mid - h), Offset(x + 0.5, mid + h), p);
    }
    // Shade outside the trim.
    if (ts != null && te != null && !live) {
      final shade = Paint()..color = background.withValues(alpha: 0.55);
      canvas.drawRect(Rect.fromLTRB(0, 0, xOf(ts), size.height), shade);
      canvas.drawRect(Rect.fromLTRB(xOf(te), 0, w, size.height), shade);
      final hp = Paint()
        ..color = handle
        ..strokeWidth = 3;
      for (final x in [xOf(ts), xOf(te)]) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), hp);
        canvas.drawCircle(Offset(x, size.height - 12), 9, hp);
      }
    }
    final mp = Paint()
      ..color = marker
      ..strokeWidth = 2;
    for (final m in markers) {
      final x = xOf(m);
      if (x < 0 || x > w) continue;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), mp);
      canvas.drawPath(
        Path()
          ..moveTo(x, 0)
          ..lineTo(x + 10, 6)
          ..lineTo(x, 12)
          ..close(),
        mp,
      );
    }
    final pos = position;
    if (pos != null) {
      final x = xOf(pos);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = head
          ..strokeWidth = 2,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old._length != _length ||
      !identical(old.peaks, peaks) ||
      old.trimStart != trimStart ||
      old.trimEnd != trimEnd ||
      old.position != position ||
      old.markers.length != markers.length ||
      old.wave != wave;
}

/// Horizontal input meter (peak, in dBFS) with a clip light.
class LevelMeter extends StatelessWidget {
  const LevelMeter({super.key, required this.level, this.clipped = false});

  /// 0..1 linear peak.
  final double level;
  final bool clipped;

  static double toDb(double level) =>
      level <= 0 ? -60 : (20 * math.log(level) / math.ln10).clamp(-60, 0);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final db = toDb(level);
    final frac = (db + 60) / 60;
    final color = db > -3
        ? scheme.error
        : db > -12
        ? Colors.amber.shade600
        : Colors.green.shade500;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 14,
              child: Stack(
                children: [
                  Container(color: scheme.surfaceContainerHighest),
                  FractionallySizedBox(
                    widthFactor: frac,
                    child: Container(color: color),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 64,
          child: Text(
            level <= 0 ? '-∞ dB' : '${db.toStringAsFixed(0)} dB',
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: 'Clipping (too loud)',
          child: Icon(
            Icons.circle,
            size: 12,
            color: clipped ? scheme.error : scheme.outlineVariant,
          ),
        ),
      ],
    );
  }
}

/// PNG picture of a waveform (for Asset Locker thumbnails).
Future<Uint8List> waveformPng(
  Float32List peaks, {
  int width = 256,
  int height = 128,
  Color color = const Color(0xFF4F8CFF),
  Color background = const Color(0xFF1B1F27),
}) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = background,
  );
  final p = Paint()
    ..color = color
    ..strokeWidth = 1;
  final mid = height / 2;
  for (var x = 0; x < width; x++) {
    final a = (x / width * peaks.length).floor();
    final b = math.max(a + 1, ((x + 1) / width * peaks.length).floor());
    final h = math.max(0.5, math.sqrt(peakIn(peaks, a, b)) * (mid - 4));
    canvas.drawLine(Offset(x + 0.5, mid - h), Offset(x + 0.5, mid + h), p);
  }
  final img = await rec.endRecording().toImage(width, height);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return data!.buffer.asUint8List();
}

/// "1:05.3"
String formatSeconds(double s, {bool tenths = true}) {
  final total = s.isFinite ? math.max(0.0, s) : 0.0;
  final m = total ~/ 60;
  final sec = total - m * 60;
  final secText = tenths
      ? sec.toStringAsFixed(1).padLeft(4, '0')
      : sec.floor().toString().padLeft(2, '0');
  return '$m:$secText';
}
