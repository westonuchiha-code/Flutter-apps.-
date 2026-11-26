import 'dart:io';

import 'package:app_shell/app_shell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:save_manager/main.dart';

void main() {
  testWidgets('home page loads', (tester) async {
    final dir = Directory.systemTemp.createTempSync('save_manager_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final services = (await tester.runAsync(
      () => ShellServices.create(appConfig, root: dir),
    ))!;
    await tester.pumpWidget(
      ShellApp(services: services, home: (_) => const HomePage()),
    );
    expect(find.text('Hello'), findsOneWidget);
  });
}
