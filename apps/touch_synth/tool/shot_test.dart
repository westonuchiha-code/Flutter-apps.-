// Landscape screenshot with three fingers down (text renders as boxes).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:touch_synth/app/synth_controller.dart';
import 'package:touch_synth/main.dart';

import '../test/synth_test.dart' show FakeOutput;

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: '.');
  testWidgets('shot', (tester) async {
    tester.view.physicalSize = const Size(2340, 1080);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final c = SynthController(output: FakeOutput());
    await c.init();
    c.fingerDown(1, const Offset(0.2, 0.3));
    c.fingerDown(2, const Offset(0.45, 0.6));
    c.fingerDown(3, const Offset(0.73, 0.2));
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('s'),
        child: TouchSynthApp(controller: c),
      ),
    );
    await tester.pump();
    final b = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('s')),
    );
    await tester.runAsync(() async {
      final img = await b.toImage(pixelRatio: 1);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$out/touch.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  });
}
