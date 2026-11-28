import 'package:controller_lab/src/model/controls.dart';
import 'package:controller_lab/src/sdl/sdl_api.dart';

/// A controller plugged into [FakeSdl].
class FakePad {
  FakePad({
    required this.id,
    required this.name,
    this.vendor = 0,
    this.product = 0,
    this.mapped = true,
    this.type = GamepadType.standard,
    this.buttons = 15,
    this.axes = 6,
    this.hats = 0,
    this.connection = Connection.wireless,
    this.battery = 80,
  });

  final int id;
  final String name;
  final int vendor, product;
  final bool mapped;
  final GamepadType type;
  final int buttons, axes, hats;
  Connection connection;
  int battery;

  final Set<GButton> down = {};
  final Map<GAxis, int> axis = {};
  final Map<int, bool> rawButtons = {};
  final Map<int, int> rawAxes = {};
  final Map<int, int> rawHats = {};
  final List<(int, int, int)> rumbles = [];
}

/// SDL3 without SDL: tests plug pads in and out and press their buttons.
class FakeSdl implements SdlApi {
  final Map<int, FakePad> pads = {};
  final Set<int> opened = {};
  Map<String, String>? hints;
  bool failInit = false;
  bool quitCalled = false;
  bool _events = false;

  void plug(FakePad p) {
    pads[p.id] = p;
    _events = true;
  }

  void unplug(int id) {
    pads.remove(id);
    _events = true;
  }

  /// A battery/remap event, as SDL would send.
  void event() => _events = true;

  /// The Wii U Pro as SDL's Wii driver presents it.
  static FakePad wiiUPro({int id = 1}) => FakePad(
    id: id,
    name: 'Nintendo Wii U Pro Controller',
    vendor: 0x057e,
    product: 0x0330,
  );

  @override
  String get version => '3.4.20';

  @override
  bool init(Map<String, String> hints) {
    this.hints = hints;
    return !failInit;
  }

  @override
  String lastError() => failInit ? 'No joystick subsystem' : '';

  @override
  bool pumpEvents() {
    final e = _events;
    _events = false;
    return e;
  }

  @override
  List<int> joystickIds() => pads.keys.toList();

  @override
  bool open(int id) => pads.containsKey(id) && opened.add(id);

  @override
  void close(int id) => opened.remove(id);

  @override
  ControllerInfo info(int id, String source) {
    final p = pads[id]!;
    return ControllerInfo(
      id: id,
      name: p.name,
      source: source,
      vendorId: p.vendor,
      productId: p.product,
      guid: '0500000000000000000000000000000$id',
      joystickType: p.mapped ? 1 : 0,
      gamepadType: p.mapped ? p.type : GamepadType.unknown,
      realGamepadType: p.mapped ? p.type : GamepadType.unknown,
      connection: p.connection,
      power: PowerState.onBattery,
      batteryPercent: p.battery,
      isGamepad: p.mapped,
      mapping: p.mapped ? 'guid,${p.name},a:b0,b:b1,' : '',
      gamepadName: p.mapped ? p.name : '',
      buttonCount: p.buttons,
      axisCount: p.axes,
      hatCount: p.hats,
      hasButtons: p.mapped
          ? GButton.values.take(15).toSet()
          : const <GButton>{},
      hasAxes: p.mapped ? GAxis.values.toSet() : const <GAxis>{},
      labels: p.mapped
          ? const {
              GButton.south: ButtonLabel.a,
              GButton.east: ButtonLabel.b,
              GButton.west: ButtonLabel.x,
              GButton.north: ButtonLabel.y,
            }
          : const {},
    );
  }

  @override
  (Connection, PowerState, int) power(int id) {
    final p = pads[id];
    if (p == null) return (Connection.unknown, PowerState.unknown, -1);
    return (p.connection, PowerState.onBattery, p.battery);
  }

  @override
  void readState(int id, PadState into) {
    final p = pads[id];
    if (p == null) return;
    for (var i = 0; i < into.buttons.length; i++) {
      into.setRawButton(i, p.rawButtons[i] ?? false);
    }
    for (var i = 0; i < into.axes.length; i++) {
      into.setRawAxis(i, p.rawAxes[i] ?? 0);
    }
    for (var i = 0; i < into.hats.length; i++) {
      into.setRawHat(i, p.rawHats[i] ?? 0);
    }
    if (!p.mapped) return;
    for (final b in GButton.values) {
      into.setButton(b, p.down.contains(b));
    }
    for (final a in GAxis.values) {
      into.setAxis(a, p.axis[a] ?? 0);
    }
  }

  @override
  bool rumble(int id, int low, int high, int ms) {
    pads[id]?.rumbles.add((low, high, ms));
    return pads.containsKey(id);
  }

  @override
  void quit() => quitCalled = true;
}
