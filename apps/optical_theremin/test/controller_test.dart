import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optical_theremin/src/app/theremin_controller.dart';
import 'package:optical_theremin/src/core/settings.dart';
import 'package:optical_theremin/src/input/camera_backend.dart';

import 'fakes.dart';

void main() {
  const webcam = CameraOption(id: 'cam', label: 'Webcam');

  test('starts the preferred camera and maps zones to controls', () async {
    final backend = FakeCameraBackend(cameras: [webcam]);
    final c = ThereminController(cameraBackend: backend, tone: FakeTone());
    c.updateSettings(c.settings.copyWith(mirror: false, lockExposure: false));
    await c.initialize();
    expect(c.camera, webcam);
    expect(c.cameraError, isNull);

    // Default calibration: dark 10, bright 180.
    backend.emit(splitImage(10, 180));
    expect(c.pitchControl, 0);
    expect(c.volumeControl, 1);
    // Inverted pitch by default: dark pitch zone = top of the range.
    expect(c.engine.targetMidi, c.settings.highNote);
  });

  test('mirroring swaps the zones', () async {
    final backend = FakeCameraBackend(cameras: [webcam]);
    final c = ThereminController(cameraBackend: backend, tone: FakeTone());
    c.updateSettings(c.settings.copyWith(lockExposure: false));
    await c.initialize();
    backend.emit(splitImage(10, 180)); // mirrored: left (pitch) is bright
    expect(c.pitchControl, 1);
    expect(c.volumeControl, 0);
  });

  test('falls back to touch when there is no camera', () async {
    final c = ThereminController(
      cameraBackend: FakeCameraBackend(),
      tone: FakeTone(),
    );
    await c.initialize();
    expect(c.usingTouch, isTrue);
    expect(c.cameraError, contains('No camera'));

    c.touch(const Offset(1, 0)); // far right, top = highest and loudest
    expect(c.engine.targetMidi, c.settings.highNote);
    c.touch(const Offset(0, 1));
    expect(c.engine.targetMidi, c.settings.lowNote);
  });

  test('reports camera start errors', () async {
    final c = ThereminController(
      cameraBackend: FakeCameraBackend(
        cameras: [webcam],
        startError: Exception('Camera busy'),
      ),
      tone: FakeTone(),
    );
    await c.initialize();
    expect(c.cameraError, 'Camera busy');
  });

  test('locks exposure after the camera settles', () {
    fakeAsync((async) {
      final backend = FakeCameraBackend(cameras: [webcam]);
      final c = ThereminController(cameraBackend: backend, tone: FakeTone());
      c.initialize();
      async.elapse(const Duration(seconds: 2));
      expect(backend.exposureLocked, isTrue);
      expect(c.exposureLockWorked, isTrue);
      c.updateSettings(c.settings.copyWith(lockExposure: false));
      async.flushMicrotasks();
      expect(backend.exposureLocked, isFalse);
    });
  });

  test('calibration records the light range', () {
    fakeAsync((async) {
      final backend = FakeCameraBackend(cameras: [webcam]);
      final c = ThereminController(cameraBackend: backend, tone: FakeTone());
      c.updateSettings(c.settings.copyWith(mirror: false, lockExposure: false));
      c.initialize();
      async.flushMicrotasks();
      backend.emit(splitImage(100, 100));

      c.calibrate(duration: const Duration(seconds: 1));
      backend.emit(splitImage(50, 60));
      backend.emit(splitImage(150, 160));
      async.elapse(const Duration(seconds: 2));

      expect(c.calibrated, isTrue);
      expect(c.pitchCalibration.dark, closeTo(55, 1e-9));
      expect(c.pitchCalibration.bright, closeTo(145, 1e-9));
      expect(c.volumeCalibration.dark, closeTo(65, 1e-9));
    });
  });

  test('calibration fails without light change', () {
    fakeAsync((async) {
      final backend = FakeCameraBackend(cameras: [webcam]);
      final c = ThereminController(cameraBackend: backend, tone: FakeTone());
      c.updateSettings(c.settings.copyWith(lockExposure: false));
      c.initialize();
      async.flushMicrotasks();
      backend.emit(splitImage(100, 100));
      c.calibrate(duration: const Duration(seconds: 1));
      async.elapse(const Duration(seconds: 2));
      expect(c.calibrated, isFalse);
      expect(c.calibrationMessage, contains('barely changed'));
    });
  });

  test('play drives the tone output', () {
    fakeAsync((async) {
      final tone = FakeTone();
      final c = ThereminController(
        cameraBackend: FakeCameraBackend(),
        tone: tone,
      );
      c.initialize();
      async.flushMicrotasks();
      c.updateSettings(c.settings.copyWith(wave: Wave.saw));
      expect(tone.wave, Wave.saw);

      c.touch(const Offset(0.5, 0));
      c.startSound();
      async.elapse(const Duration(milliseconds: 500));
      expect(tone.started, isTrue);
      expect(tone.updates, greaterThan(10));
      expect(tone.frequency, closeTo(c.engine.frequency, 1e-6));
      expect(tone.volume, greaterThan(0.5));

      c.stopSound();
      async.flushMicrotasks();
      expect(tone.started, isFalse);
      c.dispose();
    });
  });
}
