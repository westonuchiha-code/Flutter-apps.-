// The real-time stream API of flutter_soloud is marked experimental; the
// package version is pinned in pubspec.yaml so it cannot change under us.
// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';

import 'package:chip_synth/chip_synth.dart';

/// Live chip-synth output.
abstract class SynthOutput {
  Future<void> init();
  void setSound(SoundSpec spec);

  /// Performance controls: pitch (Hz), loudness and shape (0–1).
  void update({
    required double hz,
    required double level,
    required double timbre,
  });

  /// Recent output waveform, for the oscilloscope.
  Stream<Float32List> get scope;

  /// Plays a rendered WAV (a recording). Completes when playback ends or
  /// [stopClip] is called.
  Future<void> playClip(Uint8List wav);
  Future<void> stopClip();

  Future<void> dispose();
}

const _sampleRate = 48000;

/// State living in the background audio isolate. Only the control fields
/// are sent with each update; the engine is created inside the isolate.
class LiveSynthState {
  LiveSynthState({
    required this.spec,
    this.hz = 220,
    this.level = 0,
    this.timbre = 0.5,
  });

  SoundSpec spec;
  double hz;
  double level;
  double timbre;
  SynthEngine? _engine;
  SoundSpec? _applied;
  int _chunks = 0;
}

/// Runs in the audio isolate: renders the next chunk of audio.
int feedLiveSynth(
  Float32List out,
  int frames,
  LiveSynthState s,
  void Function(Object? event) emitToUi,
) {
  final engine = s._engine ??= SynthEngine(_sampleRate.toDouble());
  if (s._applied != s.spec) {
    engine.configure(s.spec);
    s._applied = s.spec;
  }
  engine.setControls(s.hz, s.level, s.timbre);
  engine.render(out, frames);
  if (++s._chunks % 8 == 0) emitToUi(engine.scopeSnapshot());
  return frames;
}

/// Runs in the audio isolate: copies new controls into the live state.
void updateLiveSynth(LiveSynthState current, LiveSynthState next) {
  current
    ..spec = next.spec
    ..hz = next.hz
    ..level = next.level
    ..timbre = next.timbre;
}

/// [SynthOutput] that streams the chip synth into SoLoud from a background
/// isolate (Android, Windows, Linux).
class SoLoudSynthOutput implements SynthOutput {
  final SoLoud _soloud = SoLoud.instance;
  RealtimeStreamFeeder<LiveSynthState>? _feeder;
  final _scope = StreamController<Float32List>.broadcast();
  SoundSpec _spec = const SoundSpec();
  double _hz = 220, _level = 0, _timbre = 0.5;

  AudioSource? _clip;
  SoundHandle? _clipHandle;
  Completer<void>? _clipDone;
  Timer? _clipWatch;

  @override
  Stream<Float32List> get scope => _scope.stream;

  @override
  Future<void> init() async {
    if (!_soloud.isInitialized) {
      // A small buffer keeps the delay between hand and sound short.
      await _soloud.init(sampleRate: _sampleRate, bufferSize: 1024);
    }
    final stream = _soloud.setRealtimeStream(
      sampleRate: _sampleRate,
      channels: Channels.stereo,
      format: BufferType.f32le,
      bufferFrames: 8192,
    );
    final handle = _soloud.play(stream.source);
    stream.bindActiveVoice(handle);
    _feeder = await stream.startFloat32Feeder<LiveSynthState>(
      initialState: LiveSynthState(spec: _spec),
      onFeed: feedLiveSynth,
      onStateUpdate: updateLiveSynth,
      onUiEvent: (event) {
        if (event is Float32List && !_scope.isClosed) _scope.add(event);
      },
      chunkFrames: 256,
    );
  }

  void _send() => _feeder?.updateState(
    LiveSynthState(spec: _spec, hz: _hz, level: _level, timbre: _timbre),
  );

  @override
  void setSound(SoundSpec spec) {
    _spec = spec;
    _send();
  }

  @override
  void update({
    required double hz,
    required double level,
    required double timbre,
  }) {
    _hz = hz;
    _level = level;
    _timbre = timbre;
    _send();
  }

  @override
  Future<void> playClip(Uint8List wav) async {
    await stopClip();
    final source = await _soloud.loadMem('recording.wav', wav);
    _clip = source;
    final done = _clipDone = Completer<void>();
    final handle = _clipHandle = _soloud.play(source);
    _clipWatch = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (!_soloud.getIsValidVoiceHandle(handle)) unawaited(stopClip());
    });
    return done.future;
  }

  @override
  Future<void> stopClip() async {
    _clipWatch?.cancel();
    _clipWatch = null;
    final handle = _clipHandle;
    final source = _clip;
    final done = _clipDone;
    _clipHandle = null;
    _clip = null;
    _clipDone = null;
    if (handle != null && _soloud.getIsValidVoiceHandle(handle)) {
      await _soloud.stop(handle);
    }
    if (source != null) await _soloud.disposeSource(source);
    if (done != null && !done.isCompleted) done.complete();
  }

  @override
  Future<void> dispose() async {
    await stopClip();
    await _feeder?.dispose();
    _feeder = null;
    await _scope.close();
  }
}
