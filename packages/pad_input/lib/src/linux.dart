import 'dart:async';
import 'dart:io';

import 'buttons.dart';
import 'gamepad.dart';

/// Linux controllers (best-effort): the kernel's joystick devices,
/// /dev/input/js*, read as they send events. Nothing to load, so [open]
/// always succeeds; without permission to read the devices (or without
/// any) nothing is found.
class LinuxPadSource implements PadSource {
  LinuxPadSource({this.log, this.folder = '/dev/input'});

  /// Troubleshooting notes, if wanted.
  final void Function(String message)? log;

  /// Where the joystick devices are.
  final String folder;

  final Map<String, _LinuxPad> _pads = {};
  static final _jsDevice = RegExp(r'^js\d+$');

  @override
  bool open() => true;

  @override
  void close() {
    for (final pad in _pads.values) {
      unawaited(pad.input?.cancel());
    }
    _pads.clear();
  }

  @override
  PadKind? read(bool rescan, Set<PadButton> pressed) {
    if (rescan) _findPads();
    PadKind? touched;
    for (final pad in _pads.values) {
      final mine = linuxPadPressed(pad.buttons, pad.axes, sony: pad.sony);
      if (mine.isEmpty) continue;
      touched = pad.sony ? PadKind.playstation : PadKind.xbox;
      pressed.addAll(mine);
    }
    return touched;
  }

  @override
  ({int sony, int others}) count() {
    final sony = _pads.values.where((p) => p.sony).length;
    return (sony: sony, others: _pads.length - sony);
  }

  void _findPads() {
    final List<FileSystemEntity> entries;
    try {
      entries = Directory(folder).listSync();
    } catch (_) {
      return;
    }
    for (final entry in entries) {
      final name = entry.uri.pathSegments.last;
      if (!_jsDevice.hasMatch(name) || _pads.containsKey(name)) continue;
      var sony = false;
      try {
        final vendor = File('/sys/class/input/$name/device/id/vendor')
            .readAsStringSync()
            .trim();
        sony = vendor.toLowerCase() == '054c';
      } catch (_) {
        // Unknown maker: treat it as an Xbox-style pad.
      }
      final pad = _LinuxPad(sony);
      _pads[name] = pad;
      log?.call('controller $name found (${sony ? 'Sony' : 'other maker'})');
      void drop() => _pads.remove(name);
      var heard = false;
      var pressedOnce = false;
      // The device hands over whatever events have arrived; it closes or
      // errors when the controller is unplugged.
      pad.input = File(entry.path).openRead().listen(
        (bytes) {
          applyJsEvents(bytes, pad.pending, pad.buttons, pad.axes);
          if (!heard) {
            heard = true;
            log?.call('controller $name: first ${bytes.length} bytes read');
          }
          if (!pressedOnce && pad.buttons.isNotEmpty) {
            pressedOnce = true;
            log?.call(
              'controller $name: first button press seen (button ${pad.buttons.first})',
            );
          }
        },
        onError: (Object error) {
          log?.call('controller $name: read failed: $error');
          drop();
        },
        onDone: () {
          log?.call('controller $name: closed');
          drop();
        },
        cancelOnError: true,
      );
    }
  }
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
void applyJsEvents(
  List<int> bytes,
  List<int> pending,
  Set<int> buttons,
  Map<int, int> axes,
) {
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
Set<PadButton> linuxPadPressed(
  Set<int> buttons,
  Map<int, int> axes, {
  required bool sony,
}) {
  const threshold = 16000;
  const shared = {
    0: PadButton.south,
    1: PadButton.east,
    4: PadButton.l1,
    5: PadButton.r1,
  };
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

  final way =
      direction(axes[6] ?? 0, axes[7] ?? 0) ??
      direction(axes[0] ?? 0, axes[1] ?? 0);
  if (way != null) pressed.add(way);
  return pressed;
}
