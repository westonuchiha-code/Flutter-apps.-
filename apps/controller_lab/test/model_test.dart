import 'package:controller_lab/src/android/android_backend.dart';
import 'package:controller_lab/src/layouts/layout.dart';
import 'package:controller_lab/src/layouts/raw.dart';
import 'package:controller_lab/src/layouts/standard.dart';
import 'package:controller_lab/src/layouts/wii_u_pro.dart';
import 'package:controller_lab/src/model/backend.dart';
import 'package:controller_lab/src/model/controls.dart';
import 'package:controller_lab/src/model/guess.dart';
import 'package:controller_lab/src/model/lab.dart';
import 'package:controller_lab/src/sdl/sdl_backend.dart';
import 'package:controller_lab/src/sdl/sdl_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_sdl.dart';

/// A backend that just reports an error (for the fallback test).
class _NoBackend extends PadBackend {
  @override
  String get title => 'none';
  @override
  String? get problem => 'SDL3 not found.';
  @override
  bool start() => false;
  @override
  bool poll() => false;
  @override
  List<PadDevice> get devices => const [];
  @override
  void dispose() {}
}

class _OnePad extends PadBackend {
  final pad = PadDevice(
    ControllerInfo(id: 9, name: 'Keys', source: 'k', isGamepad: true),
    PadState(),
  );
  bool _first = true;
  @override
  String get title => 'keys';
  @override
  String? get problem => null;
  @override
  bool start() => true;
  @override
  bool poll() {
    final f = _first;
    _first = false;
    return f;
  }

  @override
  List<PadDevice> get devices => [pad];
  @override
  void dispose() {}
}

void main() {
  group('SDL backend', () {
    test('sets the hints (Wii driver on) before init', () {
      final sdl = FakeSdl();
      final b = SdlBackend(sdl);
      expect(b.start(), isTrue);
      expect(sdl.hints!['SDL_JOYSTICK_HIDAPI_WII'], '1');
      expect(sdl.hints!['SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS'], '1');
      expect(sdl.hints!['SDL_JOYSTICK_ENHANCED_REPORTS'], '1');
      final off = FakeSdl();
      SdlBackend(off, hints: const SdlHints(wii: false)).start();
      expect(off.hints!['SDL_JOYSTICK_HIDAPI_WII'], '0');
    });

    test('no library or a failed init is reported', () {
      final missing = SdlBackend(null)..loadProblem = 'SDL3 not found.';
      expect(missing.start(), isFalse);
      expect(missing.problem, 'SDL3 not found.');
      final sdl = FakeSdl()..failInit = true;
      final b = SdlBackend(sdl);
      expect(b.start(), isFalse);
      expect(b.problem, contains('No joystick subsystem'));
    });

    test('hot-plug: connect, read, disconnect', () {
      final sdl = FakeSdl();
      final b = SdlBackend(sdl)..start();
      expect(b.poll(), isFalse);
      expect(b.devices, isEmpty);

      sdl.plug(FakeSdl.wiiUPro());
      expect(b.poll(), isTrue);
      expect(b.devices.single.info.name, 'Nintendo Wii U Pro Controller');
      expect(b.devices.single.info.vidPid, '057e:0330');
      expect(sdl.opened, {1});

      sdl.pads[1]!.down.add(GButton.east);
      expect(b.poll(), isFalse); // state changes aren't list changes
      expect(b.devices.single.state.button(GButton.east), isTrue);

      sdl.plug(FakePad(id: 2, name: 'Odd BT pad', mapped: false, buttons: 9));
      expect(b.poll(), isTrue);
      expect(b.devices, hasLength(2));

      sdl.unplug(1);
      expect(b.poll(), isTrue);
      expect(b.devices.single.info.id, 2);
      expect(sdl.opened, {2});

      b.dispose();
      expect(sdl.quitCalled, isTrue);
      expect(sdl.opened, isEmpty);
    });

    test('battery is re-read about once a second', () {
      final sdl = FakeSdl()..plug(FakeSdl.wiiUPro());
      final b = SdlBackend(sdl)..start();
      b.poll();
      sdl.pads[1]!.battery = 40;
      var changed = false;
      for (var i = 0; i < 60; i++) {
        changed |= b.poll();
      }
      expect(changed, isTrue);
      expect(b.devices.single.info.batteryPercent, 40);
    });

    test('rumble goes to the pad with 0..65535 strengths', () {
      final sdl = FakeSdl()..plug(FakeSdl.wiiUPro());
      final b = SdlBackend(sdl)..start();
      b.poll();
      expect(b.rumble(1, low: 1, high: 0.5, ms: 200), isTrue);
      expect(sdl.pads[1]!.rumbles.single, (65535, 32768, 200));
      expect(b.rumble(7), isFalse);
    });
  });

  group('layouts', () {
    test('the Wii U Pro gets its own drawing; others the generic ones', () {
      final sdl = FakeSdl()
        ..plug(FakeSdl.wiiUPro())
        ..plug(
          FakePad(
            id: 2,
            name: 'Xbox 360 Controller',
            type: GamepadType.xbox360,
          ),
        )
        ..plug(FakePad(id: 3, name: 'USB Joystick', mapped: false));
      final b = SdlBackend(sdl)..start();
      b.poll();
      final byId = {for (final d in b.devices) d.info.id: d.info};
      expect(layoutFor(byId[1]!), isA<WiiUProLayout>());
      expect(layoutFor(byId[2]!), isA<StandardPadLayout>());
      expect(layoutFor(byId[3]!), isA<RawLayout>());
    });

    test('Wii U Pro names', () {
      ControllerInfo named(String n) =>
          ControllerInfo(id: 1, name: n, source: 's', isGamepad: true);
      expect(isWiiUPro(named('Nintendo Wii U Pro Controller')), isTrue);
      expect(isWiiUPro(named('Nintendo RVL-CNT-01-UC')), isTrue);
      expect(isWiiUPro(named('Nintendo Wii Remote Pro Controller')), isTrue);
      expect(isWiiUPro(named('Nintendo Wii Remote')), isFalse);
      // Not mapped: the raw drawing (its buttons mean nothing yet).
      expect(
        layoutFor(
          ControllerInfo(id: 1, name: 'Nintendo RVL-CNT-01-UC', source: 's'),
        ),
        isA<RawLayout>(),
      );
    });

    test('Wii U Pro: Nintendo A is on the right (SDL east)', () {
      final parts = {
        for (final p in const WiiUProLayout().parts(
          ControllerInfo(id: 1, name: 'x', source: 's'),
        ))
          p.id: p,
      };
      expect(parts['a']!.button, GButton.east);
      expect(parts['b']!.button, GButton.south);
      expect(parts['x']!.button, GButton.north);
      expect(parts['y']!.button, GButton.west);
      expect(parts['minus']!.button, GButton.back);
      expect(parts['home']!.button, GButton.guide);
      expect(parts['zl']!.axis, GAxis.leftTrigger);
      expect(parts, hasLength(19));
    });

    test('button names follow the pad type', () {
      expect(buttonName(GButton.south, GamepadType.ps5), '✕');
      expect(buttonName(GButton.back, GamepadType.ps5), 'Create');
      expect(buttonName(GButton.east, GamepadType.switchPro), 'A');
      expect(buttonName(GButton.leftShoulder, GamepadType.xbox360), 'LB');
      expect(triggerName(GAxis.rightTrigger, GamepadType.ps3), 'R2');
      expect(
        buttonName(GButton.south, GamepadType.standard, const {
          GButton.south: ButtonLabel.cross,
        }),
        '✕',
      );
    });
  });

  group('lab and checklist', () {
    late FakeSdl sdl;
    late ControllerLab lab;
    setUp(() {
      sdl = FakeSdl()..plug(FakeSdl.wiiUPro());
      lab = ControllerLab(SdlBackend(sdl))..start();
    });
    tearDown(() => lab.dispose());

    test('pressing lights the drawn part and checks it off', () {
      final d = lab.devices.single;
      final s = lab.session(d);
      expect(s.layout, isA<WiiUProLayout>());
      expect(s.done, 0);
      final a = s.parts.firstWhere((p) => p.id == 'a');
      sdl.pads[1]!.down.add(GButton.east);
      lab.tick();
      expect(a.active(d.state), isTrue);
      expect(s.checked, contains('a'));
      expect(s.checked, isNot(contains('b')));
      sdl.pads[1]!.down.clear();
      lab.tick();
      expect(a.active(d.state), isFalse);
      expect(s.checked, contains('a')); // stays checked
    });

    test('a stick is checked once pushed all four ways', () {
      final s = lab.session(lab.devices.single);
      final p = sdl.pads[1]!;
      for (final (x, y) in [(0, -32768), (32767, 0), (0, 32767)]) {
        p.axis[GAxis.leftX] = x;
        p.axis[GAxis.leftY] = y;
        lab.tick();
      }
      expect(s.checked, isNot(contains('ls')));
      p.axis[GAxis.leftX] = -32768;
      p.axis[GAxis.leftY] = 0;
      lab.tick();
      expect(s.checked, contains('ls'));
      expect(s.sticks['ls']!.gate.where((g) => g > 0.9), hasLength(4));
    });

    test('every button checked', () {
      final s = lab.session(lab.devices.single);
      final p = sdl.pads[1]!;
      for (final b in GButton.values.take(15)) {
        p.down.add(b);
        lab.tick();
        p.down.remove(b);
      }
      p.axis[GAxis.leftTrigger] = 32767;
      p.axis[GAxis.rightTrigger] = 32767;
      lab.tick();
      for (final (ax, ay) in [
        (GAxis.leftX, GAxis.leftY),
        (GAxis.rightX, GAxis.rightY),
      ]) {
        for (final (x, y) in [
          (0, -32768),
          (32767, 0),
          (0, 32767),
          (-32768, 0),
        ]) {
          p.axis[ax] = x;
          p.axis[ay] = y;
          lab.tick();
        }
        p.axis[ax] = 0;
        p.axis[ay] = 0;
      }
      expect(s.complete, isTrue, reason: '${s.done}/${s.total}');
      lab.reset(lab.devices.single);
      expect(s.done, 0);
    });

    test('rest drift gives a deadzone suggestion', () {
      final s = lab.session(lab.devices.single);
      sdl.pads[1]!.axis[GAxis.leftX] = 1638; // 5% drift
      s.measureRest();
      for (var i = 0; i < 100; i++) {
        lab.tick();
      }
      final st = s.sticks['ls']!;
      expect(st.measuring, isFalse);
      expect(st.restDrift, closeTo(0.05, 0.001));
      expect(st.suggestedDeadzone, 0.09);
    });

    test('a battery change keeps the checklist', () {
      final d = lab.devices.single;
      sdl.pads[1]!.down.add(GButton.east);
      lab.tick();
      sdl.pads[1]!.battery = 10;
      sdl.event();
      lab.tick();
      expect(lab.session(lab.devices.single).checked, contains('a'));
      expect(lab.devices.single.state, same(d.state));
    });

    test('unplugging drops its session; replugging starts fresh', () {
      sdl.pads[1]!.down.add(GButton.east);
      lab.tick();
      sdl.unplug(1);
      lab.tick();
      expect(lab.devices, isEmpty);
      sdl.plug(FakeSdl.wiiUPro());
      lab.tick();
      expect(lab.session(lab.devices.single).checked, isEmpty);
    });

    test('presses go to listeners once; holding back counts up', () {
      final heard = <GButton>[];
      lab.addPressListener((d, b) => heard.add(b));
      final p = sdl.pads[1]!;
      p.down.add(GButton.dpadDown);
      lab.tick();
      lab.tick();
      p.down.clear();
      lab.tick();
      expect(heard, [GButton.dpadDown]);
      // Wii U Pro: B is SDL's south, so that's back.
      expect(backButton(lab.devices.single.info), GButton.south);
      p.down.add(GButton.south);
      for (var i = 0; i < 5; i++) {
        lab.tick();
      }
      expect(lab.backHeld[1], 5);
      p.down.clear();
      lab.tick();
      expect(lab.backHeld[1], isNull);
    });

    test('confirm is A wherever A is', () {
      ControllerInfo t(GamepadType type, [Map<GButton, ButtonLabel>? l]) =>
          ControllerInfo(
            id: 1,
            name: 'p',
            source: 's',
            gamepadType: type,
            labels: l ?? const {},
          );
      expect(confirmButton(t(GamepadType.xbox360)), GButton.south);
      expect(confirmButton(t(GamepadType.switchPro)), GButton.east);
      expect(
        confirmButton(t(GamepadType.standard, {GButton.east: ButtonLabel.a})),
        GButton.east,
      );
    });
  });

  test('falls back to key events when SDL is missing', () {
    String? reason;
    final lab = ControllerLab(
      _NoBackend(),
      fallback: (r) {
        reason = r;
        return _OnePad();
      },
    )..start();
    expect(reason, 'SDL3 not found.');
    expect(lab.startProblem, 'SDL3 not found.');
    expect(lab.devices.single.info.name, 'Keys');
    lab.dispose();
  });

  group('Android', () {
    test('devices, keys and motion become pad state', () {
      final a = AndroidPads()
        ..setDevices([
          {
            'id': 5,
            'name': 'Xbox Wireless Controller',
            'vendorId': 0x045e,
            'productId': 0x0b13,
            'gamepad': true,
            'axes': [0, 1, 11, 14, 17, 18, 15, 16],
            'battery': 0.5,
            'batteryStatus': 3,
          },
        ]);
      final d = a.devices[5]!;
      expect(d.info.gamepadType, GamepadType.xboxOne);
      expect(d.info.batteryPercent, 50);
      expect(d.info.hasAxes, contains(GAxis.rightX));
      a.onEvent({'e': 'key', 'id': 5, 'code': 96, 'down': true});
      expect(d.state.button(GButton.south), isTrue);
      expect(d.state.buttons[0], isTrue); // raw BUTTON_A
      a.onEvent({
        'e': 'motion',
        'id': 5,
        'axes': [1.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.5, 0.0, 0.0, 0.0, -1.0, 0.0],
      });
      expect(d.state.axis(GAxis.leftX), 32767);
      expect(d.state.axis(GAxis.rightY), -32767);
      expect(d.state.axisValue(GAxis.leftTrigger), closeTo(0.5, 0.01));
      expect(d.state.button(GButton.dpadLeft), isTrue); // hat
      a.onEvent({'e': 'key', 'id': 5, 'code': 21, 'down': false});
      expect(d.state.button(GButton.dpadLeft), isTrue); // hat still held
      a.setDevices([]);
      expect(a.devices, isEmpty);
    });

    test('vendor ids guess the pad kind', () {
      expect(guessGamepadType(0x054c, 0x0ce6, ''), GamepadType.ps5);
      expect(guessGamepadType(0x054c, 0x0268, ''), GamepadType.ps3);
      expect(guessGamepadType(0x045e, 0x028e, ''), GamepadType.xbox360);
      expect(guessGamepadType(0x057e, 0x2009, ''), GamepadType.switchPro);
      expect(guessGamepadType(0x1234, 1, 'gamepad'), GamepadType.standard);
    });
  });

  test('SDL3 loads, or says clearly why not', () {
    final (sdl, problem) = FfiSdl.load();
    if (sdl != null) {
      expect(sdl.version, startsWith('3.'));
    } else {
      expect(problem, startsWith('SDL3 not found.'));
    }
  });
}
