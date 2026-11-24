// Screenshots on a phone and a desktop window (layout check).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_shell/app_shell.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:texture_capture/main.dart';
import 'package:texture_capture/src/controller.dart';
import 'package:texture_capture/src/engine/formats.dart';
import 'package:texture_capture/src/ui/home.dart';

import '../test/support.dart';

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: '.');
  for (final (name, size, dpr) in [
    ('tex_phone', const Size(1080, 2340), 2.625),
    ('tex_desktop', const Size(1400, 860), 1.0),
  ]) {
    testWidgets(name, (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.reset);
      final dir = Directory.systemTemp.createTempSync('tex_shot');
      final c = TextureController(useIsolates: false);
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
        final shot = photoOf(bricks(512));
        await c.setPhoto(shot.photo, name: 'Brick wall');
        for (var i = 0; i < 4; i++) {
          c.moveCorner(i, shot.corners[i]);
        }
        await c.setMasterSize(512);
        return s;
      }))!;
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('s'),
          child: ShellApp(
            services: services,
            home: (_) => HomePage(controller: c),
          ),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      Future<void> shot(String n) async {
        await settle();
        final b = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('s')),
        );
        await tester.runAsync(() async {
          final img = await b.toImage(pixelRatio: 1);
          final png = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$out/$n.png').writeAsBytesSync(png!.buffer.asUint8List());
        });
      }

      Future<void> tab(String t) async {
        await tester.tap(
          find.descendant(of: find.byType(TabBar), matching: find.text(t)),
        );
        await settle();
      }

      await shot('${name}_corners');
      await tab('Texture');
      await shot('${name}_texture');
      await tab('Console');
      await tester.runAsync(
        () => c.selectConsole(consoles.firstWhere((p) => p.id == 'ps1')),
      );
      await shot('${name}_ps1');
      if (name == 'tex_phone') {
        await tester.runAsync(() async {
          await c.selectConsole(consoles.firstWhere((p) => p.id == 'n64'));
          await c.setDither(true);
        });
        await shot('${name}_n64');
      }
    });
  }
}
