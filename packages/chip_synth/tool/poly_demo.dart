// Renders a short demo of the touch-synth presets: dart run tool/poly_demo.dart out.wav
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:chip_synth/chip_synth.dart';

double hz(double midi) => 440.0 * math.pow(2, (midi - 69) / 12);

void main(List<String> args) {
  const sr = 48000;
  final chunks = <Float32List>[];
  void phrase(PolySpec spec, List<List<double>> chords, {double slide = 0}) {
    final p = PolySynth(sr.toDouble())..configure(spec);
    for (final chord in chords) {
      const steps = 60; // 1.2 s per chord, finger slides a little
      for (var s = 0; s < steps; s++) {
        final t = s / steps;
        for (var i = 0; i < chord.length; i++) {
          p.setTouch(
            i,
            Touch(
              down: s < steps - 8,
              hz: hz(chord[i] + slide * t),
              y: 0.25 + 0.6 * t,
            ),
          );
        }
        final out = Float32List(sr ~/ 50 * 2);
        p.render(out, sr ~/ 50);
        chunks.add(out);
      }
    }
    for (var i = 0; i < 6; i++) {
      p.setTouch(i, const Touch());
    }
    final tail = Float32List(sr * 2);
    p.render(tail, sr);
    chunks.add(tail);
  }

  phrase(polyPresets['Fat Pad']!, [
    [57, 60, 64],
    [53, 57, 60],
    [55, 59, 62],
  ]);
  phrase(polyPresets['Lead']!, [
    [69],
    [72],
    [74],
  ], slide: 2);
  phrase(polyPresets['Acid Bass']!, [
    [33],
    [36],
    [31],
  ], slide: 3);
  phrase(polyPresets['Glass Bell']!, [
    [72, 76, 79],
    [74, 77, 81],
  ]);
  phrase(polyPresets['Chip Lead']!, [
    [69, 76],
    [72, 79],
  ], slide: 1);
  final total = chunks.fold(0, (a, c) => a + c.length);
  final all = Float32List(total);
  var o = 0;
  for (final c in chunks) {
    all.setAll(o, c);
    o += c.length;
  }
  File(args.isEmpty ? 'poly_demo.wav' : args.first)
      .writeAsBytesSync(encodeWav16(all, sr));
  stdout.writeln('${total / 2 / sr} s');
}
