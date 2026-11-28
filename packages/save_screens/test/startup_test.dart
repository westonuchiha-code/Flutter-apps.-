import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:save_screens/save_screens.dart';

import 'screen_fixtures.dart';

void main() {
  testWidgets('a start-up that fails says why instead of a blank screen', (
    tester,
  ) async {
    var left = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SaveManagerHome(
          makeConfig: (extra, check) async =>
              throw const FormatException('no storage here'),
          runner: runNow,
          onLeave: () => left = true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.textContaining("couldn't start"), findsOneWidget);
    expect(find.textContaining('no storage here'), findsOneWidget);
    await tester.tap(find.text('Back'));
    expect(left, isTrue);
  });

  testWidgets('Try again starts it again (it used to hang on the check)', (
    tester,
  ) async {
    final temp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('retry'),
    );
    Directory(p.join(temp!.path, 'cards')).createSync();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SaveManagerHome(
          makeConfig: (extra, check) async {
            calls++;
            if (calls == 1) throw const FileSystemException('denied');
            return testConfig(temp.path);
          },
          runner: runNow,
          onLeave: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.textContaining("couldn't start"), findsOneWidget);
    await tester.tap(find.text('Try again'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(calls, 2);
    expect(find.byType(SaveManagerScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    temp.deleteSync(recursive: true);
  });
}
