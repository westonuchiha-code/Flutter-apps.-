import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import '../model/controls.dart';
import 'sdl_api.dart';

// Hand-written bindings for the SDL3 calls in [SdlApi] (SDL 3.2+; the
// shipped DLL is 3.4.20). Types follow SDL3's headers: SDL_JoystickID is
// Uint32, bool is C99 bool, enums are int.

final class _SdlGuid extends Struct {
  @Array(16)
  external Array<Uint8> data;
}

const _initJoystick = 0x200;
const _initGamepad = 0x2000;

// SDL_EventType values that change the controller list or info.
const _eventJoystickAdded = 0x605;
const _eventJoystickRemoved = 0x606;
const _eventJoystickBattery = 0x607;
const _eventGamepadAdded = 0x653;
const _eventGamepadRemoved = 0x654;
const _eventGamepadRemapped = 0x655;

/// sizeof(SDL_Event) (a union padded to 128 bytes).
const _eventSize = 128;

typedef _VoidVoid = Void Function();
typedef _PtrVoid = Pointer<Utf8> Function();
typedef _IntVoid = Int32 Function();
typedef _JsPtr = Pointer<Void>;

/// SDL3 through dart:ffi. Create it with [FfiSdl.load] (null and a reason
/// when the library isn't there).
class FfiSdl implements SdlApi {
  FfiSdl._(DynamicLibrary lib)
    : _setHint = lib
          .lookupFunction<
            Bool Function(Pointer<Utf8>, Pointer<Utf8>),
            bool Function(Pointer<Utf8>, Pointer<Utf8>)
          >('SDL_SetHint'),
      _init = lib.lookupFunction<Bool Function(Uint32), bool Function(int)>(
        'SDL_Init',
      ),
      _quit = lib.lookupFunction<_VoidVoid, void Function()>('SDL_Quit'),
      _getError = lib.lookupFunction<_PtrVoid, Pointer<Utf8> Function()>(
        'SDL_GetError',
      ),
      _getVersion = lib.lookupFunction<_IntVoid, int Function()>(
        'SDL_GetVersion',
      ),
      _free = lib
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('SDL_free'),
      _pollEvent = lib
          .lookupFunction<
            Bool Function(Pointer<Uint8>),
            bool Function(Pointer<Uint8>)
          >('SDL_PollEvent'),
      _getJoysticks = lib
          .lookupFunction<
            Pointer<Uint32> Function(Pointer<Int32>),
            Pointer<Uint32> Function(Pointer<Int32>)
          >('SDL_GetJoysticks'),
      _isGamepad = lib
          .lookupFunction<Bool Function(Uint32), bool Function(int)>(
            'SDL_IsGamepad',
          ),
      _openJoystick = lib
          .lookupFunction<_JsPtr Function(Uint32), _JsPtr Function(int)>(
            'SDL_OpenJoystick',
          ),
      _closeJoystick = lib
          .lookupFunction<Void Function(_JsPtr), void Function(_JsPtr)>(
            'SDL_CloseJoystick',
          ),
      _openGamepad = lib
          .lookupFunction<_JsPtr Function(Uint32), _JsPtr Function(int)>(
            'SDL_OpenGamepad',
          ),
      _closeGamepad = lib
          .lookupFunction<Void Function(_JsPtr), void Function(_JsPtr)>(
            'SDL_CloseGamepad',
          ),
      _jsName = _str(lib, 'SDL_GetJoystickName'),
      _jsPath = _str(lib, 'SDL_GetJoystickPath'),
      _jsSerial = _str(lib, 'SDL_GetJoystickSerial'),
      _gpName = _str(lib, 'SDL_GetGamepadName'),
      _jsVendor = _u16(lib, 'SDL_GetJoystickVendor'),
      _jsProduct = _u16(lib, 'SDL_GetJoystickProduct'),
      _jsProductVersion = _u16(lib, 'SDL_GetJoystickProductVersion'),
      _jsGuid = lib
          .lookupFunction<_SdlGuid Function(_JsPtr), _SdlGuid Function(_JsPtr)>(
            'SDL_GetJoystickGUID',
          ),
      _guidToString = lib
          .lookupFunction<
            Void Function(_SdlGuid, Pointer<Utf8>, Int32),
            void Function(_SdlGuid, Pointer<Utf8>, int)
          >('SDL_GUIDToString'),
      _jsType = _int(lib, 'SDL_GetJoystickType'),
      _jsConnection = _int(lib, 'SDL_GetJoystickConnectionState'),
      _jsPower = lib
          .lookupFunction<
            Int32 Function(_JsPtr, Pointer<Int32>),
            int Function(_JsPtr, Pointer<Int32>)
          >('SDL_GetJoystickPowerInfo'),
      _jsNumAxes = _int(lib, 'SDL_GetNumJoystickAxes'),
      _jsNumButtons = _int(lib, 'SDL_GetNumJoystickButtons'),
      _jsNumHats = _int(lib, 'SDL_GetNumJoystickHats'),
      _jsAxis = lib
          .lookupFunction<
            Int16 Function(_JsPtr, Int32),
            int Function(_JsPtr, int)
          >('SDL_GetJoystickAxis'),
      _jsButton = lib
          .lookupFunction<
            Bool Function(_JsPtr, Int32),
            bool Function(_JsPtr, int)
          >('SDL_GetJoystickButton'),
      _jsHat = lib
          .lookupFunction<
            Uint8 Function(_JsPtr, Int32),
            int Function(_JsPtr, int)
          >('SDL_GetJoystickHat'),
      _jsRumble = lib
          .lookupFunction<
            Bool Function(_JsPtr, Uint16, Uint16, Uint32),
            bool Function(_JsPtr, int, int, int)
          >('SDL_RumbleJoystick'),
      _gpType = _int(lib, 'SDL_GetGamepadType'),
      _gpRealType = _int(lib, 'SDL_GetRealGamepadType'),
      _gpMapping = lib
          .lookupFunction<
            Pointer<Utf8> Function(_JsPtr),
            Pointer<Utf8> Function(_JsPtr)
          >('SDL_GetGamepadMapping'),
      _gpHasButton = lib
          .lookupFunction<
            Bool Function(_JsPtr, Int32),
            bool Function(_JsPtr, int)
          >('SDL_GamepadHasButton'),
      _gpHasAxis = lib
          .lookupFunction<
            Bool Function(_JsPtr, Int32),
            bool Function(_JsPtr, int)
          >('SDL_GamepadHasAxis'),
      _gpButton = lib
          .lookupFunction<
            Bool Function(_JsPtr, Int32),
            bool Function(_JsPtr, int)
          >('SDL_GetGamepadButton'),
      _gpAxis = lib
          .lookupFunction<
            Int16 Function(_JsPtr, Int32),
            int Function(_JsPtr, int)
          >('SDL_GetGamepadAxis'),
      _gpLabel = lib
          .lookupFunction<
            Int32 Function(_JsPtr, Int32),
            int Function(_JsPtr, int)
          >('SDL_GetGamepadButtonLabel');

  static Pointer<Utf8> Function(_JsPtr) _str(DynamicLibrary l, String n) =>
      l.lookupFunction<
        Pointer<Utf8> Function(_JsPtr),
        Pointer<Utf8> Function(_JsPtr)
      >(n);
  static int Function(_JsPtr) _u16(DynamicLibrary l, String n) =>
      l.lookupFunction<Uint16 Function(_JsPtr), int Function(_JsPtr)>(n);
  static int Function(_JsPtr) _int(DynamicLibrary l, String n) =>
      l.lookupFunction<Int32 Function(_JsPtr), int Function(_JsPtr)>(n);

  /// Where SDL3 is looked for, in order: `CONTROLLER_LAB_SDL3` (a path),
  /// next to the app (Windows: SDL3.dll beside the .exe, as CI ships it;
  /// Linux: the bundle's lib/), then the system's.
  static List<String> candidates() {
    final env = Platform.environment['CONTROLLER_LAB_SDL3'];
    final exeDir = p.dirname(Platform.resolvedExecutable);
    return [
      if (env != null && env.isNotEmpty) env,
      if (Platform.isWindows) ...[p.join(exeDir, 'SDL3.dll'), 'SDL3.dll'],
      if (Platform.isLinux) ...[
        p.join(exeDir, 'lib', 'libSDL3.so.0'),
        'libSDL3.so.0',
        'libSDL3.so',
      ],
      if (Platform.isMacOS) 'libSDL3.dylib',
    ];
  }

  /// Loads SDL3, or returns null and why not.
  static (FfiSdl?, String?) load() {
    final tried = <String>[];
    for (final c in candidates()) {
      try {
        final lib = DynamicLibrary.open(c);
        try {
          return (FfiSdl._(lib), null);
        } on ArgumentError catch (e) {
          return (null, 'SDL3 at $c is too old (missing ${e.message}).');
        }
      } on ArgumentError {
        tried.add(c);
      } catch (_) {
        tried.add(c);
      }
    }
    final where = Platform.isWindows
        ? 'SDL3.dll should be next to controller_lab.exe.'
        : Platform.isLinux
        ? 'Install it (Ubuntu 25.04+/Debian 13: sudo apt install libsdl3-0).'
        : 'SDL3 is only used on Windows and Linux.';
    return (null, 'SDL3 not found. $where (Tried: ${tried.join(', ')})');
  }

  final bool Function(Pointer<Utf8>, Pointer<Utf8>) _setHint;
  final bool Function(int) _init;
  final void Function() _quit;
  final Pointer<Utf8> Function() _getError;
  final int Function() _getVersion;
  final void Function(Pointer<Void>) _free;
  final bool Function(Pointer<Uint8>) _pollEvent;
  final Pointer<Uint32> Function(Pointer<Int32>) _getJoysticks;
  final bool Function(int) _isGamepad;
  final _JsPtr Function(int) _openJoystick, _openGamepad;
  final void Function(_JsPtr) _closeJoystick, _closeGamepad;
  final Pointer<Utf8> Function(_JsPtr) _jsName, _jsPath, _jsSerial, _gpName;
  final int Function(_JsPtr) _jsVendor, _jsProduct, _jsProductVersion;
  final _SdlGuid Function(_JsPtr) _jsGuid;
  final void Function(_SdlGuid, Pointer<Utf8>, int) _guidToString;
  final int Function(_JsPtr) _jsType, _jsConnection;
  final int Function(_JsPtr, Pointer<Int32>) _jsPower;
  final int Function(_JsPtr) _jsNumAxes, _jsNumButtons, _jsNumHats;
  final int Function(_JsPtr, int) _jsAxis, _jsHat;
  final bool Function(_JsPtr, int) _jsButton;
  final bool Function(_JsPtr, int, int, int) _jsRumble;
  final int Function(_JsPtr) _gpType, _gpRealType;
  final Pointer<Utf8> Function(_JsPtr) _gpMapping;
  final bool Function(_JsPtr, int) _gpHasButton, _gpHasAxis, _gpButton;
  final int Function(_JsPtr, int) _gpAxis, _gpLabel;

  final Map<int, _JsPtr> _joysticks = {};
  final Map<int, _JsPtr> _gamepads = {};
  Pointer<Uint8>? _event;
  Pointer<Int32>? _int32;

  static String _read(Pointer<Utf8> s) => s == nullptr ? '' : s.toDartString();

  @override
  String get version {
    final v = _getVersion();
    return '${v ~/ 1000000}.${v ~/ 1000 % 1000}.${v % 1000}';
  }

  @override
  bool init(Map<String, String> hints) {
    using((arena) {
      for (final e in hints.entries) {
        _setHint(
          e.key.toNativeUtf8(allocator: arena),
          e.value.toNativeUtf8(allocator: arena),
        );
      }
    });
    _event = calloc<Uint8>(_eventSize);
    _int32 = calloc<Int32>();
    return _init(_initGamepad | _initJoystick);
  }

  @override
  String lastError() => _read(_getError());

  @override
  bool pumpEvents() {
    final ev = _event;
    if (ev == null) return false;
    var changed = false;
    // SDL_PollEvent pumps (reads the controllers) when the queue is empty.
    // The button/axis events themselves aren't needed: state is read
    // directly, so the queue is just drained.
    var n = 0;
    while (_pollEvent(ev) && n++ < 4096) {
      final type = ev.cast<Uint32>().value;
      if (type == _eventJoystickAdded ||
          type == _eventJoystickRemoved ||
          type == _eventJoystickBattery ||
          type == _eventGamepadAdded ||
          type == _eventGamepadRemoved ||
          type == _eventGamepadRemapped) {
        changed = true;
      }
    }
    return changed;
  }

  @override
  List<int> joystickIds() {
    final count = _int32!;
    final ids = _getJoysticks(count);
    if (ids == nullptr) return const [];
    final out = [for (var i = 0; i < count.value; i++) ids[i]];
    _free(ids.cast());
    return out;
  }

  @override
  bool open(int id) {
    final js = _openJoystick(id);
    if (js == nullptr) return false;
    _joysticks[id] = js;
    if (_isGamepad(id)) {
      final gp = _openGamepad(id);
      if (gp != nullptr) _gamepads[id] = gp;
    }
    return true;
  }

  @override
  void close(int id) {
    final gp = _gamepads.remove(id);
    if (gp != null) _closeGamepad(gp);
    final js = _joysticks.remove(id);
    if (js != null) _closeJoystick(js);
  }

  @override
  ControllerInfo info(int id, String source) {
    final js = _joysticks[id]!;
    // A remap can make a joystick a gamepad (or not) while it's open.
    if (!_gamepads.containsKey(id) && _isGamepad(id)) {
      final gp = _openGamepad(id);
      if (gp != nullptr) _gamepads[id] = gp;
    }
    final gp = _gamepads[id];
    final guid = using((arena) {
      final buf = arena<Uint8>(33).cast<Utf8>();
      _guidToString(_jsGuid(js), buf, 33);
      return buf.toDartString();
    });
    var mapping = '';
    if (gp != null) {
      final m = _gpMapping(gp);
      mapping = _read(m);
      if (m != nullptr) _free(m.cast());
    }
    final (conn, power, pct) = this.power(id);
    return ControllerInfo(
      id: id,
      name: _read(_jsName(js)),
      source: source,
      vendorId: _jsVendor(js),
      productId: _jsProduct(js),
      productVersion: _jsProductVersion(js),
      guid: guid,
      path: _read(_jsPath(js)),
      serial: _read(_jsSerial(js)),
      joystickType: _jsType(js),
      gamepadType: gp == null
          ? GamepadType.unknown
          : GamepadType.fromSdl(_gpType(gp)),
      realGamepadType: gp == null
          ? GamepadType.unknown
          : GamepadType.fromSdl(_gpRealType(gp)),
      connection: conn,
      power: power,
      batteryPercent: pct,
      isGamepad: gp != null,
      mapping: mapping,
      gamepadName: gp == null ? '' : _read(_gpName(gp)),
      buttonCount: _jsNumButtons(js).clamp(0, 512),
      axisCount: _jsNumAxes(js).clamp(0, 64),
      hatCount: _jsNumHats(js).clamp(0, 16),
      hasButtons: gp == null
          ? const {}
          : {
              for (final b in GButton.values)
                if (_gpHasButton(gp, b.index)) b,
            },
      hasAxes: gp == null
          ? const {}
          : {
              for (final a in GAxis.values)
                if (_gpHasAxis(gp, a.index)) a,
            },
      labels: gp == null
          ? const {}
          : {
              for (final b in [
                GButton.south,
                GButton.east,
                GButton.west,
                GButton.north,
              ])
                b: ButtonLabel.values[_gpLabel(gp, b.index).clamp(0, 8)],
            },
    );
  }

  @override
  (Connection, PowerState, int) power(int id) {
    final js = _joysticks[id];
    if (js == null) return (Connection.unknown, PowerState.unknown, -1);
    final pct = _int32!..value = -1;
    final state = _jsPower(js, pct);
    return (
      Connection.fromSdl(_jsConnection(js)),
      PowerState.fromSdl(state),
      pct.value,
    );
  }

  @override
  void readState(int id, PadState into) {
    final js = _joysticks[id];
    if (js == null) return;
    for (var i = 0; i < into.buttons.length; i++) {
      into.setRawButton(i, _jsButton(js, i));
    }
    for (var i = 0; i < into.axes.length; i++) {
      into.setRawAxis(i, _jsAxis(js, i));
    }
    for (var i = 0; i < into.hats.length; i++) {
      into.setRawHat(i, _jsHat(js, i));
    }
    final gp = _gamepads[id];
    if (gp == null) return;
    for (final b in GButton.values) {
      into.setButton(b, _gpButton(gp, b.index));
    }
    for (final a in GAxis.values) {
      into.setAxis(a, _gpAxis(gp, a.index));
    }
  }

  @override
  bool rumble(int id, int low, int high, int ms) {
    final js = _joysticks[id];
    return js != null && _jsRumble(js, low, high, ms);
  }

  @override
  void quit() {
    for (final id in _joysticks.keys.toList()) {
      close(id);
    }
    _quit();
    if (_event != null) calloc.free(_event!);
    if (_int32 != null) calloc.free(_int32!);
    _event = null;
    _int32 = null;
  }
}
