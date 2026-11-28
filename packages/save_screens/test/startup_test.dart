import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
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
}
