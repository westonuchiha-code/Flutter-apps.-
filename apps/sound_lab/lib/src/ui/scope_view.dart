import 'dart:math' as math;

import 'package:chip_synth/chip_synth.dart' show fft;
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../engine.dart';

/// Spectrum in [bands] log-spaced bands from 30 Hz to 16 kHz, in dB (-90..0).
Float32List spectrum(Float32List samples, {int bands = 48}) {
  final n = samples.length;
  final re = Float64List(n), im = Float64List(n);
  for (var i = 0; i < n; i++) {
    final w = 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1)); // Hann
    re[i] = samples[i] * w;
  }
  fft(re, im);
  final out = Float32List(bands);
  final binHz = labRate / n;
  for (var b = 0; b < bands; b++) {
    final lo = 30 * math.pow(16000 / 30, b / bands);
    final hi = 30 * math.pow(16000 / 30, (b + 1) / bands);
    var a = (lo / binHz).floor().clamp(1, n ~/ 2 - 1);
    final z = (hi / binHz).ceil().clamp(a + 1, n ~/ 2);
    var peak = 0.0;
    for (; a < z; a++) {
      final m = math.sqrt(re[a] * re[a] + im[a] * im[a]) / (n / 4);
      if (m > peak) peak = m;
    }
    out[b] = (20 * math.log(math.max(peak, 1e-6)) / math.ln10)
        .clamp(-90, 0)
        .toDouble();
  }
  return out;
}

/// Live waveform or spectrum of what's playing. Tap to switch.
class ScopeView extends StatefulWidget {
  const ScopeView({super.key, required this.scope});

  final ValueListenable<Float32List> scope;

  @override
  State<ScopeView> createState() => _ScopeViewState();
}

class _ScopeViewState extends State<ScopeView> {
  bool _spectrum = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: _spectrum
          ? 'Spectrum (tap for waveform)'
          : 'Waveform (tap for spectrum)',
      child: GestureDetector(
        onTap: () => setState(() => _spectrum = !_spectrum),
        child: ValueListenableBuilder(
          valueListenable: widget.scope,
          builder: (context, data, _) => CustomPaint(
            size: Size.infinite,
            painter: _ScopePainter(
              data: data,
              spectrum: _spectrum ? spectrum(data) : null,
              line: scheme.primary,
              grid: scheme.outlineVariant,
              background: scheme.surfaceContainer,
              label: scheme.outline,
            ),
          ),
        ),
      ),
    );
  }
}

class _ScopePainter extends CustomPainter {
  _ScopePainter({
    required this.data,
    required this.spectrum,
    required this.line,
    required this.grid,
    required this.background,
    required this.label,
  });

  final Float32List data;
  final Float32List? spectrum;
  final Color line, grid, background, label;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(10),
    );
    canvas.drawRRect(r, Paint()..color = background);
    canvas.save();
    canvas.clipRRect(r);
    final mid = size.height / 2;
    final sp = spectrum;
    if (sp == null) {
      canvas.drawLine(
        Offset(0, mid),
        Offset(size.width, mid),
        Paint()..color = grid,
      );
      // Start at a rising zero crossing so the wave stands still.
      var start = 0;
      for (var i = 1; i < data.length ~/ 2; i++) {
        if (data[i - 1] <= 0 && data[i] > 0) {
          start = i;
          break;
        }
      }
      final n = data.length - start;
      final path = Path();
      final count = math.min(n, data.length ~/ 2);
      for (var i = 0; i < count; i++) {
        final x = i / (count - 1) * size.width;
        final y = mid - data[start + i].clamp(-1.0, 1.0) * (mid - 4);
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    } else {
      final w = size.width / sp.length;
      final p = Paint()..color = line;
      for (var b = 0; b < sp.length; b++) {
        final h = (sp[b] + 90) / 90 * size.height;
        canvas.drawRect(Rect.fromLTWH(b * w + 1, size.height - h, w - 2, h), p);
      }
      final tp = TextPainter(
        text: TextSpan(
          text: '30 Hz – 16 kHz',
          style: TextStyle(color: label, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, const Offset(6, 4));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScopePainter old) => true;
}
