import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../core/luma_image.dart';
import 'android_camera_backend.dart';
import 'desktop_camera_backend.dart';

/// A camera the player can choose.
@immutable
class CameraOption {
  const CameraOption({required this.id, required this.label, this.data});

  final String id;
  final String label;

  /// Backend-specific handle.
  final Object? data;

  @override
  bool operator ==(Object other) => other is CameraOption && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Delivers upright, unmirrored brightness thumbnails from a camera.
abstract class CameraBackend {
  /// The backend for this platform, or null if cameras are not supported.
  static CameraBackend? forCurrentPlatform() {
    if (kIsWeb) return null;
    if (Platform.isAndroid) return AndroidCameraBackend();
    if (Platform.isWindows || Platform.isLinux) return DesktopCameraBackend();
    return null;
  }

  Future<List<CameraOption>> listCameras();

  /// Index into [listCameras] of the camera to use by default.
  int preferredCameraIndex(List<CameraOption> cameras) => 0;

  Future<void> start(
    CameraOption camera, {
    required void Function(LumaImage frame) onFrame,
    required void Function(String message) onError,
  });

  Future<void> stop();

  /// Locks or unlocks auto-exposure. Returns false if unsupported.
  Future<bool> setExposureLocked(bool locked);
}
