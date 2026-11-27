import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:save_kit/save_kit.dart';
import 'package:save_screens/save_screens.dart';

import 'screen_fixtures.dart';

void main() {
  testWidgets('a host with no library: Start game hands over the save', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('start_save');
    addTearDown(() => dir.deleteSync(recursive: true));
    makeCards(dir.path);
    final asked = <CardSave>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SaveManagerHome(
          makeConfig: (extra, check) async => testConfig(dir.path),
          runner: runNow,
          showHints: false,
          startSystems: const {'PS1'},
          onStartSave: (s) async {
            asked.add(s);
            return 'Handed to the XMB';
          },
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final screen = tester.widget<SaveManagerScreen>(
      find.byType(SaveManagerScreen),
    );
    final c = screen.controller;
    final ps1 = c.state.saves.where((s) => s.system == 'PS1').toList();
    final ps2 = c.state.saves.where((s) => s.system == 'PS2').toList();
    expect(ps1, isNotEmpty);
    expect(ps2, isNotEmpty);
    // PS1 saves offer Start game; PS2 (not in startSystems) don't.
    bool offers(CardSave s) => c.state
        .optionsForSave(s, false)
        .expand((g) => g.items)
        .any((o) => o.verb == 'start');
    expect(ps1.every(offers), isTrue);
    expect(ps2.any(offers), isFalse);
    screen.onGame!(ps1.first.gameId);
    await tester.pump();
    expect(asked, [ps1.first]);
    expect(c.notice, 'Handed to the XMB');
    await tester.pumpWidget(const SizedBox());
  });
}
