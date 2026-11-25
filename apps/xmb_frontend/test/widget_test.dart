import 'dart:io';

import 'package:app_shell/app_shell.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xmb_frontend/main.dart';
import 'package:xmb_frontend/src/library/scanner.dart';
import 'package:xmb_frontend/src/state.dart';
import 'package:xmb_frontend/src/ui/home.dart';

void main() {
  testWidgets('the menu opens on Game and moves with the d-pad', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('xmb_ui');
    final services = (await tester.runAsync(
      () => ShellServices.create(appConfig, root: dir),
    ))!;
    final state = MenuState()
      ..romsDir = '/roms'
      ..games = const [
        Game(
          system: 'gba',
          path: '/roms/Game Boy Advance/Emerald.gba',
          title: 'Emerald',
          size: 16 << 20,
        ),
        Game(
          system: 'ps1',
          path: '/roms/PS1/Spyro.chd',
          title: 'Spyro',
          size: 300 << 20,
        ),
      ];
    state.togglePin('ps1:spyro.chd');
    await tester.pumpWidget(
      ShellApp(
        services: services,
        home: (_) => HomePage(state: state),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Game'), findsOneWidget);
    expect(find.text('Spyro'), findsOneWidget); // pinned, on the front
    expect(find.text('All Games'), findsOneWidget);
    // Down to All Games, open it, Emerald is there.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(find.text('Emerald'), findsOneWidget);
    // Y: options for the selected game; B closes it, B leaves the folder.
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonY);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Pin to Front'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(find.text('All Games'), findsOneWidget);
    // Left: Settings.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(find.text('ROMs Folder'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });
}
