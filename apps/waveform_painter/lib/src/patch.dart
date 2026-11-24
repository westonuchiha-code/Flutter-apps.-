import 'dart:typed_data';

import 'package:chip_synth/chip_synth.dart';

import 'shape.dart';

/// Most waves a patch can morph between.
const maxWaves = 4;

/// A saved Waveform Painter sound: the drawn waves plus synth settings.
class WavePatch {
  const WavePatch({
    required this.name,
    required this.waves,
    required this.spec,
  });

  static const kind = 'wavetable';

  final String name;
  final List<Float32List> waves;
  final PolySpec spec;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'version': 1,
    'name': name,
    'points': wavePoints,
    'waves': [
      for (final w in waves)
        [for (final v in w) double.parse(v.toStringAsFixed(4))],
    ],
    'synth': spec.toJson(),
  };

  factory WavePatch.fromJson(Object? json) {
    if (json is! Map || json['kind'] != kind) {
      throw const FormatException('Not a Waveform Painter wave');
    }
    final waves = <Float32List>[];
    for (final w in (json['waves'] as List?) ?? const []) {
      if (w is! List || w.isEmpty) continue;
      final pts = [
        for (final v in w) v is num ? v.toDouble().clamp(-1.0, 1.0) : 0.0,
      ];
      // Any length is accepted; resample to wavePoints.
      waves.add(
        Float32List.fromList(
          List.generate(
            wavePoints,
            (i) => pts[(i * pts.length / wavePoints).floor()],
          ),
        ),
      );
      if (waves.length == maxWaves) break;
    }
    if (waves.isEmpty) waves.add(WavePreset.sine.build());
    final synth = json['synth'];
    return WavePatch(
      name: (json['name'] as String?) ?? 'Wave',
      waves: waves,
      spec: synth is Map
          ? PolySpec.fromJson(synth.cast<String, Object?>())
          : const PolySpec(),
    );
  }
}
