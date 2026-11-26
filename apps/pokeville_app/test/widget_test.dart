import 'dart:io';

import 'package:app_shell/app_shell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:pokeville/pokeville.dart';
import 'package:pokeville_app/main.dart';

void main() {
  testWidgets('opens the Pokéville folder from the settings', (tester) async {
    final dir = Directory.systemTemp.createTempSync('pokeville_app_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    // the PC's example folder (the package's test copy)
    final from = Directory(
      p.join(
        '..',
        '..',
        'packages',
        'pokeville',
        'test',
        'fixtures',
        'example-pokeville',
      ),
    );
    final box = p.join(dir.path, 'Pokeville');
    for (final f in from.listSync(recursive: true).whereType<File>()) {
      final to = p.join(box, p.relative(f.path, from: from.path));
      Directory(p.dirname(to)).createSync(recursive: true);
      f.copySync(to);
    }
    final services = (await tester.runAsync(
      () => ShellServices.create(appConfig, root: dir),
    ))!;
    services.settings.set(folderSetting, box);
    await tester.pumpWidget(
      ShellApp(services: services, home: (_) => const HomePage()),
    );
    for (
      var i = 0;
      i < 20 && find.byType(PokevilleScreen).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(find.byType(PokevilleScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1)); // the settings' save timer
  });
}
