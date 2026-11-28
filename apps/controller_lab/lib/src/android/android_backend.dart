import 'dart:async';

import 'package:flutter/services.dart';

import '../model/backend.dart';
import '../model/controls.dart';
import '../model/guess.dart';

/// Android key codes a controller sends, in the order of the raw button
/// list (so the generic drawing numbers them the same way every time).
final androidButtons = <(int, String)>[
  (96, 'BUTTON_A'),
  (97, 'BUTTON_B'),
  (98, 'BUTTON_C'),
  (99, 'BUTTON_X'),
  (100, 'BUTTON_Y'),
  (101, 'BUTTON_Z'),
  (102, 'BUTTON_L1'),
  (103, 'BUTTON_R1'),
  (104, 'BUTTON_L2'),
  (105, 'BUTTON_R2'),
  (106, 'BUTTON_THUMBL'),
  (107, 'BUTTON_THUMBR'),
  (108, 'BUTTON_START'),
  (109, 'BUTTON_SELECT'),
  (110, 'BUTTON_MODE'),
  (19, 'DPAD_UP'),
  (20, 'DPAD_DOWN'),
  (21, 'DPAD_LEFT'),
  (22, 'DPAD_RIGHT'),
  (23, 'DPAD_CENTER'),
  (4, 'BACK'),
  for (var i = 1; i <= 16; i++) (187 + i, 'BUTTON_$i'),
];

/// MotionEvent axes, in the order MainActivity sends them.
const androidAxes = [
  'AXIS_X',
  'AXIS_Y',
  'AXIS_Z',
  'AXIS_RZ',
  'AXIS_RX',
  'AXIS_RY',
  'AXIS_LTRIGGER',
  'AXIS_RTRIGGER',
  'AXIS_BRAKE',
  'AXIS_GAS',
  'AXIS_HAT_X',
  'AXIS_HAT_Y',
];

/// Android's standard gamepad keys → SDL's positional buttons
/// (KEYCODE_BUTTON_A is the bottom button, like SDL's south).
const androidGamepadKeys = <int, GButton>{
  96: GButton.south,
  97: GButton.east,
  99: GButton.west,
  100: GButton.north,
  102: GButton.leftShoulder,
  103: GButton.rightShoulder,
  106: GButton.leftStick,
  107: GButton.rightStick,
  108: GButton.start,
  109: GButton.back,
  110: GButton.guide,
  19: GButton.dpadUp,
  20: GButton.dpadDown,
  21: GButton.dpadLeft,
  22: GButton.dpadRight,
};

// MotionEvent axis ids, for the device's motion ranges.
const _axisZ = 11, _axisRx = 12, _axisLTrigger = 17, _axisBrake = 23;

/// Turns MainActivity's messages into [PadDevice]s. Kept apart from the
/// channels so tests can feed it maps.
class AndroidPads {
  final Map<int, PadDevice> devices = {};
  final Map<int, Set<int>> _axesOf = {};
  bool dirty = true;

  /// Replaces the device list with MainActivity's "devices" answer.
  void setDevices(List<Object?> list) {
    final seen = <int>{};
    for (final raw in list) {
      if (raw is! Map) continue;
      final m = raw.cast<Object?, Object?>();
      final id = (m['id'] as num?)?.toInt();
      if (id == null) continue;
      seen.add(id);
      final vendor = (m['vendorId'] as num?)?.toInt() ?? 0;
      final product = (m['productId'] as num?)?.toInt() ?? 0;
      final name = m['name'] as String? ?? 'Controller $id';
      final battery = (m['battery'] as num?)?.toDouble();
      final status = (m['batteryStatus'] as num?)?.toInt() ?? 0;
      final axes = {
        for (final a in (m['axes'] as List?) ?? const []) (a as num).toInt(),
      };
      _axesOf[id] = axes;
      final gamepad = m['gamepad'] == true;
      final type = guessGamepadType(vendor, product, name);
      final info = ControllerInfo(
        id: id,
        name: name,
        source: 'Android',
        vendorId: vendor,
        productId: product,
        guid: m['descriptor'] as String? ?? '',
        joystickType: gamepad ? 1 : 0,
        gamepadType: gamepad ? type : GamepadType.unknown,
        realGamepadType: gamepad ? type : GamepadType.unknown,
        connection: Connection.unknown,
        power: battery == null
            ? PowerState.unknown
            : switch (status) {
                2 => PowerState.charging, // BatteryState.STATUS_CHARGING
                3 => PowerState.onBattery, // DISCHARGING
                5 => PowerState.charged, // FULL
                _ => PowerState.unknown,
              },
        batteryPercent: battery == null || battery.isNaN
            ? -1
            : (battery * 100).round(),
        isGamepad: gamepad,
        gamepadName: gamepad ? name : '',
        mapping: gamepad
            ? 'Android standard gamepad keys (KEYCODE_BUTTON_A = bottom)'
            : '',
        buttonCount: androidButtons.length,
        axisCount: androidAxes.length,
        hasButtons: gamepad ? androidGamepadKeys.values.toSet() : const {},
        hasAxes: gamepad
            ? {
                GAxis.leftX,
                GAxis.leftY,
                if (axes.contains(_axisZ) || axes.contains(_axisRx)) ...[
                  GAxis.rightX,
                  GAxis.rightY,
                ],
                if (axes.contains(_axisLTrigger) ||
                    axes.contains(_axisBrake)) ...[
                  GAxis.leftTrigger,
                  GAxis.rightTrigger,
                ],
              }
            : const {},
        notes: [
          "Android doesn't say whether it's wired or Bluetooth.",
          if (m['external'] == false) 'Built into this device.',
          if ((m['controllerNumber'] as num?)?.toInt() case final n? when n > 0)
            'Android calls it player $n.',
        ],
      );
      final old = devices[id];
      devices[id] = PadDevice(
        info,
        old?.state ??
            (PadState(buttons: androidButtons.length, axes: androidAxes.length)
              ..buttonNames = [for (final b in androidButtons) b.$2]
              ..axisNames = androidAxes),
      );
    }
    devices.removeWhere((k, _) => !seen.contains(k));
    dirty = true;
  }

  /// One "key" or "motion" message.
  void onEvent(Map<Object?, Object?> m) {
    final id = (m['id'] as num?)?.toInt();
    final d = devices[id];
    if (d == null) return;
    final s = d.state;
    final hat = _hats[id!] ??= [0, 0];
    final keyDpad = _keyDpads[id] ??= {};
    void dpad(GButton b, bool down, {required bool fromKey}) =>
        _setDpadOrButton(s, hat, keyDpad, b, down, fromKey: fromKey);
    switch (m['e']) {
      case 'key':
        final code = (m['code'] as num).toInt();
        final down = m['down'] == true;
        final i = androidButtons.indexWhere((b) => b.$1 == code);
        if (i >= 0) s.setRawButton(i, down);
        final b = androidGamepadKeys[code];
        if (b != null) dpad(b, down, fromKey: true);
        // Digital L2/R2 count as fully pulled triggers.
        if (code == 104) s.setAxis(GAxis.leftTrigger, down ? 32767 : 0);
        if (code == 105) s.setAxis(GAxis.rightTrigger, down ? 32767 : 0);
      case 'motion':
        final v = [for (final a in (m['axes'] as List)) (a as num).toDouble()];
        if (v.length < androidAxes.length) return;
        int i16(double x) => (x.clamp(-1.0, 1.0) * 32767).round();
        for (var i = 0; i < v.length && i < s.axes.length; i++) {
          s.setRawAxis(i, i16(v[i]));
        }
        final axes = _axesOf[id] ?? const {};
        final useRx = !axes.contains(_axisZ) && axes.contains(_axisRx);
        s
          ..setAxis(GAxis.leftX, i16(v[0]))
          ..setAxis(GAxis.leftY, i16(v[1]))
          ..setAxis(GAxis.rightX, i16(useRx ? v[4] : v[2]))
          ..setAxis(GAxis.rightY, i16(useRx ? v[5] : v[3]));
        if (axes.contains(_axisLTrigger) || axes.contains(_axisBrake)) {
          s
            ..setAxis(GAxis.leftTrigger, i16(v[6] > v[8] ? v[6] : v[8]))
            ..setAxis(GAxis.rightTrigger, i16(v[7] > v[9] ? v[7] : v[9]));
        }
        // A d-pad that reports as a hat.
        hat[0] = v[10];
        hat[1] = v[11];
        dpad(GButton.dpadLeft, hat[0] < -0.5, fromKey: false);
        dpad(GButton.dpadRight, hat[0] > 0.5, fromKey: false);
        dpad(GButton.dpadUp, hat[1] < -0.5, fromKey: false);
        dpad(GButton.dpadDown, hat[1] > 0.5, fromKey: false);
    }
  }

  final Map<int, List<double>> _hats = {};
  final Map<int, Set<GButton>> _keyDpads = {};

  /// The d-pad can come as keys or as a hat; it's held if either says so.
  static void _setDpadOrButton(
    PadState s,
    List<double> hat,
    Set<GButton> keyDpad,
    GButton b,
    bool down, {
    required bool fromKey,
  }) {
    final isDpad =
        b.index >= GButton.dpadUp.index && b.index <= GButton.dpadRight.index;
    if (!isDpad) {
      s.setButton(b, down);
      return;
    }
    if (fromKey) {
      down ? keyDpad.add(b) : keyDpad.remove(b);
    }
    final fromHat = switch (b) {
      GButton.dpadLeft => hat[0] < -0.5,
      GButton.dpadRight => hat[0] > 0.5,
      GButton.dpadUp => hat[1] < -0.5,
      _ => hat[1] > 0.5,
    };
    s.setButton(b, keyDpad.contains(b) || fromHat);
  }
}

/// Controllers on Android, from MainActivity's InputDevice channel.
class AndroidBackend extends PadBackend {
  AndroidBackend({
    this.methods = const MethodChannel('controller_lab/input'),
    this.events = const EventChannel('controller_lab/events'),
  });

  final MethodChannel methods;
  final EventChannel events;
  final AndroidPads pads = AndroidPads();
  StreamSubscription<Object?>? _sub;
  String? _problem;

  @override
  String get title => 'Android input';

  @override
  String? get problem => _problem;

  @override
  List<String> get details => const [
    'Android InputDevice: key codes and MotionEvent axes as Android reports them.',
  ];

  @override
  List<PadDevice> get devices => pads.devices.values.toList(growable: false);

  @override
  bool get canRumble => true;

  @override
  bool start() {
    _sub = events.receiveBroadcastStream().listen((e) {
      if (e is! Map) return;
      if (e['e'] == 'devices') {
        unawaited(_refresh());
      } else {
        pads.onEvent(e.cast<Object?, Object?>());
      }
    }, onError: (Object e) => _problem = 'Android input: $e');
    unawaited(_refresh());
    return true;
  }

  Future<void> _refresh() async {
    try {
      final list = await methods.invokeMethod<List<Object?>>('devices');
      pads.setDevices(list ?? const []);
    } on MissingPluginException {
      _problem = 'This build has no Android input channel.';
      pads.dirty = true;
    } on PlatformException catch (e) {
      _problem = 'Android input: ${e.message}';
      pads.dirty = true;
    }
  }

  @override
  bool poll() {
    final d = pads.dirty;
    pads.dirty = false;
    return d;
  }

  @override
  bool rumble(int id, {double low = 0.6, double high = 0.6, int ms = 400}) {
    unawaited(
      methods
          .invokeMethod<bool>('rumble', {'id': id, 'ms': ms})
          .catchError((_) => false),
    );
    return true;
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _sub = null;
  }
}
