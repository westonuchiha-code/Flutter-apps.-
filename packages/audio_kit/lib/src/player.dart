import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

/// Plays one audio file (or a range of it) and reports the position.
class ClipPlayer extends ChangeNotifier {
  AudioSource? _source;
  SoundHandle? _handle;
  Timer? _timer;
  double _end = double.infinity;
  String? error;

  /// Current position in seconds (while playing).
  double position = 0;
  bool get playing => _handle != null;

  Future<void> load(File file) async {
    await stop();
    final soloud = SoLoud.instance;
    try {
      if (!soloud.isInitialized) await soloud.init();
      final old = _source;
      _source = null;
      if (old != null) await soloud.disposeSource(old);
      _source = await soloud.loadFile(file.path);
      error = null;
    } catch (e) {
      error = 'Could not load audio: $e';
    }
    notifyListeners();
  }

  /// Plays from [from] seconds, stopping at [to] (default: the end).
  Future<void> play({double from = 0, double? to}) async {
    final source = _source;
    if (source == null) return;
    await stop();
    final soloud = SoLoud.instance;
    final h = soloud.play(source, paused: true);
    if (from > 0) {
      soloud.seek(h, Duration(microseconds: (from * 1e6).round()));
    }
    soloud.setPause(h, false);
    _handle = h;
    _end = to ?? double.infinity;
    position = from;
    _timer = Timer.periodic(const Duration(milliseconds: 30), (_) => _tick());
    notifyListeners();
  }

  void _tick() {
    final h = _handle;
    if (h == null) return;
    final soloud = SoLoud.instance;
    if (!soloud.getIsValidVoiceHandle(h)) {
      unawaited(stop());
      return;
    }
    position = soloud.getPosition(h).inMicroseconds / 1e6;
    if (position >= _end) {
      unawaited(stop());
      return;
    }
    notifyListeners();
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    final h = _handle;
    _handle = null;
    if (h != null) {
      try {
        await SoLoud.instance.stop(h);
      } catch (_) {}
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    final h = _handle;
    final s = _source;
    if (SoLoud.instance.isInitialized) {
      if (h != null) unawaited(SoLoud.instance.stop(h));
      if (s != null) unawaited(SoLoud.instance.disposeSource(s));
    }
    super.dispose();
  }
}
