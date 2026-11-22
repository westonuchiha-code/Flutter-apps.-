import 'dart:async';

import 'package:light_capture/light_capture.dart';

import '../core/luma_image.dart';
import 'camera_backend.dart';

/// Windows and Linux: uses the light_capture plugin (native webcam capture).
class DesktopCameraBackend extends CameraBackend {
  StreamSubscription<LightCaptureFrame>? _subscription;

  @override
  Future<List<CameraOption>> listCameras() async => [
    for (final c in await LightCapture.listCameras())
      CameraOption(id: c.id, label: c.name, data: c),
  ];

  @override
  Future<void> start(
    CameraOption camera, {
    required void Function(LumaImage frame) onFrame,
    required void Function(String message) onError,
  }) async {
    await stop();
    _subscription = LightCapture.frames.listen(
      (frame) => onFrame(LumaImage(frame.width, frame.height, frame.pixels)),
      onError: (Object error) => onError(error.toString()),
    );
    try {
      await LightCapture.start(camera.data! as LightCaptureCamera);
    } catch (_) {
      await _subscription?.cancel();
      _subscription = null;
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    final subscription = _subscription;
    _subscription = null;
    if (subscription == null) return;
    await subscription.cancel();
    await LightCapture.stop();
  }

  @override
  Future<bool> setExposureLocked(bool locked) =>
      LightCapture.setAutoExposure(!locked);
}
