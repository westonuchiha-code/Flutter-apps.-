import 'dart:math' as math;
import 'dart:typed_data';

import 'package:chip_synth/chip_synth.dart';
import 'package:test/test.dart';

double rms(Float32List x, [int from = 0, int? to]) {
  to ??= x.length;
  var s = 0.0;
  for (var i = from; i < to; i++) {
    s += x[i] * x[i];
  }
  return math.sqrt(s / (to - from));
}

Float32List play(PolySynth p, int frames) {
  final out = Float32List(frames * 2);
  p.render(out, frames);
  return out;
}

void main() {
  test('silent with no fingers, sound with one, chords add up', () {
    final p = PolySynth(48000)
      ..configure(const PolySpec(delayMix: 0, reverbMix: 0));
    expect(rms(play(p, 4800)), lessThan(1e-6));
    p.setTouch(0, const Touch(down: true, hz: 220, y: 0.7));
    final one = rms(play(p, 9600), 4800);
    expect(one, greaterThan(0.02));
    p.setTouch(1, const Touch(down: true, hz: 330, y: 0.7));
    p.setTouch(2, const Touch(down: true, hz: 440, y: 0.7));
    expect(p.activeVoices, 3);
    final chord = play(p, 9600);
    expect(chord.every((v) => v.isFinite && v.abs() <= 1), isTrue);
  });

  test('release fades the voice out and frees it', () {
    final p = PolySynth(48000)
      ..configure(const PolySpec(release: 0.1, delayMix: 0, reverbMix: 0));
    p.setTouch(0, const Touch(down: true, hz: 220));
    play(p, 4800);
    p.setTouch(0, const Touch(down: false, hz: 220));
    final tail = play(p, 48000);
    expect(rms(tail, 80000), lessThan(1e-3));
    expect(p.activeVoices, 0);
  });

  test('finger height opens the filter', () {
    double brightness(double y) {
      final p = PolySynth(48000)
        ..configure(const PolySpec(delayMix: 0, reverbMix: 0, cutoff: 0.2));
      p.setTouch(0, Touch(down: true, hz: 110, y: y));
      final out = play(p, 9600);
      // Energy of the sample-to-sample difference ~ high-frequency content.
      var d = 0.0;
      for (var i = 4800 * 2; i < out.length - 2; i += 2) {
        d += (out[i + 2] - out[i]) * (out[i + 2] - out[i]);
      }
      return d;
    }

    expect(brightness(0.9), greaterThan(brightness(0.1) * 2));
  });

  test('every chip sound works in the poly engine', () {
    for (final chip in chipCatalog) {
      for (final patch in chip.patches) {
        final p = PolySynth(48000)
          ..configure(
            PolySpec(
              engine: EngineKind.chip,
              chipId: chip.id,
              patchId: patch.id,
              delayMix: 0,
              reverbMix: 0,
            ),
          );
        p.setTouch(0, const Touch(down: true, hz: 262, y: 0.5));
        final out = play(p, 9600);
        expect(
          out.every((v) => v.isFinite),
          isTrue,
          reason: '${chip.id}/${patch.id}',
        );
        expect(
          rms(out, 4800),
          greaterThan(0.01),
          reason: '${chip.id}/${patch.id}',
        );
      }
    }
  });

  test('presets and JSON round trip', () {
    for (final s in polyPresets.values) {
      expect(PolySpec.fromJson(s.toJson()), s);
    }
    expect(PolySpec.fromJson(const {}), const PolySpec());
  });

  test('renders faster than real time (6 voices + effects)', () {
    final p = PolySynth(48000)..configure(polyPresets['Fat Pad']!);
    for (var i = 0; i < maxVoices; i++) {
      p.setTouch(i, Touch(down: true, hz: 110.0 * (i + 1), y: 0.5));
    }
    final sw = Stopwatch()..start();
    play(p, 48000);
    expect(sw.elapsedMilliseconds, lessThan(1000));
    // ignore: avoid_print
    print('1 s of 6-voice audio rendered in ${sw.elapsedMilliseconds} ms');
  });
}
