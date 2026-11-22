import 'dart:async';

import 'package:camera/camera.dart';

import '../core/luma_image.dart';
import 'camera_backend.dart';

/// Android: uses the official camera plugin's image stream.
class AndroidCameraBackend extends CameraBackend {
  CameraController? _controller;
  bool _busy = false;

  @override
  Future<List<CameraOption>> listCameras() async {
    final cameras = await availableCameras();
    return [
      for (final (i, c) in cameras.indexed)
        CameraOption(
          id: c.name,
          label: switch (c.lensDirection) {
            CameraLensDirection.front => 'Front camera',
            CameraLensDirection.back => 'Back camera',
            CameraLensDirection.external => 'External camera ${i + 1}',
          },
          data: c,
        ),
    ];
  }

  /// The front camera faces up when the phone lies on a table, which is the
  /// natural way to play.
  @override
  int preferredCameraIndex(List<CameraOption> cameras) {
    final front = cameras.indexWhere(
      (c) =>
          (c.data as CameraDescription).lensDirection ==
          CameraLensDirection.front,
    );
    return front < 0 ? 0 : front;
  }

  @override
  Future<void> start(
    CameraOption camera, {
    required void Function(LumaImage frame) onFrame,
    required void Function(String message) onError,
  }) async {
    await stop();
    final description = camera.data! as CameraDescription;
    final controller = CameraController(
      description,
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    _controller = controller;
    try {
      await controller.initialize();
    } on CameraException catch (e) {
      _controller = null;
      await controller.dispose();
      throw Exception(switch (e.code) {
        'CameraAccessDenied' ||
        'CameraAccessDeniedWithoutPrompt' ||
        'CameraAccessRestricted' =>
          'Camera permission was denied. Allow camera access for this app in '
              'Android Settings > Apps.',
        _ => 'Could not open the camera: ${e.description ?? e.code}',
      });
    }
    // The image arrives in the sensor's orientation; rotate it upright for an
    // app held in portrait.
    final quarterTurns = description.sensorOrientation ~/ 90;
    await controller.startImageStream((image) {
      if (_busy || image.planes.isEmpty) return;
      _busy = true;
      try {
        final y = image.planes.first;
        final luma = LumaImage.fromPlane(
          y.bytes,
          width: image.width,
          height: image.height,
          rowStride: y.bytesPerRow,
          pixelStride: y.bytesPerPixel ?? 1,
        ).rotated(quarterTurns);
        onFrame(luma);
      } catch (e) {
        onError('Camera frame error: $e');
      } finally {
        _busy = false;
      }
    });
  }

  @override
  Future<void> stop() async {
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    if (controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
    await controller.dispose();
  }

  @override
  Future<bool> setExposureLocked(bool locked) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return false;
    try {
      await controller.setExposureMode(
        locked ? ExposureMode.locked : ExposureMode.auto,
      );
      return true;
    } on CameraException {
      return false;
    }
  }
}
