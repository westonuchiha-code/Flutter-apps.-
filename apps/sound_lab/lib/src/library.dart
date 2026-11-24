import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:app_shell/app_shell.dart';
import 'package:audio_kit/audio_kit.dart';
import 'package:fx_kit/fx_kit.dart';

import 'controller.dart';
import 'engine.dart';

/// Longest sample Sound Lab loads.
const maxSampleSeconds = 30.0;

/// Reads drawn waves from a Waveform Painter wave or a sound preset.
(String, List<List<double>>)? wavesFromJson(Object? json) {
  if (json is! Map) return null;
  final kind = json['kind'];
  if (kind != 'wavetable' && kind != SoundPreset.kind) return null;
  final waves = [
    for (final w in (json['waves'] as List?) ?? const [])
      if (w is List && w.isNotEmpty)
        [for (final v in w) v is num ? v.toDouble() : 0.0],
  ];
  if (waves.isEmpty) return null;
  return ((json['name'] as String?) ?? 'Wave', waves.take(4).toList());
}

class LabLibrary {
  LabLibrary(this.locker);

  final AssetLocker locker;

  Future<Object?> readJson(AssetInfo info) async {
    final bytes = await locker.read(info);
    if (bytes == null) throw StateError('The file is missing.');
    return jsonDecode(utf8.decode(bytes));
  }

  Future<Float32List> decodeSample(AssetInfo info) async {
    if (info.extension != 'wav') {
      throw FormatException(
        'Only WAV files can be used (this is .${info.extension}).',
      );
    }
    final bytes = await locker.read(info);
    if (bytes == null) throw StateError('The file is missing.');
    return Isolate.run(
      () => decodeWavMono(
        bytes,
        targetRate: labRate,
        maxSeconds: maxSampleSeconds,
      ),
    );
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

  Future<AssetInfo> savePreset(LabController c, String name) {
    c.name = name;
    final p = c.toPreset();
    return locker.save(
      type: AssetType.preset,
      name: name,
      bytes: utf8.encode(const JsonEncoder.withIndent(' ').convert(p.toJson())),
      extension: 'json',
      tags: ['sound', p.source.name, 'sound lab'],
      extra: {
        'kind': SoundPreset.kind,
        'source': p.source.name,
        'effects': p.fx.length,
      },
    );
  }

  /// Loads a sound preset, or a Waveform Painter wave as a wave source.
  /// Returns a note for the user if something was missing.
  Future<String?> loadPreset(LabController c, AssetInfo info) async {
    final json = await readJson(info);
    if (json is Map && json['kind'] == 'wavetable') {
      final w = wavesFromJson(json)!;
      c.setWaves(w.$1, w.$2);
      return null;
    }
    final p = SoundPreset.fromJson(json);
    Float32List? data;
    var label = '';
    String? note;
    if (p.source == SourceKind.sample) {
      final asset = await find(p.sampleType, p.sampleId);
      if (asset == null) {
        note = 'Its sample is no longer in the Asset Locker; using the analog synth.';
      } else {
        data = await decodeSample(asset);
        label = asset.name;
      }
    }
    c.applyPreset(p, sampleData: data, sampleLabel: label);
    return note;
  }

  static Future<Uint8List> renderNoteWav(LabController c, int note) {
    final snap = c.snapshot();
    return Isolate.run(
      () => encodeWavStereo16(renderNote(snap, note), labRate),
    );
  }

  static Future<Uint8List> processSampleWav(LabController c) {
    final snap = c.snapshot();
    return Isolate.run(() => encodeWavStereo16(processSample(snap), labRate));
  }

  Future<AssetInfo> saveWav(
    String name,
    Uint8List wav,
    List<String> tags,
  ) async {
    final mono = decodeWavMono(wav, targetRate: labRate);
    return locker.save(
      type: AssetType.sample,
      name: name,
      bytes: wav,
      extension: 'wav',
      thumbnail: await waveformPng(floatPeaks(mono, labRate ~/ 100)),
      tags: ['sound lab', ...tags],
      extra: {'seconds': mono.length / labRate},
    );
  }
}
