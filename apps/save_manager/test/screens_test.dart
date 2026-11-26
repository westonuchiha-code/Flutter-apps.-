// The screens over the real controller and a temp folder of made-up
// cards: list -> open -> options -> copy -> back, by touch and by keys, at
// the PC's 1920×1080, the Retroid's ~450×390 and a phone's 390×844 (an
// overflow anywhere fails the test).
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:save_manager/src/controller.dart';
import 'package:save_manager/src/flow.dart';
import 'package:save_manager/src/state.dart';
import 'package:save_manager/src/ui/screen.dart';

import 'screen_fixtures.dart';

const sizes = {
  'pc': (Size(1920, 1080), 1.0),
  'retroid': (Size(1240 / 2.75, 1080 / 2.75), 2.75),
  'phone': (Size(390, 844), 3.0),
};

void main() {
  late Directory temp;
  late SaveManagerController c;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('save_manager_screens');
    makeCards(temp.path);
    c = SaveManagerController(testConfig(temp.path), runner: runNow);
  });
  tearDown(() {
    c.dispose();
    temp.deleteSync(recursive: true);
  });

  Future<void> show(WidgetTester tester, String size, {bool? hints}) async {
    final (dp, dpr) = sizes[size]!;
    setView(tester, dp, dpr: dpr);
    await tester.pumpWidget(
      host(SaveManagerScreen(controller: c, showHints: hints)),
    );
    await c.settled();
    // a few frames: the scrollers ease to the selected save and card
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> done(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    tester.view.reset();
  }

  for (final size in sizes.keys) {
    testWidgets('list -> open -> options -> copy -> back by touch ($size)', (
      tester,
    ) async {
      await show(tester, size);
      expect(c.state.allSaves.length, 9);
      expect(c.state.mode, Mode.list);
      // the grid's columns are what's on screen
      expect(c.state.cols, size == 'pc' ? 5 : lessThan(6));

      // a tap on another save stands on it, a second tap opens it
      await tester.tap(find.byKey(const ValueKey('save-1')));
      await tester.pump();
      expect(c.state.index, 1);
      expect(c.state.mode, Mode.list);
      await tester.tap(find.byKey(const ValueKey('save-1')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(c.state.mode, Mode.opened);
      expect(find.text('THIS SAVE'), findsOneWidget);
      expect(find.text('THE GAME'), findsOneWidget);
      expect(find.byKey(const ValueKey('page-button-0')), findsOneWidget);

      // B back to the list, long press for the options
      await press(tester, LogicalKeyboardKey.escape);
      expect(c.state.mode, Mode.list);
      await tester.longPress(find.byKey(const ValueKey('save-1')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(c.state.mode, Mode.options);
      final copy = c.state.flatOptions().indexWhere((o) => o.verb == 'copy');
      final move = c.state.flatOptions().indexWhere((o) => o.verb == 'move');
      await tester.tap(find.byKey(ValueKey('option-$move')));
      await tester.pump();
      expect(c.state.option, move, reason: 'a tap highlights');
      expect(c.flow.isOpen(), isFalse);
      await tester.tap(find.byKey(ValueKey('option-$copy')));
      await tester.pump();
      expect(c.state.option, copy);
      await tester.tap(find.byKey(ValueKey('option-$copy')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(c.flow.kind, FlowKind.copy);
      expect(find.byKey(const ValueKey('copy-button-0')), findsOneWidget);

      // B leaves the copy screen, B again leaves the options
      await press(tester, LogicalKeyboardKey.escape);
      expect(c.flow.isOpen(), isFalse);
      await press(tester, LogicalKeyboardKey.escape);
      expect(c.state.mode, Mode.list);
      await done(tester);
    });

    testWidgets('card page, customize, pick, ask ($size)', (tester) async {
      await show(tester, size);
      // the column keeps the selected save's card in sight
      final mine = c.state.column().indexOf(c.state.current()!.card!);
      await tester.tap(find.byKey(ValueKey('card-$mine')));
      await tester.pump();
      expect(c.state.cardI, mine);
      await tester.tap(find.byKey(ValueKey('card-$mine')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(c.state.mode, Mode.card);
      expect(find.text('THIS CARD'), findsOneWidget);
      // CUSTOMIZE
      await tester.tap(find.byKey(const ValueKey('page-button-0')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(c.flow.kind, FlowKind.look);
      expect(find.byKey(const ValueKey('look-3')), findsOneWidget);
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.escape);
      expect(c.flow.isOpen(), isFalse);
      // Y: the card's options; More... -> Check asks which card? no: it's
      // this card's, so it runs; Delete card asks, safe answer first
      await press(tester, LogicalKeyboardKey.keyY);
      expect(c.state.mode, Mode.options);
      final del = c.state.flatOptions().indexWhere(
        (o) => o.verb == 'delete_card',
      );
      c.selectOption(del);
      await press(tester, LogicalKeyboardKey.enter);
      expect(c.flow.kind, FlowKind.ask);
      expect(c.flow.items[c.flow.index].label, 'KEEP IT');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('ask-1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ask-0'))); // KEEP IT
      await tester.pump(const Duration(milliseconds: 100));
      expect(c.flow.isOpen(), isFalse);
      for (var i = 0; i < 3 && c.state.mode != Mode.list; i++) {
        await press(tester, LogicalKeyboardKey.escape);
      }
      expect(c.state.mode, Mode.list);
      // a picker: Undelete from a save's card page asks nothing; from the
      // list's options More... "Bring back a deleted card" lists none
      c.selectSave(0);
      c.confirm(); // open it
      await tester.pump(const Duration(milliseconds: 100));
      c.selectPageButton(3); // DELETE
      c.confirm();
      await tester.pump(const Duration(milliseconds: 100));
      expect(c.flow.kind, FlowKind.ask);
      expect(find.byKey(const ValueKey('ask-0')), findsOneWidget);
      await press(tester, LogicalKeyboardKey.escape);
      // the format picker
      c.flow.begin('format', c.state.cards, [], null);
      c.showNotice('picker');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('pick-0')), findsOneWidget);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(c.flow.index, 1);
      await press(tester, LogicalKeyboardKey.escape);
      await done(tester);
    });
  }

  testWidgets('keys: d-pad steps the grid as drawn, X marks, F stars', (
    tester,
  ) async {
    await show(tester, 'phone', hints: true);
    final cols = c.state.cols;
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(c.state.index, cols, reason: 'down = one visible row');
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(c.state.index, cols + 1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyX);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyX);
    await tester.pump();
    expect(c.state.marks.length, 1, reason: 'a short X marks one');
    // hold X: every save of that game
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyX);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyX);
    await tester.pump();
    expect(c.notice, contains('marked from that game'));
    await press(tester, LogicalKeyboardKey.escape); // unmark all
    expect(c.state.marks, isEmpty);
    await press(tester, LogicalKeyboardKey.keyF);
    expect(c.state.current()!.favorite, isTrue);
    expect(find.byKey(const ValueKey('notice')), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(c.notice, isEmpty, reason: 'notices go after ~4 s');
    await press(tester, LogicalKeyboardKey.pageDown);
    expect(c.state.filter, 1);
    await done(tester);
  });

  testWidgets('rename asks for the name', (tester) async {
    await show(tester, 'retroid');
    c.selectCard(0);
    c.confirm();
    c.selectPageButton(1); // RENAME
    c.confirm();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('rename-field')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('rename-field')),
      'Daily card',
    );
    await tester.tap(find.byKey(const ValueKey('rename-ok')));
    await tester.pump(const Duration(milliseconds: 300));
    await c.settled();
    await tester.pump();
    expect(c.state.cards.any((k) => k.name == 'Daily card'), isTrue);
    await done(tester);
  });

  testWidgets('Android: a job that changes a card asks about the emulators', (
    tester,
  ) async {
    c.dispose();
    final check = EmulatorCheck();
    c = SaveManagerController(
      SaveManagerConfig(
        cardDirs: testConfig(temp.path).cardDirs,
        backupRoot: testConfig(temp.path).backupRoot,
        exportDir: testConfig(temp.path).exportDir,
        namesFile: testConfig(temp.path).namesFile,
        looksFile: testConfig(temp.path).looksFile,
        testRoots: [temp.path],
        running: check.running,
        utcOffset: 0,
      ),
      runner: runNow,
      check: check,
    );
    await show(tester, 'retroid');
    final before = c.state.allSaves.length;
    c.selectListButton(0); // COPY
    c.confirm();
    expect(c.flow.kind, FlowKind.copy);
    c.confirm(); // COPY on the copy screen
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.asking, isNotNull);
    expect(c.asking!.lines.first, startsWith('Close '));
    expect(find.byKey(const ValueKey('ask-0')), findsOneWidget);
    expect(c.asking!.index, 0, reason: 'NOT YET comes first');
    await tester.tap(find.byKey(const ValueKey('ask-0')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.asking, isNull);
    expect(c.flow.isOpen(), isFalse);
    expect(c.notice, startsWith('Nothing was changed'));
    // again, yes this time: it copies, and the yes counts for a while
    c.selectListButton(0);
    c.confirm();
    c.confirm();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('ask-1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ask-1')));
    await c.settled();
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.notice, startsWith('Copied'));
    expect(c.state.allSaves.length, before + 1);
    expect(check.fresh, isTrue);
    c.selectListButton(0);
    c.confirm();
    c.confirm();
    expect(c.asking, isNull, reason: 'a fresh yes is not asked again');
    await c.settled();
    await done(tester);
  });
}
