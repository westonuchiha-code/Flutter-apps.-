import 'dart:math' as math;

import '../layouts/layout.dart';
import 'controls.dart';

/// How far a stick has gone, which way, and how still it sits at rest.
class StickStats {
  /// Sectors around the stick for its gate (the outline of how far it
  /// reaches in each direction).
  static const sectors = 32;

  /// How far (0..1) counts as "all the way" in a direction.
  static const reach = 0.85;

  double minX = 0, maxX = 0, minY = 0, maxY = 0;
  final List<double> gate = List.filled(sectors, 0);

  /// The biggest drift seen while measuring at rest (0..1), once measured.
  double? restDrift;
  int _measureLeft = 0;
  double _measureMax = 0;

  bool get measuring => _measureLeft > 0;

  bool get up => minY <= -reach;
  bool get down => maxY >= reach;
  bool get left => minX <= -reach;
  bool get right => maxX >= reach;

  /// It has been pushed all the way up, down, left and right.
  bool get complete => up && down && left && right;

  /// Suggested deadzone: the drift at rest plus a little margin, rounded
  /// up to the next 1%.
  double? get suggestedDeadzone => restDrift == null
      ? null
      : (math.min(1.0, restDrift! * 1.25 + 0.02) * 100).ceil() / 100;

  void add(double x, double y) {
    minX = math.min(minX, x);
    maxX = math.max(maxX, x);
    minY = math.min(minY, y);
    maxY = math.max(maxY, y);
    final m = math.min(1.0, math.sqrt(x * x + y * y));
    if (m > 0.05) {
      final a = (math.atan2(y, x) + math.pi) / (2 * math.pi);
      final i = (a * sectors).floor() % sectors;
      if (m > gate[i]) gate[i] = m;
    }
    if (_measureLeft > 0) {
      _measureMax = math.max(_measureMax, m);
      if (--_measureLeft == 0) restDrift = _measureMax;
    }
  }

  /// Measures the drift over the next [frames] readings (let go first).
  void measureRest([int frames = 90]) {
    _measureLeft = frames;
    _measureMax = 0;
  }
}

/// Range of a trigger or a raw axis.
class AxisStats {
  double min = double.infinity, max = double.negativeInfinity;

  void add(double v) {
    if (v < min) min = v;
    if (v > max) max = v;
  }
}

/// One controller's test: which parts have been tried, stick ranges and
/// gates, rest drift.
class TestSession {
  TestSession(this.layout, this.info) : parts = layout.parts(info);

  final ControllerLayout layout;
  final ControllerInfo info;
  final List<LayoutPart> parts;
  final Set<String> checked = {};
  final Map<String, StickStats> sticks = {};
  final Map<String, AxisStats> axes = {};
  int _lastVersion = -1;

  int get done => parts.where((p) => checked.contains(p.id)).length;
  int get total => parts.length;
  bool get complete => done == total && total > 0;

  StickStats stick(String id) => sticks.putIfAbsent(id, StickStats.new);
  AxisStats axis(String id) => axes.putIfAbsent(id, AxisStats.new);

  /// Reads [s]; true if anything new was checked off.
  bool update(PadState s) {
    final measuring = sticks.values.any((st) => st.measuring);
    if (s.version == _lastVersion && !measuring) return false;
    _lastVersion = s.version;
    var newly = false;
    for (final p in parts) {
      var ok = false;
      switch (p.kind) {
        case PartKind.button:
          ok = p.value(s) > 0.5;
        case PartKind.trigger:
          final v = p.value(s);
          axis(p.id).add(v);
          ok = axis(p.id).max >= 0.9;
        case PartKind.axis:
          final v = p.value(s);
          final a = axis(p.id)..add(v);
          // Both ends (a trigger resting at -1 counts when it reaches +1).
          ok = a.min <= -StickStats.reach && a.max >= StickStats.reach;
        case PartKind.stick:
          final (x, y) = p.stick(s);
          final st = stick(p.id)..add(x, y);
          ok = st.complete;
      }
      if (ok && checked.add(p.id)) newly = true;
    }
    return newly;
  }

  void measureRest() {
    for (final p in parts.where((p) => p.kind == PartKind.stick)) {
      stick(p.id).measureRest();
    }
  }

  void reset() {
    checked.clear();
    sticks.clear();
    axes.clear();
    _lastVersion = -1;
  }
}
