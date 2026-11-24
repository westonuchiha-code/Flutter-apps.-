// Phone screenshots: source tab and effects tab (layout check).
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_shell/app_shell.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fx_kit/fx_kit.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sound_lab/main.dart';
import 'package:sound_lab/src/controller.dart';
import 'package:sound_lab/src/engine.dart';
import 'package:sound_lab/src/ui/home.dart';

import '../test/widget_test.dart' show FakeOutput;

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: '.');
  testWidgets('shot', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('lab_shot');
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
    final fake = FakeOutput();
    final c = LabController(fake);
    await tester.runAsync(c.init);
    c.name = 'Dusty keys';
    c.addEffect(EffectKind.bitcrush);
    c.addEffect(EffectKind.chorus);
    c.moveEffect(0, 2);
    // A real render feeds the scope.
    final note = renderNote(c.snapshot(), 57, hold: 0.3, tail: 0);
    fake.emitScope(
      Float32List.fromList([
        for (var i = 0; i < scopeSize; i++) note[(4000 + i) * 2],
      ]),
    );
    c.noteOn(57);
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

    await shot('lab_source');
    await tester.tap(find.text('Effects (3)'));
    await tester.pump();
    await tester.tap(find.byTooltip('Show knobs').at(1));
    await tester.tap(find.bySemanticsLabel(RegExp('Waveform')));
    await tester.pump();
    await shot('lab_effects');
    expect(math.pi, greaterThan(3));
  });
}
