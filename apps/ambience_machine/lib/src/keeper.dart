import 'dart:io';

import 'package:flutter/services.dart';

/// Keeps playback going with the screen off. On Android this runs a
/// media-playback service with a notification (Stop button included);
/// desktop apps keep playing anyway, so it does nothing there.
class PlaybackKeeper {
  PlaybackKeeper({void Function()? onStopRequested}) {
    if (Platform.isAndroid) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'stopRequested') onStopRequested?.call();
      });
    }
  }

  static const _channel = MethodChannel('ambience/service');

  Future<void> start(String title, String text) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('start', {'title': title, 'text': text});
    } on PlatformException catch (_) {
      // Playback still works while the app is on screen.
    }
  }

  Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('stop');
    } on PlatformException catch (_) {}
  }
}
