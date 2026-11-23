// Small DSP building blocks shared by the chip emulations. Pure Dart (no
// Flutter imports) so the synth runs in background isolates and tests.
import 'dart:math' as math;
import 'dart:typed_data';

/// Number of sub-samples computed per output sample. Chip outputs change in
/// hard steps; averaging 8 sub-samples (a box filter) removes most aliasing.
const oversample = 8;

/// First-order high-pass, used as the DC-blocking coupling capacitor.
class HighPass {
  HighPass(double cutoffHz, double sampleRate)
    : _a = math.exp(-2 * math.pi * cutoffHz / sampleRate);
  final double _a;
  double _x = 0;
  double _y = 0;

  double process(double x) {
    _y = _a * (_y + x - _x);
    _x = x;
    return _y;
  }
}

/// Second-order (RBJ) low-pass, used for each machine's output filtering.
class LowPass {
  LowPass(double cutoffHz, double sampleRate, {double q = 0.7071}) {
    final f = math.min(cutoffHz, sampleRate * 0.45);
    final w = 2 * math.pi * f / sampleRate;
    final alpha = math.sin(w) / (2 * q);
    final cosW = math.cos(w);
    final a0 = 1 + alpha;
    _b0 = (1 - cosW) / 2 / a0;
    _b1 = (1 - cosW) / a0;
    _b2 = _b0;
    _a1 = -2 * cosW / a0;
    _a2 = (1 - alpha) / a0;
  }

  late final double _b0, _b1, _b2, _a1, _a2;
  double _x1 = 0, _x2 = 0, _y1 = 0, _y2 = 0;

  double process(double x) {
    final y = _b0 * x + _b1 * _x1 + _b2 * _x2 - _a1 * _y1 - _a2 * _y2;
    _x2 = _x1;
    _x1 = x;
    _y2 = _y1;
    _y1 = y;
    return y;
  }
}

/// Steps through a table of levels; the table is one waveform period.
/// [tick] advances one sub-sample.
class TableOsc {
  TableOsc(List<double> table) : table = Float64List.fromList(table);

  Float64List table;
  double phase = 0;
  double _inc = 0;

  /// Sets the waveform frequency; [subRate] is the sub-sample rate.
  void setFrequency(double hz, double subRate) => _inc = hz / subRate;

  /// Steps per second of the table (for chips that clock their pattern).
  void setStepRate(double stepsPerSecond, double subRate) =>
      _inc = stepsPerSecond / table.length / subRate;

  double tick() {
    final n = table.length;
    var i = (phase * n).toInt();
    if (i >= n) i = n - 1;
    final v = table[i];
    phase += _inc;
    if (phase >= 1) phase -= phase.floorToDouble();
    return v;
  }
}

/// Linear-feedback shift register noise clocked at a fixed rate.
class LfsrNoise {
  LfsrNoise({required this.bits, required this.taps, int seed = 1})
    : _reg = seed;

  /// Register width in bits.
  final int bits;

  /// Bit positions XORed to form the feedback bit.
  final List<int> taps;

  int _reg;
  double _phase = 0;
  double _inc = 0;

  void setClock(double hz, double subRate) => _inc = hz / subRate;

  /// Current output bit (0 or 1).
  int get bit => _reg & 1;

  /// Raw register (for chips that read several bits).
  int get register => _reg;

  void step() {
    var fb = 0;
    for (final t in taps) {
      fb ^= (_reg >> t) & 1;
    }
    _reg = (_reg >> 1) | (fb << (bits - 1));
    if (_reg == 0) _reg = 1;
  }

  /// Advances one sub-sample; returns the output bit.
  int tick() {
    _phase += _inc;
    // Cap the work per sub-sample for very high clock rates.
    var guard = 64;
    while (_phase >= 1 && guard-- > 0) {
      _phase -= 1;
      step();
    }
    if (_phase >= 1) _phase -= _phase.floorToDouble();
    return _reg & 1;
  }
}

/// Builds a 4-bit (0–15) wavetable of [length] samples from a function of
/// phase (0–1) returning -1..1.
List<double> wave4bit(double Function(double phase) f, {int length = 32}) => [
  for (var i = 0; i < length; i++)
    ((f(i / length).clamp(-1.0, 1.0) + 1) * 7.5).roundToDouble(),
];

/// Gentle saturating clip to keep the output within -1..1.
double softClip(double x) {
  if (x > 3) return 1;
  if (x < -3) return -1;
  return x * (27 + x * x) / (27 + 9 * x * x);
}

/// Pitch ratio for [cents].
double centsToRatio(double cents) => math.pow(2, cents / 1200).toDouble();
