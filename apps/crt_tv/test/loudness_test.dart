import 'dart:math';
import 'dart:typed_data';

import 'package:crt_tv/src/loudness.dart';
import 'package:flutter_test/flutter_test.dart';

const rate = 22050;

/// A steady tone at [amplitude] (0..1) for [seconds].
List<int> tone(double amplitude, double seconds) => [
      for (var i = 0; i < (rate * seconds).round(); i++) (sin(i * 2 * pi * 440 / rate) * amplitude * 32767).round(),
    ];

void main() {
  test('a steady tone measures at its real level and peak', () {
    final l = analyseLoudness(Int16List.fromList(tone(0.5, 4)), rate)!;
    // A sine wave's average level is 3 dB under its peak.
    expect(l.peak, closeTo(-6.0, 0.1));
    expect(l.level, closeTo(-9.0, 0.2));
  });

  test('silence between the loud parts does not drag the level down', () {
    final talky = Int16List.fromList([...tone(0.5, 2), ...List.filled(rate * 6, 0), ...tone(0.5, 2)]);
    final solid = Int16List.fromList(tone(0.5, 4));
    expect(analyseLoudness(talky, rate)!.level, closeTo(analyseLoudness(solid, rate)!.level, 0.3));
  });

  test('pure silence has no level', () {
    expect(analyseLoudness(Int16List(rate * 3), rate), isNull);
    expect(analyseLoudness(Int16List(0), rate), isNull);
  });

  test('loud videos are turned down and quiet ones up, to the same level', () {
    const loud = Loudness(-14, -6);
    const quiet = Loudness(-30, -12);
    expect(loud.level + levelingGain(loud), closeTo(kTargetLevel, 0.01));
    expect(quiet.level + levelingGain(quiet), closeTo(kTargetLevel, 0.01));
  });

  test('a quiet video with loud peaks is only turned up as far as is clean', () {
    const dynamic = Loudness(-32, -2);
    final gain = levelingGain(dynamic);
    expect(gain, closeTo(1.0, 0.01), reason: 'peak plus gain stays 1 dB under full scale');
    expect(dynamic.peak + gain, lessThan(0));
  });

  test('odd measurements cannot move the volume wildly', () {
    expect(levelingGain(const Loudness(-70, -60)), 12);
    expect(levelingGain(const Loudness(0, 0)), -18);
  });

  test('measurements survive saving and loading', () {
    final back = Loudness.fromJson(const Loudness(-21.5, -3.25).toJson())!;
    expect(back.level, -21.5);
    expect(back.peak, -3.25);
    expect(Loudness.fromJson('nonsense'), isNull);
  });
}
