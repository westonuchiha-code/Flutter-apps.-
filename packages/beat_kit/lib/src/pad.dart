/// How a pad plays its sample.
enum PadMode {
  /// Plays to the end once tapped.
  oneShot('One-shot'),

  /// Plays while held down.
  hold('Hold'),

  /// Loops until tapped again.
  loop('Loop');

  const PadMode(this.label);
  final String label;

  static PadMode byName(Object? n) =>
      values.firstWhere((m) => m.name == n, orElse: () => oneShot);
}

/// Playback settings of one pad.
class PadSettings {
  const PadSettings({
    this.start = 0,
    this.end = 1,
    this.pitch = 0,
    this.reverse = false,
    this.volume = 0.8,
    this.pan = 0,
    this.mode = PadMode.oneShot,
  });

  /// Trim start/end as fractions of the sample (0..1).
  final double start, end;

  /// Semitones (-24..24).
  final double pitch;
  final bool reverse;

  /// 0..1.
  final double volume;

  /// -1 (left) .. 1 (right).
  final double pan;
  final PadMode mode;

  PadSettings copyWith({
    double? start,
    double? end,
    double? pitch,
    bool? reverse,
    double? volume,
    double? pan,
    PadMode? mode,
  }) => PadSettings(
    start: start ?? this.start,
    end: end ?? this.end,
    pitch: pitch ?? this.pitch,
    reverse: reverse ?? this.reverse,
    volume: volume ?? this.volume,
    pan: pan ?? this.pan,
    mode: mode ?? this.mode,
  );

  Map<String, Object?> toJson() => {
    'start': start,
    'end': end,
    'pitch': pitch,
    'reverse': reverse,
    'volume': volume,
    'pan': pan,
    'mode': mode.name,
  };

  static double _d(Object? v, double def, double lo, double hi) =>
      v is num ? v.toDouble().clamp(lo, hi) : def;

  factory PadSettings.fromJson(Object? json) {
    if (json is! Map) return const PadSettings();
    final s = _d(json['start'], 0, 0, 1);
    final e = _d(json['end'], 1, 0, 1);
    return PadSettings(
      start: s < e ? s : 0,
      end: s < e ? e : 1,
      pitch: _d(json['pitch'], 0, -24, 24),
      reverse: json['reverse'] == true,
      volume: _d(json['volume'], 0.8, 0, 1),
      pan: _d(json['pan'], 0, -1, 1),
      mode: PadMode.byName(json['mode']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PadSettings &&
      other.start == start &&
      other.end == end &&
      other.pitch == pitch &&
      other.reverse == reverse &&
      other.volume == volume &&
      other.pan == pan &&
      other.mode == mode;

  @override
  int get hashCode =>
      Object.hash(start, end, pitch, reverse, volume, pan, mode);
}
