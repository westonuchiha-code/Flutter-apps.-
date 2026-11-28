import 'dart:io';

import 'android/android_backend.dart';
import 'model/backend.dart';
import 'model/key_backend.dart';
import 'model/lab.dart';
import 'sdl/sdl_backend.dart';
import 'sdl/sdl_ffi.dart';

/// The best backend for this platform: SDL3 on Windows and Linux (key
/// events if SDL3 can't load), Android's input devices on Android.
ControllerLab createLab({SdlHints hints = const SdlHints()}) {
  PadBackend keys(String? reason) =>
      KeyBackend(android: Platform.isAndroid, reason: reason);
  if (Platform.isAndroid) {
    return ControllerLab(AndroidBackend(), fallback: keys);
  }
  final (sdl, problem) = FfiSdl.load();
  final backend = SdlBackend(sdl, hints: hints)..loadProblem = problem;
  return ControllerLab(backend, fallback: keys);
}
