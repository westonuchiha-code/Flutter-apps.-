import 'package:flutter_test/flutter_test.dart';
import 'package:optical_theremin/src/core/music.dart';

void main() {
  test('midiToHz', () {
    expect(midiToHz(69), closeTo(440, 1e-9));
    expect(midiToHz(81), closeTo(880, 1e-9));
    expect(midiToHz(60), closeTo(261.6256, 1e-3));
  });

  test('noteName', () {
    expect(noteName(69), 'A4');
    expect(noteName(60), 'C4');
    expect(noteName(61), 'C♯4');
    expect(noteName(48), 'C3');
  });

  test('continuous scale does not snap', () {
    expect(quantizeToScale(60.37, ScaleType.continuous), 60.37);
  });

  test('chromatic snaps to nearest semitone', () {
    expect(quantizeToScale(60.4, ScaleType.chromatic), 60);
    expect(quantizeToScale(60.6, ScaleType.chromatic), 61);
  });

  test('major scale snaps to scale notes', () {
    // C major: C# (61) is not in the scale; 61.3 is closer to D (62).
    expect(quantizeToScale(61.3, ScaleType.major), 62);
    expect(quantizeToScale(60.9, ScaleType.major), 60);
    // In D major (root 2), C# is in the scale.
    expect(quantizeToScale(61.1, ScaleType.major, root: 2), 61);
  });

  test('pentatonic snaps across gaps', () {
    // C major pentatonic: C D E G A. F (65) -> E (64) or G (67).
    expect(quantizeToScale(65.0, ScaleType.majorPentatonic), 64);
    expect(quantizeToScale(66.0, ScaleType.majorPentatonic), 67);
  });
}
