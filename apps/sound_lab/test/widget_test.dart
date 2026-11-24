import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:app_shell/app_shell.dart';
import 'package:chip_synth/chip_synth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fx_kit/fx_kit.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sound_lab/main.dart';
import 'package:sound_lab/src/controller.dart';
import 'package:sound_lab/src/engine.dart';
import 'package:sound_lab/src/library.dart';
import 'package:sound_lab/src/output.dart';
import 'package:sound_lab/src/ui/home.dart';

class FakeOutput implements LabOutput {
  LabUpdate? last;
  final messages = <Object>[];
  final _scope = StreamController<Float32List>.broadcast(sync: true);

  @override
  Future<void> init() async {}
  @override
  void update(LabUpdate u) => last = u;
  @override
  void send(Object message) => messages.add(message);
  @override
  Stream<Float32List> get scope => _scope.stream;
  void emitScope(Float32List s) => _scope.add(s);
  @override
  Future<void> dispose() async {}
}

double peak(Float32List b) => b.map((v) => v.abs()).reduce(math.max);

LabSnapshot snap({
  PolySpec spec = labDefaultSpec,
  List<EffectSpec> fx = const [],
  Wavetable? table,
  Float32List? sample,
  bool useSample = false,
}) => LabSnapshot(
  spec: spec,
  fx: fx,
  table: table,
  sample: sample,
  sampleRoot: 60,
  useSample: useSample,
);

void main() {
  group('engine', () {
    test('analog, chip and wave sources all sound and stay in range', () {
      for (final s in [
        snap(),
        snap(
          spec: labDefaultSpec.copyWith(
            engine: EngineKind.chip,
            chipId: 'sid',
            patchId: 'saw',
          ),
        ),
        snap(
          table: Wavetable.fromCycles([
            List.generate(64, (i) => i < 32 ? 1.0 : -1.0),
          ]),
        ),
      ]) {
        final out = renderNote(s, 60, hold: 0.5, tail: 0.2);
        expect(out.length, (0.7 * labRate).round() * 2);
        expect(peak(out), greaterThan(0.05));
        expect(peak(out), lessThanOrEqualTo(1));
      }
    });

    test('a sample plays at its own pitch on its root note, an octave up twice as fast', () {
      final data = Float32List.fromList(
        List.generate(4800, (i) => math.sin(i / 7) * 0.5),
      );
      int lastSound(Float32List b) {
        var last = 0;
        for (var i = 0; i < b.length; i += 2) {
          if (b[i].abs() > 1e-4) last = i ~/ 2;
        }
        return last;
      }

      final root = renderNote(
        snap(sample: data, useSample: true),
        60,
        hold: 0.5,
        tail: 0,
      );
      final up = renderNote(
        snap(sample: data, useSample: true),
        72,
        hold: 0.5,
        tail: 0,
      );
      expect(lastSound(root), closeTo(4799, 3));
      expect(lastSound(up), closeTo(2399, 3));
    });

    test('effect order matters and processing adds the tail', () {
      final data = Float32List.fromList(
        List.generate(4800, (i) => math.sin(i / 5) * 0.4),
      );
      final a = processSample(
        snap(
          sample: data,
          fx: [
            EffectSpec(EffectKind.bitcrush, values: {'bits': 3}),
            EffectSpec(EffectKind.echo, values: {'mix': 0.8, 'time': 50}),
          ],
        ),
        tail: 0.5,
      );
      final b = processSample(
        snap(
          sample: data,
          fx: [
            EffectSpec(EffectKind.echo, values: {'mix': 0.8, 'time': 50}),
            EffectSpec(EffectKind.bitcrush, values: {'bits': 3}),
          ],
        ),
        tail: 0.5,
      );
      expect(a.length, (4800 + 24000) * 2);
      var diff = 0.0;
      for (var i = 0; i < a.length; i++) {
        diff += (a[i] - b[i]).abs();
      }
      expect(diff, greaterThan(1));
      expect(
        peak(Float32List.sublistView(a, 6000 * 2, 8000 * 2)),
        greaterThan(0.01),
        reason: 'echo tail',
      );
    });

    test('scope snapshots arrive about 25 times a second', () {
      final e = LabEngine()..configure(labDefaultSpec, const []);
      final shots = <Object?>[];
      final out = Float32List(192 * 2);
      for (var i = 0; i < labRate ~/ 192; i++) {
        e.render(out, 192, shots.add);
      }
      expect(shots.length, closeTo(25, 1));
      expect((shots.first! as Float32List).length, scopeSize);
    });
  });

  group('controller', () {
    test('effects: add, edit, move, remove; notes reach the engine', () async {
      final out = FakeOutput();
      final c = LabController(out);
      await c.init();
      c.addEffect(EffectKind.drive);
      c.addEffect(EffectKind.echo);
      expect(c.fx.map((e) => e.kind), [
        EffectKind.reverb,
        EffectKind.drive,
        EffectKind.echo,
      ]);
      c.moveEffect(2, 0);
      expect(c.fx.first.kind, EffectKind.echo);
      c.updateEffect(c.fx.first.withValue('mix', 0.9));
      expect(out.last!.fx.first['mix'], 0.9);
      c.removeEffect(c.fx.last);
      expect(c.fx, hasLength(2));
      c.noteOn(60);
      expect(out.last!.touches.where((t) => t.down), hasLength(1));
      c.noteOff(60);
      expect(out.last!.touches.where((t) => t.down), isEmpty);
      c.setSource(SourceKind.chip);
      expect(out.last!.spec.engine, EngineKind.chip);
    });

    test(
      'preset round trip (wave source) and Waveform Painter waves',
      () async {
        final c = LabController(FakeOutput());
        await c.init();
        c.setWaves('Glass', [
          [0, 1, 0, -1],
          [1, -1],
        ]);
        c.addEffect(EffectKind.phaser);
        c.name = 'Shimmer';
        final p = SoundPreset.fromJson(c.toPreset().toJson());
        final d = LabController(FakeOutput());
        await d.init();
        d.applyPreset(p);
        expect(d.source, SourceKind.wavetable);
        expect(d.waves, hasLength(2));
        expect(d.fx.map((e) => e.kind), [EffectKind.reverb, EffectKind.phaser]);
        expect(d.name, 'Shimmer');

        final painter = {
          'kind': 'wavetable',
          'name': 'Saw-ish',
          'waves': [
            [1, 0, -1],
          ],
        };
        expect(wavesFromJson(painter)!.$1, 'Saw-ish');
        expect(wavesFromJson({'kind': 'sample_pad_kit'}), isNull);
      },
    );

    test(
      'a sample preset without its sample falls back to the analog synth',
      () async {
        final c = LabController(FakeOutput());
        c.applyPreset(
          const SoundPreset(
            name: 'Gone',
            source: SourceKind.sample,
            sampleId: 'x',
          ),
        );
        expect(c.source, SourceKind.analog);
      },
    );
  });

  testWidgets('tabs, adding an effect and its knobs, scope', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('lab_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final services = (await tester.runAsync(
      () => ShellServices.create(appConfig, root: dir),
    ))!;
    final out = FakeOutput();
    final c = LabController(out);
    await tester.runAsync(c.init);
    await tester.pumpWidget(
      ShellApp(
        services: services,
        home: (_) => HomePage(controller: c),
      ),
    );
    await tester.pump();
    expect(find.text('Wave 1 '), findsOneWidget);

    await tester.tap(find.text('Chip'));
    await tester.pump();
    expect(c.source, SourceKind.chip);

    await tester.tap(find.text('Effects (1)'));
    await tester.pump();
    expect(find.text('Reverb'), findsOneWidget);
    await tester.tap(find.text('Add effect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bitcrush').last);
    await tester.pumpAndSettle();
    expect(c.fx.last.kind, EffectKind.bitcrush);
    expect(
      find.text('Sample-rate divide'),
      findsOneWidget,
      reason: 'new effects open their knobs',
    );
    await tester.tap(find.byType(Switch).last);
    await tester.pump();
    expect(c.fx.last.on, isFalse);

    out.emitScope(
      Float32List.fromList(List.generate(scopeSize, (i) => math.sin(i / 10))),
    );
    await tester.pump();
    await tester.tap(find.bySemanticsLabel(RegExp('Waveform')));
    await tester.pump();
  });
}
