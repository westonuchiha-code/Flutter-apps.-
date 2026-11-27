import 'package:crt_tv/src/gamepad.dart';
import 'package:flutter_test/flutter_test.dart';

/// One raw Linux joystick event: time, value, type, number.
List<int> event(int value, int type, int number) {
  final v = value & 0xFFFF;
  return [0, 0, 0, 0, v & 0xFF, v >> 8, type, number];
}

void main() {
  test(
    'button and axis events build up the pad state, even split across reads',
    () {
      final buttons = <int>{};
      final axes = <int, int>{};
      final pending = <int>[];
      final bytes = [
        ...event(1, 0x81, 0), // starting state: button 0 held
        ...event(-32767, 0x82, 1), // starting state: stick up
        ...event(1, 1, 3),
      ];
      applyJsEvents(bytes.sublist(0, 11), pending, buttons, axes);
      expect(buttons, {0});
      expect(pending.length, 3, reason: 'half an event waits for the rest');
      applyJsEvents(bytes.sublist(11), pending, buttons, axes);
      expect(buttons, {0, 3});
      expect(axes, {1: -32767});
      expect(pending, isEmpty);
      applyJsEvents(event(0, 1, 0), pending, buttons, axes);
      expect(buttons, {3});
    },
  );

  test('Xbox-style layout', () {
    expect(linuxPadPressed({0, 1, 2, 3}, {}, sony: false), {
      PadButton.south,
      PadButton.east,
      PadButton.west,
      PadButton.north,
    });
    expect(linuxPadPressed({4, 5, 6, 7, 10}, {}, sony: false), {
      PadButton.l1,
      PadButton.r1,
      PadButton.select,
      PadButton.start,
      PadButton.r3,
    });
    // Triggers are axes that rest fully low.
    expect(linuxPadPressed({}, {2: -32767, 5: 32767}, sony: false), {
      PadButton.r2,
    });
    expect(linuxPadPressed({}, {}, sony: false), isEmpty);
  });

  test(
    'PlayStation layout swaps triangle and square and has trigger buttons',
    () {
      expect(linuxPadPressed({2}, {}, sony: true), {PadButton.north});
      expect(linuxPadPressed({3}, {}, sony: true), {PadButton.west});
      expect(linuxPadPressed({6, 7, 8, 9, 12}, {2: 32767}, sony: true), {
        PadButton.l2,
        PadButton.r2,
        PadButton.select,
        PadButton.start,
        PadButton.r3,
      });
    },
  );

  test('the controller kind is known from what is plugged in', () {
    expect(kindFromConnected(sony: 1, others: 0), PadKind.playstation);
    expect(kindFromConnected(sony: 0, others: 2), PadKind.xbox);
    expect(
      kindFromConnected(sony: 1, others: 1),
      isNull,
      reason: 'both kinds: go by the one last touched',
    );
    expect(
      kindFromConnected(sony: 0, others: 0),
      isNull,
      reason: 'nothing plugged in: keep what was shown',
    );
  });

  test('d-pad and stick give one direction, d-pad first', () {
    expect(linuxPadPressed({}, {7: -32767}, sony: true), {PadButton.up});
    expect(linuxPadPressed({}, {6: 32767}, sony: true), {PadButton.right});
    expect(linuxPadPressed({}, {1: 32767}, sony: false), {PadButton.down});
    expect(linuxPadPressed({}, {0: -32767}, sony: false), {PadButton.left});
    expect(
      linuxPadPressed({}, {0: 5000, 1: -4000}, sony: false),
      isEmpty,
      reason: 'dead zone',
    );
    expect(linuxPadPressed({}, {6: -32767, 1: 32767}, sony: false), {
      PadButton.left,
    });
  });
}
