// The real-time stream API of flutter_soloud is experimental; the package
// version is pinned in pubspec.yaml.
// ignore_for_file: experimental_member_use
import 'package:chip_synth/chip_synth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

/// Sound output for the touch synth.
abstract class PolyOutput {
  Future<void> init();
  void update(PolySpec spec, List<Touch> touches);
  Future<void> dispose();
}

const _rate = 48000;

/// State living in the audio isolate.
class PolyState {
  PolyState(this.spec, this.touches);
  PolySpec spec;
  List<Touch> touches;
  PolySynth? _synth;
  PolySpec? _applied;
}

int feedPoly(
  Float32List out,
  int frames,
  PolyState s,
  void Function(Object?) emit,
) {
  final synth = s._synth ??= PolySynth(_rate.toDouble());
  if (s._applied != s.spec) {
    synth.configure(s.spec);
    s._applied = s.spec;
  }
  for (var i = 0; i < maxVoices && i < s.touches.length; i++) {
    synth.setTouch(i, s.touches[i]);
  }
  synth.render(out, frames);
  return frames;
}

void updatePoly(PolyState current, PolyState next) {
  current
    ..spec = next.spec
    ..touches = next.touches;
}

/// Streams the synth into SoLoud from a background isolate.
class SoLoudPolyOutput implements PolyOutput {
  RealtimeStreamFeeder<PolyState>? _feeder;

  @override
  Future<void> init() async {
    final soloud = SoLoud.instance;
    if (!soloud.isInitialized) {
      await soloud.init(sampleRate: _rate, bufferSize: 512);
    }
    final stream = soloud.setRealtimeStream(
      sampleRate: _rate,
      channels: Channels.stereo,
      format: BufferType.f32le,
      bufferFrames: 8192,
    );
    final handle = soloud.play(stream.source);
    stream.bindActiveVoice(handle);
    _feeder = await stream.startFloat32Feeder<PolyState>(
      initialState: PolyState(
        const PolySpec(),
        List.filled(maxVoices, const Touch()),
      ),
      onFeed: feedPoly,
      onStateUpdate: updatePoly,
      chunkFrames: 192,
    );
  }

  @override
  void update(PolySpec spec, List<Touch> touches) =>
      _feeder?.updateState(PolyState(spec, List.of(touches)));

  @override
  Future<void> dispose() async {
    await _feeder?.dispose();
    _feeder = null;
  }
}
