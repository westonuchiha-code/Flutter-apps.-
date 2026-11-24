/// Tempo and step timing. A bar is 16 sixteenth-note steps.
class Transport {
  const Transport({this.bpm = 110, this.swing = 0, this.sampleRate = 48000});

  static const stepsPerBar = 16;

  final double bpm;

  /// 0 (straight) .. 0.5 (heavy shuffle): even steps get longer, odd shorter.
  final double swing;
  final int sampleRate;

  /// Length of a straight sixteenth note in frames (fractional).
  double get baseStep => sampleRate * 60 / bpm / 4;

  /// One bar in frames (swing keeps pairs the same total length).
  int get barFrames => (baseStep * stepsPerBar).round();

  /// Frame at which [step] (counted from 0 since play) starts. Computing
  /// from the start avoids rounding drift between steps.
  int stepStart(int step) {
    final pairs = step ~/ 2;
    var f = pairs * 2 * baseStep;
    if (step.isOdd) f += baseStep * (1 + swing);
    return f.round();
  }

  int stepLength(int step) => stepStart(step + 1) - stepStart(step);
}
