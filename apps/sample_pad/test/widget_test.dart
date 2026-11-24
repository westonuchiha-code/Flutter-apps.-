import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:app_shell/app_shell.dart';
import 'package:audio_kit/audio_kit.dart';
import 'package:beat_kit/beat_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sample_pad/main.dart';
import 'package:sample_pad/src/controller.dart';
import 'package:sample_pad/src/output.dart';
import 'package:sample_pad/src/ui/home.dart';

class FakeOutput implements BeatOutput {
  final sent = <BeatCommand>[];
  final _events = StreamController<Object?>.broadcast(sync: true);

  void emit(Object e) => _events.add(e);

  @override
  Stream<Object?> get events => _events.stream;
  @override
  Future<void> init() async {}
  @override
  void send(BeatCommand command) => sent.add(command);
  @override
  Future<void> dispose() async {}
}

/// "Records" a known signal: value = sample index / 1e6 (so cuts are checkable).
class FakeMic extends MicRecorder {
  File? _file;
  double secs = 0;

  @override
  double get seconds => secs;

  @override
  Future<bool> start(
    File file, {
    int sampleRate = 48000,
    MicSource source = MicSource.unprocessed,
  }) async {
    _file = file;
    state = MicState.recording;
    return true;
  }

  @override
  Future<WavInfo?> stop() async {
    final f = _file;
    if (f == null) return null;
    final n = engineRate * 6;
    final data = Float32List(n);
    for (var i = 0; i < n; i++) {
      data[i] = (i % 1000) / 2000;
    }
    await f.writeAsBytes(encodeWavMono16(data, engineRate));
    _file = null;
    state = MicState.idle;
    return parseWav(await f.readAsBytes());
  }
}

PadController make(FakeOutput out, Directory dir, [FakeMic? mic]) =>
    PadController(
      output: out,
      tempDir: dir,
      micFactory: mic == null ? null : () => mic,
    );

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('pad_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('pattern, tempo, tap tempo and the loop lock', () async {
    final out = FakeOutput();
    final c = make(out, dir);
    await c.init();
    c.setSample(3, Float32List(100), name: 'Snare');
    c.toggleStep(3, 4);
    expect(c.stepOn(3, 4), isTrue);
    expect((out.sent.whereType<SetPattern>().last).masks[3], 1 << 4);
    final t = DateTime(2026);
    for (var i = 0; i < 4; i++) {
      c.tapTempo(t.add(Duration(milliseconds: 500 * i)));
    }
    expect(c.bpm, 120);
    c.addLayer(Float32List(10), 1, 0);
    c.setBpm(90);
    expect(c.bpm, 120, reason: 'locked while loops exist');
    c.undoLayer();
    c.setBpm(90);
    expect(c.bpm, 90);
    c.setSample(3, null);
    expect(c.stepOn(3, 4), isFalse);
  });

  test('trim silence keeps a little lead-in', () async {
    final c = make(FakeOutput(), dir);
    final data = Float32List(48000);
    for (var i = 24000; i < 48000; i++) {
      data[i] = 0.5;
    }
    c.setSample(0, data);
    c.trimSilence(0);
    expect(c.pads[0].settings.start, closeTo((24000 - 240) / 48000, 1e-6));
  });

  test('kit round trip through toKit/applyKit', () async {
    final c = make(FakeOutput(), dir);
    c.setSample(
      0,
      Float32List(50),
      name: 'Kick',
      assetId: 'k1',
      assetType: 'sample',
    );
    c.setPad(0, const PadSettings(pitch: -5, mode: PadMode.hold));
    c.toggleStep(0, 0);
    c.setBpm(95);
    final kit = Kit.fromJson(c.toKit().toJson());
    final d = make(FakeOutput(), dir);
    d.applyKit(kit, [Float32List(50), ...List.filled(15, null)]);
    expect(d.pads[0].name, 'Kick');
    expect(d.pads[0].assetId, 'k1');
    expect(d.pads[0].settings.pitch, -5);
    expect(d.stepOn(0, 0), isTrue);
    expect(d.bpm, 95);
  });

  test('cutLayer applies the timing offset and pads short takes', () {
    final data = Float32List(48000);
    for (var i = 0; i < data.length; i++) {
      data[i] = (i % 1000) / 2000;
    }
    final wav = encodeWavMono16(data, engineRate);
    final cut = cutLayer(wav, markSeconds: 0.5, latencyMs: 10, frames: 30000);
    expect(cut.length, 30000);
    // Source index 24480 -> value 480/2000 at cut index 0 (+ fade), check index 500.
    expect(cut[500], closeTo(((24480 + 500) % 1000) / 2000, 1e-3));
    expect(cut[29000], 0, reason: 'past the end of the take');
  });

  test('mix render has the right length and sound', () async {
    final c = make(FakeOutput(), dir);
    c.setSample(
      0,
      Float32List.fromList(List.generate(4800, (i) => math.sin(i / 10) * 0.5)),
    );
    c.toggleStep(0, 0);
    c.setBpm(120);
    final wav = renderMix(c.snapshot(), 2);
    final info = parseWav(wav);
    expect(info.format.channels, 2);
    expect(info.frames, 96000 * 2);
    final mono = decodeWavMono(wav);
    expect(mono.sublist(0, 4000).any((v) => v.abs() > 0.1), isTrue);
  });

  test(
    'loop recording marks on the next bar and adds a layer after N bars',
    () async {
      final out = FakeOutput();
      final mic = FakeMic();
      final c = make(out, dir, mic)..latencyMs = 0;
      await c.init();
      c.setBpm(120);
      c.setLayerBars(1);
      await c.recordLayer();
      expect(c.layerRec, LayerRec.waiting);
      expect(c.playing, isTrue);
      mic.secs = 1.0;
      out.emit(const StepEvent(0, 0, 0));
      expect(c.layerRec, LayerRec.recording);
      out.emit(const StepEvent(0, 16, 96000));
      expect(c.layerRec, LayerRec.processing);
      for (var i = 0; i < 100 && c.layers.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(c.layers, hasLength(1));
      final l = c.layers.single;
      expect(l.data.length, 96000);
      expect(l.data[500], closeTo(((48000 + 500) % 1000) / 2000, 1e-3));
      expect(out.sent.whereType<AddLayer>().single.startBar, 0);
      expect(c.layerRec, LayerRec.idle);
    },
  );

  testWidgets('pads, steps and loops screens', (tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = (await tester.runAsync(
      () => ShellServices.create(appConfig, root: dir),
    ))!;
    final out = FakeOutput();
    final c = make(out, dir);
    await tester.runAsync(c.init);
    c.setSample(0, Float32List(4800), name: 'Kick');
    await tester.pumpWidget(
      ShellApp(
        services: services,
        home: (_) => HomePage(controller: c),
      ),
    );
    await tester.pump();
    expect(find.text('Kick'), findsOneWidget);
    await tester.tap(find.text('Kick'));
    expect(out.sent.whereType<Trigger>().single.pad, 0);

    await tester.tap(find.text('Steps'));
    await tester.pump();
    expect(find.text('16 steps'), findsOneWidget);
    await tester.tap(find.byType(GestureDetector).at(0), warnIfMissed: false);

    await tester.tap(find.text('Loops'));
    await tester.pump();
    expect(find.text('Record loop'), findsOneWidget);
    expect(find.text('No loops yet.'), findsOneWidget);

    await tester.tap(find.text('Pads'));
    await tester.pump();
    await tester.tap(
      find
          .descendant(
            of: find.byType(GridView),
            matching: find.byIcon(Icons.add),
          )
          .first,
    ); // empty pad opens its editor
    await tester.pumpAndSettle();
    expect(find.text('From Asset Locker'), findsOneWidget);
    expect(find.text('Record with mic'), findsOneWidget);
  });
}
