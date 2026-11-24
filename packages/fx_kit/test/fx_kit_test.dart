import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fx_kit/fx_kit.dart';
import 'package:test/test.dart';

const sr = 48000.0;

Float32List sine(double hz, int frames, {double amp = 0.5}) {
  final b = Float32List(frames * 2);
  for (var i = 0; i < frames; i++) {
    final v = amp * math.sin(2 * math.pi * hz * i / sr);
    b[i * 2] = v;
    b[i * 2 + 1] = v;
  }
  return b;
}

double rms(Float32List b, [int from = 0]) {
  var s = 0.0;
  for (var i = from * 2; i < b.length; i++) {
    s += b[i] * b[i];
  }
  return math.sqrt(s / (b.length - from * 2));
}

Float32List run(EffectSpec s, Float32List input) {
  final e = Effect.create(s, sr);
  final buf = Float32List.fromList(input);
  // Process in blocks like the real feeder does.
  final frames = buf.length ~/ 2;
  for (var at = 0; at < frames; at += 192) {
    final n = math.min(192, frames - at);
    final view = Float32List.sublistView(buf, at * 2, (at + n) * 2);
    e.process(view, n);
  }
  return buf;
}

void main() {
  test(
    'every effect: silence stays silent, noise stays finite and bounded',
    () {
      final rnd = math.Random(1);
      final noise = Float32List.fromList(
        List.generate(48000 * 2, (_) => rnd.nextDouble() * 2 - 1),
      );
      for (final k in EffectKind.values) {
        final silent = run(EffectSpec(k), Float32List(9600));
        expect(
          silent.every((v) => v.abs() < 1e-6),
          isTrue,
          reason: '${k.name} silence',
        );
        final out = run(EffectSpec(k), noise);
        expect(
          out.every((v) => v.isFinite && v.abs() < 8),
          isTrue,
          reason: '${k.name} noise',
        );
      }
    },
  );

  test('filter: low-pass cuts highs, high-pass cuts lows', () {
    final lp = EffectSpec(
      EffectKind.filter,
      values: {'cutoff': 500, 'resonance': 0},
    );
    expect(rms(run(lp, sine(8000, 9600)), 4800), lessThan(0.01));
    expect(
      rms(run(lp, sine(100, 9600)), 4800),
      closeTo(0.5 / math.sqrt2, 0.03),
    );
    final hp = EffectSpec(
      EffectKind.filter,
      values: {'mode': 1, 'cutoff': 2000, 'resonance': 0},
    );
    expect(rms(run(hp, sine(60, 9600)), 4800), lessThan(0.01));
  });

  test('EQ boosts the mid band by about the set amount', () {
    final eq = EffectSpec(EffectKind.eq, values: {'mid': 12, 'midFreq': 1000});
    final out = rms(run(eq, sine(1000, 9600)), 4800);
    expect(gainToDb(out / (0.5 / math.sqrt2)), closeTo(12, 1));
  });

  test('bitcrush quantizes to the bit depth', () {
    final b = run(
      EffectSpec(EffectKind.bitcrush, values: {'bits': 2, 'downsample': 1}),
      sine(100, 480),
    );
    final levels = {for (final v in b) (v * 2).round() / 2};
    expect(levels.length, lessThanOrEqualTo(5));
  });

  test('echo repeats after the set time', () {
    final input = Float32List(48000 * 2);
    input[0] = 1;
    input[1] = 1;
    final out = run(
      EffectSpec(
        EffectKind.echo,
        values: {
          'time': 100,
          'feedback': 0,
          'mix': 1,
          'pingpong': 0,
          'damp': 0,
        },
      ),
      input,
    );
    var peakAt = 0;
    var peak = 0.0;
    for (var i = 100; i < 48000; i++) {
      if (out[i * 2].abs() > peak) {
        peak = out[i * 2].abs();
        peakAt = i;
      }
    }
    expect(peakAt, closeTo(4800, 2));
    expect(peak, greaterThan(0.4));
  });

  test('reverb has a tail that dies away', () {
    final input = Float32List(48000 * 4 * 2);
    for (var i = 0; i < 480; i++) {
      input[i * 2] = input[i * 2 + 1] = 0.5;
    }
    final out = run(
      EffectSpec(EffectKind.reverb, values: {'mix': 1, 'size': 0.5}),
      input,
    );
    expect(rms(Float32List.sublistView(out, 9600, 48000)), greaterThan(1e-3));
    expect(
      rms(Float32List.sublistView(out, 48000 * 7, 48000 * 8)),
      lessThan(1e-3),
    );
  });

  test('compressor turns loud signals down; ring mod makes a carrier', () {
    final c = EffectSpec(
      EffectKind.compressor,
      values: {'threshold': -30, 'ratio': 10, 'makeup': 0, 'attack': 1},
    );
    expect(rms(run(c, sine(200, 9600, amp: 0.9)), 4800), lessThan(0.15));
    final dc = Float32List(9600)..fillRange(0, 9600, 0.5);
    final ring = run(
      EffectSpec(EffectKind.ringmod, values: {'freq': 1000, 'mix': 1}),
      dc,
    );
    expect(ring.map((v) => v.abs()).reduce(math.max), closeTo(0.5, 0.01));
    expect(rms(ring), closeTo(0.5 / math.sqrt2, 0.02));
  });

  test('chain keeps running effects when knobs or order change', () {
    final chain = FxChain(sr);
    final a = EffectSpec(EffectKind.echo);
    final b = EffectSpec(EffectKind.drive);
    chain.configure([a, b]);
    final echo = chain.effect(a.id);
    chain.configure([b, a.withValue('mix', 0.9)]);
    expect(identical(chain.effect(a.id), echo), isTrue);
    expect(chain.specs.first.kind, EffectKind.drive);
    chain.configure([b.withOn(false)]);
    expect(chain.effect(a.id), isNull);
    final buf = sine(440, 192);
    final before = Float32List.fromList(buf);
    chain.process(buf, 192);
    expect(buf, before, reason: 'switched-off effects are skipped');
  });

  test('params: log knobs, snapping, formatting', () {
    final cutoff = EffectKind.filter.param('cutoff');
    expect(cutoff.fromKnob(0), 20);
    expect(cutoff.fromKnob(1), 20000);
    expect(cutoff.toKnob(cutoff.fromKnob(0.37)), closeTo(0.37, 1e-9));
    expect(cutoff.format(2500), '2.5 kHz');
    final bits = EffectKind.bitcrush.param('bits');
    expect(bits.clamp(5.4), 5);
    expect(EffectKind.filter.param('mode').format(1), 'High-pass');
    expect(EffectSpec(EffectKind.chorus, values: {'mix': 9})['mix'], 1);
  });

  test('sound preset JSON round trip, unknown effects skipped', () {
    final p = SoundPreset(
      name: 'Wobble',
      source: SourceKind.wavetable,
      synth: const {'release': 0.5},
      waves: const [
        [0, 1, 0, -1],
      ],
      fx: [
        EffectSpec(EffectKind.phaser, values: {'rate': 2}),
        EffectSpec(EffectKind.reverb, on: false),
      ],
    );
    final json = p.toJson();
    (json['fx'] as List).add({'kind': 'future_effect'});
    final back = SoundPreset.fromJson(json);
    expect(back.name, 'Wobble');
    expect(back.source, SourceKind.wavetable);
    expect(back.waves.single, [0, 1, 0, -1]);
    expect(back.fx, hasLength(2));
    expect(back.fx.first['rate'], 2);
    expect(back.fx.last.on, isFalse);
    expect(
      () => SoundPreset.fromJson({'kind': 'wavetable'}),
      throwsFormatException,
    );
  });
}
