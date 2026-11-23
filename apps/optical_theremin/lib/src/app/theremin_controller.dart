import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show Offset, Rect;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../audio/synth_output.dart';
import '../core/calibration.dart';
import '../core/luma_image.dart';
import '../core/settings.dart';
import '../core/theremin_engine.dart';
import '../input/camera_backend.dart';
import '../recording/take.dart';
import '../recording/take_store.dart';

import 'package:chip_synth/chip_synth.dart';

import 'exporter.dart';
import 'settings_store.dart';

/// Image regions that control pitch and the second control, in fractions of
/// the image.
const pitchZoneTwoZones = Rect.fromLTRB(0, 0, 0.5, 1);
const secondZoneTwoZones = Rect.fromLTRB(0.5, 0, 1, 1);
const pitchZoneSingle = Rect.fromLTRB(0, 0, 1, 1);

/// Longest recording, to protect storage.
const maxRecording = Duration(minutes: 10);

/// Renders a take to WAV bytes; replaceable in tests.
typedef TakeRenderer = Future<Uint8List> Function(Take take);

Future<Uint8List> renderTakeInBackground(Take take) =>
    Isolate.run(() => renderTakeWav(take));

/// App state: connects the camera (or touch pad), the theremin engine, the
/// chip synth, recordings and settings.
class ThereminController extends ChangeNotifier {
  ThereminController({
    required this.cameraBackend,
    required this.synth,
    TakeStore? takeStore,
    SettingsStore? settingsStore,
    this.exporter,
    TakeRenderer? renderer,
  }) : takeStore = takeStore ?? MemoryTakeStore(),
       settingsStore = settingsStore ?? MemorySettingsStore(),
       renderer = renderer ?? renderTakeInBackground;

  final CameraBackend? cameraBackend;
  final SynthOutput synth;
  final TakeStore takeStore;
  final SettingsStore settingsStore;
  final Exporter? exporter;
  final TakeRenderer renderer;

  ThereminSettings _settings = const ThereminSettings();
  ThereminSettings get settings => _settings;

  late final ThereminEngine engine = ThereminEngine(_settings);

  List<CameraOption> cameras = const [];

  /// The active camera, or null when playing with the touch pad.
  CameraOption? camera;
  bool get usingTouch => camera == null;

  bool initialized = false;
  bool playing = false;
  String? cameraError;
  String? audioError;

  /// Short-lived message for a snackbar (saved, exported, ...).
  final ValueNotifier<String?> toast = ValueNotifier(null);

  /// Latest oscilloscope data from the synth.
  final ValueNotifier<Float32List?> scope = ValueNotifier(null);
  StreamSubscription<Float32List>? _scopeSub;

  /// Whether the camera accepted the exposure lock (null = not tried yet).
  bool? exposureLockWorked;

  /// Latest camera image, oriented as shown on screen.
  LumaImage? frame;

  /// Raw brightness (0–255) of the pitch and second zones.
  double pitchLevel = 0;
  double secondLevel = 0;

  /// Calibrated control values (0–1).
  double pitchControl = 0;
  double secondControl = 0;

  ZoneCalibration pitchCalibration = const ZoneCalibration();
  ZoneCalibration secondCalibration = const ZoneCalibration();
  bool calibrated = false;

  bool calibrating = false;
  double calibrationProgress = 0;
  String? calibrationMessage;
  CalibrationRecorder? _pitchRecorder;
  CalibrationRecorder? _secondRecorder;

  // Recording and recordings.
  TakeRecorder? _recorder;
  bool get recording => _recorder != null;
  Duration get recordingTime => _recorder?.duration ?? Duration.zero;
  List<Take> takes = const [];

  /// Take being played back, and take whose audio is being rendered.
  String? playingTakeId;
  String? busyTakeId;

  Timer? _audioTimer;
  int _cameraGeneration = 0;
  bool _disposed = false;
  Timer? _saveTimer;

  Future<void> initialize() async {
    final saved = await settingsStore.load();
    if (saved != null) {
      _settings = saved;
      engine.settings = saved;
    }
    try {
      await synth.init();
      synth.setSound(_settings.sound);
      _scopeSub = synth.scope.listen((data) => scope.value = data);
    } catch (e) {
      audioError =
          'No sound output available. Check that speakers or headphones '
          'are connected, then restart the app. ($e)';
    }
    try {
      takes = await takeStore.list();
    } catch (_) {
      takes = const [];
    }
    final backend = cameraBackend;
    if (backend != null) {
      try {
        cameras = await backend.listCameras();
      } catch (e) {
        cameraError = 'Could not list cameras: $e';
      }
      if (cameras.isNotEmpty) {
        final remembered = cameras.where((c) => c.id == _settings.cameraId);
        await selectCamera(
          remembered.isNotEmpty
              ? remembered.first
              : _settings.cameraId == touchPadId
              ? null
              : cameras[backend.preferredCameraIndex(cameras)],
          remember: false,
        );
      } else {
        cameraError ??= 'No camera found. Use the touch pad instead.';
        _setControls(pitch: 0.5, second: 0);
      }
    }
    initialized = true;
    _notify();
  }

  /// Stored as [ThereminSettings.cameraId] when the touch pad was chosen.
  static const touchPadId = 'touch';

  /// Switches to [option], or to the touch pad when null.
  Future<void> selectCamera(
    CameraOption? option, {
    bool keepCalibration = false,
    bool remember = true,
  }) async {
    final generation = ++_cameraGeneration;
    await cameraBackend?.stop();
    camera = option;
    frame = null;
    cameraError = null;
    exposureLockWorked = null;
    if (remember) {
      _settings = _settings.copyWith(cameraId: option?.id ?? touchPadId);
      _scheduleSave();
    }
    if (!keepCalibration) {
      calibrated = false;
      pitchCalibration = const ZoneCalibration();
      secondCalibration = const ZoneCalibration();
    }
    if (option == null) {
      // Touch pad starts silent until touched.
      _setControls(pitch: 0.5, second: 0);
      _notify();
      return;
    }
    _notify();
    try {
      await cameraBackend!.start(
        option,
        onFrame: (image) {
          if (generation == _cameraGeneration) _onFrame(image);
        },
        onError: (message) {
          if (generation != _cameraGeneration) return;
          cameraError = message;
          _notify();
        },
      );
    } catch (e) {
      if (generation != _cameraGeneration) return;
      cameraError = e.toString().replaceFirst('Exception: ', '');
      _notify();
      return;
    }
    if (_settings.lockExposure) {
      // Let auto-exposure adapt to the room first, then hold it.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (generation != _cameraGeneration) return;
      await _applyExposureLock(true);
    }
  }

  Future<void> _applyExposureLock(bool locked) async {
    final backend = cameraBackend;
    if (backend == null || camera == null) return;
    try {
      final ok = await backend.setExposureLocked(locked);
      exposureLockWorked = locked ? ok : null;
    } catch (_) {
      exposureLockWorked = locked ? false : null;
    }
    _notify();
  }

  void _onFrame(LumaImage image) {
    final shown = _settings.mirror ? image.mirrored() : image;
    frame = shown;
    final twoZones = _settings.twoZones;
    pitchLevel = shown.meanIn(twoZones ? pitchZoneTwoZones : pitchZoneSingle);
    secondLevel = twoZones ? shown.meanIn(secondZoneTwoZones) : 0;
    if (calibrating) {
      _pitchRecorder?.add(pitchLevel);
      _secondRecorder?.add(secondLevel);
    }
    _setControls(
      pitch: pitchCalibration.normalize(pitchLevel),
      second: twoZones ? secondCalibration.normalize(secondLevel) : null,
    );
    _notify();
  }

  /// [second] is the calibrated second-zone value, or null in one-zone mode.
  void _setControls({required double pitch, double? second}) {
    pitchControl = pitch;
    secondControl = second ?? 1;
    final toVolume = _settings.secondControl == SecondControl.volume;
    engine.setControls(
      pitchControl: pitch,
      volumeControl: second != null && toVolume ? second : null,
      shapeControl: second != null && !toVolume ? second : null,
    );
  }

  /// Touch pad input: [position] in fractions of the pad. Left→right raises
  /// the pitch, bottom→top raises the second control.
  void touch(Offset position) {
    if (!usingTouch) return;
    final x = position.dx.clamp(0.0, 1.0);
    final up = 1 - position.dy.clamp(0.0, 1.0);
    _touchReleased = false;
    // Undo the camera-oriented inversions so the pad always feels the same.
    _setControls(
      pitch: _settings.invertPitch ? 1 - x : x,
      second: _settings.invertSecond ? 1 - up : up,
    );
    _notify();
  }

  void releaseTouch() {
    if (!usingTouch) return;
    if (_settings.secondControl == SecondControl.volume) {
      _setControls(pitch: pitchControl, second: _settings.invertSecond ? 1 : 0);
    }
    _touchReleased = true;
    _notify();
  }

  /// In shape mode, letting go of the pad silences the sound.
  bool _touchReleased = true;

  Future<void> togglePlaying() => playing ? stopSound() : startSound();

  Future<void> startSound() async {
    if (playing || audioError != null) return;
    await stopTake();
    playing = true;
    var last = clock.now();
    _audioTimer = Timer.periodic(const Duration(milliseconds: 10), (_) {
      final now = clock.now();
      engine.step(now.difference(last).inMicroseconds / 1e6);
      last = now;
      _tick();
    });
    _notify();
  }

  /// Sends the current performance to the synth (and the recorder).
  void _tick() {
    var level = engine.volume;
    if (usingTouch &&
        _settings.secondControl == SecondControl.shape &&
        _touchReleased) {
      level = 0;
    }
    final hz = engine.frequency;
    final timbre = engine.shape;
    synth.update(hz: hz, level: level, timbre: timbre);
    final recorder = _recorder;
    if (recorder != null) {
      recorder.add(hz: hz, level: level, timbre: timbre, spec: _settings.sound);
      if (recorder.duration >= maxRecording) {
        unawaited(stopRecording());
      } else if (recorder.frames % 10 == 0) {
        _notify(); // update the timer display
      }
    }
  }

  Future<void> stopSound() async {
    if (!playing) return;
    if (recording) await stopRecording();
    playing = false;
    _audioTimer?.cancel();
    _audioTimer = null;
    synth.update(hz: engine.frequency, level: 0, timbre: engine.shape);
    _notify();
  }

  // --- Recording -----------------------------------------------------------

  Future<void> toggleRecording() =>
      recording ? stopRecording() : startRecording();

  Future<void> startRecording() async {
    if (recording || audioError != null) return;
    if (!playing) await startSound();
    _recorder = TakeRecorder(_settings.sound);
    _notify();
  }

  Future<void> stopRecording() async {
    final recorder = _recorder;
    _recorder = null;
    if (recorder == null) return;
    _notify();
    if (recorder.frames < controlRate ~/ 2) {
      toast.value = 'Recording too short - not saved.';
      return;
    }
    final now = clock.now();
    final take = recorder.finish(
      id: 'take-${now.millisecondsSinceEpoch}',
      name: _defaultName(now),
      now: now,
    );
    await takeStore.save(take);
    takes = [take, ...takes];
    toast.value = 'Saved "${take.name}"';
    _notify();
  }

  String _defaultName(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'Take ${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}.${two(t.minute)}.${two(t.second)}';
  }

  Future<void> playTake(Take take) async {
    await stopTake();
    if (playing) await stopSound();
    busyTakeId = take.id;
    _notify();
    try {
      final wav = await renderer(take);
      if (_disposed || busyTakeId != take.id) return;
      busyTakeId = null;
      playingTakeId = take.id;
      _notify();
      await synth.playClip(wav);
    } catch (e) {
      toast.value = 'Could not play the recording: $e';
    } finally {
      if (busyTakeId == take.id) busyTakeId = null;
      if (playingTakeId == take.id) playingTakeId = null;
      _notify();
    }
  }

  Future<void> stopTake() async {
    if (playingTakeId == null && busyTakeId == null) return;
    busyTakeId = null;
    playingTakeId = null;
    await synth.stopClip();
    _notify();
  }

  Future<void> exportTake(Take take) async {
    final exporter = this.exporter;
    if (exporter == null) return;
    busyTakeId = take.id;
    _notify();
    try {
      final wav = await renderer(take);
      final safeName = take.name.replaceAll(RegExp(r'[^\w\- .]'), '_');
      final message = await exporter.exportWav('$safeName.wav', wav);
      if (message != null) toast.value = message;
    } catch (e) {
      toast.value = 'Export failed: $e';
    } finally {
      busyTakeId = null;
      _notify();
    }
  }

  Future<void> renameTake(Take take, String name) => _replaceTake(
    take.copyWith(name: name.trim().isEmpty ? take.name : name.trim()),
  );

  /// Changes the chip / sound / effects a take is rendered with.
  Future<void> revoiceTake(Take take, SoundSpec sound) =>
      _replaceTake(take.copyWith(sound: sound));

  Future<void> _replaceTake(Take updated) async {
    await takeStore.save(updated);
    takes = [for (final t in takes) t.id == updated.id ? updated : t];
    _notify();
  }

  Future<void> deleteTake(Take take) async {
    if (playingTakeId == take.id) await stopTake();
    await takeStore.delete(take.id);
    takes = takes.where((t) => t.id != take.id).toList();
    _notify();
  }

  // --- Settings ------------------------------------------------------------

  void updateSettings(ThereminSettings next) {
    final previous = _settings;
    _settings = next;
    engine.settings = next;
    if (next.sound != previous.sound) synth.setSound(next.sound);
    if (next.lockExposure != previous.lockExposure) {
      unawaited(_applyExposureLock(next.lockExposure));
    }
    if (next.twoZones != previous.twoZones || next.mirror != previous.mirror) {
      // Zones now see different light; the old calibration no longer fits.
      calibrated = false;
      pitchCalibration = const ZoneCalibration();
      secondCalibration = const ZoneCalibration();
    }
    // Re-evaluate the current input with the new settings.
    _setControls(
      pitch: pitchControl,
      second: next.twoZones || usingTouch ? secondControl : null,
    );
    _scheduleSave();
    _notify();
  }

  void updateSound(SoundSpec sound) =>
      updateSettings(_settings.copyWith(sound: sound));

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(settingsStore.save(_settings));
    });
  }

  /// Records the light range for a few seconds while the player sweeps
  /// their hand(s) from fully covering the camera to fully away.
  Future<void> calibrate({
    Duration duration = const Duration(seconds: 4),
  }) async {
    if (calibrating || usingTouch || frame == null) return;
    calibrating = true;
    calibrationMessage = null;
    calibrationProgress = 0;
    _pitchRecorder = CalibrationRecorder();
    _secondRecorder = CalibrationRecorder();
    _notify();

    final start = clock.now();
    while (true) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (_disposed) return;
      final elapsed = clock.now().difference(start);
      if (elapsed >= duration) break;
      calibrationProgress = elapsed.inMilliseconds / duration.inMilliseconds;
      _notify();
    }

    calibrating = false;
    final pitch = _pitchRecorder!.result();
    final second = _secondRecorder!.result();
    _pitchRecorder = null;
    _secondRecorder = null;
    if (pitch == null || (_settings.twoZones && second == null)) {
      calibrationMessage =
          'The light barely changed. Make sure light reaches the camera, '
          'then sweep your hand from covering it to fully away.';
    } else {
      pitchCalibration = pitch;
      if (second != null) secondCalibration = second;
      calibrated = true;
      calibrationMessage = 'Calibrated.';
    }
    _notify();
  }

  /// Releases the camera and silences audio (e.g. app sent to background).
  Future<void> pause() async {
    await stopSound();
    await stopTake();
    _cameraGeneration++;
    await cameraBackend?.stop();
  }

  /// Re-opens the camera after [pause].
  Future<void> resume() async {
    if (camera != null) {
      await selectCamera(camera, keepCalibration: true, remember: false);
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _audioTimer?.cancel();
    _saveTimer?.cancel();
    unawaited(settingsStore.save(_settings));
    unawaited(_scopeSub?.cancel());
    _cameraGeneration++;
    unawaited(cameraBackend?.stop());
    unawaited(synth.dispose());
    toast.dispose();
    scope.dispose();
    super.dispose();
  }
}
