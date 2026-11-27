import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';

import 'loudness.dart';

/// Finds out how loud a video is by having a hidden player decode a few
/// minutes of its sound into a scratch file (much faster than real time)
/// and measuring that. One at a time, like [DurationProber].
class LoudnessProber {
  LoudnessProber(this._scratchDir);

  final Directory _scratchDir;

  static const _sampleRate = 22050;
  static const _sampleSeconds = 300;

  Future<void> _queue = Future<void>.value();
  Player? _player;
  int _count = 0;

  /// [length] is the video's length if known; it lets the sample skip the
  /// very start, which is often a logo or silence. [stillWanted] is asked
  /// when this request's turn comes; if it says no (the channel has moved
  /// on), nothing is measured and the result is null.
  Future<Loudness?> measure(String path, {Duration? length, bool Function()? stillWanted}) {
    final result = _queue.then((_) async {
      if (stillWanted != null && !stillWanted()) return null;
      return _measureNow(path, length);
    });
    _queue = result.then<void>((_) {});
    return result;
  }

  Future<Loudness?> _measureNow(String path, Duration? length) async {
    // Two alternating files, in case the previous one is still being let go.
    final scratch = File('${_scratchDir.path}${Platform.pathSeparator}level_probe_${_count++ % 2}.pcm');
    StreamSubscription<bool>? finished;
    try {
      final player = _player ??= Player();
      final native = player.platform;
      if (native is! NativePlayer) return null;
      if (scratch.existsSync()) scratch.deleteSync();
      const options = {
        'ao': 'pcm',
        'ao-pcm-waveheader': 'no',
        'audio-format': 's16',
        'audio-channels': 'mono',
        'audio-samplerate': '$_sampleRate',
        'vid': 'no',
        'sid': 'no',
        // Makes each video get a fresh output file.
        'gapless-audio': 'no',
        'length': '$_sampleSeconds',
      };
      for (final option in options.entries) {
        await native.setProperty(option.key, option.value);
      }
      await native.setProperty('ao-pcm-file', scratch.path);

      var start = Duration.zero;
      if (length != null && length > const Duration(minutes: 2)) {
        start = length * 0.1;
        if (start > const Duration(minutes: 2)) start = const Duration(minutes: 2);
      }
      final done = Completer<void>();
      finished = player.stream.completed.listen((completed) {
        if (completed && !done.isCompleted) done.complete();
      });
      await player.open(Media(path, start: start > Duration.zero ? start : null), play: true);
      await done.future.timeout(const Duration(seconds: 20), onTimeout: () {});
      await player.stop();
      if (!scratch.existsSync()) return null;
      final bytes = await scratch.readAsBytes();
      return analyseLoudness(Int16List.sublistView(bytes, 0, bytes.length - bytes.length % 2), _sampleRate);
    } catch (_) {
      return null;
    } finally {
      await finished?.cancel();
      try {
        if (scratch.existsSync()) scratch.deleteSync();
      } catch (_) {
        // Still in use; it's overwritten next time round.
      }
    }
  }
}
