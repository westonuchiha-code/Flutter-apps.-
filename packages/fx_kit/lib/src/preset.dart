import 'effects.dart';

/// Where a sound comes from.
enum SourceKind { analog, chip, wavetable, sample }

/// The shared sound preset: a source plus an effect chain. Any music app
/// can load it (synth settings are kept as the `chip_synth` PolySpec JSON).
class SoundPreset {
  const SoundPreset({
    required this.name,
    required this.source,
    this.synth = const {},
    this.waves = const [],
    this.sampleId,
    this.sampleType,
    this.sampleRoot = 60,
    this.fx = const [],
  });

  static const kind = 'sound';

  final String name;
  final SourceKind source;

  /// PolySpec JSON (analog/chip/wavetable sources).
  final Map<String, Object?> synth;

  /// Drawn cycles for a wavetable source.
  final List<List<double>> waves;

  /// Asset Locker reference for a sample source.
  final String? sampleId, sampleType;

  /// MIDI note at which the sample plays at its own pitch.
  final int sampleRoot;
  final List<EffectSpec> fx;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'version': 1,
    'name': name,
    'source': source.name,
    if (synth.isNotEmpty) 'synth': synth,
    if (waves.isNotEmpty)
      'waves': [
        for (final w in waves)
          [for (final v in w) double.parse(v.toStringAsFixed(4))],
      ],
    if (sampleId != null) 'sampleId': sampleId,
    if (sampleType != null) 'sampleType': sampleType,
    'sampleRoot': sampleRoot,
    'fx': [for (final e in fx) e.toJson()],
  };

  factory SoundPreset.fromJson(Object? j) {
    if (j is! Map || j['kind'] != kind) {
      throw const FormatException('Not a sound preset');
    }
    final src = SourceKind.values.firstWhere(
      (s) => s.name == j['source'],
      orElse: () => SourceKind.analog,
    );
    final synth = j['synth'];
    return SoundPreset(
      name: (j['name'] as String?) ?? 'Sound',
      source: src,
      synth: synth is Map ? synth.cast<String, Object?>() : const {},
      waves: [
        for (final w in (j['waves'] as List?) ?? const [])
          if (w is List) [for (final v in w) v is num ? v.toDouble() : 0.0],
      ],
      sampleId: j['sampleId'] as String?,
      sampleType: j['sampleType'] as String?,
      sampleRoot: ((j['sampleRoot'] as num?) ?? 60).toInt().clamp(0, 127),
      fx: [
        for (final e in (j['fx'] as List?) ?? const []) ?EffectSpec.fromJson(e),
      ],
    );
  }
}
