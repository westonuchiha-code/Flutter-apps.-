import 'dart:math' as math;

import 'music.dart';
import 'settings.dart';

/// Turns 0–1 control values into a smoothed pitch, loudness and shape.
///
/// Pure logic (no audio, no camera) so it can be unit tested.
class ThereminEngine {
  ThereminEngine(this.settings);

  ThereminSettings settings;

  double _targetMidi = 60;
  double _targetVolume = 0;
  double _targetShape = 0.5;
  double _midi = 60;
  double _volume = 0;
  double _shape = 0.5;
  bool _started = false;

  /// Current (smoothed) pitch as a fractional MIDI note.
  double get midi => _midi;

  /// Current (smoothed) loudness, 0–1 (before the master volume).
  double get volume => _volume;

  /// Current (smoothed) sound shape, 0–1.
  double get shape => _shape;

  double get frequency => midiToHz(_midi);

  /// Pitch the player is aiming for (after scale snapping).
  double get targetMidi => _targetMidi;

  /// Sets the control inputs (0–1, already calibrated; 1 = brightest).
  /// [volumeControl] null means full volume; [shapeControl] null means the
  /// fixed shape from the settings.
  void setControls({
    required double pitchControl,
    double? volumeControl,
    double? shapeControl,
  }) {
    final s = settings;
    final p = s.invertPitch ? 1 - pitchControl : pitchControl;
    final raw = s.lowNote + p.clamp(0.0, 1.0) * (s.highNote - s.lowNote);
    _targetMidi = quantizeToScale(raw, s.scale, root: s.root);

    var v = 1.0;
    if (volumeControl != null) {
      v = (s.invertSecond ? 1 - volumeControl : volumeControl).clamp(0.0, 1.0);
      // Squared for a more natural loudness curve; silence near the bottom.
      v = v < 0.03 ? 0 : v * v;
    }
    _targetVolume = v;

    _targetShape = shapeControl == null
        ? s.shape
        : (s.invertSecond ? 1 - shapeControl : shapeControl).clamp(0.0, 1.0);

    if (!_started) {
      _started = true;
      _midi = _targetMidi;
      _shape = _targetShape;
    }
  }

  /// Advances smoothing by [seconds].
  void step(double seconds) {
    final glide = settings.glideMs / 1000;
    final pitchAlpha = glide <= 0 ? 1.0 : 1 - math.exp(-seconds / glide);
    _midi += (_targetMidi - _midi) * pitchAlpha;
    // Volume and shape always get a short ramp.
    final fast = 1 - math.exp(-seconds / 0.02);
    _volume += (_targetVolume - _volume) * fast;
    final shapeAlpha = 1 - math.exp(-seconds / 0.04);
    _shape += (_targetShape - _shape) * shapeAlpha;
  }
}
