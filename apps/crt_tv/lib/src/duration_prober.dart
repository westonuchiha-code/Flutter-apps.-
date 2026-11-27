import 'dart:async';

import 'package:media_kit/media_kit.dart';

/// Finds out how long a video is by opening it in a hidden, silent player.
///
/// "Live" channels need every video's length to work out what would be on
/// right now. Probes run one at a time so they never fight over the CPU.
class DurationProber {
  Future<void> _queue = Future<void>.value();

  Future<Duration?> probe(String path) {
    final result = _queue.then((_) => _probeNow(path));
    _queue = result.then<void>((_) {});
    return result;
  }

  // One hidden player is reused for every probe instead of making and
  // disposing one per file.
  Player? _player;

  Future<Duration?> _probeNow(String path) async {
    StreamSubscription<Duration>? durationSub;
    StreamSubscription<String>? errorSub;
    try {
      // vo defaults to 'null', so this player never opens a window.
      // ignore: prefer_const_constructors
      final player = _player ??= Player(
        configuration: PlayerConfiguration(muted: true),
      );
      final found = Completer<Duration?>();
      durationSub = player.stream.duration.listen((d) {
        if (d > Duration.zero && !found.isCompleted) found.complete(d);
      });
      errorSub = player.stream.error.listen((_) {
        if (!found.isCompleted) found.complete(null);
      });
      await player.open(Media(path), play: false);
      return await found.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () => null,
      );
    } catch (_) {
      return null;
    } finally {
      await durationSub?.cancel();
      await errorSub?.cancel();
      try {
        // Resets the length to zero so the next file's length is a change.
        await _player?.stop();
      } catch (_) {}
    }
  }
}
