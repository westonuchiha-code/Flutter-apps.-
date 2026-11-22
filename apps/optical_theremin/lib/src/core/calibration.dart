import 'package:flutter/foundation.dart';

/// Brightness range of one control zone: [dark] maps to 0, [bright] to 1.
@immutable
class ZoneCalibration {
  const ZoneCalibration({this.dark = 10, this.bright = 180});

  final double dark;
  final double bright;

  /// Brightness (0–255) to a 0–1 control value.
  double normalize(double level) {
    final span = bright - dark;
    if (span <= 0) return 0;
    return ((level - dark) / span).clamp(0.0, 1.0);
  }
}

/// Records the darkest and brightest levels seen while the player sweeps
/// their hand over the camera.
class CalibrationRecorder {
  double? _min;
  double? _max;

  void add(double level) {
    _min = _min == null || level < _min! ? level : _min;
    _max = _max == null || level > _max! ? level : _max;
  }

  /// Minimum brightness change for a usable calibration.
  static const minimumSpan = 12.0;

  /// The recorded range, or null if the light barely changed.
  ZoneCalibration? result() {
    final min = _min;
    final max = _max;
    if (min == null || max == null || max - min < minimumSpan) return null;
    // Small margins so the extremes are reachable.
    final margin = (max - min) * 0.05;
    return ZoneCalibration(dark: min + margin, bright: max - margin);
  }
}
