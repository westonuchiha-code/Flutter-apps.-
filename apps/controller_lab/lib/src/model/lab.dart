import 'package:flutter/foundation.dart';

import '../layouts/layout.dart';
import '../layouts/raw.dart';
import 'backend.dart';
import 'controls.dart';
import 'guess.dart';
import 'session.dart';

/// The button that means "OK" on [info]: A wherever it is (Nintendo puts
/// A on the right, SDL's east; Xbox and PlayStation's ✕ at the bottom).
GButton confirmButton(ControllerInfo info) {
  // SDL's Wii driver reports the Wii U Pro as a "standard" pad, whose
  // labels say A is at the bottom: the controller itself says otherwise.
  if (isWiiUPro(info)) return GButton.east;
  final label = info.labels[GButton.east];
  if (label == ButtonLabel.a) return GButton.east;
  if (label != null) return GButton.south;
  final t = info.gamepadType;
  return t == GamepadType.switchPro || t == GamepadType.joyConPair
      ? GButton.east
      : GButton.south;
}

/// The "back" button on [info] (B / ○).
GButton backButton(ControllerInfo info) =>
    confirmButton(info) == GButton.east ? GButton.south : GButton.east;

/// Everything the screens show: the backend's controllers, a test
/// session for each, and button presses for navigating the app.
class ControllerLab extends ChangeNotifier {
  ControllerLab(this.backend, {this.fallback});

  PadBackend backend;

  /// Used instead when [backend] can't start (SDL3 missing): key events.
  final PadBackend Function(String? reason)? fallback;

  /// Bumped every tick in which a controller's state changed (drawings
  /// repaint on it without rebuilding the page).
  final ValueNotifier<int> frame = ValueNotifier(0);

  final Map<int, TestSession> _sessions = {};
  final Map<int, TestSession> _rawSessions = {};
  final Map<int, int> _versions = {};
  final Map<int, List<bool>> _held = {};
  final List<void Function(PadDevice, GButton)> _pressListeners = [];

  List<PadDevice> devices = const [];
  bool started = false;

  /// Why the first-choice backend isn't in use (SDL3 not found...).
  String? startProblem;

  /// How many ticks [backButton] has been held, per controller (holding
  /// it leaves the test page).
  final Map<int, int> backHeld = {};

  void start() {
    if (started) return;
    started = true;
    if (!backend.start()) {
      startProblem = backend.problem;
      final fb = fallback;
      if (fb != null) {
        backend.dispose();
        backend = fb(startProblem)..start();
      }
    }
    tick();
  }

  /// [listener] hears every button press (not release) of every pad.
  void addPressListener(void Function(PadDevice, GButton) listener) =>
      _pressListeners.add(listener);
  void removePressListener(void Function(PadDevice, GButton) listener) =>
      _pressListeners.remove(listener);

  TestSession session(PadDevice d) {
    final layout = layoutFor(d.info);
    final s = _sessions[d.info.id];
    if (s != null && s.layout.id == layout.id && _same(s.info, d.info)) {
      return s;
    }
    return _sessions[d.info.id] = TestSession(layout, d.info);
  }

  /// The raw-joystick view's own checklist.
  TestSession rawSession(PadDevice d) {
    final s = _rawSessions[d.info.id];
    if (s != null && _same(s.info, d.info)) return s;
    return _rawSessions[d.info.id] = TestSession(const RawLayout(), d.info);
  }

  /// Same controls (a battery or connection change keeps the checklist).
  static bool _same(ControllerInfo a, ControllerInfo b) =>
      identical(a, b) ||
      (a.mapping == b.mapping &&
          a.isGamepad == b.isGamepad &&
          a.buttonCount == b.buttonCount &&
          a.axisCount == b.axisCount &&
          a.hatCount == b.hatCount);

  PadDevice? byId(int? id) {
    for (final d in devices) {
      if (d.info.id == id) return d;
    }
    return null;
  }

  /// Reads the controllers once (about 60 times a second).
  void tick() {
    if (!started) return;
    final listChanged = backend.poll();
    if (listChanged) {
      devices = backend.devices;
      final ids = {for (final d in devices) d.info.id};
      _sessions.removeWhere((k, _) => !ids.contains(k));
      _rawSessions.removeWhere((k, _) => !ids.contains(k));
      _versions.removeWhere((k, _) => !ids.contains(k));
      _held.removeWhere((k, _) => !ids.contains(k));
      backHeld.removeWhere((k, _) => !ids.contains(k));
    }
    var any = listChanged;
    for (final d in devices) {
      final id = d.info.id;
      final s = d.state;
      final changed = _versions[id] != s.version;
      final s1 = session(d);
      final measuring = s1.sticks.values.any((st) => st.measuring);
      if (changed || measuring) {
        _versions[id] = s.version;
        s1.update(s);
        rawSession(d).update(s);
        any = true;
      }
      if (changed) _edges(d);
      final back = backButton(d.info);
      if (s.button(back)) {
        backHeld[id] = (backHeld[id] ?? 0) + 1;
        any = true;
      } else if (backHeld.remove(id) != null) {
        any = true;
      }
    }
    if (any) frame.value++;
    if (listChanged) notifyListeners();
  }

  void _edges(PadDevice d) {
    final held = _held.putIfAbsent(
      d.info.id,
      () => List.filled(GButton.values.length, false),
    );
    for (final b in GButton.values) {
      final now = d.state.button(b);
      if (now && !held[b.index]) {
        for (final l in List.of(_pressListeners)) {
          l(d, b);
        }
      }
      held[b.index] = now;
    }
  }

  /// Starts the checklist of [d] over.
  void reset(PadDevice d) {
    session(d).reset();
    rawSession(d).reset();
    frame.value++;
  }

  @override
  void dispose() {
    backend.dispose();
    frame.dispose();
    super.dispose();
  }
}
