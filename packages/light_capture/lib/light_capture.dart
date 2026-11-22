/// Live webcam brightness frames on Windows and Linux.
///
/// Flutter's `camera` plugin cannot stream frames on Windows, so this plugin
/// captures from the webcam natively (Media Foundation on Windows, V4L2 on
/// Linux) and sends small 8-bit luminance thumbnails to Dart.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A camera that can be passed to [LightCapture.start].
@immutable
class LightCaptureCamera {
  const LightCaptureCamera({required this.id, required this.name});

  /// Opaque platform identifier.
  final String id;

  /// Human-readable name, e.g. "Integrated Webcam".
  final String name;

  @override
  bool operator ==(Object other) =>
      other is LightCaptureCamera && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'LightCaptureCamera($name)';
}

/// An 8-bit luminance image: one byte per pixel, row-major, 0 = black.
@immutable
class LightCaptureFrame {
  const LightCaptureFrame({
    required this.width,
    required this.height,
    required this.pixels,
  });

  final int width;
  final int height;
  final Uint8List pixels;
}

/// Error reported by the platform while capturing.
class LightCaptureException implements Exception {
  const LightCaptureException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Entry point of the plugin.
class LightCapture {
  LightCapture._();

  static const MethodChannel _methods = MethodChannel('light_capture');
  static const EventChannel _events = EventChannel('light_capture/frames');

  /// Whether this platform has a native implementation.
  static bool get isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux);

  static Stream<LightCaptureFrame>? _frames;

  /// Frames from the running camera. Listen before calling [start].
  /// Capture errors arrive as [LightCaptureException] stream errors.
  static Stream<LightCaptureFrame> get frames => _frames ??= _events
      .receiveBroadcastStream()
      .map(_decodeFrame)
      .handleError(
        (Object error) => throw error is PlatformException
            ? LightCaptureException(error.message ?? error.code)
            : error,
      );

  static LightCaptureFrame _decodeFrame(dynamic event) {
    final map = event as Map<Object?, Object?>;
    return LightCaptureFrame(
      width: map['width']! as int,
      height: map['height']! as int,
      pixels: map['pixels']! as Uint8List,
    );
  }

  /// Lists connected cameras.
  static Future<List<LightCaptureCamera>> listCameras() async {
    final list = await _methods.invokeListMethod<Object?>('listCameras') ?? [];
    return [
      for (final entry in list.cast<Map<Object?, Object?>>())
        LightCaptureCamera(
          id: entry['id']! as String,
          name: entry['name']! as String,
        ),
    ];
  }

  /// Opens [camera] and starts streaming [frames].
  /// Throws [LightCaptureException] if the camera cannot be opened.
  static Future<void> start(LightCaptureCamera camera) async {
    try {
      await _methods.invokeMethod<void>('start', {'id': camera.id});
    } on PlatformException catch (e) {
      throw LightCaptureException(e.message ?? e.code);
    }
  }

  /// Stops the camera.
  static Future<void> stop() => _methods.invokeMethod<void>('stop');

  /// Turns the camera's automatic exposure (and gain) on or off.
  /// Returns false if the camera does not support it.
  static Future<bool> setAutoExposure(bool enabled) async =>
      await _methods.invokeMethod<bool>('setAutoExposure', {
        'enabled': enabled,
      }) ??
      false;
}
