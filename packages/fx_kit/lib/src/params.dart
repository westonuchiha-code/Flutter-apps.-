import 'dart:math' as math;

/// One knob of an effect.
class ParamDef {
  const ParamDef(
    this.id,
    this.label,
    this.min,
    this.max,
    this.def, {
    this.unit = '',
    this.log = false,
    this.step,
    this.choices,
  });

  final String id, label;
  final double min, max, def;
  final String unit;

  /// Knob travel is logarithmic (frequencies, times).
  final bool log;

  /// Snap to multiples of this (e.g. 1 for whole bits).
  final double? step;

  /// Discrete options; the value is the index.
  final List<String>? choices;

  double clamp(double v) {
    var x = v.clamp(min, max).toDouble();
    final s = step;
    if (s != null) x = ((x - min) / s).round() * s + min;
    return x;
  }

  /// Knob position 0..1 → value.
  double fromKnob(double k) {
    final t = k.clamp(0.0, 1.0);
    final v = log && min > 0
        ? min * math.pow(max / min, t).toDouble()
        : min + (max - min) * t;
    return clamp(v);
  }

  /// Value → knob position 0..1.
  double toKnob(double v) {
    final x = v.clamp(min, max);
    if (log && min > 0) return math.log(x / min) / math.log(max / min);
    return max == min ? 0 : (x - min) / (max - min);
  }

  String format(double v) {
    final c = choices;
    if (c != null) return c[v.round().clamp(0, c.length - 1)];
    if (unit == '%') return '${(v * 100).round()}%';
    if (unit == 'Hz' && v >= 1000) {
      return '${(v / 1000).toStringAsFixed(1)} kHz';
    }
    if (unit == 'ms' && v >= 1000) return '${(v / 1000).toStringAsFixed(2)} s';
    final digits = step != null && step! >= 1 ? 0 : (v.abs() < 10 ? 1 : 0);
    return '${v.toStringAsFixed(digits)}${unit.isEmpty ? '' : ' $unit'}';
  }
}

double dbToGain(double db) => math.pow(10, db / 20).toDouble();
double gainToDb(double g) => 20 * math.log(math.max(g, 1e-9)) / math.ln10;
