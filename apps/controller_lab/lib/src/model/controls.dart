/// What a controller is and what it is doing right now, in the terms SDL3
/// uses, so every backend (SDL on Windows/Linux, Android's input devices,
/// plain key events) reports the same things.
library;

/// SDL's gamepad buttons, by position (same order and numbers as
/// `SDL_GamepadButton`): [south] is the bottom face button (Xbox A,
/// PlayStation ✕, Nintendo B), [east] the right one (Nintendo A).
enum GButton {
  south,
  east,
  west,
  north,
  back,
  guide,
  start,
  leftStick,
  rightStick,
  leftShoulder,
  rightShoulder,
  dpadUp,
  dpadDown,
  dpadLeft,
  dpadRight,
  misc1,
  rightPaddle1,
  leftPaddle1,
  rightPaddle2,
  leftPaddle2,
  touchpad,
  misc2,
  misc3,
  misc4,
  misc5,
  misc6,
}

/// SDL's gamepad axes (same numbers as `SDL_GamepadAxis`). Sticks read
/// -32768..32767 (down and right are positive), triggers 0..32767.
enum GAxis { leftX, leftY, rightX, rightY, leftTrigger, rightTrigger }

/// `SDL_GamepadType`: what kind of pad SDL thinks it is.
enum GamepadType {
  unknown('Unknown'),
  standard('Standard'),
  xbox360('Xbox 360'),
  xboxOne('Xbox One'),
  ps3('PlayStation 3'),
  ps4('PlayStation 4'),
  ps5('PlayStation 5'),
  switchPro('Nintendo Switch Pro'),
  joyConLeft('Joy-Con (L)'),
  joyConRight('Joy-Con (R)'),
  joyConPair('Joy-Con pair'),
  gameCube('GameCube'),
  steam('Steam');

  const GamepadType(this.label);
  final String label;

  static GamepadType fromSdl(int v) =>
      v >= 0 && v < values.length ? values[v] : unknown;

  /// SDL's own constant name, as the owner will see it in other tools.
  String get sdlName => switch (this) {
    unknown => 'SDL_GAMEPAD_TYPE_UNKNOWN',
    standard => 'SDL_GAMEPAD_TYPE_STANDARD',
    xbox360 => 'SDL_GAMEPAD_TYPE_XBOX360',
    xboxOne => 'SDL_GAMEPAD_TYPE_XBOXONE',
    ps3 => 'SDL_GAMEPAD_TYPE_PS3',
    ps4 => 'SDL_GAMEPAD_TYPE_PS4',
    ps5 => 'SDL_GAMEPAD_TYPE_PS5',
    switchPro => 'SDL_GAMEPAD_TYPE_NINTENDO_SWITCH_PRO',
    joyConLeft => 'SDL_GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_LEFT',
    joyConRight => 'SDL_GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_RIGHT',
    joyConPair => 'SDL_GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_PAIR',
    gameCube => 'SDL_GAMEPAD_TYPE_GAMECUBE',
    steam => 'SDL_GAMEPAD_TYPE_STEAM',
  };
}

/// `SDL_JoystickType`.
const joystickTypeNames = [
  'Unknown',
  'Gamepad',
  'Wheel',
  'Arcade stick',
  'Flight stick',
  'Dance pad',
  'Guitar',
  'Drum kit',
  'Arcade pad',
  'Throttle',
];

/// `SDL_JoystickConnectionState`.
enum Connection {
  unknown('Connection unknown'),
  wired('Wired'),
  wireless('Wireless');

  const Connection(this.label);
  final String label;

  static Connection fromSdl(int v) => switch (v) {
    1 => wired,
    2 => wireless,
    _ => unknown,
  };
}

/// `SDL_PowerState`.
enum PowerState {
  unknown('Battery unknown'),
  onBattery('On battery'),
  noBattery('No battery'),
  charging('Charging'),
  charged('Charged');

  const PowerState(this.label);
  final String label;

  static PowerState fromSdl(int v) => switch (v) {
    1 => onBattery,
    2 => noBattery,
    3 => charging,
    4 => charged,
    _ => unknown,
  };
}

/// `SDL_GamepadButtonLabel`: what is printed on a face button.
enum ButtonLabel { unknown, a, b, x, y, cross, circle, square, triangle }

/// What a controller is (it doesn't change while it is plugged in, apart
/// from power and a remapping).
class ControllerInfo {
  ControllerInfo({
    required this.id,
    required this.name,
    required this.source,
    this.vendorId = 0,
    this.productId = 0,
    this.productVersion = 0,
    this.guid = '',
    this.path = '',
    this.serial = '',
    this.joystickType = 0,
    this.gamepadType = GamepadType.unknown,
    this.realGamepadType = GamepadType.unknown,
    this.connection = Connection.unknown,
    this.power = PowerState.unknown,
    this.batteryPercent = -1,
    this.isGamepad = false,
    this.mapping = '',
    this.gamepadName = '',
    this.buttonCount = 0,
    this.axisCount = 0,
    this.hatCount = 0,
    this.hasButtons = const {},
    this.hasAxes = const {},
    this.labels = const {},
    this.notes = const [],
  });

  /// The backend's id for it (SDL's joystick instance id; Android's
  /// device id). Unique while it stays connected.
  final int id;

  /// The joystick's name (SDL's, as RetroArch/PCSX2/Godot show it).
  final String name;

  /// Which backend found it ('SDL 3.4.20', 'Android', 'Key events').
  final String source;
  final int vendorId, productId, productVersion;
  final String guid, path, serial;

  /// Index into [joystickTypeNames].
  final int joystickType;
  final GamepadType gamepadType;

  /// The type SDL detected before any SDL_GAMECONTROLLERTYPE override.
  final GamepadType realGamepadType;
  Connection connection;
  PowerState power;

  /// 0..100, or -1 when unknown.
  int batteryPercent;

  /// SDL has a gamepad mapping for it (its buttons have names).
  final bool isGamepad;

  /// SDL's mapping string (`guid,name,a:b0,...`), when [isGamepad].
  final String mapping;

  /// SDL's gamepad name (from the mapping), when [isGamepad].
  final String gamepadName;
  final int buttonCount, axisCount, hatCount;

  /// Which gamepad buttons / axes the mapping has.
  final Set<GButton> hasButtons;
  final Set<GAxis> hasAxes;

  /// What SDL says is printed on the face buttons.
  final Map<GButton, ButtonLabel> labels;

  /// Backend remarks to show (e.g. "Android doesn't say how it's connected").
  final List<String> notes;

  String get joystickTypeName =>
      joystickType >= 0 && joystickType < joystickTypeNames.length
      ? joystickTypeNames[joystickType]
      : 'Unknown';

  static String hex4(int v) => v.toRadixString(16).padLeft(4, '0');

  /// "057e:0330" (USB vendor and product ids).
  String get vidPid => '${hex4(vendorId)}:${hex4(productId)}';

  /// One line: how it's connected, power, what SDL calls it.
  String get summary {
    final parts = <String>[
      if (connection != Connection.unknown) connection.label,
      if (batteryPercent >= 0)
        '$batteryPercent%'
      else if (power != PowerState.unknown)
        power.label,
      isGamepad ? gamepadType.label : 'not mapped (joystick only)',
    ];
    return parts.join(' · ');
  }
}

/// What a controller is doing right now: the raw joystick (numbered
/// buttons, axes, hats) and, when SDL has a mapping, the named gamepad
/// buttons and axes.
class PadState {
  PadState({int buttons = 0, int axes = 0, int hats = 0})
    : buttons = List.filled(buttons, false),
      axes = List.filled(axes, 0),
      hats = List.filled(hats, 0);

  final List<bool> buttons;
  final List<int> axes;

  /// SDL hat bits: 1 up, 2 right, 4 down, 8 left.
  final List<int> hats;
  final List<bool> gButtons = List.filled(GButton.values.length, false);
  final List<int> gAxes = List.filled(GAxis.values.length, 0);

  /// Names for the raw buttons / axes, where the backend has them
  /// (Android's key codes and axis names).
  List<String>? buttonNames, axisNames;

  /// Bumped whenever anything changes (the drawing repaints on it).
  int version = 0;

  bool button(GButton b) => gButtons[b.index];
  int axis(GAxis a) => gAxes[a.index];

  /// -1..1 (triggers 0..1).
  double axisValue(GAxis a) => (gAxes[a.index] / 32767).clamp(-1.0, 1.0);

  void setRawButton(int i, bool v) {
    if (i < 0 || i >= buttons.length || buttons[i] == v) return;
    buttons[i] = v;
    version++;
  }

  void setRawAxis(int i, int v) {
    if (i < 0 || i >= axes.length || axes[i] == v) return;
    axes[i] = v;
    version++;
  }

  void setRawHat(int i, int v) {
    if (i < 0 || i >= hats.length || hats[i] == v) return;
    hats[i] = v;
    version++;
  }

  void setButton(GButton b, bool v) {
    if (gButtons[b.index] == v) return;
    gButtons[b.index] = v;
    version++;
  }

  void setAxis(GAxis a, int v) {
    if (gAxes[a.index] == v) return;
    gAxes[a.index] = v;
    version++;
  }

  /// Everything back at rest (e.g. the controller went away).
  void clear() {
    for (var i = 0; i < buttons.length; i++) {
      setRawButton(i, false);
    }
    for (var i = 0; i < axes.length; i++) {
      setRawAxis(i, 0);
    }
    for (var i = 0; i < hats.length; i++) {
      setRawHat(i, 0);
    }
    for (final b in GButton.values) {
      setButton(b, false);
    }
    for (final a in GAxis.values) {
      setAxis(a, 0);
    }
  }
}

/// A connected controller: what it is and what it's doing.
class PadDevice {
  PadDevice(this.info, this.state);
  ControllerInfo info;
  final PadState state;
}
