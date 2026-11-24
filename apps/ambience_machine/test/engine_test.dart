import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ambience_machine/src/engine.dart';
import 'package:ambience_machine/src/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fx_kit/fx_kit.dart';

Float32List render(AmbienceEngine e, int frames, [List<Object?>? events]) {
  final out = Float32List(frames * 2);
  const block = 192;
  final tmp = Float32List(block * 2);
  for (var at = 0; at < frames; at += block) {
    final n = math.min(block, frames - at);
    e.render(tmp, n, events?.add);
    out.setRange(at * 2, (at + n) * 2, tmp);
  }
  return out;
}

double rms(Float32List b, [int from = 0, int? to]) {
  final end = to ?? b.length ~/ 2;
  var s = 0.0;
  for (var i = from * 2; i < end * 2; i++) {
    s += b[i] * b[i];
  }
  return math.sqrt(s / math.max(1, (end - from) * 2));
}

void main() {
  test('drift wanders smoothly within -1..1', () {
    final d = Drift(3);
    var prev = d.value;
    var maxStep = 0.0;
    for (var i = 0; i < 5000; i++) {
      d.advance(0.01, 2);
      expect(d.value.abs(), lessThanOrEqualTo(1));
      maxStep = math.max(maxStep, (d.value - prev).abs());
      prev = d.value;
    }
    expect(maxStep, lessThan(0.05));
  });

  test('sample loops have no jump at the seam', () {
    // A sine whose period does not divide the length: a plain loop would click.
    final data = Float32List.fromList(
      List.generate(48000, (i) => math.sin(i / 37.3)),
    );
    final loop = SampleLoop(data, 0);
    final len = loop.loopLength;
    final seam = (loop.valueAt(len - 1.0) - loop.valueAt(0)).abs();
    expect(seam, lessThan(0.06));
    // Plain looping would jump by much more here.
    expect((data[len - 1] - data[0]).abs(), greaterThan(0.06));
  });

  test('note clouds play about as many notes as asked', () {
    final layer = LayerSpec(
      kind: LayerKind.synth,
      density: 30,
      noteLength: 0.5,
    );
    final cloud = NoteCloud(layer, 1);
    final out = Float32List(64 * 2);
    var sounding = false;
    for (var i = 0; i < 60 * ambRate ~/ 64; i++) {
      out.fillRange(0, 128, 0);
      cloud.render(out, 64, 1);
      sounding = sounding || out.any((v) => v != 0);
    }
    final onsets = cloud.notesStarted;
    expect(sounding, isTrue);
    expect(onsets, inInclusiveRange(15, 45));
  });

  test('every noise texture makes sound and stays in range', () {
    for (final t in NoiseType.values) {
      final n = NoiseTexture(t, 5);
      final out = Float32List(ambRate * 2);
      for (var at = 0; at < ambRate; at += 64) {
        final view = Float32List.sublistView(out, at * 2, (at + 64) * 2);
        n.render(view, 64, 1);
      }
      expect(rms(out), greaterThan(0.01), reason: t.name);
      expect(
        out.every((v) => v.isFinite && v.abs() < 3),
        isTrue,
        reason: t.name,
      );
    }
  });

  group('engine', () {
    SceneSpec scene({int? id, List<LayerSpec>? layers}) => SceneSpec(
      id: id,
      layers:
          layers ??
          [
            LayerSpec(
              kind: LayerKind.noise,
              noise: NoiseType.rumble,
              volume: 1,
              drift: 0,
            ),
          ],
      fx: [
        EffectSpec(EffectKind.reverb, values: {'mix': 0.1}),
      ],
    );

    test('silent until played, then fades in; stop fades out', () {
      final e = AmbienceEngine()..handle(SetScene(scene()));
      expect(rms(render(e, 4800)), 0);
      e.handle(const SetPlaying(true, fade: 1));
      final out = render(e, ambRate * 2);
      expect(rms(out, 0, 2400), lessThan(rms(out, ambRate, ambRate * 2)));
      e.handle(const SetPlaying(false, fade: 0.5));
      render(e, ambRate);
      expect(rms(render(e, 4800)), 0);
    });

    test('a new scene crossfades; editing keeps layers running', () {
      final e = AmbienceEngine()
        ..handle(SetScene(scene(id: 1)))
        ..handle(const SetPlaying(true, fade: 0));
      render(e, ambRate);
      final events = <Object?>[];
      e.handle(
        SetScene(
          scene(
            id: 2,
            layers: [
              LayerSpec(id: 99, kind: LayerKind.noise, noise: NoiseType.rain),
            ],
          ),
          fade: 1,
        ),
      );
      render(e, ambRate * 2, events);
      final last = events.whereType<LevelsEvent>().last;
      expect(last.levels.keys, [99]);

      // Edit in place: same id, louder; the layer object keeps going.
      final s2 = scene(
        id: 2,
        layers: [
          LayerSpec(
            id: 99,
            kind: LayerKind.noise,
            noise: NoiseType.rain,
            volume: 1,
          ),
        ],
      );
      e.handle(SetScene(s2));
      events.clear();
      render(e, ambRate, events);
      expect(events.whereType<LevelsEvent>().last.levels[99], greaterThan(0));
    });

    test('removed layers fade out instead of cutting off', () {
      final a = LayerSpec(
        id: 10,
        kind: LayerKind.noise,
        noise: NoiseType.rumble,
        volume: 1,
        drift: 0,
      );
      final e = AmbienceEngine()
        ..handle(SetScene(SceneSpec(id: 5, layers: [a])))
        ..handle(const SetPlaying(true, fade: 0));
      render(e, ambRate * 2);
      e.handle(SetScene(SceneSpec(id: 5, layers: const [])));
      final out = render(e, ambRate * 3);
      expect(
        rms(out, 0, 480),
        greaterThan(0.001),
        reason: 'still audible at first',
      );
      expect(rms(out, ambRate * 2, ambRate * 3), lessThan(1e-4));
    });

    test('sample layers wait for their sample, then loop it', () {
      final e = AmbienceEngine()
        ..handle(
          SetScene(
            SceneSpec(
              layers: [
                LayerSpec(
                  kind: LayerKind.sample,
                  sampleKey: 'creek',
                  volume: 1,
                  drift: 0,
                ),
              ],
            ),
          ),
        )
        ..handle(const SetPlaying(true, fade: 0));
      expect(rms(render(e, 4800)), 0);
      e.handle(
        SetSample(
          'creek',
          Float32List.fromList(
            List.generate(24000, (i) => math.sin(i / 9) * 0.5),
          ),
        ),
      );
      final out = render(e, ambRate * 3);
      expect(
        rms(out, ambRate * 2, ambRate * 3),
        greaterThan(0.05),
        reason: 'still playing after the sample ends',
      );
    });

    test('sleep timer fades out and stops', () {
      final events = <Object?>[];
      final e = AmbienceEngine()
        ..handle(SetScene(scene()))
        ..handle(const SetPlaying(true, fade: 0))
        ..handle(const SetSleep(2));
      render(e, ambRate * 3, events);
      expect(events.whereType<StoppedEvent>(), hasLength(1));
      expect(e.playing, isFalse);
      expect(rms(render(e, 4800)), 0);
      expect(
        events.whereType<LevelsEvent>().first.sleepLeft,
        closeTo(1.9, 0.1),
      );
    });
  });

  test('render to PCM has the right length and fades at both ends', () {
    final pcm = renderAmbience(
      SceneSpec(
        layers: [
          LayerSpec(kind: LayerKind.noise, noise: NoiseType.waves, volume: 1),
        ],
      ),
      const {},
      8,
    );
    expect(pcm.length, 8 * ambRate * 2);
    expect(pcm[0], 0);
    expect(pcm.last.abs(), lessThan(200));
  });

  test('scene JSON round trip', () {
    final s = SceneSpec(
      name: 'Night creek',
      layers: [
        LayerSpec(
          kind: LayerKind.sample,
          sampleKey: 'creek-1',
          sampleType: 'recording',
          pitch: -2,
          name: 'Creek',
        ),
        LayerSpec(
          kind: LayerKind.synth,
          sound: const {'kind': 'sound', 'name': 'Glass', 'source': 'analog'},
          scale: ScaleKind.dorian,
          density: 4,
        ),
        LayerSpec(
          kind: LayerKind.noise,
          noise: NoiseType.wind,
          muted: true,
          drift: 0.9,
        ),
      ],
      fx: [EffectSpec(EffectKind.echo)],
    );
    final back = SceneSpec.fromJson(s.toJson());
    expect(back.name, 'Night creek');
    expect(back.layers.map((l) => l.kind), [
      LayerKind.sample,
      LayerKind.synth,
      LayerKind.noise,
    ]);
    expect(back.layers[0].sampleKey, 'creek-1');
    expect(back.layers[0].pitch, -2);
    expect(back.layers[1].scale, ScaleKind.dorian);
    expect(back.layers[1].sound['name'], 'Glass');
    expect(back.layers[2].muted, isTrue);
    expect(back.fx.single.kind, EffectKind.echo);
    expect(() => SceneSpec.fromJson({'kind': 'sound'}), throwsFormatException);
  });

  test('speed: 8 busy layers run well faster than real time', () {
    final layers = [
      for (final t in NoiseType.values)
        LayerSpec(kind: LayerKind.noise, noise: t),
      LayerSpec(kind: LayerKind.synth, density: 60, noteLength: 4),
      LayerSpec(kind: LayerKind.synth, density: 60, noteLength: 4),
      LayerSpec(kind: LayerKind.sample, sampleKey: 's'),
      LayerSpec(kind: LayerKind.sample, sampleKey: 's'),
    ];
    final e = AmbienceEngine()
      ..handle(SetSample('s', Float32List(ambRate * 4)))
      ..handle(
        SetScene(
          SceneSpec(
            layers: layers,
            fx: [EffectSpec(EffectKind.reverb), EffectSpec(EffectKind.echo)],
          ),
        ),
      )
      ..handle(const SetPlaying(true, fade: 0));
    final sw = Stopwatch()..start();
    render(e, ambRate * 10);
    final speed = 10 / (sw.elapsedMilliseconds / 1000);
    // ignore: avoid_print
    print('Ambience: ${speed.toStringAsFixed(1)}x real time');
    expect(speed, greaterThan(3));
  });
}
