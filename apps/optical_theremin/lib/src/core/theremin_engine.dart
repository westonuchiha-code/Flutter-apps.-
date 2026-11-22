import 'dart:math' as math;

import 'music.dart';
import 'settings.dart';

/// Turns 0–1 control values into a smoothed pitch and volume.
///
/// Pure logic (no audio, no camera) so it can be unit tested.
class ThereminEngine {
  ThereminEngine(this.settings);

  ThereminSettings settings;

  double _targetMidi = 60;
  double _targetVolume = 0;
  double _midi = 60;
  double _volume = 0;
  bool _started = false;

  /// Current (smoothed) pitch as a fractional MIDI note.
  double get midi => _midi;

  /// Current (smoothed) volume, 0–1, including the master volume.
  double get volume => _volume;

  double get frequency => midiToHz(_midi);

  /// Pitch the player is aiming for (after scale snapping).
  double get targetMidi => _targetMidi;

  /// Sets the control inputs. [pitchControl] and [volumeControl] are 0–1,
  /// already normalized by calibration (1 = brightest).
  void setControls({required double pitchControl, double? volumeControl}) {
    final s = settings;
    final p = s.invertPitch ? 1 - pitchControl : pitchControl;
    final raw = s.lowNote + p.clamp(0.0, 1.0) * (s.highNote - s.lowNote);
    _targetMidi = quantizeToScale(raw, s.scale, root: s.root);

    var v = 1.0;
    if (volumeControl != null) {
      v = (s.invertVolume ? 1 - volumeControl : volumeControl).clamp(0.0, 1.0);
      // Squared for a more natural loudness curve; silence near the bottom.
      v = v < 0.03 ? 0 : v * v;
    }
    _targetVolume = v * s.masterVolume;

    if (!_started) {
      _started = true;
      _midi = _targetMidi;
    }
  }

  /// Advances smoothing by [seconds].
  void step(double seconds) {
    final glide = settings.glideMs / 1000;
    final pitchAlpha = glide <= 0 ? 1.0 : 1 - math.exp(-seconds / glide);
    _midi += (_targetMidi - _midi) * pitchAlpha;
    // Volume always gets a short ramp to avoid clicks.
    final volumeAlpha = 1 - math.exp(-seconds / 0.02);
    _volume += (_targetVolume - _volume) * volumeAlpha;
  }
}
