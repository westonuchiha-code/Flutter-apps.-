import 'dart:math' as math;

/// Converts a (possibly fractional) MIDI note number to a frequency in Hz.
double midiToHz(double midi) => 440.0 * math.pow(2, (midi - 69) / 12);

const _noteNames = [
  'C',
  'C♯',
  'D',
  'D♯',
  'E',
  'F',
  'F♯',
  'G',
  'G♯',
  'A',
  'A♯',
  'B',
];

/// Name of a MIDI note, e.g. 69 -> "A4", 60 -> "C4".
String noteName(int midi) => '${_noteNames[midi % 12]}${midi ~/ 12 - 1}';

/// Name of a pitch class (0 = C).
String pitchClassName(int pitchClass) => _noteNames[pitchClass % 12];

/// Musical scales the pitch can snap to.
enum ScaleType {
  continuous('Continuous (no snapping)', null),
  chromatic('Chromatic', [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]),
  major('Major', [0, 2, 4, 5, 7, 9, 11]),
  minor('Minor', [0, 2, 3, 5, 7, 8, 10]),
  majorPentatonic('Major pentatonic', [0, 2, 4, 7, 9]),
  minorPentatonic('Minor pentatonic', [0, 3, 5, 7, 10]),
  blues('Blues', [0, 3, 5, 6, 7, 10]);

  const ScaleType(this.label, this.steps);

  final String label;

  /// Semitone offsets from the root, or null for continuous pitch.
  final List<int>? steps;
}

/// Snaps [midi] to the nearest note of [scale] built on [root] (0 = C).
/// Continuous scales return [midi] unchanged.
double quantizeToScale(double midi, ScaleType scale, {int root = 0}) {
  final steps = scale.steps;
  if (steps == null) return midi;
  final nearest = midi.round();
  // Search outward from the nearest semitone for a note in the scale.
  for (var distance = 0; distance <= 12; distance++) {
    final candidates = distance == 0
        ? [nearest]
        // Prefer the candidate closer to the exact pitch.
        : (midi >= nearest
              ? [nearest + distance, nearest - distance]
              : [nearest - distance, nearest + distance]);
    for (final note in candidates) {
      if (steps.contains((note - root) % 12)) return note.toDouble();
    }
  }
  return nearest.toDouble();
}
