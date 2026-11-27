import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'diag.dart';

/// Controller buttons by position, so they mean the same on every brand:
/// [south] is ✕ on PlayStation and A on Xbox, [east] is ○ / B, [west] is
/// □ / X and [north] is △ / Y.
enum PadButton {
  up,
  down,
  left,
  right,
  south,
  east,
  west,
  north,
  l1,
  r1,
  l2,
  r2,
  select,
  start,
  l3,
  r3,
}

/// Which symbols are printed on the controller in use.
enum PadKind { playstation, xbox }

typedef _ReadNative =Uint32 Function(Uint32 index, Pointer<Uint8> state);
typedef _ReadDart = int Function(int index, Pointer<Uint8> state);
typedef _CapsNative = Uint32 Function(IntPtr index, Pointer<Uint8> caps, Uint32 size);
typedef _CapsDart = int Function(int index, Pointer<Uint8> caps, int size);

/// Reads game controllers on desktop. Windows: Xbox-style ones through
/// XInput, and everything else (PlayStation, generic USB pads) through the
/// older joystick interface. Linux: the kernel's joystick devices
/// (/dev/input/js*). Android delivers controller buttons as key presses, so
/// those are handled with the keyboard instead.
class GamepadInput {
  GamepadInput({required this.onButton, required this.isActive, this.onChanged, this.onQuitHold});

  /// Called once per press; the four directions repeat while held.
  final void Function(PadButton button) onButton;

  /// Controllers report input even when another window has focus, so the
  /// owner says when the TV is actually in front.
  final bool Function() isActive;

  static const _tick = Duration(milliseconds: 50);
  static const _firstRepeat = Duration(milliseconds: 450);
  static const _nextRepeat = Duration(milliseconds: 220);
  static const _directions = [PadButton.up, PadButton.down, PadButton.left, PadButton.right];

  static const _xinputSlots = 4;
  static const _xinputSize = 16;
  static const _xinputStickThreshold = 16000;
  static const _xinputTriggerThreshold = 100;
  static const _xinputButtons = {
    0x0001: PadButton.up,
    0x0002: PadButton.down,
    0x0004: PadButton.left,
    0x0008: PadButton.right,
    0x0010: PadButton.start,
    0x0020: PadButton.select,
    0x0040: PadButton.l3,
    0x0080: PadButton.r3,
    0x0100: PadButton.l1,
    0x0200: PadButton.r1,
    0x1000: PadButton.south,
    0x2000: PadButton.east,
    0x4000: PadButton.west,
    0x8000: PadButton.north,
  };

  static const _joySlots = 16;
  static const _joySize = 52; // JOYINFOEX
  static const _joyCapsSize = 728; // JOYCAPSW
  static const _joyReturnAll = 0xFF;
  static const _joyCentre = 32767;
  static const _joyStickThreshold = 16000;
  static const _joyPovCentred = 0xFFFF;
  static const _microsoft = 0x045E;
  static const _sony = 0x054C;

  /// Called once when Select and Start have both been held for a moment:
  /// the way out when nothing on screen can be seen or reached.
  final void Function()? onQuitHold;

  static const _quitHold = Duration(milliseconds: 1500);
  DateTime? _quitSince;
  bool _quitFired = false;

  /// Called when a controller is plugged in or removed, or [kind] changes.
  final void Function()? onChanged;

  /// The kind of controller in use: the one plugged in, or with several
  /// kinds plugged in, the one last touched.
  PadKind kind = PadKind.xbox;

  /// How many controllers are plugged in.
  int connected = 0;

  PadKind _reportedKind = PadKind.xbox;
  int _reportedConnected = 0;

  /// Button order shared by PlayStation pads and most generic USB pads.
  static const _joyButtons = [
    PadButton.west,
    PadButton.south,
    PadButton.east,
    PadButton.north,
    PadButton.l1,
    PadButton.r1,
    PadButton.l2,
    PadButton.r2,
    PadButton.select,
    PadButton.start,
    PadButton.l3,
    PadButton.r3,
  ];

  _ReadDart? _xinputGetState;
  _ReadDart? _joyGetPosEx;
  _CapsDart? _joyGetDevCaps;
  Pointer<Uint8>? _buffer;
  Pointer<Uint8>? _caps;
  Timer? _timer;
  final Set<int> _xinputConnected = {};
  final Map<int, int> _joyMakers = {};
  int _ticks = 0;
  Set<PadButton> _down = {};
  PadButton? _heldDirection;
  DateTime _nextFire = DateTime.now();

  void start() {
    if (_timer != null) return;
    if (Platform.isLinux) {
      _timer = Timer.periodic(_tick, (_) => _poll());
      return;
    }
    if (!Platform.isWindows) return;
    for (final name in const ['xinput1_4.dll', 'xinput9_1_0.dll']) {
      try {
        _xinputGetState =
            DynamicLibrary.open(name).lookupFunction<_ReadNative, _ReadDart>('XInputGetState');
        break;
      } catch (_) {
        // Try the older library.
      }
    }
    try {
      final winmm = DynamicLibrary.open('winmm.dll');
      _joyGetPosEx = winmm.lookupFunction<_ReadNative, _ReadDart>('joyGetPosEx');
      _joyGetDevCaps = winmm.lookupFunction<_CapsNative, _CapsDart>('joyGetDevCapsW');
    } catch (_) {
      // No joystick interface; XInput alone still works.
    }
    if (_xinputGetState == null && _joyGetPosEx == null) return;
    _buffer = calloc<Uint8>(_joySize);
    _caps = calloc<Uint8>(_joyCapsSize);
    _timer = Timer.periodic(_tick, (_) => _poll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    final buffer = _buffer;
    if (buffer != null) calloc.free(buffer);
    _buffer = null;
    final caps = _caps;
    if (caps != null) calloc.free(caps);
    _caps = null;
    for (final pad in _linuxPads.values) {
      unawaited(pad.input?.cancel());
    }
    _linuxPads.clear();
  }

  void _poll() {
    // Asking about an unplugged slot is slow, so look for new controllers
    // only once a second.
    final rescan = _ticks++ % 20 == 0;
    final pressed = <PadButton>{};
    final buffer = _buffer;
    if (buffer != null) {
      _readXInput(buffer, rescan, pressed);
      _readJoysticks(buffer, rescan, pressed);
    }
    if (Platform.isLinux) _readLinux(rescan, pressed);
    if (rescan) _countConnected();
    if (kind != _reportedKind || connected != _reportedConnected) {
      _reportedKind = kind;
      _reportedConnected = connected;
      onChanged?.call();
    }

    final active = isActive();
    final now = DateTime.now();
    if (pressed.contains(PadButton.select) && pressed.contains(PadButton.start)) {
      _quitSince ??= now;
      if (!_quitFired && active && now.difference(_quitSince!) >= _quitHold) {
        _quitFired = true;
        onQuitHold?.call();
      }
    } else {
      _quitSince = null;
      _quitFired = false;
    }
    PadButton? direction;
    for (final d in _directions) {
      if (pressed.remove(d)) direction ??= d;
    }
    for (final button in pressed) {
      if (active && !_down.contains(button)) onButton(button);
    }
    _down = pressed;

    if (direction != _heldDirection) {
      _heldDirection = direction;
      _nextFire = now.add(_firstRepeat);
    } else if (direction == null || now.isBefore(_nextFire)) {
      return;
    } else {
      _nextFire = now.add(_nextRepeat);
    }
    if (direction != null && active) onButton(direction);
  }

  /// Works out what's plugged in, so the right symbols show before any
  /// button has been pressed.
  void _countConnected() {
    final int sony;
    final int others;
    if (Platform.isLinux) {
      sony = _linuxPads.values.where((p) => p.sony).length;
      others = _linuxPads.length - sony;
    } else {
      sony = _joyMakers.values.where((m) => m == _sony).length;
      final microsoft = _joyMakers.values.where((m) => m == _microsoft).length;
      final xinput = _xinputConnected.length;
      // With XInput active, Microsoft joysticks are those same pads again.
      others = xinput + (_joyMakers.length - sony - microsoft) + (xinput == 0 ? microsoft : 0);
    }
    connected = sony + others;
    kind = kindFromConnected(sony: sony, others: others) ?? kind;
  }

  static int Function()? _foregroundWindow;
  static int Function(int, Pointer<Uint32>)? _windowProcess;

  /// Whether one of this app's windows is the one in front (Windows only;
  /// true elsewhere). Asked of Windows directly, which is more dependable
  /// than waiting to be told.
  static bool appInFront() {
    if (!Platform.isWindows) return true;
    try {
      final user32 = DynamicLibrary.open('user32.dll');
      _foregroundWindow ??=
          user32.lookupFunction<IntPtr Function(), int Function()>('GetForegroundWindow');
      _windowProcess ??= user32.lookupFunction<Uint32 Function(IntPtr, Pointer<Uint32>),
          int Function(int, Pointer<Uint32>)>('GetWindowThreadProcessId');
      final owner = calloc<Uint32>();
      try {
        _windowProcess!(_foregroundWindow!(), owner);
        return owner.value == pid;
      } finally {
        calloc.free(owner);
      }
    } catch (_) {
      return true;
    }
  }

  void _readXInput(Pointer<Uint8> buffer, bool rescan, Set<PadButton> pressed) {
    final getState = _xinputGetState;
    if (getState == null) return;
    for (var i = 0; i < _xinputSlots; i++) {
      if (!rescan && !_xinputConnected.contains(i)) continue;
      if (getState(i, buffer) != 0) {
        _xinputConnected.remove(i);
        continue;
      }
      _xinputConnected.add(i);
      final before = pressed.length;
      final pad = ByteData.sublistView(buffer.asTypedList(_xinputSize));
      final buttons = pad.getUint16(4, Endian.little);
      _xinputButtons.forEach((mask, button) {
        if (buttons & mask != 0) pressed.add(button);
      });
      if (pad.getUint8(6) > _xinputTriggerThreshold) pressed.add(PadButton.l2);
      if (pad.getUint8(7) > _xinputTriggerThreshold) pressed.add(PadButton.r2);
      final stick = _fromStick(
        pad.getInt16(8, Endian.little),
        pad.getInt16(10, Endian.little),
        _xinputStickThreshold,
      );
      if (stick != null) pressed.add(stick);
      if (pressed.length > before) kind = PadKind.xbox;
    }
  }

  void _readJoysticks(Pointer<Uint8> buffer, bool rescan, Set<PadButton> pressed) {
    final getPos = _joyGetPosEx;
    if (getPos == null) return;
    for (var i = 0; i < _joySlots; i++) {
      if (!rescan && !_joyMakers.containsKey(i)) continue;
      final info = ByteData.sublistView(buffer.asTypedList(_joySize));
      info.setUint32(0, _joySize, Endian.little);
      info.setUint32(4, _joyReturnAll, Endian.little);
      if (getPos(i, buffer) != 0) {
        _joyMakers.remove(i);
        continue;
      }
      final maker = _joyMakers[i] ??= _makerOf(i);
      // Xbox pads show up here too, with their buttons in another order;
      // XInput already reads those.
      if (maker == _microsoft && _xinputConnected.isNotEmpty) continue;

      final mine = <PadButton>{};
      final buttons = info.getUint32(32, Endian.little);
      for (var b = 0; b < _joyButtons.length; b++) {
        if (buttons & (1 << b) != 0) mine.add(_joyButtons[b]);
      }
      // The d-pad is a "hat": an angle in hundredths of a degree, 0 = up.
      final pov = info.getUint32(40, Endian.little);
      if (pov != _joyPovCentred && pov <= 36000) {
        mine.add(switch (((pov + 4500) % 36000) ~/ 9000) {
          0 => PadButton.up,
          1 => PadButton.right,
          2 => PadButton.down,
          _ => PadButton.left,
        });
      } else {
        // Stick axes run 0..65535, and up is the low end.
        final stick = _fromStick(
          info.getUint32(8, Endian.little) - _joyCentre,
          _joyCentre - info.getUint32(12, Endian.little),
          _joyStickThreshold,
        );
        if (stick != null) mine.add(stick);
      }
      if (mine.isEmpty) continue;
      // A PlayStation pad wins even if a wrapper also presents it as an Xbox one.
      kind = maker == _sony ? PadKind.playstation : PadKind.xbox;
      pressed.addAll(mine);
    }
  }

  // ---------------------------------------------------------------------------
  // Linux

  final Map<String, _LinuxPad> _linuxPads = {};
  static final _jsDevice = RegExp(r'^js\d+$');

  void _readLinux(bool rescan, Set<PadButton> pressed) {
    if (rescan) _findLinuxPads();
    for (final pad in _linuxPads.values) {
      final mine = linuxPadPressed(pad.buttons, pad.axes, sony: pad.sony);
      if (mine.isEmpty) continue;
      kind = pad.sony ? PadKind.playstation : PadKind.xbox;
      pressed.addAll(mine);
    }
  }

  void _findLinuxPads() {
    final List<FileSystemEntity> entries;
    try {
      entries = Directory('/dev/input').listSync();
    } catch (_) {
      return;
    }
    for (final entry in entries) {
      final name = entry.uri.pathSegments.last;
      if (!_jsDevice.hasMatch(name) || _linuxPads.containsKey(name)) continue;
      var sony = false;
      try {
        final vendor = File('/sys/class/input/$name/device/id/vendor').readAsStringSync().trim();
        sony = vendor.toLowerCase() == '054c';
      } catch (_) {
        // Unknown maker: treat it as an Xbox-style pad.
      }
      final pad = _LinuxPad(sony);
      _linuxPads[name] = pad;
      diag('controller $name found (${sony ? 'Sony' : 'other maker'})');
      void drop() => _linuxPads.remove(name);
      var heard = false;
      var pressedOnce = false;
      // The device hands over whatever events have arrived; it closes or
      // errors when the controller is unplugged.
      pad.input = File(entry.path).openRead().listen(
            (bytes) {
              applyJsEvents(bytes, pad.pending, pad.buttons, pad.axes);
              if (!heard) {
                heard = true;
                diag('controller $name: first ${bytes.length} bytes read');
              }
              if (!pressedOnce && pad.buttons.isNotEmpty) {
                pressedOnce = true;
                diag('controller $name: first button press seen (button ${pad.buttons.first})');
              }
            },
            onError: (Object error) {
              diag('controller $name: read failed: $error');
              drop();
            },
            onDone: () {
              diag('controller $name: closed');
              drop();
            },
            cancelOnError: true,
          );
    }
  }

  // ---------------------------------------------------------------------------

  /// The USB vendor id of joystick [index], or 0 if it can't be read.
  int _makerOf(int index) {
    final getCaps = _joyGetDevCaps;
    final caps = _caps;
    if (getCaps == null || caps == null) return 0;
    if (getCaps(index, caps, _joyCapsSize) != 0) return 0;
    return ByteData.sublistView(caps.asTypedList(2)).getUint16(0, Endian.little);
  }

  /// [x] grows to the right and [y] grows upward.
  PadButton? _fromStick(int x, int y, int threshold) {
    if (x.abs() < threshold && y.abs() < threshold) return null;
    if (y.abs() >= x.abs()) return y > 0 ? PadButton.up : PadButton.down;
    return x > 0 ? PadButton.right : PadButton.left;
  }
}

/// The kind of controller to show symbols for, going only by what's plugged
/// in. Null when that doesn't settle it (nothing, or both kinds at once).
PadKind? kindFromConnected({required int sony, required int others}) {
  if (sony > 0 && others == 0) return PadKind.playstation;
  if (sony == 0 && others > 0) return PadKind.xbox;
  return null;
}

class _LinuxPad {
  _LinuxPad(this.sony);

  final bool sony;
  final Set<int> buttons = {};
  final Map<int, int> axes = {};
  final List<int> pending = [];
  StreamSubscription<List<int>>? input;
}

/// Applies raw Linux joystick events to a pad's state. Each event is eight
/// bytes: a time (4), a value (2, signed), a type (1: 1 = button, 2 = axis,
/// plus 0x80 for "this is the starting state") and a button or axis number.
/// [pending] carries a half-received event over to the next call.
void applyJsEvents(List<int> bytes, List<int> pending, Set<int> buttons, Map<int, int> axes) {
  pending.addAll(bytes);
  var offset = 0;
  for (; offset + 8 <= pending.length; offset += 8) {
    var value = pending[offset + 4] | (pending[offset + 5] << 8);
    if (value >= 0x8000) value -= 0x10000;
    final type = pending[offset + 6] & 0x7F;
    final number = pending[offset + 7];
    if (type == 1) {
      value != 0 ? buttons.add(number) : buttons.remove(number);
    } else if (type == 2) {
      axes[number] = value;
    }
  }
  pending.removeRange(0, offset);
}

/// Which buttons a Linux joystick's state means. Linux numbers buttons in a
/// fixed order per driver; PlayStation pads differ from Xbox-style ones.
Set<PadButton> linuxPadPressed(Set<int> buttons, Map<int, int> axes, {required bool sony}) {
  const threshold = 16000;
  const shared = {0: PadButton.south, 1: PadButton.east, 4: PadButton.l1, 5: PadButton.r1};
  const xbox = {
    2: PadButton.west,
    3: PadButton.north,
    6: PadButton.select,
    7: PadButton.start,
    9: PadButton.l3,
    10: PadButton.r3,
  };
  const playstation = {
    2: PadButton.north,
    3: PadButton.west,
    6: PadButton.l2,
    7: PadButton.r2,
    8: PadButton.select,
    9: PadButton.start,
    11: PadButton.l3,
    12: PadButton.r3,
  };
  final pressed = <PadButton>{};
  final layout = sony ? playstation : xbox;
  for (final b in buttons) {
    final button = shared[b] ?? layout[b];
    if (button != null) pressed.add(button);
  }
  if (!sony) {
    // Xbox triggers are axes that rest at the low end.
    if ((axes[2] ?? -32767) > 0) pressed.add(PadButton.l2);
    if ((axes[5] ?? -32767) > 0) pressed.add(PadButton.r2);
  }
  // Axes 6 and 7 are the d-pad, 0 and 1 the left stick; up is negative.
  PadButton? direction(int x, int y) {
    if (x.abs() < threshold && y.abs() < threshold) return null;
    if (y.abs() >= x.abs()) return y < 0 ? PadButton.up : PadButton.down;
    return x > 0 ? PadButton.right : PadButton.left;
  }

  final way = direction(axes[6] ?? 0, axes[7] ?? 0) ?? direction(axes[0] ?? 0, axes[1] ?? 0);
  if (way != null) pressed.add(way);
  return pressed;
}

/// What's printed on [button] on that kind of controller.
String padLabel(PadButton button, PadKind kind) {
  final ps = kind == PadKind.playstation;
  return switch (button) {
    PadButton.up => 'D-pad ↑',
    PadButton.down => 'D-pad ↓',
    PadButton.left => 'D-pad ←',
    PadButton.right => 'D-pad →',
    PadButton.south => ps ? '✕' : 'A',
    PadButton.east => ps ? '○' : 'B',
    PadButton.west => ps ? '□' : 'X',
    PadButton.north => ps ? '△' : 'Y',
    PadButton.l1 => ps ? 'L1' : 'LB',
    PadButton.r1 => ps ? 'R1' : 'RB',
    PadButton.l2 => ps ? 'L2' : 'LT',
    PadButton.r2 => ps ? 'R2' : 'RT',
    PadButton.select => ps ? 'Share' : 'Back',
    PadButton.start => ps ? 'Options' : 'Start',
    PadButton.l3 => ps ? 'L3' : 'LS',
    PadButton.r3 => ps ? 'R3' : 'RS',
  };
}
