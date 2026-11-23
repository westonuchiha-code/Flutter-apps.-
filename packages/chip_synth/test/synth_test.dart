import 'dart:math' as math;
import 'dart:typed_data';

import 'package:chip_synth/chip_synth.dart';
import 'package:test/test.dart';

/// Renders [seconds] of [spec] at [hz] and returns the stereo samples.
Float32List render(
  SoundSpec spec, {
  double hz = 220,
  double level = 1,
  double timbre = 0.5,
  double seconds = 0.5,
}) {
  final e = SynthEngine(48000)..configure(spec);
  e.setControls(hz, level, timbre);
  final out = Float32List((48000 * seconds).toInt() * 2);
  e.render(out, out.length ~/ 2);
  return out;
}

double rms(Float32List x, {int skip = 0}) {
  var sum = 0.0;
  for (var i = skip; i < x.length; i++) {
    sum += x[i] * x[i];
  }
  return math.sqrt(sum / (x.length - skip));
}

/// Dominant period (in samples) of the left channel, by autocorrelation.
double periodOf(Float32List stereo, {int minLag = 20, int maxLag = 2000}) {
  final n = stereo.length ~/ 2;
  final x = Float64List(n);
  for (var i = 0; i < n; i++) {
    x[i] = stereo[i * 2];
  }
  final start = n ~/ 4;
  final corr = Float64List(maxLag);
  var best = 0.0;
  for (var lag = minLag; lag < maxLag; lag++) {
    var c = 0.0;
    for (var i = start; i < n - maxLag; i++) {
      c += x[i] * x[i + lag];
    }
    corr[lag] = c;
    if (c > best) best = c;
  }
  // The first strong peak is the period (later peaks are multiples of it).
  var bestLag = minLag;
  for (var lag = minLag + 1; lag < maxLag - 1; lag++) {
    if (corr[lag] >= 0.9 * best &&
        corr[lag] >= corr[lag - 1] &&
        corr[lag] >= corr[lag + 1]) {
      bestLag = lag;
      break;
    }
  }
  return bestLag.toDouble();
}

void main() {
  test('every chip sound renders at a sensible level without NaN', () {
    for (final chip in chipCatalog) {
      for (final patch in chip.patches) {
        final out = render(SoundSpec(chipId: chip.id, patchId: patch.id));
        expect(out.every((v) => v.isFinite), isTrue, reason: patch.id);
        final level = rms(out, skip: 9600);
        expect(
          level,
          inInclusiveRange(0.05, 0.6),
          reason: '${chip.id}/${patch.id} rms $level',
        );
        expect(out.every((v) => v.abs() <= 1), isTrue);
      }
    }
  });

  test('silence when the level is zero', () {
    for (final chip in chipCatalog) {
      final out = render(
        SoundSpec(chipId: chip.id, patchId: chip.patches.first.id),
        level: 0,
      );
      expect(rms(out, skip: 24000), lessThan(0.02), reason: chip.id);
    }
  });

  test('pitch registers quantize like the hardware', () {
    // Game Boy: 131072 / (2048 - x).
    expect(GbPulse.quantize(440), closeTo(131072 / (2048 - 1750), 1e-9));
    // SID: 16-bit register at the PAL clock is fine-grained.
    expect(SidVoice.quantize(440), closeTo(440, 0.06));
  });

  test('Game Boy pulse plays the expected pitch', () {
    final out = render(const SoundSpec(chipId: 'gb', patchId: 'pulse'));
    final expected = 48000 / GbPulse.quantize(220);
    expect(periodOf(out), closeTo(expected, 1.5));
  });

  test('bass sounds play an octave lower', () {
    final out = render(
      const SoundSpec(chipId: 'gb', patchId: 'wavebass'),
      hz: 440,
      timbre: 0,
    );
    expect(periodOf(out, maxLag: 400), closeTo(48000 / 220, 2));
  });

  test('Atari 2600 can only reach a few pitches', () {
    // A2 and a quarter-tone above land on the same divider.
    final a = render(
      const SoundSpec(chipId: 'tia', patchId: 'square'),
      hz: 440,
    );
    final b = render(
      const SoundSpec(chipId: 'tia', patchId: 'square'),
      hz: 440 * math.pow(2, 0.5 / 12).toDouble(),
    );
    expect(periodOf(a, maxLag: 300), periodOf(b, maxLag: 300));
  });

  test('speech chip sings only table pitches', () {
    for (final p in tmsPitchPeriods) {
      expect(p, inInclusiveRange(15, 159));
    }
    final out = render(
      const SoundSpec(chipId: 'speech', patchId: 'vowels'),
      hz: 8000 / 77.0, // between table entries 76 and 78
    );
    final period = periodOf(out, maxLag: 600);
    // 76 or 78 samples at 8 kHz = 456 or 468 samples at 48 kHz.
    expect(
      [456.0, 468.0].any((p) => (p - period).abs() < 3),
      isTrue,
      reason: 'period $period',
    );
  });

  test('arpeggio cycles through the chord', () {
    final plain = render(const SoundSpec(chipId: 'gb', patchId: 'pulse'));
    final arp = render(
      const SoundSpec(chipId: 'gb', patchId: 'pulse', arp: 'major'),
    );
    expect(arp, isNot(equals(plain)));
  });

  test('echo adds a tail after the sound stops', () {
    final e = SynthEngine(
      48000,
    )..configure(const SoundSpec(chipId: 'gb', patchId: 'pulse', echoMix: 0.6));
    final out = Float32List(48000 * 2);
    e.setControls(330, 1, 0.5);
    e.render(out, 12000);
    e.setControls(330, 0, 0.5);
    e.render(out, 36000, offset: 12000);
    // 300 ms echo: sound comes back after the note ended at 250 ms.
    final tail = Float32List.sublistView(out, 2 * 26000, 2 * 30000);
    expect(rms(tail), greaterThan(0.02));
  });

  test('bitcrush reduces the number of output levels', () {
    final out = render(
      const SoundSpec(chipId: 'sid', patchId: 'saw', crushBits: 2),
      seconds: 0.2,
    );
    final levels = out.map((v) => v.toStringAsFixed(3)).toSet();
    expect(levels.length, lessThan(12));
  });

  test('SoundSpec JSON round trip and equality', () {
    const spec = SoundSpec(
      chipId: 'fm',
      patchId: 'bell',
      vibratoCents: 20,
      arp: 'minor',
      echoMix: 0.3,
      crushBits: 4,
      master: 0.5,
    );
    final copy = SoundSpec.fromJson(spec.toJson());
    expect(copy, spec);
    expect(copy.hashCode, spec.hashCode);
    expect(SoundSpec.fromJson(const {}), const SoundSpec());
  });
}
