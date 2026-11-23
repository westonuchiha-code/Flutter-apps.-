import 'dart:io';

import 'package:app_shell/app_shell.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:starter_app/main.dart';

void main() {
  test('platformName covers the target platforms', () {
    expect(platformName(TargetPlatform.windows), 'Windows');
    expect(platformName(TargetPlatform.android), 'Android');
    expect(platformName(TargetPlatform.linux), 'Linux');
  });

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.android,
    TargetPlatform.linux,
  ]) {
    testWidgets('counter increments on ${platform.name}', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      final dir = Directory.systemTemp.createTempSync('starter_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final services = (await tester.runAsync(
        () => ShellServices.create(starterConfig, root: dir),
      ))!;
      await tester.pumpWidget(
        ShellApp(services: services, home: (_) => const HomePage()),
      );

      expect(find.text('Running on ${platformName(platform)}'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();

      expect(find.text('1'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
