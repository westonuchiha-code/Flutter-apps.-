import 'package:fx_kit/fx_kit.dart';

enum LayerKind { sample, synth, noise }

enum NoiseType {
  wind('Wind'),
  rain('Rain'),
  waves('Waves'),
  rumble('Rumble');

  const NoiseType(this.label);
  final String label;

  static NoiseType byName(Object? n) =>
      values.firstWhere((t) => t.name == n, orElse: () => wind);
}

enum ScaleKind {
  majorPentatonic('Major pentatonic', [0, 2, 4, 7, 9]),
  minorPentatonic('Minor pentatonic', [0, 3, 5, 7, 10]),
  major('Major', [0, 2, 4, 5, 7, 9, 11]),
  minor('Minor', [0, 2, 3, 5, 7, 8, 10]),
  dorian('Dorian', [0, 2, 3, 5, 7, 9, 10]),
  lydian('Lydian', [0, 2, 4, 6, 7, 9, 11]),
  wholeTone('Whole tone', [0, 2, 4, 6, 8, 10]);

  const ScaleKind(this.label, this.steps);
  final String label;
  final List<int> steps;

  static ScaleKind byName(Object? n) =>
      values.firstWhere((t) => t.name == n, orElse: () => majorPentatonic);
}

double _d(Object? v, double def, double lo, double hi) =>
    v is num ? v.toDouble().clamp(lo, hi) : def;

/// One layer of an ambience.
class LayerSpec {
  LayerSpec({
    int? id,
    required this.kind,
    this.name = '',
    this.volume = 0.7,
    this.pan = 0,
    this.tone = 1,
    this.drift = 0.5,
    this.driftSpeed = 0.3,
    this.muted = false,
    this.sampleKey,
    this.sampleType,
    this.pitch = 0,
    this.sound = const {},
    this.root = 48,
    this.scale = ScaleKind.majorPentatonic,
    this.octaves = 2,
    this.density = 8,
    this.noteLength = 3,
    this.noise = NoiseType.wind,
  }) : id = id ?? _next++;

  static int _next = 1;

  final int id;
  final LayerKind kind;
  final String name;

  /// 0..1.
  final double volume;

  /// -1..1.
  final double pan;

  /// Brightness 0 (dark) .. 1 (open).
  final double tone;

  /// How far volume/pan/tone/pitch wander (0..1).
  final double drift;

  /// How fast they wander (0 = minutes, 1 = seconds).
  final double driftSpeed;
  final bool muted;

  // Sample layers: Asset Locker id/type; pitch in semitones.
  final String? sampleKey, sampleType;
  final double pitch;

  // Synth layers: a SoundPreset JSON, note range, how often notes come.
  final Map<String, Object?> sound;
  final int root;
  final ScaleKind scale;
  final int octaves;

  /// Notes per minute.
  final double density;

  /// Seconds each note is held (on average).
  final double noteLength;

  final NoiseType noise;

  LayerSpec copyWith({
    String? name,
    double? volume,
    double? pan,
    double? tone,
    double? drift,
    double? driftSpeed,
    bool? muted,
    double? pitch,
    int? root,
    ScaleKind? scale,
    int? octaves,
    double? density,
    double? noteLength,
    NoiseType? noise,
  }) => LayerSpec(
    id: id,
    kind: kind,
    name: name ?? this.name,
    volume: volume ?? this.volume,
    pan: pan ?? this.pan,
    tone: tone ?? this.tone,
    drift: drift ?? this.drift,
    driftSpeed: driftSpeed ?? this.driftSpeed,
    muted: muted ?? this.muted,
    sampleKey: sampleKey,
    sampleType: sampleType,
    pitch: pitch ?? this.pitch,
    sound: sound,
    root: root ?? this.root,
    scale: scale ?? this.scale,
    octaves: octaves ?? this.octaves,
    density: density ?? this.density,
    noteLength: noteLength ?? this.noteLength,
    noise: noise ?? this.noise,
  );

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'name': name,
    'volume': volume,
    'pan': pan,
    'tone': tone,
    'drift': drift,
    'driftSpeed': driftSpeed,
    'muted': muted,
    if (kind == LayerKind.sample) ...{
      'sampleKey': sampleKey,
      'sampleType': sampleType,
      'pitch': pitch,
    },
    if (kind == LayerKind.synth) ...{
      'sound': sound,
      'root': root,
      'scale': scale.name,
      'octaves': octaves,
      'density': density,
      'noteLength': noteLength,
    },
    if (kind == LayerKind.noise) 'noise': noise.name,
  };

  static LayerSpec? fromJson(Object? j) {
    if (j is! Map) return null;
    final kind = LayerKind.values.where((k) => k.name == j['kind']).firstOrNull;
    if (kind == null) return null;
    final sound = j['sound'];
    return LayerSpec(
      kind: kind,
      name: (j['name'] as String?) ?? '',
      volume: _d(j['volume'], 0.7, 0, 1),
      pan: _d(j['pan'], 0, -1, 1),
      tone: _d(j['tone'], 1, 0, 1),
      drift: _d(j['drift'], 0.5, 0, 1),
      driftSpeed: _d(j['driftSpeed'], 0.3, 0, 1),
      muted: j['muted'] == true,
      sampleKey: j['sampleKey'] as String?,
      sampleType: j['sampleType'] as String?,
      pitch: _d(j['pitch'], 0, -12, 12),
      sound: sound is Map ? sound.cast<String, Object?>() : const {},
      root: _d(j['root'], 48, 24, 84).round(),
      scale: ScaleKind.byName(j['scale']),
      octaves: _d(j['octaves'], 2, 1, 4).round(),
      density: _d(j['density'], 8, 1, 120),
      noteLength: _d(j['noteLength'], 3, 0.2, 20),
      noise: NoiseType.byName(j['noise']),
    );
  }
}

/// A whole ambience: layers plus a shared effect chain.
class SceneSpec {
  SceneSpec({
    int? id,
    this.name = 'New ambience',
    this.layers = const [],
    this.fx = const [],
  }) : id = id ?? _next++;

  static int _next = 1;
  static const kind = 'ambience_scene';
  static const maxLayers = 8;

  /// Changes only when a different scene is loaded (crossfade).
  final int id;
  final String name;
  final List<LayerSpec> layers;
  final List<EffectSpec> fx;

  SceneSpec copyWith({
    String? name,
    List<LayerSpec>? layers,
    List<EffectSpec>? fx,
  }) => SceneSpec(
    id: id,
    name: name ?? this.name,
    layers: layers ?? this.layers,
    fx: fx ?? this.fx,
  );

  Map<String, Object?> toJson() => {
    'kind': kind,
    'version': 1,
    'name': name,
    'layers': [for (final l in layers) l.toJson()],
    'fx': [for (final e in fx) e.toJson()],
  };

  factory SceneSpec.fromJson(Object? j) {
    if (j is! Map || j['kind'] != kind) {
      throw const FormatException('Not an ambience');
    }
    return SceneSpec(
      name: (j['name'] as String?) ?? 'Ambience',
      layers: [
        for (final l in (j['layers'] as List?) ?? const [])
          ?LayerSpec.fromJson(l),
      ].take(maxLayers).toList(),
      fx: [
        for (final e in (j['fx'] as List?) ?? const []) ?EffectSpec.fromJson(e),
      ],
    );
  }
}
