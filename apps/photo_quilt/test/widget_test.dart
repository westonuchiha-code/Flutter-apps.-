import 'dart:io';

import 'package:app_shell/app_shell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photo_quilt/main.dart';
import 'package:photo_quilt/src/quilt.dart';
import 'package:photo_quilt/src/ui/home.dart';
import 'package:photo_quilt/src/work.dart';

import 'support.dart';

void main() {
  test('a landscape makes a quilt with mixed blocks', () {
    final p = landscape();
    final palette = photoPalette((p, 10));
    expect(palette.length, lessThanOrEqualTo(10));
    final (q, pic) = buildQuilt((
      p,
      QuiltSettings(columns: 24, palette: palette),
    ));
    expect(q.rows, 16);
    expect(q.counts.length, greaterThan(1));
    expect(pic.width, 24 * 24 + 1);
    expect(encodePng(pic).length, greaterThan(1000));
  });

  testWidgets('empty page, then a quilt with its controls', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('quilt_ui');
    addTearDown(() => dir.deleteSync(recursive: true));
    final services = (await tester.runAsync(
      () => ShellServices.create(appConfig, root: dir),
    ))!;
    await tester.pumpWidget(
      ShellApp(services: services, home: (_) => const HomePage()),
    );
    expect(find.text('Open a photo'), findsOneWidget);
    await tester.pumpWidget(
      ShellApp(
        services: services,
        home: (_) => HomePage(key: const Key('q'), photo: landscape()),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(find.text('Fabric colours'), findsOneWidget);
    expect(find.textContaining('patches'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
