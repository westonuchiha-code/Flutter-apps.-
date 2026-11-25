import 'dart:io';

import 'package:flutter/services.dart';

import 'launch.dart';

/// The Android side (MainActivity.kt). Off Android (tests, Linux) every call
/// answers as if nothing were installed.
class AndroidBridge {
  const AndroidBridge();
  static const _channel = MethodChannel('xmb/android');

  bool get available => Platform.isAndroid;

  /// Which of [packages] are installed.
  Future<Set<String>> installed(List<String> packages) async {
    if (!available) return {};
    final r = await _channel.invokeListMethod<String>('installed', {
      'packages': packages,
    });
    return {...?r};
  }

  /// Whether the app may read every file (needed to find ROMs and hand their
  /// paths to the emulators).
  Future<bool> hasAllFiles() async {
    if (!available) return true;
    return await _channel.invokeMethod<bool>('hasAllFiles') ?? false;
  }

  /// Opens Android's "All files access" page for this app.
  Future<void> requestAllFiles() async {
    if (available) await _channel.invokeMethod<void>('requestAllFiles');
  }

  /// Internal storage and SD cards (folder paths).
  Future<List<String>> storageRoots() async {
    if (!available) return ['/'];
    final r = await _channel.invokeListMethod<String>('storageRoots');
    return r ?? const ['/storage/emulated/0'];
  }

  /// Starts an app; returns an error message, or null when it started.
  Future<String?> launch(LaunchSpec spec) async {
    if (!available) return 'Games start on Android only.';
    return _channel.invokeMethod<String>('launch', spec.toMap());
  }
}
