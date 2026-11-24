// The real-time stream API of flutter_soloud is experimental; the package
// version is pinned in pubspec.yaml.
// ignore_for_file: experimental_member_use
import 'dart:typed_data';

import 'package:chip_synth/chip_synth.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

const synthRate = 48000;

abstract class WaveOutput {
  Future<void> init();

  /// Sent only when the drawn waves change (it carries the whole table).
  void setTable(Wavetable table);

  /// Cheap: sent on every key press and knob move.
  void update(PolySpec spec, List<Touch> touches, double morph);
  Future<void> dispose();
}

/// Lives in the audio isolate.
class PainterState {
  PainterState(this.spec, this.touches, this.morph);
  PolySpec spec;
  List<Touch> touches;
  double morph;
  PolySynth? synth;
  PolySpec? applied;
  Wavetable? pendingTable;
}

int _feed(
  Float32List out,
  int frames,
  PainterState s,
  void Function(Object?) emit,
) {
  final synth = s.synth ??= PolySynth(synthRate.toDouble());
  final table = s.pendingTable;
  if (table != null) {
    synth.wavetable = table;
    s.pendingTable = null;
  }
  if (s.applied != s.spec) {
    synth.configure(s.spec);
    s.applied = s.spec;
  }
  synth.morph = s.morph;
  for (var i = 0; i < maxVoices && i < s.touches.length; i++) {
    synth.setTouch(i, s.touches[i]);
  }
  synth.render(out, frames);
  return frames;
}

void _update(PainterState current, PainterState next) {
  current
    ..spec = next.spec
    ..touches = next.touches
    ..morph = next.morph;
}

void _message(PainterState s, Object? m) {
  if (m is Wavetable) s.pendingTable = m;
}

class SoLoudWaveOutput implements WaveOutput {
  RealtimeStreamFeeder<PainterState>? _feeder;
  Wavetable? _pendingTable;

  @override
  Future<void> init() async {
    final soloud = SoLoud.instance;
    if (!soloud.isInitialized) {
      await soloud.init(sampleRate: synthRate, bufferSize: 512);
    }
    final stream = soloud.setRealtimeStream(
      sampleRate: synthRate,
      channels: Channels.stereo,
      format: BufferType.f32le,
      bufferFrames: 8192,
    );
    final handle = soloud.play(stream.source);
    stream.bindActiveVoice(handle);
    _feeder = await stream.startFloat32Feeder<PainterState>(
      initialState: PainterState(
        const PolySpec(),
        List.filled(maxVoices, const Touch()),
        0,
      ),
      onFeed: _feed,
      onStateUpdate: _update,
      onMessage: _message,
      chunkFrames: 192,
    );
    final t = _pendingTable;
    if (t != null) _feeder!.sendMessage(t);
  }

  @override
  void setTable(Wavetable table) {
    final f = _feeder;
    f == null ? _pendingTable = table : f.sendMessage(table);
  }

  @override
  void update(PolySpec spec, List<Touch> touches, double morph) =>
      _feeder?.updateState(PainterState(spec, List.of(touches), morph));

  @override
  Future<void> dispose() async {
    await _feeder?.dispose();
    _feeder = null;
  }
}
