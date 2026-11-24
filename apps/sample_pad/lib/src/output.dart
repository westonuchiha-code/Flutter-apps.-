// The real-time stream API of flutter_soloud is experimental; the package
// version is pinned in pubspec.yaml.
// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:typed_data';

import 'package:beat_kit/beat_kit.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

const engineRate = 48000;

/// Where the engine runs: the audio isolate (real) or nowhere (tests).
abstract class BeatOutput {
  Future<void> init();
  void send(BeatCommand command);
  Stream<Object?> get events;
  Future<void> dispose();
}

/// Feeds a [BeatEngine] living in SoLoud's real-time feeder isolate.
class SoLoudBeatOutput implements BeatOutput {
  RealtimeStreamFeeder<BeatEngine>? _feeder;
  final _events = StreamController<Object?>.broadcast();
  final _pending = <BeatCommand>[];

  @override
  Stream<Object?> get events => _events.stream;

  @override
  Future<void> init() async {
    final soloud = SoLoud.instance;
    if (!soloud.isInitialized) {
      await soloud.init(sampleRate: engineRate, bufferSize: 512);
    }
    final stream = soloud.setRealtimeStream(
      sampleRate: engineRate,
      channels: Channels.stereo,
      format: BufferType.f32le,
      bufferFrames: 8192,
    );
    final handle = soloud.play(stream.source);
    stream.bindActiveVoice(handle);
    _feeder = await stream.startFloat32Feeder<BeatEngine>(
      initialState: BeatEngine(sampleRate: engineRate),
      onFeed: _feed,
      onMessage: _message,
      onUiEvent: _events.add,
      chunkFrames: 192,
    );
    for (final c in _pending) {
      _feeder!.sendMessage(c);
    }
    _pending.clear();
  }

  static int _feed(
    Float32List out,
    int frames,
    BeatEngine engine,
    void Function(Object?) emit,
  ) {
    engine.render(out, frames, emit);
    return frames;
  }

  static void _message(BeatEngine engine, Object? message) {
    if (message is BeatCommand) engine.handle(message);
  }

  @override
  void send(BeatCommand command) {
    final f = _feeder;
    f == null ? _pending.add(command) : f.sendMessage(command);
  }

  @override
  Future<void> dispose() async {
    await _feeder?.dispose();
    _feeder = null;
    await _events.close();
  }
}
