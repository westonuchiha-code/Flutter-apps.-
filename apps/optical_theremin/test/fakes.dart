import 'dart:typed_data';

import 'package:optical_theremin/src/audio/tone_output.dart';
import 'package:optical_theremin/src/core/luma_image.dart';
import 'package:optical_theremin/src/core/settings.dart';
import 'package:optical_theremin/src/input/camera_backend.dart';

/// Image whose left half has brightness [left] and right half [right].
LumaImage splitImage(int left, int right, {int width = 8, int height = 6}) {
  final pixels = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      pixels[y * width + x] = x < width ~/ 2 ? left : right;
    }
  }
  return LumaImage(width, height, pixels);
}

class FakeCameraBackend extends CameraBackend {
  FakeCameraBackend({this.cameras = const [], this.startError});

  final List<CameraOption> cameras;
  final Object? startError;
  void Function(LumaImage)? _onFrame;
  bool exposureLocked = false;
  int starts = 0;

  @override
  Future<List<CameraOption>> listCameras() async => cameras;

  @override
  Future<void> start(
    CameraOption camera, {
    required void Function(LumaImage frame) onFrame,
    required void Function(String message) onError,
  }) async {
    starts++;
    if (startError != null) throw startError!;
    _onFrame = onFrame;
  }

  void emit(LumaImage image) => _onFrame?.call(image);

  @override
  Future<void> stop() async => _onFrame = null;

  @override
  Future<bool> setExposureLocked(bool locked) async {
    exposureLocked = locked;
    return true;
  }
}

class FakeTone implements ToneOutput {
  bool started = false;
  Wave wave = Wave.sine;
  double frequency = 0;
  double volume = 0;
  int updates = 0;

  @override
  Future<void> init() async {}
  @override
  Future<void> start() async => started = true;
  @override
  Future<void> stop() async => started = false;
  @override
  void setWave(Wave wave) => this.wave = wave;
  @override
  void update({required double frequency, required double volume}) {
    this.frequency = frequency;
    this.volume = volume;
    updates++;
  }

  @override
  Future<void> dispose() async {}
}
