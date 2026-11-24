// The real-time stream API of flutter_soloud is experimental; the package
// version is pinned in pubspec.yaml.
// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:typed_data';

import 'package:chip_synth/chip_synth.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

const speechRate = 48000;

sealed class SpeechCommand {
  const SpeechCommand();
}

class Say extends SpeechCommand {
  const Say(this.words, this.settings);
  final List<SpokenWord> words;
  final SpeechSettings settings;
}

class SingWord extends SpeechCommand {
  const SingWord(this.word, this.hz, this.settings);
  final SpokenWord word;
  final double hz;
  final SpeechSettings settings;
}

class SingPitch extends SpeechCommand {
  const SingPitch(this.hz);
  final double hz;
}

class ReleaseWord extends SpeechCommand {
  const ReleaseWord();
}

class StopSpeech extends SpeechCommand {
  const StopSpeech();
}

/// Progress from the audio side.
class SpeechProgress {
  const SpeechProgress(this.wordIndex, this.busy);
  final int wordIndex;
  final bool busy;
}

abstract class SpeechOutput {
  Future<void> init();
  void send(SpeechCommand c);
  Stream<SpeechProgress> get progress;
  Future<void> dispose();
}

class _State {
  final synth = SpeechSynth(speechRate.toDouble());
  final mono = Float32List(4096);
  int lastWord = -2;
  bool lastBusy = false;
}

int _feed(Float32List out, int frames, _State s, void Function(Object?) emit) {
  s.synth.render(s.mono, frames);
  for (var i = 0; i < frames; i++) {
    out[i * 2] = s.mono[i];
    out[i * 2 + 1] = s.mono[i];
  }
  final busy = s.synth.busy;
  if (s.synth.wordIndex != s.lastWord || busy != s.lastBusy) {
    s
      ..lastWord = s.synth.wordIndex
      ..lastBusy = busy;
    emit(SpeechProgress(s.synth.wordIndex, busy));
  }
  return frames;
}

void _message(_State s, Object? m) {
  final synth = s.synth;
  switch (m) {
    case Say(:final words, :final settings):
      synth.speak(words, settings);
    case SingWord(:final word, :final hz, :final settings):
      synth.singWord(word, hz, settings);
    case SingPitch(:final hz):
      synth.setSingPitch(hz);
    case ReleaseWord():
      synth.releaseWord();
    case StopSpeech():
      synth.stop();
  }
}

class SoLoudSpeechOutput implements SpeechOutput {
  RealtimeStreamFeeder<_State>? _feeder;
  final _progress = StreamController<SpeechProgress>.broadcast();

  @override
  Stream<SpeechProgress> get progress => _progress.stream;

  @override
  Future<void> init() async {
    final soloud = SoLoud.instance;
    if (!soloud.isInitialized) {
      await soloud.init(sampleRate: speechRate, bufferSize: 512);
    }
    final stream = soloud.setRealtimeStream(
      sampleRate: speechRate,
      channels: Channels.stereo,
      format: BufferType.f32le,
      bufferFrames: 8192,
    );
    final handle = soloud.play(stream.source);
    stream.bindActiveVoice(handle);
    _feeder = await stream.startFloat32Feeder<_State>(
      initialState: _State(),
      onFeed: _feed,
      onMessage: _message,
      onUiEvent: (e) {
        if (e is SpeechProgress) _progress.add(e);
      },
      chunkFrames: 256,
    );
  }

  @override
  void send(SpeechCommand c) => _feeder?.sendMessage(c);

  @override
  Future<void> dispose() async {
    await _feeder?.dispose();
    _feeder = null;
    await _progress.close();
  }
}
