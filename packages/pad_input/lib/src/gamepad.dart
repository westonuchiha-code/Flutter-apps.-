import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'buttons.dart';
import 'linux.dart';
import 'windows.dart';

/// One way of reading controllers, polled by [GamepadInput] every tick.
/// The real ones are [WindowsPadSource] and [LinuxPadSource]; tests give
/// their own.
abstract class PadSource {
  /// Gets ready to be read; false when it can't work here (nothing to
  /// read controllers with), and it is then left alone.
  bool open();

  /// Adds the buttons held now to [pressed]. [rescan] (about once a second)
  /// is the time to look for controllers that were plugged in. Returns the
  /// kind of the controller that had something held (the last one, if
  /// several), or null if none did.
  PadKind? read(bool rescan, Set<PadButton> pressed);

  /// What's plugged in: PlayStation pads ([sony]) and the rest. Asked
  /// after each rescan.
  ({int sony, int others}) count();

  /// Lets go of what [open] took.
  void close();
}

/// Reads game controllers on desktop. Windows: Xbox-style ones through
/// XInput, and everything else (PlayStation, generic USB pads) through the
/// older joystick interface. Linux: the kernel's joystick devices
/// (/dev/input/js*). Android delivers controller buttons as key presses, so
/// those are handled with the keyboard instead (see [PadKeys]); there this
/// polls nothing.
class GamepadInput {
  GamepadInput({
    required this.onButton,
    required this.isActive,
    this.onChanged,
    this.onQuitHold,
    this.onRelease,
    this.log,
    this._sources,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Called once per press; the four directions repeat while held.
  final void Function(PadButton button) onButton;

  /// Called when a button other than a direction is let go (for "hold"
  /// actions). Also called if the press was not passed on (the app was not
  /// in front), so treat a release without a press as nothing.
  final void Function(PadButton button)? onRelease;

  /// Controllers report input even when another window has focus, so the
  /// owner says when the app is actually in front.
  final bool Function() isActive;

  /// Troubleshooting notes (controllers found, read errors), if wanted.
  final void Function(String message)? log;

  final List<PadSource>? _sources;
  final DateTime Function() _clock;

  /// How often the controllers are read.
  static const tick = Duration(milliseconds: 50);

  /// How long a direction is held before it repeats, then how often.
  static const firstRepeat = Duration(milliseconds: 450);
  static const nextRepeat = Duration(milliseconds: 220);
  static const _directions = [
    PadButton.up,
    PadButton.down,
    PadButton.left,
    PadButton.right,
  ];

  /// Called once when Select and Start have both been held for a moment:
  /// the way out when nothing on screen can be seen or reached.
  final void Function()? onQuitHold;

  static const quitHold = Duration(milliseconds: 1500);
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

  Timer? _timer;
  List<PadSource> _open = const [];
  bool _started = false;
  int _ticks = 0;
  Set<PadButton> _down = {};
  PadButton? _heldDirection;
  DateTime _nextFire = DateTime.now();

  /// Whether controllers are being read (false on Android, in tests
  /// without sources, or where no controller library could be loaded).
  bool get polling => _open.isNotEmpty;

  /// The sources this platform reads controllers with. None on Android
  /// (key events), and none under `flutter test` (no hardware there).
  static List<PadSource> platformSources({void Function(String)? log}) {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return const [];
    if (Platform.isWindows) return [WindowsPadSource()];
    if (Platform.isLinux) return [LinuxPadSource(log: log)];
    return const [];
  }

  /// Starts reading controllers (every [tick]).
  void start() {
    if (_started) return;
    _started = true;
    _open = [
      for (final s in _sources ?? platformSources(log: log))
        if (s.open()) s,
    ];
    if (_open.isEmpty) return;
    _nextFire = _clock();
    _timer = Timer.periodic(tick, (_) => poll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    for (final s in _open) {
      s.close();
    }
    _open = const [];
    _started = false;
  }

  /// Reads the controllers once and passes on what changed; [start] calls
  /// this every [tick] (tests call it themselves).
  @visibleForTesting
  void poll() {
    // Asking about an unplugged slot is slow, so look for new controllers
    // only once a second.
    final rescan = _ticks++ % 20 == 0;
    final pressed = <PadButton>{};
    for (final s in _open) {
      final touched = s.read(rescan, pressed);
      if (touched != null) kind = touched;
    }
    if (rescan) _countConnected();
    if (kind != _reportedKind || connected != _reportedConnected) {
      _reportedKind = kind;
      _reportedConnected = connected;
      onChanged?.call();
    }

    final active = isActive();
    final now = _clock();
    if (pressed.contains(PadButton.select) &&
        pressed.contains(PadButton.start)) {
      _quitSince ??= now;
      if (!_quitFired && active && now.difference(_quitSince!) >= quitHold) {
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
    final release = onRelease;
    if (release != null) {
      for (final button in _down) {
        if (!pressed.contains(button)) release(button);
      }
    }
    _down = pressed;

    if (direction != _heldDirection) {
      _heldDirection = direction;
      _nextFire = now.add(firstRepeat);
    } else if (direction == null || now.isBefore(_nextFire)) {
      return;
    } else {
      _nextFire = now.add(nextRepeat);
    }
    if (direction != null && active) onButton(direction);
  }

  /// Works out what's plugged in, so the right symbols show before any
  /// button has been pressed.
  void _countConnected() {
    var sony = 0, others = 0;
    for (final s in _open) {
      final n = s.count();
      sony += n.sony;
      others += n.others;
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
      _foregroundWindow ??= user32
          .lookupFunction<IntPtr Function(), int Function()>(
            'GetForegroundWindow',
          );
      _windowProcess ??= user32
          .lookupFunction<
            Uint32 Function(IntPtr, Pointer<Uint32>),
            int Function(int, Pointer<Uint32>)
          >('GetWindowThreadProcessId');
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
}
