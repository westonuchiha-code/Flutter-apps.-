import 'package:flutter/foundation.dart';

import 'package:chip_synth/chip_synth.dart';

import 'music.dart';

/// What the second hand (right zone / touch pad height) controls.
enum SecondControl {
  volume('Volume'),
  shape('Sound shape');

  const SecondControl(this.label);
  final String label;
}

/// User-adjustable theremin settings (saved between launches).
@immutable
class ThereminSettings {
  const ThereminSettings({
    this.sound = const SoundSpec(),
    this.lowNote = 48, // C3
    this.highNote = 84, // C6
    this.scale = ScaleType.continuous,
    this.root = 0,
    this.glideMs = 80,
    this.twoZones = true,
    this.secondControl = SecondControl.volume,
    this.shape = 0.5,
    this.invertPitch = true,
    this.invertSecond = false,
    this.lockExposure = true,
    this.mirror = true,
    this.cameraId,
  });

  /// Chip, sound and effects.
  final SoundSpec sound;

  /// Pitch range as MIDI note numbers.
  final int lowNote;
  final int highNote;

  final ScaleType scale;

  /// Root note of [scale] (0 = C).
  final int root;

  /// Portamento time constant in milliseconds.
  final double glideMs;

  /// true: left half of the image controls pitch, right half the
  /// [secondControl] (like a theremin's two antennas).
  final bool twoZones;

  final SecondControl secondControl;

  /// Sound shape (0–1) when the second hand is not controlling it.
  final double shape;

  /// true: less light = higher pitch (covering the camera is like moving
  /// your hand closer to a theremin's pitch antenna).
  final bool invertPitch;

  /// true: less light on the second zone = more volume / shape.
  final bool invertSecond;

  /// Lock the camera's auto-exposure so it does not cancel out light changes.
  final bool lockExposure;

  /// Show the camera image mirrored (like a mirror / selfie view).
  final bool mirror;

  /// Last used camera (null = default camera or touch pad).
  final String? cameraId;

  ThereminSettings copyWith({
    SoundSpec? sound,
    int? lowNote,
    int? highNote,
    ScaleType? scale,
    int? root,
    double? glideMs,
    bool? twoZones,
    SecondControl? secondControl,
    double? shape,
    bool? invertPitch,
    bool? invertSecond,
    bool? lockExposure,
    bool? mirror,
    String? cameraId,
  }) => ThereminSettings(
    sound: sound ?? this.sound,
    lowNote: lowNote ?? this.lowNote,
    highNote: highNote ?? this.highNote,
    scale: scale ?? this.scale,
    root: root ?? this.root,
    glideMs: glideMs ?? this.glideMs,
    twoZones: twoZones ?? this.twoZones,
    secondControl: secondControl ?? this.secondControl,
    shape: shape ?? this.shape,
    invertPitch: invertPitch ?? this.invertPitch,
    invertSecond: invertSecond ?? this.invertSecond,
    lockExposure: lockExposure ?? this.lockExposure,
    mirror: mirror ?? this.mirror,
    cameraId: cameraId ?? this.cameraId,
  );

  Map<String, Object?> toJson() => {
    'sound': sound.toJson(),
    'lowNote': lowNote,
    'highNote': highNote,
    'scale': scale.name,
    'root': root,
    'glideMs': glideMs,
    'twoZones': twoZones,
    'second': secondControl.name,
    'shape': shape,
    'invertPitch': invertPitch,
    'invertSecond': invertSecond,
    'lockExposure': lockExposure,
    'mirror': mirror,
    'cameraId': cameraId,
  };

  factory ThereminSettings.fromJson(Map<String, Object?> j) {
    const d = ThereminSettings();
    T pick<T>(String key, T fallback) {
      final v = j[key];
      return v is T ? v : fallback;
    }

    double num_(String key, double fallback) =>
        (j[key] as num?)?.toDouble() ?? fallback;
    final low = (j['lowNote'] as num?)?.toInt() ?? d.lowNote;
    final high = (j['highNote'] as num?)?.toInt() ?? d.highNote;
    return ThereminSettings(
      sound: j['sound'] is Map
          ? SoundSpec.fromJson((j['sound']! as Map).cast<String, Object?>())
          : d.sound,
      lowNote: low.clamp(24, 96),
      highNote: high.clamp(24, 96) > low ? high.clamp(24, 96) : d.highNote,
      scale: ScaleType.values.firstWhere(
        (s) => s.name == j['scale'],
        orElse: () => d.scale,
      ),
      root: ((j['root'] as num?)?.toInt() ?? 0) % 12,
      glideMs: num_('glideMs', d.glideMs),
      twoZones: pick('twoZones', d.twoZones),
      secondControl: SecondControl.values.firstWhere(
        (s) => s.name == j['second'],
        orElse: () => d.secondControl,
      ),
      shape: num_('shape', d.shape),
      invertPitch: pick('invertPitch', d.invertPitch),
      invertSecond: pick('invertSecond', d.invertSecond),
      lockExposure: pick('lockExposure', d.lockExposure),
      mirror: pick('mirror', d.mirror),
      cameraId: j['cameraId'] as String?,
    );
  }
}
