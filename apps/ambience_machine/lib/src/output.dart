// The real-time stream API of flutter_soloud is experimental; the package
// version is pinned in pubspec.yaml.
// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';

import 'engine.dart';

abstract class AmbOutput {
  Future<void> init();
  void send(AmbCommand command);
  Stream<Object?> get events;
  Future<void> dispose();
}

class SoLoudAmbOutput implements AmbOutput {
  RealtimeStreamFeeder<AmbienceEngine>? _feeder;
  final _events = StreamController<Object?>.broadcast();
  final _pending = <AmbCommand>[];

  @override
  Stream<Object?> get events => _events.stream;

  static int _feed(
    Float32List out,
    int frames,
    AmbienceEngine e,
    void Function(Object?) emit,
  ) {
    e.render(out, frames, emit);
    return frames;
  }

  static void _message(AmbienceEngine e, Object? m) {
    if (m is AmbCommand) e.handle(m);
  }

  @override
  Future<void> init() async {
    final soloud = SoLoud.instance;
    if (!soloud.isInitialized) {
      await soloud.init(sampleRate: ambRate, bufferSize: 1024);
    }
    final stream = soloud.setRealtimeStream(
      sampleRate: ambRate,
      channels: Channels.stereo,
      format: BufferType.f32le,
      bufferFrames: 16384,
    );
    final handle = soloud.play(stream.source);
    stream.bindActiveVoice(handle);
    _feeder = await stream.startFloat32Feeder<AmbienceEngine>(
      initialState: AmbienceEngine(),
      onFeed: _feed,
      onMessage: _message,
      onUiEvent: _events.add,
      // Ambience doesn't need low latency: bigger chunks, more headroom.
      chunkFrames: 512,
      targetBufferedFrames: 4096,
      tickInterval: const Duration(milliseconds: 8),
    );
    for (final c in _pending) {
      _feeder!.sendMessage(c);
    }
    _pending.clear();
  }

  @override
  void send(AmbCommand command) {
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
