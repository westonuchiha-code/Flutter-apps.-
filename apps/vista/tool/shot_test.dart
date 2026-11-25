// Screenshots on a phone and a desktop window (look check).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_shell/app_shell.dart';
import 'package:engine3d/engine3d.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vista/main.dart';
import 'package:vista/src/land.dart';
import 'package:vista/src/ui/home.dart';

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: '.');
  for (final (name, size, dpr, land) in [
    (
      'vista_phone',
      const Size(1080, 2340),
      2.625,
      LandSettings(time: 17.6, seed: 7),
    ),
    (
      'vista_desktop',
      const Size(1400, 860),
      1.0,
      LandSettings(
        preset: 'islands',
        height: 0.45,
        roughness: 0.55,
        ridges: 0.3,
        erosion: 0.4,
        seaLevel: 0.42,
        time: 11,
        clouds: 0.6,
        seed: 4,
      ),
    ),
  ]) {
    testWidgets(name, (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.reset);
      final dir = Directory.systemTemp.createTempSync('vista_shot');
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
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('s'),
          child: ShellApp(
            services: services,
            home: (_) => HomePage(initial: land),
          ),
        ),
      );
      for (
        var i = 0;
        i < 60 && find.byType(Viewport3D).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 33));
      }
      final b = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('s')),
      );
      await tester.runAsync(() async {
        final img = await b.toImage(pixelRatio: 1);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
      await tester.pumpWidget(const SizedBox());
    });
  }
}
