import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ambience_machine/main.dart';
import 'package:ambience_machine/src/controller.dart';
import 'package:ambience_machine/src/engine.dart';
import 'package:ambience_machine/src/keeper.dart';
import 'package:ambience_machine/src/library.dart';
import 'package:ambience_machine/src/output.dart';
import 'package:ambience_machine/src/scene.dart';
import 'package:ambience_machine/src/ui/home.dart';
import 'package:app_shell/app_shell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fx_kit/fx_kit.dart';
import 'package:material_ui/material_ui.dart';

class FakeOutput implements AmbOutput {
  final sent = <AmbCommand>[];
  final _events = StreamController<Object?>.broadcast(sync: true);
  void emit(Object e) => _events.add(e);

  @override
  Future<void> init() async {}
  @override
  void send(AmbCommand command) => sent.add(command);
  @override
  Stream<Object?> get events => _events.stream;
  @override
  Future<void> dispose() async {}
}

class FakeKeeper implements PlaybackKeeper {
  final calls = <String>[];
  @override
  Future<void> start(String title, String text) async =>
      calls.add('start:$title');
  @override
  Future<void> stop() async => calls.add('stop');
}

void main() {
  test(
    'playing starts the background keeper; the sleep timer and Stop end it',
    () async {
      final out = FakeOutput();
      final keeper = FakeKeeper();
      final c = AmbienceController(out, keeper: keeper);
      await c.init();
      expect(out.sent.whereType<SetScene>(), hasLength(1));
      c.setPlaying(true);
      expect(keeper.calls.last, 'start:First light');
      expect(out.sent.whereType<SetPlaying>().last.playing, isTrue);
      c.setSleep(30);
      expect((out.sent.whereType<SetSleep>().last).seconds, 1800);
      out.emit(const StoppedEvent());
      expect(c.playing, isFalse);
      expect(keeper.calls.last, 'stop');
    },
  );

  test('edits keep the scene id; loading another crossfades', () async {
    final out = FakeOutput();
    final c = AmbienceController(out, keeper: FakeKeeper());
    await c.init();
    final id = c.scene.id;
    c.addLayer(LayerSpec(kind: LayerKind.noise, noise: NoiseType.rain));
    c.updateLayer(c.scene.layers.first.copyWith(volume: 0.2));
    c.removeLayer(c.scene.layers[1]);
    expect(
      out.sent.whereType<SetScene>().every((s) => s.scene.id == id),
      isTrue,
    );
    expect(c.scene.layers, hasLength(3));
    c.setPlaying(true);
    c.switchTo(SceneSpec(name: 'Other'));
    final last = out.sent.whereType<SetScene>().last;
    expect(last.scene.id, isNot(id));
    expect(last.fade, c.crossfade);
  });

  test('samples are sent to the engine only once', () async {
    final out = FakeOutput();
    final c = AmbienceController(out, keeper: FakeKeeper());
    c.provideSample('a', Float32List(10), name: 'Creek');
    c.provideSample('a', Float32List(10), name: 'Creek');
    expect(out.sent.whereType<SetSample>(), hasLength(1));
    expect(c.hasSample('a'), isTrue);
    expect(c.sampleNames['a'], 'Creek');
  });

  test(
    'sounds from Sound Lab and waves from Waveform Painter become layers',
    () {
      final wave = soundFromJson({
        'kind': 'wavetable',
        'name': 'Glass',
        'waves': [
          [0, 1, 0, -1],
        ],
      });
      expect(wave!['source'], 'wavetable');
      expect(wave['name'], 'Glass');
      final sound = soundFromJson(
        SoundPreset(
          name: 'Bell',
          source: SourceKind.chip,
          fx: [EffectSpec(EffectKind.echo)],
        ).toJson(),
      );
      expect(sound!['name'], 'Bell');
      expect(soundFromJson({'kind': 'sample_pad_kit'}), isNull);
      // And the engine can play them.
      final cloud = NoteCloud(
        LayerSpec(kind: LayerKind.synth, sound: wave, density: 60),
        1,
      );
      expect(cloud.synth.wavetable, isNotNull);
    },
  );

  testWidgets('home: play, add a layer, open its settings, effects page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('amb_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final services = (await tester.runAsync(
      () => ShellServices.create(appConfig, root: dir),
    ))!;
    final out = FakeOutput();
    final c = AmbienceController(out, keeper: FakeKeeper());
    await tester.runAsync(c.init);
    await tester.pumpWidget(
      ShellApp(
        services: services,
        home: (_) => HomePage(controller: c),
      ),
    );
    await tester.pump();
    expect(find.text('Waves'), findsOneWidget);
    expect(find.text('Soft notes'), findsOneWidget);

    await tester.tap(find.byTooltip('Play'));
    await tester.pump();
    expect(c.playing, isTrue);
    out.emit(LevelsEvent({c.scene.layers.first.id: 0.2}, null));
    await tester.pump();

    await tester.tap(find.text('Layer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rumble'));
    await tester.pumpAndSettle();
    expect(c.scene.layers.last.noise, NoiseType.rumble);

    await tester.tap(find.text('Waves'));
    await tester.pump();
    expect(find.text('Drift speed'), findsOneWidget);

    await tester.tap(find.byTooltip('Effects'));
    await tester.pumpAndSettle();
    expect(find.text('Reverb'), findsOneWidget);
  });
}
