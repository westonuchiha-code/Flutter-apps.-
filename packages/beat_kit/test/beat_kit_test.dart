import 'dart:typed_data';

import 'package:beat_kit/beat_kit.dart';
import 'package:test/test.dart';

Float32List ones(int n) => Float32List(n)..fillRange(0, n, 0.5);

BeatEngine engine() => BeatEngine(sampleRate: 1600)
  ..handle(const SetTempo(120, 0))
  ..handle(const SetMaster(1));

Float32List render(
  BeatEngine e,
  int frames, {
  int chunk = 0,
  List<Object?>? events,
}) {
  final out = Float32List(frames * 2);
  if (chunk <= 0) {
    e.render(out, frames, events?.add);
    return out;
  }
  final tmp = Float32List(chunk * 2);
  for (var at = 0; at < frames; at += chunk) {
    final n = (frames - at).clamp(0, chunk);
    e.render(tmp, n, events?.add);
    out.setRange(at * 2, (at + n) * 2, tmp);
  }
  return out;
}

int firstSound(Float32List out) {
  for (var i = 0; i < out.length; i += 2) {
    if (out[i] != 0) return i ~/ 2;
  }
  return -1;
}

void main() {
  group('Transport', () {
    test('straight and swung step starts', () {
      const t = Transport(bpm: 120, sampleRate: 48000);
      expect(t.baseStep, 6000);
      expect(t.stepStart(1), 6000);
      expect(t.barFrames, 96000);
      const s = Transport(bpm: 120, swing: 0.25, sampleRate: 48000);
      expect(s.stepStart(1), 7500);
      expect(s.stepStart(2), 12000);
      expect(s.stepLength(1), 4500);
      expect(s.stepStart(16), s.barFrames);
    });
  });

  group('BeatEngine', () {
    test('steps trigger on the exact frame, regardless of block size', () {
      // 120 bpm at 1600 Hz: a step is 200 frames.
      List<Float32List> run(int chunk) {
        final e = engine()
          ..handle(SetSample(0, ones(100)))
          ..handle(SetPattern([1 << 3, ...List.filled(15, 0)], 16))
          ..handle(const SetPlaying(true));
        return [render(e, 1000, chunk: chunk)];
      }

      final whole = run(0).single;
      expect(firstSound(whole), 600);
      for (final c in [1, 37, 64, 199]) {
        expect(run(c).single, whole, reason: 'chunk $c');
      }
    });

    test('emits step events with song frames, bars and pad activity', () {
      final events = <Object?>[];
      final e = engine()
        ..handle(SetSample(2, ones(50)))
        ..handle(SetPattern([0, 0, 1, ...List.filled(13, 0)], 16))
        ..handle(const SetPlaying(true));
      render(e, 3400, chunk: 128, events: events);
      final steps = events.whereType<StepEvent>().toList();
      expect(steps.first.frame, 0);
      expect(steps[3].frame, 600);
      expect(steps[16].isBarStart, isTrue);
      expect(steps[16].bar, 1);
      expect(steps[16].step, 0);
      expect(events.whereType<PadActivity>().first.active, 1 << 2);
    });

    test('pitch +12 plays twice as fast; reverse starts at the end', () {
      final ramp = Float32List.fromList(
        List.generate(400, (i) => i / 400 * 0.5),
      );
      int length(BeatEngine e) {
        final out = render(e, 1000);
        var last = 0;
        for (var i = 0; i < out.length; i += 2) {
          if (out[i] != 0) last = i ~/ 2;
        }
        return last;
      }

      final normal = engine()
        ..handle(SetSample(0, ramp))
        ..handle(const Trigger(0));
      final fast = engine()
        ..handle(SetSample(0, ramp))
        ..handle(const SetPad(0, PadSettings(pitch: 12, volume: 1)))
        ..handle(const Trigger(0));
      expect(length(normal), closeTo(398, 2));
      expect(length(fast), closeTo(199, 2));

      final rev = engine()
        ..handle(SetSample(0, ramp))
        ..handle(const SetPad(0, PadSettings(reverse: true, volume: 1)))
        ..handle(const Trigger(0));
      final out = render(rev, 200);
      expect(out[2 * 30], greaterThan(out[2 * 150])); // loud end first
    });

    test('trim plays only the chosen part', () {
      final e = engine()
        ..handle(SetSample(0, ones(1000)))
        ..handle(const SetPad(0, PadSettings(start: 0.5, end: 0.6)))
        ..handle(const Trigger(0));
      final out = render(e, 400);
      expect(out[2 * 50], greaterThan(0));
      expect(out[2 * 120], 0);
    });

    test('loop mode repeats until tapped again; hold stops on release', () {
      final loop = engine()
        ..handle(SetSample(0, ones(100)))
        ..handle(const SetPad(0, PadSettings(mode: PadMode.loop)))
        ..handle(const Trigger(0));
      expect(render(loop, 500)[2 * 450], greaterThan(0));
      loop.handle(const Trigger(0));
      render(loop, 200);
      expect(render(loop, 100).every((v) => v == 0), isTrue);

      final hold = engine()
        ..handle(SetSample(0, ones(1000)))
        ..handle(const SetPad(0, PadSettings(mode: PadMode.hold)))
        ..handle(const Trigger(0));
      expect(render(hold, 100)[2 * 90], greaterThan(0));
      hold.handle(const Release(0));
      render(hold, 200);
      expect(render(hold, 100).every((v) => v == 0), isTrue);
    });

    test('loop layers stay locked to the bar', () {
      // 1 bar = 3200 frames at 120 bpm / 1600 Hz.
      final layer = Float32List.fromList(
        List.generate(3200, (i) => (i % 100) / 1000),
      );
      final e = engine()
        ..handle(AddLayer(1, layer, 3))
        ..handle(const SetPlaying(true));
      final out = render(e, 3200 * 2 + 10, chunk: 77);
      const g = 0.7071;
      expect(out[2 * 150], closeTo(layer[150] * g, 1e-6));
      expect(out[2 * (3200 + 42)], closeTo(layer[42] * g, 1e-6));
      e.handle(const SetLayer(1, gain: 1, muted: true));
      expect(render(e, 100).every((v) => v == 0), isTrue);
      e.handle(const RemoveLayer(1));
    });

    test('limiter never exceeds full scale', () {
      final e = engine();
      for (var p = 0; p < 8; p++) {
        e
          ..handle(SetSample(p, Float32List(500)..fillRange(0, 500, 1)))
          ..handle(SetPad(p, const PadSettings(volume: 1)))
          ..handle(Trigger(p));
      }
      final out = render(e, 400);
      expect(out.every((v) => v.abs() <= 1.0), isTrue);
      expect(out[2 * 200], greaterThan(0.9));
    });
  });

  test('kit and pad settings round trip and validate', () {
    final kit = Kit(
      name: 'Dusty',
      bpm: 92,
      swing: 0.2,
      steps: 32,
      pads: [
        const KitPad(
          sampleId: 'kick-1',
          sampleType: 'sample',
          name: 'Kick',
          settings: PadSettings(pitch: -3, reverse: true, mode: PadMode.hold),
        ),
      ],
      masks: [0x1111],
    );
    final back = Kit.fromJson(kit.toJson());
    expect(back.name, 'Dusty');
    expect(back.pads, hasLength(padCount));
    expect(back.pads.first.settings, kit.pads.first.settings);
    expect(back.masks.first, 0x1111);
    expect(back.steps, 32);
    expect(() => Kit.fromJson({'kind': 'other'}), throwsFormatException);
    final bad = PadSettings.fromJson({'start': 0.9, 'end': 0.1, 'pitch': 99});
    expect(bad.start, 0);
    expect(bad.end, 1);
    expect(bad.pitch, 24);
  });
}
