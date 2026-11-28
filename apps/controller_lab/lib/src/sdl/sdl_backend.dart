import '../model/backend.dart';
import '../model/controls.dart';
import 'sdl_api.dart';

/// SDL3 hints Controller Lab sets before `SDL_Init`, so it sees the
/// controllers the way the owner's SDL programs (the PC XMB in Godot 4.7,
/// RetroArch's sdl2 driver, PCSX2, RPCS3) do once they have the same
/// settings. Hints set here are SDL_HINT_NORMAL priority: an environment
/// variable of the same name (e.g. SDL_JOYSTICK_HIDAPI_WII=0) wins.
class SdlHints {
  const SdlHints({
    this.wii = true,
    this.ps3 = true,
    this.enhancedReports = true,
  });

  /// SDL_JOYSTICK_HIDAPI_WII: SDL's own Wii Remote / Wii U Pro driver
  /// (off by default in SDL because it doesn't work with the DolphinBar).
  final bool wii;

  /// SDL_JOYSTICK_HIDAPI_PS3: read a DualShock 3 itself (off by default on
  /// Windows; needs the pad on a HID driver such as DsHidMini's SXS mode).
  final bool ps3;

  /// SDL_JOYSTICK_ENHANCED_REPORTS: full reports from Bluetooth
  /// PlayStation pads (DualSense: gyro, touchpad, rumble) and Switch pads.
  final bool enhancedReports;

  Map<String, String> toMap() => {
    'SDL_JOYSTICK_HIDAPI_WII': wii ? '1' : '0',
    'SDL_JOYSTICK_HIDAPI_PS3': ps3 ? '1' : '0',
    'SDL_JOYSTICK_ENHANCED_REPORTS': enhancedReports ? '1' : '0',
    // The Flutter window isn't an SDL window: without this SDL would think
    // the app is in the background and drop controller input.
    'SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS': '1',
    // Player lights on, so the Wii U Pro's LEDs stop running once SDL has it.
    'SDL_JOYSTICK_HIDAPI_WII_PLAYER_LED': '1',
    'SDL_JOYSTICK_HIDAPI_PS5_PLAYER_LED': '1',
  };
}

/// Controllers through SDL3: hot-plug, every joystick with its gamepad
/// mapping, and their live state. Pure Dart over [SdlApi], so tests drive
/// it with a fake SDL.
class SdlBackend extends PadBackend {
  SdlBackend(this.api, {this.hints = const SdlHints()});

  /// Null when SDL3 couldn't be loaded ([loadProblem] says why).
  final SdlApi? api;
  final SdlHints hints;

  /// Why the library didn't load (set by whoever made [api]).
  String? loadProblem;

  String? _problem;
  bool _started = false;
  bool _listDirty = true;
  int _ticks = 0;
  final Map<int, PadDevice> _devices = {};

  @override
  String get title => api == null ? 'SDL3' : 'SDL ${api!.version}';

  @override
  String? get problem => _problem;

  @override
  List<String> get details => [
    for (final e in hints.toMap().entries) '${e.key}=${e.value}',
  ];

  @override
  List<PadDevice> get devices => _devices.values.toList(growable: false);

  @override
  bool get canRumble => _started;

  @override
  bool start() {
    final sdl = api;
    if (sdl == null) {
      _problem = loadProblem ?? 'SDL3 library not found.';
      return false;
    }
    if (!sdl.init(hints.toMap())) {
      _problem = 'SDL_Init failed: ${sdl.lastError()}';
      return false;
    }
    _started = true;
    _problem = null;
    return true;
  }

  @override
  bool poll() {
    final sdl = api;
    if (!_started || sdl == null) return false;
    var changed = false;
    if (sdl.pumpEvents()) _listDirty = true;
    if (_listDirty) {
      _listDirty = false;
      changed = _reconcile(sdl);
    }
    // Battery and connection change slowly: once a second is plenty.
    if (++_ticks % 60 == 0) {
      for (final d in _devices.values) {
        final (c, p, pct) = sdl.power(d.info.id);
        if (c != d.info.connection ||
            p != d.info.power ||
            pct != d.info.batteryPercent) {
          d.info
            ..connection = c
            ..power = p
            ..batteryPercent = pct;
          changed = true;
        }
      }
    }
    for (final d in _devices.values) {
      sdl.readState(d.info.id, d.state);
    }
    return changed;
  }

  /// Opens new controllers, forgets gone ones, re-reads what each is (a
  /// remap changes its gamepad mapping). True if anything changed.
  bool _reconcile(SdlApi sdl) {
    final ids = sdl.joystickIds().toSet();
    var changed = false;
    for (final gone in _devices.keys.where((k) => !ids.contains(k)).toList()) {
      sdl.close(gone);
      _devices.remove(gone);
      changed = true;
    }
    for (final id in ids) {
      final old = _devices[id];
      if (old == null && !sdl.open(id)) continue;
      final info = sdl.info(id, title);
      if (old != null && _sameInfo(old.info, info)) continue;
      _devices[id] = PadDevice(
        info,
        old != null &&
                old.state.buttons.length == info.buttonCount &&
                old.state.axes.length == info.axisCount &&
                old.state.hats.length == info.hatCount
            ? old.state
            : PadState(
                buttons: info.buttonCount,
                axes: info.axisCount,
                hats: info.hatCount,
              ),
      );
      changed = true;
    }
    return changed;
  }

  static bool _sameInfo(ControllerInfo a, ControllerInfo b) =>
      a.name == b.name &&
      a.isGamepad == b.isGamepad &&
      a.mapping == b.mapping &&
      a.gamepadType == b.gamepadType &&
      a.connection == b.connection &&
      a.power == b.power &&
      a.batteryPercent == b.batteryPercent;

  @override
  bool rumble(int id, {double low = 0.6, double high = 0.6, int ms = 400}) {
    final sdl = api;
    if (!_started || sdl == null || !_devices.containsKey(id)) return false;
    int s(double v) => (v.clamp(0.0, 1.0) * 0xFFFF).round();
    return sdl.rumble(id, s(low), s(high), ms);
  }

  @override
  void dispose() {
    final sdl = api;
    if (_started && sdl != null) {
      for (final id in _devices.keys) {
        sdl.close(id);
      }
      sdl.quit();
    }
    _devices.clear();
    _started = false;
  }
}
