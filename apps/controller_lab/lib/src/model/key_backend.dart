import 'package:flutter/services.dart';
import 'package:pad_input/pad_input.dart';

import 'backend.dart';
import 'controls.dart';

/// [PadButton] (pad_input's positional buttons) → SDL's.
const padToGButton = <PadButton, GButton>{
  PadButton.up: GButton.dpadUp,
  PadButton.down: GButton.dpadDown,
  PadButton.left: GButton.dpadLeft,
  PadButton.right: GButton.dpadRight,
  PadButton.south: GButton.south,
  PadButton.east: GButton.east,
  PadButton.west: GButton.west,
  PadButton.north: GButton.north,
  PadButton.l1: GButton.leftShoulder,
  PadButton.r1: GButton.rightShoulder,
  PadButton.select: GButton.back,
  PadButton.start: GButton.start,
  PadButton.l3: GButton.leftStick,
  PadButton.r3: GButton.rightStick,
};

/// The fallback: controller buttons that reach Flutter as key events
/// (read with pad_input's [PadKeys]), as one "controller". No sticks or
/// names: Flutter's key events don't carry them.
class KeyBackend extends PadBackend {
  KeyBackend({required this.android, this.reason});

  /// On Android the arrow keys are the d-pad.
  final bool android;

  /// Why the better backend isn't in use (shown with the list).
  final String? reason;

  late final PadKeys _keys = PadKeys(android: android);
  late final PadDevice _device = PadDevice(
    ControllerInfo(
      id: 0,
      name: 'Controller keys',
      source: 'Key events',
      isGamepad: true,
      gamepadType: GamepadType.standard,
      gamepadName: 'Flutter key events',
      mapping: 'Flutter key events (gameButtonA = bottom button)',
      hasButtons: {...padToGButton.values, GButton.guide},
      hasAxes: const {GAxis.leftTrigger, GAxis.rightTrigger},
      notes: const [
        'Only buttons that arrive as key events: no sticks, no names.',
      ],
    ),
    PadState(),
  );
  bool _dirty = true;

  @override
  String get title => 'Key events';

  @override
  String? get problem => reason;

  @override
  List<PadDevice> get devices => [_device];

  @override
  bool start() {
    HardwareKeyboard.instance.addHandler(handle);
    return true;
  }

  /// Reads [event]; never consumes it (the app still navigates with it).
  bool handle(KeyEvent event) {
    final down = event is! KeyUpEvent;
    final s = _device.state;
    if (event.logicalKey == LogicalKeyboardKey.gameButtonMode) {
      s.setButton(GButton.guide, down);
      return false;
    }
    final b = _keys.buttonFor(event.logicalKey);
    if (b == null) return false;
    switch (b) {
      case PadButton.l2:
        s.setAxis(GAxis.leftTrigger, down ? 32767 : 0);
      case PadButton.r2:
        s.setAxis(GAxis.rightTrigger, down ? 32767 : 0);
      default:
        s.setButton(padToGButton[b]!, down);
    }
    return false;
  }

  @override
  bool poll() {
    final d = _dirty;
    _dirty = false;
    return d;
  }

  @override
  void dispose() => HardwareKeyboard.instance.removeHandler(handle);
}
