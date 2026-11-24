import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:app_shell/app_shell.dart';
import 'package:audio_kit/audio_kit.dart';
import 'package:chip_synth/chip_synth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:waveform_painter/main.dart';
import 'package:waveform_painter/src/controller.dart';
import 'package:waveform_painter/src/output.dart';
import 'package:waveform_painter/src/patch.dart';
import 'package:waveform_painter/src/shape.dart';
import 'package:waveform_painter/src/ui/home.dart';
import 'package:waveform_painter/src/ui/keyboard.dart';
import 'package:waveform_painter/src/ui/wave_canvas.dart';

class FakeOutput implements WaveOutput {
  int tables = 0;
  List<Touch> touches = const [];
  double morph = 0;

  @override
  Future<void> init() async {}
  @override
  void setTable(Wavetable table) => tables++;
  @override
  void update(PolySpec spec, List<Touch> t, double m) {
    touches = List.of(t);
    morph = m;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  group('shape tools', () {
    test('presets have the right shape', () {
      final tri = WavePreset.triangle.build();
      expect(tri[0], closeTo(0, 0.02));
      expect(tri[64], closeTo(1, 0.02));
      expect(tri[192], closeTo(-1, 0.02));
      expect(WavePreset.square.build()[200], -1);
      expect(WavePreset.saw.build().first, 1);
    });

    test('draw segment fills between points, either direction', () {
      final w = blankWave();
      drawSegment(w, 0.5, 1, 0.25, 0);
      expect(w[64], 0);
      expect(w[128], 1);
      expect(w[96], closeTo(0.5, 0.02));
      drawSegment(w, 0.9, 5, 0.9, 5);
      expect(w[230], 1, reason: 'clamped');
    });

    test('mirror, normalize, smooth, invert, reverse', () {
      final w = Float32List.fromList(
        List.generate(wavePoints, (i) => i < 128 ? 0.5 : 0.0),
      );
      final m = mirror(w);
      expect(m[200], -0.5);
      final n = normalize(
        Float32List.fromList(
          List.generate(wavePoints, (i) => i < 128 ? 0.75 : 0.25),
        ),
      );
      expect(n[0], closeTo(1, 1e-6));
      expect(n[255], closeTo(-1, 1e-6));
      expect(normalize(Float32List(8)).every((v) => v == 0), isTrue);
      final sq = WavePreset.square.build();
      final sm = smooth(sq);
      expect(sm[128].abs(), lessThan(1));
      expect(invert(sq)[0], -1);
      expect(reverse(WavePreset.saw.build()).first, closeTo(-1, 0.01));
    });

    test('waves from a picture: row brightness and outline', () {
      // 4x4 image: black background, white bottom half; middle row is grey.
      const w = 4, h = 4;
      final rgba = Uint8List(w * h * 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final o = (y * w + x) * 4;
          final v = y >= 2 ? 255 : (y == 1 && x >= 2 ? 128 : 0);
          rgba[o] = rgba[o + 1] = rgba[o + 2] = v;
          rgba[o + 3] = 255;
        }
      }
      final row = waveFromRow(rgba, w, h, 1 / 3);
      expect(row[0], -1);
      expect(row[255], closeTo(0, 0.01));
      final outline = waveFromOutline(rgba, w, h);
      expect(outline[0], closeTo(1 - 2 * 2 / 3, 1e-6)); // first change at y=2
      expect(outline[255], closeTo(1 - 2 * 1 / 3, 1e-6)); // grey at y=1
    });
  });

  test('patch JSON round trip; other presets are rejected', () {
    final p = WavePatch(
      name: 'Glass',
      waves: [WavePreset.saw.build(), WavePreset.square.build()],
      spec: defaultSpec.copyWith(release: 1.2),
    );
    final back = WavePatch.fromJson(p.toJson());
    expect(back.name, 'Glass');
    expect(back.waves, hasLength(2));
    expect(back.waves[1][200], -1);
    expect(back.spec.release, 1.2);
    expect(
      () => WavePatch.fromJson({'kind': 'sample_pad_kit'}),
      throwsFormatException,
    );
    final short = WavePatch.fromJson({
      'kind': 'wavetable',
      'waves': [
        [1, -1],
      ],
    });
    expect(short.waves.single.length, wavePoints);
  });

  test(
    'controller: notes use free voices, waves, undo, morph, exports',
    () async {
      final out = FakeOutput();
      final c = PainterController(out);
      await c.init();
      expect(out.tables, 1);
      c.noteOn(60);
      c.noteOn(64);
      expect(out.touches.where((t) => t.down), hasLength(2));
      expect(out.touches.first.hz, closeTo(261.63, 0.01));
      c.noteOff(60);
      expect(out.touches.where((t) => t.down), hasLength(1));
      c.allOff();

      c.addWave();
      expect(c.waves, hasLength(2));
      expect(c.morph, 1, reason: 'editing wave B plays B');
      c.apply((_) => WavePreset.square.build());
      expect(c.wave[200], -1);
      c.undo();
      expect(c.wave[200], isNot(-1));
      c.undo();
      expect(c.waves, hasLength(1));

      final cycle = parseWav(c.singleCycleWav());
      expect(cycle.frames, tableSize);
      final note = c.renderNoteWav(seconds: 0.5);
      final samples = decodeWavMono(note);
      expect(samples.length, 24000);
      expect(samples.map((v) => v.abs()).reduce(math.max), greaterThan(0.05));
    },
  );

  testWidgets('draw on the canvas and play the keyboard', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('painter_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final services = (await tester.runAsync(
      () => ShellServices.create(appConfig, root: dir),
    ))!;
    final out = FakeOutput();
    final c = PainterController(out);
    await tester.runAsync(c.init);
    await tester.pumpWidget(
      ShellApp(
        services: services,
        home: (_) => HomePage(controller: c),
      ),
    );
    await tester.pump();

    // Drag across the top of the canvas: the wave goes to +1 there.
    final canvas = find.byType(WaveCanvas);
    final tl = tester.getTopLeft(canvas);
    final size = tester.getSize(canvas);
    await tester.dragFrom(
      tl + Offset(size.width * 0.6, 2),
      Offset(size.width * 0.3, 0),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.wave[200], closeTo(1, 0.05));
    expect(c.canUndo, isTrue);
    expect(out.tables, greaterThan(1));

    // Press the lowest white key.
    final keys = find.byType(PianoKeyboard);
    final kb = tester.getBottomLeft(keys);
    final g = await tester.startGesture(kb + const Offset(10, -10));
    await tester.pump();
    expect(out.touches.where((t) => t.down), hasLength(1));
    await g.up();
    await tester.pump();
    expect(out.touches.where((t) => t.down), isEmpty);

    await tester.tap(find.text('Mirror'));
    await tester.pump();
    expect(c.wave[10], closeTo(-c.wave[138], 1e-6));
    await tester.tap(find.byTooltip('Sound'));
    await tester.pumpAndSettle();
    expect(find.text('Release'), findsOneWidget);
  });
}
