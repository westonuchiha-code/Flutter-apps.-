import 'dart:io';

import 'package:app_shell/app_shell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:save_manager/main.dart';
import 'package:save_manager/src/ui/screen.dart';

import 'screen_fixtures.dart';

void main() {
  testWidgets('home page reads the cards it is given', (tester) async {
    final dir = Directory.systemTemp.createTempSync('save_manager_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    makeCards(dir.path);
    final services = (await tester.runAsync(
      () => ShellServices.create(appConfig, root: dir),
    ))!;
    await tester.pumpWidget(
      ShellApp(
        services: services,
        home: (_) => HomePage(
          makeConfig: (extra, check) async => testConfig(dir.path),
          runner: runNow,
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(SaveManagerScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('save-0')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
