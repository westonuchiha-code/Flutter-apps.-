import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scan_ranch/main.dart';
import 'package:scan_ranch/model/game_state.dart';

void main() {
  testWidgets('scan by typing a code, name it, see it in the box', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = GameState(MemorySaveStore(), random: math.Random(1));
    await tester.pumpWidget(
      ScanRanchApp(
        game: game,
        scanner: (context, onCode) => const ColoredBox(color: Colors.black),
      ),
    );
    await tester.pump();
    expect(find.text('Your ranch is empty.'), findsOneWidget);

    // Find a barcode that holds a creature.
    var code = 700000000000;
    while (GameState(MemorySaveStore()).scan('$code') is! CreatureFound) {
      code++;
    }

    await tester.tap(find.text('Scan').last);
    await tester.pump();
    await tester.tap(find.text('Type a code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '$code');
    await tester.tap(find.widgetWithText(FilledButton, 'Scan'));
    await tester.pumpAndSettle();
    expect(find.textContaining('appeared!'), findsOneWidget);

    await tester.tap(find.textContaining('Keep'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Gnash');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(game.creatures.single.name, 'Gnash');

    await tester.tap(find.text('Box'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Gnash'), findsOneWidget);
  });
}
