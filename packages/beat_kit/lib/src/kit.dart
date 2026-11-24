import 'engine.dart';
import 'pad.dart';

/// A saved kit: pad settings, which sample each pad uses, the pattern and
/// the tempo. Samples are referenced by Asset Locker id.
class Kit {
  const Kit({
    this.name = 'Kit',
    this.bpm = 110,
    this.swing = 0,
    this.steps = 16,
    this.pads = const [],
    this.masks = const [],
  });

  final String name;
  final double bpm;
  final double swing;
  final int steps;
  final List<KitPad> pads;
  final List<int> masks;

  static const kind = 'sample_pad_kit';

  Map<String, Object?> toJson() => {
    'kind': kind,
    'version': 1,
    'name': name,
    'bpm': bpm,
    'swing': swing,
    'steps': steps,
    'pads': [for (final p in pads) p.toJson()],
    'masks': masks,
  };

  factory Kit.fromJson(Object? json) {
    if (json is! Map || json['kind'] != kind) {
      throw const FormatException('Not a Sample Pad kit');
    }
    final pads = [
      for (final p in (json['pads'] as List?) ?? const []) KitPad.fromJson(p),
    ];
    final masks = [
      for (final m in (json['masks'] as List?) ?? const [])
        if (m is int) m else 0,
    ];
    return Kit(
      name: (json['name'] as String?) ?? 'Kit',
      bpm: ((json['bpm'] as num?) ?? 110).toDouble().clamp(30, 300),
      swing: ((json['swing'] as num?) ?? 0).toDouble().clamp(0, 0.5),
      steps: ((json['steps'] as num?) ?? 16).toInt().clamp(1, maxSteps),
      pads: [
        for (var i = 0; i < padCount; i++)
          i < pads.length ? pads[i] : const KitPad(),
      ],
      masks: [
        for (var i = 0; i < padCount; i++) i < masks.length ? masks[i] : 0,
      ],
    );
  }
}

class KitPad {
  const KitPad({
    this.sampleId,
    this.sampleType,
    this.name = '',
    this.settings = const PadSettings(),
  });

  /// Asset Locker id and type name of the sample (null = empty pad).
  final String? sampleId;
  final String? sampleType;
  final String name;
  final PadSettings settings;

  Map<String, Object?> toJson() => {
    if (sampleId != null) 'sampleId': sampleId,
    if (sampleType != null) 'sampleType': sampleType,
    'name': name,
    'settings': settings.toJson(),
  };

  factory KitPad.fromJson(Object? json) {
    if (json is! Map) return const KitPad();
    return KitPad(
      sampleId: json['sampleId'] as String?,
      sampleType: json['sampleType'] as String?,
      name: (json['name'] as String?) ?? '',
      settings: PadSettings.fromJson(json['settings']),
    );
  }
}
