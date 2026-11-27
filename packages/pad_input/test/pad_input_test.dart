import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pad_input/pad_input.dart';

import 'fakes.dart';

void main() {
  late FakeSource source;
  late FakeClock clock;
  late PadInput input;

  setUp(() {
    source = FakeSource();
    clock = FakeClock();
    input = PadInput(
      sources: [source],
      clock: clock.call,
      isActive: () => true,
    );
  });

  void tick([int n = 1]) {
    for (var i = 0; i < n; i++) {
      clock.advance(GamepadInput.tick);
      input.reader!.poll();
    }
  }

  void press(PadButton b) {
    source.held = {b};
    tick();
    source.held = {};
    tick();
  }

  group('PadInput', () {
    test('reads only while something is attached', () {
      expect(input.reader, isNull);
      final h = input.attach(onButton: (_) {});
      expect(input.polling, isTrue);
      h.detach();
      expect(input.reader, isNull);
      expect(source.closed, isTrue);
    });

    test('the newest enabled handle gets the buttons', () {
      final older = <PadButton>[], newer = <PadButton>[];
      var newerOn = true;
      final a = input.attach(onButton: older.add);
      final b = input.attach(onButton: newer.add, enabled: () => newerOn);
      press(PadButton.south);
      expect(older, isEmpty);
      expect(newer, [PadButton.south]);
      newerOn = false;
      press(PadButton.east);
      expect(older, [PadButton.east]);
      expect(newer, [PadButton.south]);
      b.detach();
      newerOn = true;
      press(PadButton.north);
      expect(older, [PadButton.east, PadButton.north]);
      a.detach();
    });

    test('a release goes to the handle that had the press', () {
      final firstUp = <PadButton>[], secondUp = <PadButton>[];
      final a = input.attach(onButton: (_) {}, onRelease: firstUp.add);
      source.held = {PadButton.west};
      tick();
      final b = input.attach(onButton: (_) {}, onRelease: secondUp.add);
      source.held = {};
      tick();
      expect(firstUp, [PadButton.west]);
      expect(secondUp, isEmpty);
      b.detach();
      a.detach();
    });

    test('plugging in and first use are announced', () {
      var notes = 0;
      input.addListener(() => notes++);
      final h = input.attach(onButton: (_) {});
      expect(input.hasPad, isFalse);
      source.others = 1;
      tick(21); // the next rescan
      expect(input.hasPad, isTrue);
      expect(input.connected, 1);
      expect(notes, 1);
      expect(input.used, isFalse);
      press(PadButton.start);
      expect(input.used, isTrue);
      expect(notes, 2);
      h.detach();
    });
  });

  group('PadListener', () {
    tearDown(() => PadInput.instance = null);

    Widget app(Widget child) => WidgetsApp(
      color: const Color(0xFF000000),
      onGenerateRoute: (settings) =>
          PageRouteBuilder<void>(pageBuilder: (_, _, _) => child),
    );

    testWidgets('controller buttons reach onButton while on top', (
      tester,
    ) async {
      PadInput.instance = input;
      final got = <PadButton>[], up = <PadButton>[];
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        WidgetsApp(
          navigatorKey: nav,
          color: const Color(0xFF000000),
          onGenerateRoute: (_) => PageRouteBuilder<void>(
            pageBuilder: (_, _, _) => PadListener(
              onButton: got.add,
              onRelease: up.add,
              child: const SizedBox(),
            ),
          ),
        ),
      );
      press(PadButton.south);
      expect(got, [PadButton.south]);
      expect(up, [PadButton.south]);

      // A page on top: the listener underneath hears nothing.
      nav.currentState!.push(
        PageRouteBuilder<void>(pageBuilder: (_, _, _) => const SizedBox()),
      );
      await tester.pumpAndSettle();
      press(PadButton.east);
      expect(got, [PadButton.south]);
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      press(PadButton.east);
      expect(got, [PadButton.south, PadButton.east]);

      await tester.pumpWidget(const SizedBox());
      expect(input.reader, isNull, reason: 'detached when it goes');
    });

    testWidgets('disabled, it lets buttons go by', (tester) async {
      PadInput.instance = input;
      final got = <PadButton>[];
      await tester.pumpWidget(
        app(
          PadListener(
            onButton: got.add,
            enabled: false,
            child: const SizedBox(),
          ),
        ),
      );
      press(PadButton.south);
      expect(got, isEmpty);
    });

    testWidgets('on Android it reads the controller key events', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      PadInput.instance = input;
      final got = <PadButton>[], up = <PadButton>[];
      final focus = FocusNode();
      await tester.pumpWidget(
        app(
          PadListener(
            onButton: got.add,
            onRelease: up.add,
            child: Focus(focusNode: focus, autofocus: true, child: Container()),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      expect(got, [PadButton.south, PadButton.down]);
      expect(up, [PadButton.south]);
      // A keyboard letter is not a controller key.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      expect(got.length, 2);
      focus.dispose();
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
