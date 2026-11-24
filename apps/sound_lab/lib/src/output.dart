// The real-time stream API of flutter_soloud is experimental; the package
// version is pinned in pubspec.yaml.
// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:typed_data';

import 'package:chip_synth/chip_synth.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:fx_kit/fx_kit.dart';

import 'engine.dart';

/// Small, frequent state: synth settings, effects, keys.
class LabUpdate {
  const LabUpdate(this.spec, this.fx, this.touches, this.morph, this.useSample);
  final PolySpec spec;
  final List<EffectSpec> fx;
  final List<Touch> touches;
  final double morph;
  final bool useSample;
}

/// Big, rare messages.
class TableMsg {
  const TableMsg(this.table);
  final Wavetable? table;
}

class SampleMsg {
  const SampleMsg(this.data, this.root);
  final Float32List? data;
  final int root;
}

abstract class LabOutput {
  Future<void> init();
  void update(LabUpdate u);
  void send(Object message);

  /// Scope snapshots (Float32List of [scopeSize] samples).
  Stream<Float32List> get scope;
  Future<void> dispose();
}

class _State {
  _State(this.u);
  LabUpdate u;
  LabEngine? engine;
}

int _feed(Float32List out, int frames, _State s, void Function(Object?) emit) {
  final e = s.engine ??= LabEngine();
  e
    ..useSample = s.u.useSample
    ..configure(s.u.spec, s.u.fx)
    ..setTouches(s.u.touches);
  e.synth.morph = s.u.morph;
  e.render(out, frames, emit);
  return frames;
}

void _update(_State current, _State next) => current.u = next.u;

void _message(_State s, Object? m) {
  final e = s.engine ??= LabEngine();
  switch (m) {
    case TableMsg(:final table):
      e.synth.wavetable = table;
    case SampleMsg(:final data, :final root):
      e.sampler = data == null ? null : SamplePlayer(data, root);
  }
}

class SoLoudLabOutput implements LabOutput {
  RealtimeStreamFeeder<_State>? _feeder;
  final _scope = StreamController<Float32List>.broadcast();
  final _pending = <Object>[];

  @override
  Stream<Float32List> get scope => _scope.stream;

  @override
  Future<void> init() async {
    final soloud = SoLoud.instance;
    if (!soloud.isInitialized) {
      await soloud.init(sampleRate: labRate, bufferSize: 512);
    }
    final stream = soloud.setRealtimeStream(
      sampleRate: labRate,
      channels: Channels.stereo,
      format: BufferType.f32le,
      bufferFrames: 8192,
    );
    final handle = soloud.play(stream.source);
    stream.bindActiveVoice(handle);
    _feeder = await stream.startFloat32Feeder<_State>(
      initialState: _State(
        LabUpdate(
          const PolySpec(),
          const [],
          List.filled(maxVoices, const Touch()),
          0,
          false,
        ),
      ),
      onFeed: _feed,
      onStateUpdate: _update,
      onMessage: _message,
      onUiEvent: (e) {
        if (e is Float32List) _scope.add(e);
      },
      chunkFrames: 192,
    );
    for (final m in _pending) {
      _feeder!.sendMessage(m);
    }
    _pending.clear();
  }

  @override
  void update(LabUpdate u) => _feeder?.updateState(_State(u));

  @override
  void send(Object message) {
    final f = _feeder;
    f == null ? _pending.add(message) : f.sendMessage(message);
  }

  @override
  Future<void> dispose() async {
    await _feeder?.dispose();
    _feeder = null;
    await _scope.close();
  }
}
