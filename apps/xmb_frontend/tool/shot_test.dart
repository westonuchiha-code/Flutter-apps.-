// Screenshots (look check): TV, Retroid Pocket Classic, phone.
import 'dart:async';
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
import 'package:cross_save/cross_save.dart';
import 'package:xmb_frontend/src/ui/home.dart';
import 'package:xmb_frontend/src/ui/xmb.dart';

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
    (
      'xmb_video',
      const Size(1240, 1080),
      2.75,
      [LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.arrowRight],
    ),
    (
      'xmb_memory',
      const Size(1240, 1080),
      2.75,
      [LogicalKeyboardKey.arrowRight],
    ),
    ('xmb_phone', const Size(1080, 2340), 2.625, <LogicalKeyboardKey>[]),
    // The Retroid Pocket Classic: 1240×1080, wider than tall, at the
    // densities Android may use for it.
    ('xmb_classic_x2', const Size(1240, 1080), 2.0, <LogicalKeyboardKey>[]),
    ('xmb_classic_x275', const Size(1240, 1080), 2.75, <LogicalKeyboardKey>[]),
    (
      'xmb_classic_options',
      const Size(1240, 1080),
      2.75,
      [LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.gameButtonY],
    ),
    (
      'xmb_classic_folder',
      const Size(1240, 1080),
      2.75,
      [
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.gameButtonA,
      ],
    ),
  ]) {
    testWidgets(name, (tester) => shoot(tester, out, name, size, dpr, keys));
  }
  // Sign in with GitHub (the code panel) and Get Emulators, at the
  // Retroid Pocket Classic's size and on a phone.
  for (final (where, size, dpr) in [
    ('classic', const Size(1240, 1080), 2.75),
    ('phone', const Size(1080, 2340), 2.625),
  ]) {
    testWidgets(
      'xmb_${where}_sign_in',
      (tester) => shoot(
        tester,
        out,
        'xmb_${where}_sign_in',
        size,
        dpr,
        const [],
        after: (cs) => unawaited(
          showGitHubSignIn(
            tester.element(find.byType(XmbView)),
            cs,
            login: DeviceLogin(
              clientId: 'shot',
              post: (url, form) async => (
                status: 200,
                body:
                    '{"device_code":"d","user_code":"WDJB-MJHT",'
                    '"verification_uri":"https://github.com/login/device",'
                    '"expires_in":900,"interval":5}',
              ),
              wait: (_) => Completer<void>().future,
            ),
          ),
        ),
      ),
    );
    testWidgets(
      'xmb_${where}_get_emulators',
      (tester) => shoot(
        tester,
        out,
        'xmb_${where}_get_emulators',
        size,
        dpr,
        const [LogicalKeyboardKey.gameButtonA],
      ),
    );
    testWidgets(
      'xmb_${where}_setup_retroarch',
      (tester) =>
          shoot(tester, out, 'xmb_${where}_setup_retroarch', size, dpr, const [
            LogicalKeyboardKey.gameButtonA,
            LogicalKeyboardKey.gameButtonY,
            LogicalKeyboardKey.arrowDown,
            LogicalKeyboardKey.gameButtonA,
          ]),
    );
  }
}

Future<void> shoot(
  WidgetTester tester,
  String out,
  String name,
  Size size,
  double dpr,
  List<LogicalKeyboardKey> keys, {
  void Function(CrossSaveController cs)? after,
}) async {
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
        'monospace',
        ['/usr/share/fonts/truetype/jetbrains-mono/JetBrainsMono-Bold.ttf'],
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
  final cs = CrossSaveController(services.storage)
    ..folders = const XmbFolders('/storage/emulated/0/XMB Frontend');
  await tester.pumpWidget(
    RepaintBoundary(
      key: const Key('s'),
      child: ShellApp(
        services: services,
        home: (_) => HomePage(state: demo(), crossSave: cs),
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
  after?.call(cs);
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
}
