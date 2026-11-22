import 'package:flutter/foundation.dart';

import 'music.dart';

/// Oscillator shapes offered in the UI.
enum Wave {
  sine('Sine'),
  triangle('Triangle'),
  saw('Saw'),
  square('Square');

  const Wave(this.label);
  final String label;
}

/// User-adjustable theremin settings.
@immutable
class ThereminSettings {
  const ThereminSettings({
    this.wave = Wave.sine,
    this.lowNote = 48, // C3
    this.highNote = 84, // C6
    this.scale = ScaleType.continuous,
    this.root = 0,
    this.glideMs = 80,
    this.twoZones = true,
    this.invertPitch = true,
    this.invertVolume = false,
    this.masterVolume = 0.8,
    this.lockExposure = true,
    this.mirror = true,
  });

  final Wave wave;

  /// Pitch range as MIDI note numbers.
  final int lowNote;
  final int highNote;

  final ScaleType scale;

  /// Root note of [scale] (0 = C).
  final int root;

  /// Portamento time constant in milliseconds.
  final double glideMs;

  /// true: left half of the image controls pitch, right half volume
  /// (like a theremin's two antennas). false: the whole image controls pitch.
  final bool twoZones;

  /// true: less light = higher pitch (covering the camera is like moving
  /// your hand closer to a theremin's pitch antenna).
  final bool invertPitch;

  /// true: less light = louder.
  final bool invertVolume;

  final double masterVolume;

  /// Lock the camera's auto-exposure so it does not cancel out light changes.
  final bool lockExposure;

  /// Show the camera image mirrored (like a mirror / selfie view).
  final bool mirror;

  ThereminSettings copyWith({
    Wave? wave,
    int? lowNote,
    int? highNote,
    ScaleType? scale,
    int? root,
    double? glideMs,
    bool? twoZones,
    bool? invertPitch,
    bool? invertVolume,
    double? masterVolume,
    bool? lockExposure,
    bool? mirror,
  }) => ThereminSettings(
    wave: wave ?? this.wave,
    lowNote: lowNote ?? this.lowNote,
    highNote: highNote ?? this.highNote,
    scale: scale ?? this.scale,
    root: root ?? this.root,
    glideMs: glideMs ?? this.glideMs,
    twoZones: twoZones ?? this.twoZones,
    invertPitch: invertPitch ?? this.invertPitch,
    invertVolume: invertVolume ?? this.invertVolume,
    masterVolume: masterVolume ?? this.masterVolume,
    lockExposure: lockExposure ?? this.lockExposure,
    mirror: mirror ?? this.mirror,
  );
}
