import 'dart:math' as math;
import 'dart:typed_data';

import 'package:chip_synth/chip_synth.dart';
import 'package:test/test.dart';

/// Magnitude of harmonic [h] in a cycle.
double harmonic(Float32List c, int h) {
  final re = Float64List(c.length), im = Float64List(c.length);
  for (var i = 0; i < c.length; i++) {
    re[i] = c[i];
  }
  fft(re, im);
  return math.sqrt(re[h] * re[h] + im[h] * im[h]) / (c.length / 2);
}

void main() {
  test('fft round trip', () {
    final re = Float64List.fromList(
      List.generate(64, (i) => math.sin(i * 0.3) + i % 5),
    );
    final im = Float64List(64);
    final orig = Float64List.fromList(re);
    fft(re, im);
    fft(re, im, inverse: true);
    for (var i = 0; i < 64; i++) {
      expect(re[i], closeTo(orig[i], 1e-9));
    }
  });

  test('prepareCycle resamples, removes DC, normalizes', () {
    final c = prepareCycle([0.5, 0.5, 0.25, 0.25]);
    expect(c.length, tableSize);
    expect(c.reduce((a, b) => a + b) / tableSize, closeTo(0, 1e-6));
    expect(c.map((v) => v.abs()).reduce(math.max), closeTo(1, 1e-6));
    expect(prepareCycle([0, 0, 0]).every((v) => v == 0), isTrue);
  });

  test('high notes use band-limited cycles (no aliasing harmonics)', () {
    final saw = List.generate(256, (i) => i / 128 - 1.0);
    final t = Wavetable.fromCycles([saw]);
    // At 4 kHz / 48 kHz only harmonics up to 6 fit below Nyquist.
    const inc = 4000 / 48000;
    final level = Wavetable.levelFor(inc);
    final cycle = Float32List.fromList(
      List.generate(tableSize, (i) => t.sample(i / tableSize, 0, inc)),
    );
    expect(harmonic(cycle, 1), greaterThan(0.3));
    expect(harmonic(cycle, 12), lessThan(1e-3), reason: 'level $level');
    // Low notes keep the bright harmonics.
    final low = t.cycleAt(0);
    expect(harmonic(low, 40), greaterThan(0.005));
  });

  test('morph blends neighbouring cycles', () {
    final sine = List.generate(256, (i) => math.sin(2 * math.pi * i / 256));
    final t = Wavetable.fromCycles([
      sine,
      [for (final v in sine) -v],
    ]);
    expect(t.sample(0.25, 0, 0.001), closeTo(1, 1e-3));
    expect(t.sample(0.25, 1, 0.001), closeTo(-1, 1e-3));
    expect(t.sample(0.25, 0.5, 0.001), closeTo(0, 1e-3));
  });

  test('PolySynth plays a wavetable on the analog engine', () {
    final synth = PolySynth(48000)
      ..configure(
        const PolySpec(
          osc2Mix: 0,
          sub: 0,
          delayMix: 0,
          reverbMix: 0,
          cutoff: 1,
        ),
      )
      ..wavetable = Wavetable.fromCycles([
        List.generate(64, (i) => i < 32 ? 1.0 : -1.0),
      ]);
    synth.setTouch(0, const Touch(down: true, hz: 220, y: 1));
    final out = Float32List(4800 * 2);
    synth.render(out, 4800);
    final peak = out.map((v) => v.abs()).reduce(math.max);
    expect(peak, greaterThan(0.05));
    expect(peak, lessThanOrEqualTo(1));
  });
}
