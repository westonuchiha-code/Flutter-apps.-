// Screenshots (look check): TV, Retroid Pocket Classic, phone.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_shell/app_shell.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xmb_frontend/main.dart';
import 'package:xmb_frontend/src/library/scanner.dart';
import 'package:xmb_frontend/src/state.dart';
import 'package:xmb_frontend/src/ui/home.dart';

MenuState demo() {
  Game g(String sys, String folder, String file, String title, int mb) => Game(
    system: sys,
    path: '/storage/emulated/0/ROMs/$folder/$file',
    title: title,
    size: mb << 20,
  );
  final s = MenuState()
    ..romsDir = '/storage/emulated/0/ROMs'
    ..scanned = DateTime.now()
    ..games = [
      g(
        'ps1',
        'PS1',
        'Harry Potter and the Sorcerers Stone (USA).chd',
        "Harry Potter and the Sorcerer's Stone",
        380,
      ),
      g(
        'gbc',
        'Game Boy Color',
        'Pokemon - Crystal Version (USA, Europe).gbc',
        'Pokemon - Crystal Version',
        2,
      ),
      g(
        'gba',
        'Game Boy Advance',
        'Pokemon_Emerald_USA_GBA-TRM.gba',
        'Pokemon Emerald',
        16,
      ),
      g(
        'gba',
        'Game Boy Advance',
        'Pokemon - LeafGreen Version (USA).gba',
        'Pokemon - LeafGreen Version',
        16,
      ),
      g(
        'psp',
        'PSP',
        'Persona 3 Portable (USA).iso',
        'Persona 3 Portable',
        1400,
      ),
      g(
        'gb',
        'Game Boy',
        'Pokemon - Red Version (USA, Europe).gb',
        'Pokemon - Red Version',
        1,
      ),
      g('snes', 'SNES', 'Super Mario World (USA).sfc', 'Super Mario World', 1),
      g(
        'n64',
        'N64',
        'Legend of Zelda, The - Ocarina of Time (USA).z64',
        'The Legend of Zelda - Ocarina of Time',
        32,
      ),
    ];
  final now = DateTime.now().millisecondsSinceEpoch;
  s.togglePin('ps1:harry potter and the sorcerers stone (usa).chd');
  s.played['gbc:pokemon - crystal version (usa, europe).gbc'] = Played(
    last: now - 86400000,
    seconds: 5 * 3600,
    sessions: 9,
  );
  s.played['psp:persona 3 portable (usa).iso'] = Played(
    last: now - 3 * 86400000,
    seconds: 7200,
    sessions: 3,
  );
  return s;
}

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: '.');
  for (final (name, size, dpr, keys) in [
    ('xmb_tv', const Size(1920, 1080), 1.0, <LogicalKeyboardKey>[]),
    (
      'xmb_retroid',
      const Size(1240, 1080),
      1.5,
      [LogicalKeyboardKey.arrowDown],
    ),
    (
      'xmb_folder',
      const Size(1920, 1080),
      1.0,
      [
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.gameButtonA,
        LogicalKeyboardKey.arrowDown,
      ],
    ),
    (
      'xmb_options',
      const Size(1920, 1080),
      1.0,
      [LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.gameButtonY],
    ),
    (
      'xmb_settings',
      const Size(1920, 1080),
      1.0,
      [
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowDown,
      ],
    ),
    ('xmb_phone', const Size(1080, 2340), 2.625, <LogicalKeyboardKey>[]),
  ]) {
    testWidgets(name, (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.reset);
      final dir = Directory.systemTemp.createTempSync('xmb_shot');
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
        return ShellServices.create(appConfig, root: dir);
      }))!;
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('s'),
          child: ShellApp(
            services: services,
            home: (_) => HomePage(state: demo()),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      for (final k in keys) {
        await tester.sendKeyEvent(k);
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 30));
        }
      }
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 30));
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
