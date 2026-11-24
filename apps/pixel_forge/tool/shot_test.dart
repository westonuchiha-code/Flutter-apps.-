// Screenshots on a phone and a desktop window (layout check).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_shell/app_shell.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pixel_forge/main.dart';
import 'package:pixel_forge/src/editor.dart';
import 'package:pixel_forge/src/map_editor.dart';
import 'package:pixel_forge/src/ui/home.dart';
import 'package:pixel_forge/src/ui/map_page.dart';
import 'package:pixel_kit/pixel_kit.dart' as px;

/// A small test drawing: a mushroom made of shapes.
Editor sample() {
  final e = Editor(sprite: px.Sprite.blank(16, 16))
    ..name = 'Mushroom'
    ..setPalette(px.builtInPalettes[2]);
  void shape(
    Tool t,
    int c,
    int x0,
    int y0,
    int x1,
    int y1, {
    bool filled = true,
  }) {
    e
      ..setTool(t)
      ..setPrimary(c);
    if (e.shapeFilled != filled) e.toggleFilled();
    e.strokeStart(x0, y0);
    e.strokeMove(x1, y1);
    e.strokeEnd();
  }

  shape(Tool.ellipse, px.rgb(0xFF004D), 1, 1, 14, 9);
  shape(Tool.rect, px.rgb(0xFFF1E8), 5, 9, 10, 14);
  shape(Tool.ellipse, px.rgb(0xFFF1E8), 3, 3, 5, 5);
  shape(Tool.ellipse, px.rgb(0xFFF1E8), 9, 2, 11, 4);
  shape(Tool.rect, px.rgb(0x000000), 6, 11, 6, 12);
  shape(Tool.rect, px.rgb(0x000000), 9, 11, 9, 12);
  e
    ..setTool(Tool.pencil)
    ..addLayer()
    ..setPrimary(px.rgb(0xFF004D));
  return e;
}

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: '.');
  for (final (name, size, dpr) in [
    ('forge_phone', const Size(1080, 2340), 2.625),
    ('forge_desktop', const Size(1400, 860), 1.0),
  ]) {
    testWidgets(name, (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.reset);
      final dir = Directory.systemTemp.createTempSync('forge_shot');
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
      final e = sample();
      if (name == 'forge_phone') {
        e
          ..addFrame()
          ..selectLayer(0)
          ..setTool(Tool.select)
          ..selectAll();
        e.strokeStart(5, 5);
        e.strokeMove(5, 6);
        e.strokeEnd();
        e
          ..commitFloating()
          ..deselect()
          ..setTool(Tool.pencil)
          ..toggleOnion();
      }
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('s'),
          child: ShellApp(
            services: services,
            home: (_) => HomePage(editor: e),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
      }
      Future<void> shot(String n) async {
        final b = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('s')),
        );
        await tester.runAsync(() async {
          final img = await b.toImage(pixelRatio: 1);
          final png = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$out/$n.png').writeAsBytesSync(png!.buffer.asUint8List());
        });
      }

      await shot(name);
      if (name == 'forge_phone') {
        // Tile map: the mushroom cut into 8x8 tiles, painted in a row.
        final m = MapEditor.fromPicture(
          e.sprite.flatten(0),
          16,
          16,
          8,
          cols: 12,
          rows: 9,
        )..name = 'Mushroom field';
        for (var c = 0; c < 12; c += 2) {
          for (final (dc, dr, t) in [
            (0, 6, 1),
            (1, 6, 2),
            (0, 7, 3),
            (1, 7, 4),
          ]) {
            if (t < m.map.tileSet.length) m.map.set(c + dc, dr, t);
          }
        }
        final nav = tester.state<NavigatorState>(find.byType(Navigator).last);
        unawaited(
          nav.push(
            MaterialPageRoute<void>(
              builder: (_) => MapPage(map: m, sprite: e),
            ),
          ),
        );
        for (var i = 0; i < 20; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }
        await shot('forge_map');
      }
    });
  }
}
