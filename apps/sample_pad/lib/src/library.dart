import 'dart:convert';
import 'dart:isolate';

import 'package:app_shell/app_shell.dart';
import 'package:audio_kit/audio_kit.dart';
import 'package:beat_kit/beat_kit.dart';
import 'package:flutter/foundation.dart';

import 'controller.dart';
import 'output.dart';

/// Asset Locker work: samples in, kits and mixes out.
class PadLibrary {
  PadLibrary(this.locker);

  final AssetLocker locker;

  /// Decodes a WAV asset for a pad (off the UI thread).
  Future<Float32List> decode(AssetInfo info) async {
    if (info.extension != 'wav') {
      throw FormatException(
        'Only WAV files can go on a pad (this is .${info.extension}).',
      );
    }
    final bytes = await locker.read(info);
    if (bytes == null) throw StateError('The file is missing.');
    return runInBackground(decodePadSample, bytes);
  }

  Future<AssetInfo?> find(String? type, String? id) async {
    if (id == null) return null;
    final list = await locker.list(
      type: type == null ? null : AssetType.byName(type),
    );
    for (final a in list) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Saves pads whose samples aren't in the locker yet, then the kit.
  Future<AssetInfo> saveKit(PadController c, String name) async {
    c.kitName = name;
    for (var i = 0; i < padCount; i++) {
      final p = c.pads[i];
      final data = p.sample;
      if (data == null || p.assetId != null) continue;
      final wav = encodeWavMono16(data, engineRate);
      final peaks = p.peaks;
      final thumb = await waveformPng(peaks);
      final saved = await locker.save(
        type: AssetType.sample,
        name: p.name.isEmpty ? '$name pad ${i + 1}' : p.name,
        bytes: wav,
        extension: 'wav',
        thumbnail: thumb,
        tags: const ['sample pad'],
        extra: {'seconds': p.seconds},
      );
      c.pads[i] = p.withAsset(saved.id, saved.type.name);
    }
    final kit = c.toKit();
    return locker.save(
      type: AssetType.preset,
      name: name,
      bytes: utf8.encode(
        const JsonEncoder.withIndent(' ').convert(kit.toJson()),
      ),
      extension: 'json',
      tags: const ['kit', 'sample pad'],
      extra: {'kind': Kit.kind},
    );
  }

  /// Loads a kit and its samples. Returns how many samples were missing.
  Future<int> loadKit(PadController c, AssetInfo info) async {
    final bytes = await locker.read(info);
    if (bytes == null) throw StateError('The kit file is missing.');
    final kit = Kit.fromJson(jsonDecode(utf8.decode(bytes)));
    final samples = List<Float32List?>.filled(padCount, null);
    var missing = 0;
    for (var i = 0; i < padCount; i++) {
      final kp = kit.pads[i];
      if (kp.sampleId == null) continue;
      final asset = await find(kp.sampleType, kp.sampleId);
      if (asset == null) {
        missing++;
        continue;
      }
      try {
        samples[i] = await decode(asset);
      } catch (_) {
        missing++;
      }
    }
    c.applyKit(kit, samples);
    return missing;
  }

  /// Renders [bars] bars to WAV (off the UI thread).
  static Future<Uint8List> renderWav(PadController c, int bars) {
    final snap = c.snapshot();
    return Isolate.run(() => renderMix(snap, bars));
  }

  Future<AssetInfo> saveMix(PadController c, String name, int bars) async {
    final wav = await renderWav(c, bars);
    final mono = decodeWavMono(wav, targetRate: engineRate);
    return locker.save(
      type: AssetType.sample,
      name: name,
      bytes: wav,
      extension: 'wav',
      thumbnail: await waveformPng(floatPeaks(mono, engineRate ~/ 100)),
      tags: const ['mix', 'sample pad'],
      extra: {'seconds': mono.length / engineRate, 'bpm': c.bpm, 'bars': bars},
    );
  }
}

/// A WAV as a pad sample (mono, engine rate, at most the longest sample).
Float32List decodePadSample(Uint8List bytes) =>
    decodeWavMono(bytes, targetRate: engineRate, maxSeconds: maxSampleSeconds);
