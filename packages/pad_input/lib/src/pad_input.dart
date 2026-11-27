import 'dart:io';

import 'package:flutter/widgets.dart';

import 'buttons.dart';
import 'gamepad.dart';

/// A screen's hold on [PadInput]: it hears buttons while it is the newest
/// enabled one. [detach] when done.
class PadHandle {
  PadHandle._(this._input, this.onButton, this.onRelease, this.enabled);

  final PadInput _input;
  final void Function(PadButton button) onButton;
  final void Function(PadButton button)? onRelease;

  /// Whether this one takes buttons now (false: the next older one may).
  final bool Function() enabled;

  void detach() => _input._detach(this);
}

/// The app's controllers, read once and shared: a [GamepadInput] that
/// runs while anything is attached, passing each press to the newest
/// attached [PadHandle] that is [PadHandle.enabled] (so a page pushed on
/// top takes the controller, and gives it back when it goes). Listen to it
/// for [connected] / [kind] / [used] changes (button hints).
///
/// Android delivers controllers as key events (see [PadKeys]), so there
/// this reads nothing and [connected] stays 0.
class PadInput extends ChangeNotifier {
  PadInput({this._sources, this._clock, bool Function()? isActive, this.log})
    : _isActive = isActive ?? defaultIsActive;

  static PadInput? _instance;

  /// The one the app shares ([PadListener]'s default).
  static PadInput get instance => _instance ??= PadInput();

  /// Tests: put in one with fake sources (null: a fresh real one later).
  @visibleForTesting
  static set instance(PadInput? input) => _instance = input;

  /// Troubleshooting notes (controllers found), if wanted.
  final void Function(String message)? log;

  final List<PadSource>? _sources;
  final DateTime Function()? _clock;
  final bool Function() _isActive;

  final List<PadHandle> _handles = [];
  final Map<PadButton, PadHandle> _pressedBy = {};
  GamepadInput? _pad;
  bool _used = false;

  /// Whether a window of this app is in front: asked of Windows directly,
  /// elsewhere whether the app is running in the foreground.
  static bool defaultIsActive() {
    if (Platform.isWindows) return GamepadInput.appInFront();
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  /// How many controllers are plugged in (always 0 on Android, and while
  /// nothing is attached).
  int get connected => _pad?.connected ?? 0;

  /// The kind of controller plugged in or last touched.
  PadKind get kind => _pad?.kind ?? PadKind.xbox;

  /// A controller is plugged in.
  bool get hasPad => connected > 0;

  /// A controller button has been pressed since the app started.
  bool get used => _used;

  /// Whether controllers are being read on this platform right now.
  bool get polling => _pad?.polling ?? false;

  /// The reader, for tests that drive it tick by tick.
  @visibleForTesting
  GamepadInput? get reader => _pad;

  /// Starts passing buttons to [onButton] (and releases of buttons that
  /// aren't directions to [onRelease]) whenever [enabled] says so and no
  /// newer enabled handle is attached.
  PadHandle attach({
    required void Function(PadButton button) onButton,
    void Function(PadButton button)? onRelease,
    bool Function()? enabled,
  }) {
    final handle = PadHandle._(this, onButton, onRelease, enabled ?? _always);
    _handles.add(handle);
    _pad ??= GamepadInput(
      onButton: _press,
      onRelease: _release,
      onChanged: notifyListeners,
      isActive: _isActive,
      log: log,
      sources: _sources,
      clock: _clock,
    )..start();
    return handle;
  }

  static bool _always() => true;

  void _detach(PadHandle handle) {
    _handles.remove(handle);
    _pressedBy.removeWhere((_, h) => h == handle);
    if (_handles.isEmpty) {
      _pad?.stop();
      _pad = null;
    }
  }

  void _press(PadButton button) {
    if (!_used) {
      _used = true;
      notifyListeners();
    }
    for (final h in _handles.reversed) {
      if (!h.enabled()) continue;
      if (!button.isDirection) _pressedBy[button] = h;
      h.onButton(button);
      return;
    }
  }

  void _release(PadButton button) {
    // The release goes to whoever had the press, even if another page is
    // in front now.
    _pressedBy.remove(button)?.onRelease?.call(button);
  }

  @override
  void dispose() {
    _pad?.stop();
    _pad = null;
    _handles.clear();
    super.dispose();
  }
}
