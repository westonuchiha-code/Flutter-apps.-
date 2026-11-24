// Phone screenshots: pads, steps, pad editor (layout check).
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_shell/app_shell.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sample_pad/main.dart';
import 'package:sample_pad/src/controller.dart';
import 'package:sample_pad/src/ui/home.dart';

import '../test/widget_test.dart' show FakeOutput;

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: '.');
  testWidgets('shot', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('pad_shot');
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
    final c = PadController(output: FakeOutput(), tempDir: dir);
    final names = [
      'Kick',
      'Snare',
      'Hat',
      'Clap',
      'Creek',
      'Vox chop',
      'Bass',
      'Bell',
    ];
    for (var i = 0; i < names.length; i++) {
      final n = 24000 + i * 3000;
      c.setSample(
        i,
        Float32List.fromList(
          List.generate(
            n,
            (k) => math.sin(k / (5 + i)) * math.exp(-k / (3000.0 + i * 900)),
          ),
        ),
        name: names[i],
      );
    }
    for (final (p, steps) in [
      (0, [0, 4, 8, 12]),
      (1, [4, 12]),
      (2, [0, 2, 4, 6, 8, 10, 12, 14]),
      (3, [12, 15]),
    ]) {
      for (final s in steps) {
        c.toggleStep(p, s);
      }
    }
    c.activePads = 1 | 4;
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

    await shot('pad_pads');
    c.currentStep = 4;
    await tester.tap(find.text('Steps'));
    await tester.pump();
    await shot('pad_steps');
    await tester.tap(find.text('Pads'));
    await tester.pump();
    await tester.tap(find.byTooltip('Edit pads'));
    await tester.pump();
    await tester.tap(find.text('Vox chop'));
    await tester.pumpAndSettle();
    await shot('pad_editor');
  });
}
