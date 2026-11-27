import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'buttons.dart';
import 'gamepad.dart';

typedef _ReadNative = Uint32 Function(Uint32 index, Pointer<Uint8> state);
typedef _ReadDart = int Function(int index, Pointer<Uint8> state);
typedef _CapsNative = Uint32 Function(
  IntPtr index,
  Pointer<Uint8> caps,
  Uint32 size,
);
typedef _CapsDart = int Function(int index, Pointer<Uint8> caps, int size);

/// Windows controllers: Xbox-style ones through XInput, everything else
/// (PlayStation, generic USB pads) through the older joystick interface
/// (winmm). Both libraries are looked up when [open] is called, and a
/// missing one is simply not used, so this loads safely on any Windows
/// (and does nothing when neither is there).
class WindowsPadSource implements PadSource {
  /// XInput's libraries, newest first: Windows 8+ has 1.4, the DirectX
  /// runtime installs 1.3, and 9.1.0 ships with every Windows since Vista.
  static const xinputLibraries = [
    'xinput1_4.dll',
    'xinput1_3.dll',
    'xinput9_1_0.dll',
  ];

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
  final Set<int> _xinputConnected = {};
  final Map<int, int> _joyMakers = {};

  @override
  bool open() {
    for (final name in xinputLibraries) {
      try {
        _xinputGetState = DynamicLibrary.open(name)
            .lookupFunction<_ReadNative, _ReadDart>('XInputGetState');
        break;
      } catch (_) {
        // Try the older library.
      }
    }
    try {
      final winmm = DynamicLibrary.open('winmm.dll');
      _joyGetPosEx = winmm.lookupFunction<_ReadNative, _ReadDart>(
        'joyGetPosEx',
      );
      _joyGetDevCaps = winmm.lookupFunction<_CapsNative, _CapsDart>(
        'joyGetDevCapsW',
      );
    } catch (_) {
      // No joystick interface; XInput alone still works.
      _joyGetPosEx = null;
      _joyGetDevCaps = null;
    }
    if (_xinputGetState == null && _joyGetPosEx == null) return false;
    _buffer = calloc<Uint8>(_joySize);
    _caps = calloc<Uint8>(_joyCapsSize);
    return true;
  }

  @override
  void close() {
    final buffer = _buffer;
    if (buffer != null) calloc.free(buffer);
    _buffer = null;
    final caps = _caps;
    if (caps != null) calloc.free(caps);
    _caps = null;
  }

  @override
  PadKind? read(bool rescan, Set<PadButton> pressed) {
    final buffer = _buffer;
    if (buffer == null) return null;
    final xbox = _readXInput(buffer, rescan, pressed);
    return _readJoysticks(buffer, rescan, pressed) ?? xbox;
  }

  @override
  ({int sony, int others}) count() {
    final sony = _joyMakers.values.where((m) => m == _sony).length;
    final microsoft = _joyMakers.values.where((m) => m == _microsoft).length;
    final xinput = _xinputConnected.length;
    // With XInput active, Microsoft joysticks are those same pads again.
    final others =
        xinput +
        (_joyMakers.length - sony - microsoft) +
        (xinput == 0 ? microsoft : 0);
    return (sony: sony, others: others);
  }

  PadKind? _readXInput(
    Pointer<Uint8> buffer,
    bool rescan,
    Set<PadButton> pressed,
  ) {
    final getState = _xinputGetState;
    if (getState == null) return null;
    PadKind? touched;
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
      final stick = fromStick(
        pad.getInt16(8, Endian.little),
        pad.getInt16(10, Endian.little),
        _xinputStickThreshold,
      );
      if (stick != null) pressed.add(stick);
      if (pressed.length > before) touched = PadKind.xbox;
    }
    return touched;
  }

  PadKind? _readJoysticks(
    Pointer<Uint8> buffer,
    bool rescan,
    Set<PadButton> pressed,
  ) {
    final getPos = _joyGetPosEx;
    if (getPos == null) return null;
    PadKind? touched;
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

      final mine = joystickPressed(
        buttons: info.getUint32(32, Endian.little),
        pov: info.getUint32(40, Endian.little),
        x: info.getUint32(8, Endian.little),
        y: info.getUint32(12, Endian.little),
      );
      if (mine.isEmpty) continue;
      // A PlayStation pad wins even if a wrapper also presents it as an Xbox one.
      touched = maker == _sony ? PadKind.playstation : PadKind.xbox;
      pressed.addAll(mine);
    }
    return touched;
  }

  /// What a joystick's JOYINFOEX state means: [buttons] (bit per button),
  /// the d-pad "hat" [pov] and the left stick's raw [x] / [y] (0..65535).
  static Set<PadButton> joystickPressed({
    required int buttons,
    required int pov,
    required int x,
    required int y,
  }) {
    final mine = <PadButton>{};
    for (var b = 0; b < _joyButtons.length; b++) {
      if (buttons & (1 << b) != 0) mine.add(_joyButtons[b]);
    }
    // The d-pad is a "hat": an angle in hundredths of a degree, 0 = up.
    if (pov != _joyPovCentred && pov <= 36000) {
      mine.add(switch (((pov + 4500) % 36000) ~/ 9000) {
        0 => PadButton.up,
        1 => PadButton.right,
        2 => PadButton.down,
        _ => PadButton.left,
      });
    } else {
      // Stick axes run 0..65535, and up is the low end.
      final stick = fromStick(
        x - _joyCentre,
        _joyCentre - y,
        _joyStickThreshold,
      );
      if (stick != null) mine.add(stick);
    }
    return mine;
  }

  /// The USB vendor id of joystick [index], or 0 if it can't be read.
  int _makerOf(int index) {
    final getCaps = _joyGetDevCaps;
    final caps = _caps;
    if (getCaps == null || caps == null) return 0;
    if (getCaps(index, caps, _joyCapsSize) != 0) return 0;
    return ByteData.sublistView(caps.asTypedList(2))
        .getUint16(0, Endian.little);
  }
}

/// The direction a stick points: [x] grows to the right and [y] grows
/// upward; inside [threshold] on both axes is the dead zone (null).
PadButton? fromStick(int x, int y, int threshold) {
  if (x.abs() < threshold && y.abs() < threshold) return null;
  if (y.abs() >= x.abs()) return y > 0 ? PadButton.up : PadButton.down;
  return x > 0 ? PadButton.right : PadButton.left;
}
