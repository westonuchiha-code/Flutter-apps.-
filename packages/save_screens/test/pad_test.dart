// A controller read by pad_input (XInput on Windows, /dev/input/js* on
// Linux) drives the screens through the same path as the keyboard and
// Android's controller keys: a fake source, no hardware.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pad_input/pad_input.dart';
import 'package:save_screens/src/controller.dart';
import 'package:save_screens/src/state.dart';
import 'package:save_screens/src/ui/screen.dart';

import 'screen_fixtures.dart';

class _FakePad implements PadSource {
  Set<PadButton> held = {};

  @override
  bool open() => true;

  @override
  PadKind? read(bool rescan, Set<PadButton> pressed) {
    pressed.addAll(held);
    return held.isEmpty ? null : PadKind.xbox;
  }

  @override
  ({int sony, int others}) count() => (sony: 0, others: 1);

  @override
  void close() {}
}

void main() {
  late Directory temp;
  late SaveManagerController c;
  late _FakePad pad;
  late PadInput input;
  var now = DateTime(2026);

  setUp(() {
    temp = Directory.systemTemp.createTempSync('save_manager_pad');
    makeCards(temp.path);
    c = SaveManagerController(testConfig(temp.path), runner: runNow);
    pad = _FakePad();
    input = PadInput(sources: [pad], clock: () => now, isActive: () => true);
    PadInput.instance = input;
  });
  tearDown(() {
    PadInput.instance = null;
    c.dispose();
    temp.deleteSync(recursive: true);
  });

  /// One read of the controller ([GamepadInput.tick] later).
  Future<void> tick(WidgetTester tester) async {
    now = now.add(GamepadInput.tick);
    input.reader!.poll();
    await tester.pump(GamepadInput.tick);
  }

  /// Presses and lets go of [button].
  Future<void> push(WidgetTester tester, PadButton button) async {
    pad.held = {button};
    await tick(tester);
    pad.held = {};
    await tick(tester);
  }

  Future<void> show(WidgetTester tester) async {
    setView(tester, const Size(390, 844), dpr: 3);
    await tester.pumpWidget(host(SaveManagerScreen(controller: c)));
    await c.settled();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> done(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    tester.view.reset();
    expect(input.reader, isNull, reason: 'the pad is let go with the screen');
  }

  testWidgets('d-pad steps, X marks (held: the game), B, RT, RB', (
    tester,
  ) async {
    await show(tester);
    expect(input.polling, isTrue);
    final cols = c.state.cols;
    await push(tester, PadButton.down);
    expect(c.state.index, cols, reason: 'down = one visible row');
    await push(tester, PadButton.right);
    expect(c.state.index, cols + 1);

    await push(tester, PadButton.west);
    expect(c.state.marks.length, 1, reason: 'a short X marks one');
    // hold X: every save of that game
    pad.held = {PadButton.west};
    await tick(tester);
    await tester.pump(const Duration(milliseconds: 600));
    pad.held = {};
    await tick(tester);
    expect(c.notice, contains('marked from that game'));
    await push(tester, PadButton.east); // unmark all
    expect(c.state.marks, isEmpty);

    await push(tester, PadButton.r2);
    expect(c.state.current()!.favorite, isTrue);
    await tester.pump(const Duration(seconds: 5));
    await push(tester, PadButton.r1);
    expect(c.state.filter, 1);
    await push(tester, PadButton.l1);
    expect(c.state.filter, 0);
    await done(tester);
  });

  testWidgets('A opens, Y the options, B back; a held d-pad repeats', (
    tester,
  ) async {
    await show(tester);
    await push(tester, PadButton.south);
    expect(c.state.mode, Mode.opened);
    await push(tester, PadButton.east);
    expect(c.state.mode, Mode.list);
    await push(tester, PadButton.north);
    expect(c.state.mode, Mode.options);
    await push(tester, PadButton.east);
    expect(c.state.mode, Mode.list);

    // Held right: one step, then repeats after 450 ms.
    final start = c.state.index;
    pad.held = {PadButton.right};
    await tick(tester);
    expect(c.state.index, start + 1);
    for (var i = 0; i < 9; i++) {
      await tick(tester);
    }
    expect(c.state.index, start + 2);
    pad.held = {};
    await tick(tester);
    await done(tester);
  });

  testWidgets('keys and controller keys still go the same way', (tester) async {
    await show(tester);
    await press(tester, LogicalKeyboardKey.gameButtonA);
    expect(c.state.mode, Mode.opened);
    await press(tester, LogicalKeyboardKey.gameButtonB);
    expect(c.state.mode, Mode.list);
    await press(tester, LogicalKeyboardKey.gameButtonY);
    expect(c.state.mode, Mode.options);
    await press(tester, LogicalKeyboardKey.escape);
    expect(c.state.mode, Mode.list);
    await done(tester);
  });

  testWidgets('a page on top takes the controller away', (tester) async {
    await show(tester);
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('x'))),
    );
    await tester.pump(const Duration(seconds: 1));
    final before = c.state.index;
    await push(tester, PadButton.right);
    expect(c.state.index, before);
    nav.pop();
    await tester.pump(const Duration(seconds: 1));
    await push(tester, PadButton.right);
    expect(c.state.index, before + 1);
    await done(tester);
  });
}
