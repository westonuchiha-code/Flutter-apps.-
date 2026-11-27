// A stand-in for media_kit's player in tests and screenshots: media_kit
// needs the native mpv library, which `flutter test` doesn't load. It
// "plays" whatever it's given: opening a file reports a moving position, so
// the TV doesn't decide the video is broken and skip it.
import 'dart:async';

import 'package:media_kit/media_kit.dart';

class FakePlayer extends PlatformPlayer {
  FakePlayer() : super(configuration: const PlayerConfiguration());

  /// Every file opened, in order.
  final List<String> opened = [];

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    if (playable is Media) {
      opened.add(playable.uri);
      final start = playable.start ?? Duration.zero;
      state = state.copyWith(playing: play);
      positionController.add(start + const Duration(seconds: 1));
    }
  }

  @override
  Future<void> play() async => state = state.copyWith(playing: true);

  @override
  Future<void> pause() async => state = state.copyWith(playing: false);

  @override
  Future<void> stop() async => state = state.copyWith(playing: false);

  @override
  Future<void> seek(Duration duration) async =>
      positionController.add(duration);

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setAudioTrack(AudioTrack track) async {}

  @override
  Future<void> setSubtitleTrack(SubtitleTrack track) async {}
}
