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

  /// "Manufacturer Model" (tells a Retroid from a phone).
  Future<String> deviceModel() async {
    if (!available) return '';
    return await _channel.invokeMethod<String>('deviceModel') ?? '';
  }

  /// Starts an app; returns an error message, or null when it started.
  Future<String?> launch(LaunchSpec spec) async {
    if (!available) return 'Games start on Android only.';
    return _channel.invokeMethod<String>('launch', spec.toMap());
  }

  /// Opens the first of [urls] Android can show (Google Play's app, else
  /// the browser); false when nothing opened.
  Future<bool> openUrl(List<String> urls) async {
    if (!available) return false;
    return await _channel.invokeMethod<bool>('openUrl', {'urls': urls}) ??
        false;
  }

  /// Start game from the Save Manager app (null: none waiting). Taken
  /// once: the next call answers null.
  Future<Map<Object?, Object?>?> takeStartRequest() async {
    if (!available) return null;
    return _channel.invokeMethod<Map<Object?, Object?>>('takeStartRequest');
  }

  /// [onRequest] hears that a start request arrived while the menu runs
  /// (then ask [takeStartRequest]).
  void listenForStartRequests(void Function() onRequest) {
    if (!available) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'startRequest') onRequest();
      return null;
    });
  }

  /// Hands the Cross-Save token to the Pokéville app ('' = signed out),
  /// through the menu's signature-protected TokenProvider.
  Future<void> setSharedToken(String token) async {
    if (!available) return;
    await _channel.invokeMethod<void>('setSharedToken', {'token': token});
  }
}
