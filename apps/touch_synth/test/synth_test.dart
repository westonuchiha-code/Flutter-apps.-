import 'package:chip_synth/chip_synth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:touch_synth/app/synth_controller.dart';
import 'package:touch_synth/audio/poly_output.dart';
import 'package:touch_synth/main.dart';
import 'package:touch_synth/ui/pad.dart';

class FakeOutput implements PolyOutput {
  PolySpec? spec;
  List<Touch> touches = const [];
  int updates = 0;
  @override
  Future<void> init() async {}
  @override
  void update(PolySpec spec, List<Touch> touches) {
    this.spec = spec;
    this.touches = List.of(touches);
    updates++;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  test('fingers map to smooth pitch and height; up to 6 voices', () async {
    final out = FakeOutput();
    final c = SynthController(output: out)
      ..lowNote = 48
      ..octaves = 2;
    await c.init();
    c.fingerDown(1, const Offset(0, 1)); // left edge, bottom
    expect(out.touches[0].down, isTrue);
    expect(out.touches[0].hz, closeTo(midiToHz(48), 1e-6));
    expect(out.touches[0].y, 0);
    c.fingerMove(1, const Offset(0.5, 0)); // middle, top: one octave up
    expect(out.touches[0].hz, closeTo(midiToHz(60), 1e-6));
    expect(out.touches[0].y, 1);
    c.fingerMove(1, const Offset(0.52, 0)); // between notes: smooth
    expect(out.touches[0].hz, greaterThan(midiToHz(60)));
    expect(out.touches[0].hz, lessThan(midiToHz(61)));
    for (var p = 2; p <= 8; p++) {
      c.fingerDown(p, Offset(p / 10, 0.5));
    }
    expect(out.touches.where((t) => t.down), hasLength(maxVoices));
    c.fingerUp(1);
    expect(out.touches[0].down, isFalse);
    expect(c.fingers[0], isNull);
  });

  test('settings persist', () async {
    final store = MemorySettingsStore();
    final c = SynthController(output: FakeOutput(), store: store);
    await c.init();
    c.setSpec(polyPresets['Acid Bass']!);
    c.setRange(low: 36, oct: 4);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final again = SynthController(output: FakeOutput(), store: store);
    await again.init();
    expect(again.spec, polyPresets['Acid Bass']);
    expect(again.lowNote, 36);
    expect(again.octaves, 4);
  });

  testWidgets('pad + controls; touching the pad plays', (tester) async {
    tester.view.physicalSize = const Size(2340, 1080);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final out = FakeOutput();
    final c = SynthController(output: out);
    await c.init();
    await tester.pumpWidget(TouchSynthApp(controller: c));
    expect(find.text('Analog'), findsOneWidget);
    final pad = tester.getRect(find.byType(TouchPad));
    final g = await tester.startGesture(pad.center);
    await tester.pump();
    expect(out.touches.first.down, isTrue);
    await g.moveBy(const Offset(60, -40));
    await tester.pump();
    await g.up();
    await tester.pump();
    expect(out.touches.first.down, isFalse);
    await tester.tap(find.text('Chip'));
    await tester.pump();
    expect(c.spec.engine, EngineKind.chip);
    await tester.pump(const Duration(seconds: 1)); // let the settings save
    expect(find.byType(DropdownButton<String>), findsWidgets); // chip pickers
  });
}
