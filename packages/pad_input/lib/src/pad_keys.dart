import 'package:flutter/services.dart';

import 'buttons.dart';
import 'gamepad.dart';

/// What a key press from a controller means: [button], and whether to act
/// on it now ([fire]; false for a release, or a held key between repeats).
typedef PadKey = ({PadButton button, bool fire});

/// Controller buttons that arrive as key presses. Android delivers every
/// controller this way (the Retroid Pocket's built-in one too): the face,
/// shoulder, Start and Select buttons as game-button keys, the d-pad as
/// arrow keys. Turning them into [PadButton]s means they follow the
/// controller settings, and the d-pad repeats at [GamepadInput]'s pace
/// instead of Android's much faster key repeat.
class PadKeys {
  PadKeys({required this.android});

  /// On Android the arrow keys (and a remote's centre/select key) are the
  /// controller's d-pad. Elsewhere they stay keyboard keys.
  final bool android;

  static final Map<LogicalKeyboardKey, PadButton> buttons = {
    LogicalKeyboardKey.gameButtonA: PadButton.south,
    LogicalKeyboardKey.gameButtonB: PadButton.east,
    LogicalKeyboardKey.gameButtonX: PadButton.west,
    LogicalKeyboardKey.gameButtonY: PadButton.north,
    LogicalKeyboardKey.gameButtonLeft1: PadButton.l1,
    LogicalKeyboardKey.gameButtonRight1: PadButton.r1,
    LogicalKeyboardKey.gameButtonLeft2: PadButton.l2,
    LogicalKeyboardKey.gameButtonRight2: PadButton.r2,
    LogicalKeyboardKey.gameButtonSelect: PadButton.select,
    LogicalKeyboardKey.gameButtonStart: PadButton.start,
    LogicalKeyboardKey.gameButtonThumbLeft: PadButton.l3,
    LogicalKeyboardKey.gameButtonThumbRight: PadButton.r3,
  };

  static final Map<LogicalKeyboardKey, PadButton> androidKeys = {
    LogicalKeyboardKey.arrowUp: PadButton.up,
    LogicalKeyboardKey.arrowDown: PadButton.down,
    LogicalKeyboardKey.arrowLeft: PadButton.left,
    LogicalKeyboardKey.arrowRight: PadButton.right,
    // A TV remote's or d-pad's centre button.
    LogicalKeyboardKey.select: PadButton.south,
  };

  /// When the held direction may fire again (in the events' own time).
  Duration? _nextRepeat;

  /// The controller button [key] is, or null for a keyboard key.
  PadButton? buttonFor(LogicalKeyboardKey key) =>
      buttons[key] ?? (android ? androidKeys[key] : null);

  /// What [event] means, or null if it isn't a controller key. A press
  /// fires once; a held direction fires again after
  /// [GamepadInput.firstRepeat], then every [GamepadInput.nextRepeat];
  /// other held buttons don't repeat.
  PadKey? read(KeyEvent event) {
    final button = buttonFor(event.logicalKey);
    if (button == null) return null;
    final direction = button.isDirection;
    final at = event.timeStamp;
    switch (event) {
      case KeyDownEvent():
        if (direction) _nextRepeat = at + GamepadInput.firstRepeat;
        return (button: button, fire: true);
      case KeyRepeatEvent():
        final next = _nextRepeat;
        if (!direction || next == null || at < next) {
          return (button: button, fire: false);
        }
        _nextRepeat = at + GamepadInput.nextRepeat;
        return (button: button, fire: true);
      default:
        if (direction) _nextRepeat = null;
        return (button: button, fire: false);
    }
  }
}
