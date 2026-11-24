// Phone screenshots of the main screen and sound sheet (layout check).
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_shell/app_shell.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:waveform_painter/main.dart';
import 'package:waveform_painter/src/controller.dart';
import 'package:waveform_painter/src/shape.dart';
import 'package:waveform_painter/src/ui/home.dart';

import '../test/widget_test.dart' show FakeOutput;

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: '.');
  testWidgets('shot', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('painter_shot');
    final services = (await tester.runAsync(() async {
      for (final (fam, files) in [
        (
          'Roboto',
          [
            'Regular',
            'Medium',
            'SemiBold',
          ].map((w) => '/usr/share/fonts/opentype/inter/Inter-$w.otf'),
        ),
        (
          'MaterialIcons',
          [
            '/opt/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ],
        ),
      ]) {
        final l = FontLoader(fam);
        for (final f in files) {
          l.addFont(
            Future.value(ByteData.sublistView(File(f).readAsBytesSync())),
          );
        }
        await l.load();
      }
      final s = await ShellServices.create(appConfig, root: dir);
      s.settings.set(themeModeSetting, 'dark');
      return s;
    }))!;
    final c = PainterController(FakeOutput());
    await tester.runAsync(c.init);
    c.name = 'Glass organ';
    c.waves[0] = Float32List.fromList(
      List.generate(wavePoints, (i) {
        final t = 2 * math.pi * i / wavePoints;
        return 0.6 * math.sin(t) +
            0.3 * math.sin(3 * t) +
            0.15 * math.sin(7 * t + 1);
      }),
    );
    c.addWave();
    c.waves[1] = smooth(WavePreset.square.build(), radius: 8);
    c.select(1);
    c.setMorph(0.4);
    c.noteOn(64);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('s'),
        child: ShellApp(
          services: services,
          home: (_) => HomePage(controller: c),
        ),
      ),
    );
    await tester.pump();
    Future<void> shot(String name) async {
      final b = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('s')),
      );
      await tester.runAsync(() async {
        final img = await b.toImage(pixelRatio: 1);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    }

    await shot('painter_main');
    await tester.tap(find.byTooltip('Sound'));
    await tester.pumpAndSettle();
    await shot('painter_sound');
  });
}
