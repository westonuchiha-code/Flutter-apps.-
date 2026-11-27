import 'dart:io';

import 'package:app_shell/app_shell.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xmb_frontend/main.dart';
import 'package:xmb_frontend/src/library/scanner.dart';
import 'package:xmb_frontend/src/state.dart';
import 'package:cross_save/cross_save.dart';
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
        home: (_) => HomePage(
          state: state,
          crossSave: CrossSaveController(services.storage),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Game'), findsOneWidget);
    expect(find.text('Spyro'), findsOneWidget); // pinned, on the front
    expect(find.text('All Games'), findsOneWidget);
    // No emulator installed (off Android): Get Emulators comes first.
    expect(find.text('Get Emulators'), findsOneWidget);
    // Down to All Games, open it, Emerald is there.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
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

  testWidgets('first run: Get Emulators and Sign In with GitHub', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1240, 1080);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('xmb_ui');
    final services = (await tester.runAsync(
      () => ShellServices.create(appConfig, root: dir),
    ))!;
    await tester.pumpWidget(
      ShellApp(
        services: services,
        home: (_) => HomePage(
          state: MenuState()..romsDir = '/roms',
          crossSave: CrossSaveController(services.storage),
        ),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
    }

    await settle();
    expect(find.text('Get Emulators'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await settle();
    for (final e in ['RetroArch', 'DuckStation', 'PPSSPP', 'Dolphin']) {
      expect(find.text(e), findsOneWidget);
    }
    expect(
      find.textContaining('Not installed  ·  Nintendo, Sega, arcade'),
      findsOneWidget,
    );
    // B, then Settings: Cross Save asks to sign in.
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await settle();
    // Down to Cross Save (ROMs, Comics, Console Folders, Storage,
    // Emulators, Get Emulators, Screen, Swap A and B, Cross Save).
    for (var i = 0; i < 8; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    }
    await settle();
    expect(
      find.text('Sign in with GitHub to share saves with the PC'),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await settle();
    expect(find.text('Sign In with GitHub'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });
}
