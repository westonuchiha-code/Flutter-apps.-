// Phone screenshots: main screen and singing mode (layout check).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_shell/app_shell.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:speech_chip_lab/main.dart';
import 'package:speech_chip_lab/src/controller.dart';
import 'package:speech_chip_lab/src/output.dart';
import 'package:speech_chip_lab/src/ui/home.dart';

import '../test/widget_test.dart' show FakeOutput;

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: '.');
  testWidgets('shot', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('speech_shot');
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
    final c = SpeechController(fake);
    await tester.runAsync(c.init);
    c.speak();
    fake.emit(const SpeechProgress(4, true));
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

    await shot('speech_main');
    c.stop();
    await tester.tap(find.text('Sing'));
    await tester.pump();
    c.noteOn(55);
    await tester.pump();
    await shot('speech_sing');
  });
}
