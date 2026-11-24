import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:app_shell/app_shell.dart';
import 'package:audio_kit/audio_kit.dart';
import 'package:fx_kit/fx_kit.dart';

import 'controller.dart';
import 'engine.dart';
import 'scene.dart';

/// Longest sample a layer loops.
const maxLoopSeconds = 120.0;

/// A Sound Lab sound, or a Waveform Painter wave turned into one.
Map<String, Object?>? soundFromJson(Object? json) {
  if (json is! Map) return null;
  if (json['kind'] == SoundPreset.kind) {
    try {
      return SoundPreset.fromJson(json).toJson();
    } catch (_) {
      return null;
    }
  }
  if (json['kind'] == 'wavetable') {
    final waves = [
      for (final w in (json['waves'] as List?) ?? const [])
        if (w is List && w.isNotEmpty)
          [for (final v in w) v is num ? v.toDouble() : 0.0],
    ];
    if (waves.isEmpty) return null;
    final synth = json['synth'];
    return SoundPreset(
      name: (json['name'] as String?) ?? 'Wave',
      source: SourceKind.wavetable,
      synth: synth is Map ? synth.cast<String, Object?>() : const {},
      waves: waves,
    ).toJson();
  }
  return null;
}

class AmbLibrary {
  AmbLibrary(this.locker);

  final AssetLocker locker;

  Future<Float32List> decode(AssetInfo info) async {
    if (info.extension != 'wav') {
      throw FormatException(
        'Only WAV files can be looped (this is .${info.extension}).',
      );
    }
    final bytes = await locker.read(info);
    if (bytes == null) throw StateError('The file is missing.');
    return Isolate.run(
      () =>
          decodeWavMono(bytes, targetRate: ambRate, maxSeconds: maxLoopSeconds),
    );
  }

  Future<Map<String, Object?>?> readSound(AssetInfo info) async {
    final bytes = await locker.read(info);
    if (bytes == null) return null;
    return soundFromJson(jsonDecode(utf8.decode(bytes)));
  }

  Future<AssetInfo?> find(String? type, String? id) async {
    if (id == null) return null;
    for (final a in await locker.list(
      type: type == null ? null : AssetType.byName(type),
    )) {
      if (a.id == id) return a;
    }
    return null;
  }

  Future<AssetInfo> saveScene(AmbienceController c, String name) {
    c.rename(name);
    return locker.save(
      type: AssetType.preset,
      name: name,
      bytes: utf8.encode(
        const JsonEncoder.withIndent(' ').convert(c.scene.toJson()),
      ),
      extension: 'json',
      tags: const ['ambience', 'ambience machine'],
      extra: {'kind': SceneSpec.kind, 'layers': c.scene.layers.length},
    );
  }

  /// Reads a scene and loads the samples its layers need. Returns the scene
  /// and how many samples are missing from the Asset Locker.
  Future<(SceneSpec, int)> loadScene(
    AmbienceController c,
    AssetInfo info,
  ) async {
    final bytes = await locker.read(info);
    if (bytes == null) throw StateError('The file is missing.');
    final scene = SceneSpec.fromJson(jsonDecode(utf8.decode(bytes)));
    var missing = 0;
    for (final l in scene.layers) {
      final key = l.sampleKey;
      if (l.kind != LayerKind.sample || key == null || c.hasSample(key)) {
        continue;
      }
      final asset = await find(l.sampleType, key);
      if (asset == null) {
        missing++;
        continue;
      }
      try {
        c.provideSample(key, await decode(asset), name: asset.name);
      } catch (_) {
        missing++;
      }
    }
    return (scene, missing);
  }

  /// Renders [seconds] of the current scene to a stereo WAV.
  static Future<Uint8List> exportWav(AmbienceController c, double seconds) {
    final scene = c.scene;
    final samples = c.samples;
    return Isolate.run(() {
      final pcm = renderAmbience(scene, samples, seconds);
      return buildWav(
        const WavFormat(sampleRate: ambRate, channels: 2),
        pcm.buffer.asUint8List(),
      );
    });
  }
}
