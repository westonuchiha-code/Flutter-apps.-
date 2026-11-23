import 'dart:async';
import 'dart:typed_data';

import 'package:optical_theremin/src/app/exporter.dart';
import 'package:optical_theremin/src/audio/synth_output.dart';
import 'package:optical_theremin/src/core/luma_image.dart';
import 'package:optical_theremin/src/synth/engine.dart';
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

class FakeSynth implements SynthOutput {
  SoundSpec sound = const SoundSpec();
  double hz = 0;
  double level = 0;
  double timbre = 0;
  int updates = 0;
  Uint8List? clip;
  Completer<void>? _clipDone;
  final _scope = StreamController<Float32List>.broadcast();

  @override
  Future<void> init() async {}
  @override
  void setSound(SoundSpec spec) => sound = spec;
  @override
  void update({
    required double hz,
    required double level,
    required double timbre,
  }) {
    this.hz = hz;
    this.level = level;
    this.timbre = timbre;
    updates++;
  }

  @override
  Stream<Float32List> get scope => _scope.stream;

  void emitScope(Float32List data) => _scope.add(data);

  @override
  Future<void> playClip(Uint8List wav) {
    clip = wav;
    return (_clipDone = Completer<void>()).future;
  }

  @override
  Future<void> stopClip() async {
    clip = null;
    final done = _clipDone;
    _clipDone = null;
    if (done != null && !done.isCompleted) done.complete();
  }

  @override
  Future<void> dispose() async {}
}

class FakeExporter implements Exporter {
  final exported = <String, Uint8List>{};

  @override
  Future<String?> exportWav(String fileName, Uint8List wav) async {
    exported[fileName] = wav;
    return 'Exported';
  }
}
