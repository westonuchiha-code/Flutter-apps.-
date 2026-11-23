import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optical_theremin/src/app/settings_store.dart';
import 'package:optical_theremin/src/app/theremin_controller.dart';
import 'package:optical_theremin/src/core/settings.dart';
import 'package:optical_theremin/src/input/camera_backend.dart';
import 'package:optical_theremin/src/recording/take_store.dart';
import 'package:chip_synth/chip_synth.dart';

import 'fakes.dart';

const webcam = CameraOption(id: 'cam', label: 'Webcam');
const backCam = CameraOption(id: 'back', label: 'Back camera');

ThereminController make({
  FakeCameraBackend? backend,
  FakeSynth? synth,
  MemoryTakeStore? takes,
  MemorySettingsStore? settings,
  FakeExporter? exporter,
}) => ThereminController(
  cameraBackend: backend ?? FakeCameraBackend(),
  synth: synth ?? FakeSynth(),
  takeStore: takes,
  settingsStore: settings,
  exporter: exporter,
  renderer: (take) async => Uint8List.fromList([1, 2, 3]),
);

void main() {
  test('starts the preferred camera and maps zones to controls', () async {
    final backend = FakeCameraBackend(cameras: [webcam]);
    final c = make(backend: backend);
    await c.initialize();
    c.updateSettings(c.settings.copyWith(mirror: false, lockExposure: false));
    expect(c.camera, webcam);
    expect(c.cameraError, isNull);

    // Default calibration: dark 10, bright 180.
    backend.emit(splitImage(10, 180));
    expect(c.pitchControl, 0);
    expect(c.secondControl, 1);
    // Inverted pitch by default: dark pitch zone = top of the range.
    expect(c.engine.targetMidi, c.settings.highNote);
  });

  test('mirroring swaps the zones', () async {
    final backend = FakeCameraBackend(cameras: [webcam]);
    final c = make(backend: backend);
    await c.initialize();
    c.updateSettings(c.settings.copyWith(lockExposure: false));
    backend.emit(splitImage(10, 180)); // mirrored: left (pitch) is bright
    expect(c.pitchControl, 1);
    expect(c.secondControl, 0);
  });

  test('remembers the chosen camera between launches', () async {
    final settings = MemorySettingsStore();
    fakeAsync((async) {
      final c = make(
        backend: FakeCameraBackend(cameras: [webcam, backCam]),
        settings: settings,
      );
      c.initialize();
      async.flushMicrotasks();
      expect(c.camera, webcam);
      c.selectCamera(backCam);
      async.elapse(const Duration(seconds: 3));
      expect(settings.saved?.cameraId, 'back');
    });
    final again = make(
      backend: FakeCameraBackend(cameras: [webcam, backCam]),
      settings: settings,
    );
    await again.initialize();
    expect(again.camera, backCam);
  });

  test('falls back to touch when there is no camera', () async {
    final c = make();
    await c.initialize();
    expect(c.usingTouch, isTrue);
    expect(c.cameraError, contains('No camera'));

    c.touch(const Offset(1, 0)); // far right, top = highest and loudest
    expect(c.engine.targetMidi, c.settings.highNote);
    c.touch(const Offset(0, 1));
    expect(c.engine.targetMidi, c.settings.lowNote);
  });

  test('reports camera start errors', () async {
    final c = make(
      backend: FakeCameraBackend(
        cameras: [webcam],
        startError: Exception('Camera busy'),
      ),
    );
    await c.initialize();
    expect(c.cameraError, 'Camera busy');
  });

  test('locks exposure after the camera settles', () {
    fakeAsync((async) {
      final backend = FakeCameraBackend(cameras: [webcam]);
      final c = make(backend: backend);
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
      final c = make(backend: backend);
      c.initialize();
      async.flushMicrotasks();
      c.updateSettings(c.settings.copyWith(mirror: false, lockExposure: false));
      backend.emit(splitImage(100, 100));

      c.calibrate(duration: const Duration(seconds: 1));
      backend.emit(splitImage(50, 60));
      backend.emit(splitImage(150, 160));
      async.elapse(const Duration(seconds: 2));

      expect(c.calibrated, isTrue);
      expect(c.pitchCalibration.dark, closeTo(55, 1e-9));
      expect(c.pitchCalibration.bright, closeTo(145, 1e-9));
      expect(c.secondCalibration.dark, closeTo(65, 1e-9));
    });
  });

  test('calibration fails without light change', () {
    fakeAsync((async) {
      final backend = FakeCameraBackend(cameras: [webcam]);
      final c = make(backend: backend);
      c.initialize();
      async.flushMicrotasks();
      c.updateSettings(c.settings.copyWith(lockExposure: false));
      backend.emit(splitImage(100, 100));
      c.calibrate(duration: const Duration(seconds: 1));
      async.elapse(const Duration(seconds: 2));
      expect(c.calibrated, isFalse);
      expect(c.calibrationMessage, contains('barely changed'));
    });
  });

  test('play drives the synth; sound changes reach it', () {
    fakeAsync((async) {
      final synth = FakeSynth();
      final c = make(synth: synth);
      c.initialize();
      async.flushMicrotasks();
      c.updateSound(const SoundSpec(chipId: 'sid', patchId: 'sync'));
      expect(synth.sound.chipId, 'sid');

      c.touch(const Offset(0.5, 0));
      c.startSound();
      async.elapse(const Duration(milliseconds: 500));
      expect(synth.updates, greaterThan(10));
      expect(synth.hz, closeTo(c.engine.frequency, 1e-6));
      expect(synth.level, greaterThan(0.9));

      c.stopSound();
      async.flushMicrotasks();
      expect(synth.level, 0);
      c.dispose();
    });
  });

  test('second hand can control the sound shape', () {
    fakeAsync((async) {
      final synth = FakeSynth();
      final c = make(synth: synth);
      c.initialize();
      async.flushMicrotasks();
      c.updateSettings(c.settings.copyWith(secondControl: SecondControl.shape));
      c.touch(const Offset(0.5, 0.1)); // near the top = lots of shape
      c.startSound();
      async.elapse(const Duration(milliseconds: 500));
      expect(synth.timbre, closeTo(0.9, 0.01));
      expect(synth.level, greaterThan(0.9)); // full volume while touching
      c.releaseTouch();
      async.elapse(const Duration(milliseconds: 50));
      expect(synth.level, 0); // letting go silences the pad
      c.dispose();
    });
  });

  test('records a take, plays and exports it', () {
    fakeAsync((async) {
      final synth = FakeSynth();
      final store = MemoryTakeStore();
      final exporter = FakeExporter();
      final c = make(synth: synth, takes: store, exporter: exporter);
      c.initialize();
      async.flushMicrotasks();
      c.touch(const Offset(0.5, 0));

      c.startRecording();
      async.flushMicrotasks();
      expect(c.playing, isTrue);
      expect(c.recording, isTrue);
      async.elapse(const Duration(seconds: 2));
      c.updateSound(const SoundSpec(chipId: 'fm', patchId: 'bell'));
      async.elapse(const Duration(seconds: 1));
      c.stopRecording();
      async.flushMicrotasks();

      expect(c.recording, isFalse);
      expect(c.takes, hasLength(1));
      final take = c.takes.single;
      expect(take.duration.inMilliseconds, closeTo(3000, 50));
      expect(take.specs.length, 2);
      expect(store.takes, contains(take.id));

      c.playTake(take);
      async.flushMicrotasks();
      expect(c.playing, isFalse); // live sound stops for playback
      expect(c.playingTakeId, take.id);
      expect(synth.clip, isNotNull);
      c.stopTake();
      async.flushMicrotasks();
      expect(c.playingTakeId, isNull);

      c.exportTake(take);
      async.flushMicrotasks();
      expect(exporter.exported.keys.single, endsWith('.wav'));

      c.renameTake(take, 'My song');
      async.flushMicrotasks();
      expect(c.takes.single.name, 'My song');

      c.revoiceTake(c.takes.single, const SoundSpec(chipId: 'tia'));
      async.flushMicrotasks();
      expect(c.takes.single.sound.chipId, 'tia');

      c.deleteTake(c.takes.single);
      async.flushMicrotasks();
      expect(c.takes, isEmpty);
      expect(store.takes, isEmpty);
      c.dispose();
    });
  });

  test('very short recordings are discarded', () {
    fakeAsync((async) {
      final c = make();
      c.initialize();
      async.flushMicrotasks();
      c.startRecording();
      async.elapse(const Duration(milliseconds: 100));
      c.stopRecording();
      async.flushMicrotasks();
      expect(c.takes, isEmpty);
      expect(c.toast.value, contains('too short'));
      c.dispose();
    });
  });
}
