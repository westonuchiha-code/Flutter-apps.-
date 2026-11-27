import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pad_input/pad_input.dart';

import 'fakes.dart';

void main() {
  late FakeSource source;
  late FakeClock clock;
  late List<PadButton> presses;
  late List<PadButton> releases;
  late bool active;
  late int changes;
  late int quits;
  late GamepadInput pad;

  setUp(() {
    source = FakeSource();
    clock = FakeClock();
    presses = [];
    releases = [];
    active = true;
    changes = 0;
    quits = 0;
    pad = GamepadInput(
      onButton: presses.add,
      onRelease: releases.add,
      isActive: () => active,
      onChanged: () => changes++,
      onQuitHold: () => quits++,
      sources: [source],
      clock: clock.call,
    )..start();
  });

  tearDown(() => pad.stop());

  /// One tick of the poller, [GamepadInput.tick] after the last.
  void tick([int n = 1]) {
    for (var i = 0; i < n; i++) {
      clock.advance(GamepadInput.tick);
      pad.poll();
    }
  }

  test('a button fires once per press, and its release is passed on', () {
    expect(source.opened, isTrue);
    expect(pad.polling, isTrue);
    source.held = {PadButton.south};
    tick(20);
    expect(presses, [PadButton.south], reason: 'held buttons do not repeat');
    expect(releases, isEmpty);
    source.held = {};
    tick();
    expect(releases, [PadButton.south]);
    source.held = {PadButton.south};
    tick();
    expect(presses, [PadButton.south, PadButton.south]);
  });

  test('a held direction repeats after 450 ms, then every 220 ms', () {
    source.held = {PadButton.down};
    tick(); // t = 0: the press
    expect(presses, [PadButton.down]);
    // 450 ms later (9 ticks) the first repeat.
    tick(8);
    expect(presses.length, 1);
    tick();
    expect(presses.length, 2);
    // Then every 220 ms: the tick at or after it (5 ticks = 250 ms).
    tick(4);
    expect(presses.length, 2);
    tick();
    expect(presses.length, 3);
    // Letting go and pressing again starts over.
    source.held = {};
    tick();
    source.held = {PadButton.down};
    tick();
    expect(presses.length, 4);
    expect(releases, isEmpty, reason: 'directions have no release');
  });

  test('changing direction fires the new one at once', () {
    source.held = {PadButton.left};
    tick();
    source.held = {PadButton.right};
    tick();
    expect(presses, [PadButton.left, PadButton.right]);
  });

  test('only one direction at a time, in up/down/left/right order', () {
    source.held = {PadButton.right, PadButton.up, PadButton.south};
    tick();
    expect(presses.toSet(), {PadButton.up, PadButton.south});
  });

  test('nothing is passed on while the app is not in front', () {
    active = false;
    source.held = {PadButton.south, PadButton.up};
    tick(30);
    expect(presses, isEmpty);
    active = true;
    tick(2);
    expect(
      presses,
      isEmpty,
      reason: 'a button already held when coming back does not fire',
    );
  });

  test('Select + Start held for 1.5 s asks to quit, once', () {
    source.held = {PadButton.select, PadButton.start};
    tick(30); // 1.45 s after the first tick
    expect(quits, 0);
    tick();
    expect(quits, 1);
    tick(40);
    expect(quits, 1);
    source.held = {};
    tick();
    source.held = {PadButton.select, PadButton.start};
    tick(32);
    expect(quits, 2);
  });

  test('what is plugged in is counted about once a second', () {
    source.sony = 1;
    tick(); // the first tick rescans
    expect(pad.connected, 1);
    expect(pad.kind, PadKind.playstation);
    expect(changes, 1);
    source
      ..sony = 0
      ..others = 2;
    tick(19);
    expect(pad.connected, 1, reason: 'not rescanned yet');
    tick();
    expect(pad.connected, 2);
    expect(pad.kind, PadKind.xbox);
    expect(changes, 2);
    expect(source.rescans, 2);
  });

  test('the kind follows the pad last touched', () {
    source
      ..sony = 1
      ..others = 1;
    tick();
    expect(pad.kind, PadKind.xbox, reason: 'both plugged in: unchanged');
    source
      ..kind = PadKind.playstation
      ..held = {PadButton.east};
    tick();
    expect(pad.kind, PadKind.playstation);
    expect(changes, 2);
  });

  test('without a usable source nothing is polled', () {
    final none = FakeSource(available: false);
    final idle = GamepadInput(
      onButton: (_) {},
      isActive: () => true,
      sources: [none],
    )..start();
    expect(idle.polling, isFalse);
    idle.stop();
    expect(none.closed, isFalse, reason: 'never opened, never closed');
    pad.stop();
    expect(source.closed, isTrue);
  });

  test('no hardware is read under flutter test', () {
    expect(GamepadInput.platformSources(), isEmpty);
  });

  group('Windows joystick state', () {
    const centre = 32767;
    test('buttons follow the PlayStation / generic order', () {
      expect(
        WindowsPadSource.joystickPressed(
          buttons: 0x1 | 0x2 | 0x200,
          pov: 0xFFFF,
          x: centre,
          y: centre,
        ),
        {PadButton.west, PadButton.south, PadButton.start},
      );
    });

    test('the hat gives the nearest direction, before the stick', () {
      Set<PadButton> at(int pov) => WindowsPadSource.joystickPressed(
        buttons: 0,
        pov: pov,
        x: 65535,
        y: centre,
      );
      expect(at(0), {PadButton.up});
      expect(at(4000), {PadButton.up});
      expect(at(9000), {PadButton.right});
      expect(at(18000), {PadButton.down});
      expect(at(27000), {PadButton.left});
      expect(at(31600), {PadButton.up});
    });

    test('the stick: up is the low end, with a dead zone', () {
      Set<PadButton> stick(int x, int y) =>
          WindowsPadSource.joystickPressed(buttons: 0, pov: 0xFFFF, x: x, y: y);
      expect(stick(centre, 0), {PadButton.up});
      expect(stick(centre, 65535), {PadButton.down});
      expect(stick(0, centre), {PadButton.left});
      expect(stick(centre + 10000, centre - 10000), isEmpty);
    });

    test('fromStick: y grows upward, the bigger axis wins', () {
      expect(fromStick(0, 20000, 16000), PadButton.up);
      expect(fromStick(30000, -20000, 16000), PadButton.right);
      expect(fromStick(-15000, 15000, 16000), isNull);
    });
  });

  group('PadKeys', () {
    KeyEvent down(LogicalKeyboardKey key, int ms) => KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.arrowDown,
      logicalKey: key,
      timeStamp: Duration(milliseconds: ms),
    );
    KeyEvent repeat(LogicalKeyboardKey key, int ms) => KeyRepeatEvent(
      physicalKey: PhysicalKeyboardKey.arrowDown,
      logicalKey: key,
      timeStamp: Duration(milliseconds: ms),
    );
    KeyEvent up(LogicalKeyboardKey key, int ms) => KeyUpEvent(
      physicalKey: PhysicalKeyboardKey.arrowDown,
      logicalKey: key,
      timeStamp: Duration(milliseconds: ms),
    );

    test('game buttons are pad buttons everywhere, arrows only on Android', () {
      final desktop = PadKeys(android: false);
      final android = PadKeys(android: true);
      expect(
        desktop.buttonFor(LogicalKeyboardKey.gameButtonA),
        PadButton.south,
      );
      expect(desktop.buttonFor(LogicalKeyboardKey.gameButtonB), PadButton.east);
      expect(
        desktop.buttonFor(LogicalKeyboardKey.gameButtonRight2),
        PadButton.r2,
      );
      expect(desktop.buttonFor(LogicalKeyboardKey.arrowUp), isNull);
      expect(android.buttonFor(LogicalKeyboardKey.arrowUp), PadButton.up);
      expect(android.buttonFor(LogicalKeyboardKey.select), PadButton.south);
      expect(android.buttonFor(LogicalKeyboardKey.keyA), isNull);
    });

    test('a held d-pad repeats at the pad pace, not the key repeat', () {
      final keys = PadKeys(android: true);
      const k = LogicalKeyboardKey.arrowDown;
      expect(keys.read(down(k, 0)), (button: PadButton.down, fire: true));
      expect(keys.read(repeat(k, 50))!.fire, isFalse);
      expect(keys.read(repeat(k, 449))!.fire, isFalse);
      expect(keys.read(repeat(k, 450))!.fire, isTrue);
      expect(keys.read(repeat(k, 600))!.fire, isFalse);
      expect(keys.read(repeat(k, 670))!.fire, isTrue);
      expect(keys.read(up(k, 700))!.fire, isFalse);
    });

    test('other held buttons never repeat', () {
      final keys = PadKeys(android: true);
      const k = LogicalKeyboardKey.gameButtonX;
      expect(keys.read(down(k, 0))!.fire, isTrue);
      expect(keys.read(repeat(k, 1000))!.fire, isFalse);
      expect(keys.read(up(k, 1100)), (button: PadButton.west, fire: false));
    });
  });

  test('labels follow the controller kind', () {
    expect(padLabel(PadButton.south, PadKind.xbox), 'A');
    expect(padLabel(PadButton.south, PadKind.playstation), '✕');
    expect(padLabel(PadButton.r2, PadKind.xbox), 'RT');
    expect(padLabel(PadButton.l1, PadKind.playstation), 'L1');
  });
}
