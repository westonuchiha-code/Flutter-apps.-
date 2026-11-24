// Phone screenshot of the main screen (layout check).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ambience_machine/main.dart';
import 'package:ambience_machine/src/controller.dart';
import 'package:ambience_machine/src/engine.dart';
import 'package:ambience_machine/src/ui/home.dart';
import 'package:app_shell/app_shell.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../test/widget_test.dart' show FakeKeeper, FakeOutput;

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: '.');
  testWidgets('shot', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('amb_shot');
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
    final c = AmbienceController(fake, keeper: FakeKeeper());
    await tester.runAsync(c.init);
    c.setPlaying(true);
    final ids = [for (final l in c.scene.layers) l.id];
    fake.emit(LevelsEvent({ids[0]: 0.12, ids[1]: 0.03, ids[2]: 0.06}, 1500));
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
    await tester.tap(find.text('Soft notes'));
    await tester.pump();
    final b = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('s')),
    );
    await tester.runAsync(() async {
      final img = await b.toImage(pixelRatio: 1);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$out/amb_main.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  });
}
