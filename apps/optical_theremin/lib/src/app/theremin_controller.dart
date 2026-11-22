import 'dart:async';
import 'dart:ui' show Offset, Rect;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../audio/tone_output.dart';
import '../core/calibration.dart';
import '../core/luma_image.dart';
import '../core/settings.dart';
import '../core/theremin_engine.dart';
import '../input/camera_backend.dart';

/// Image regions that control pitch and volume, in fractions of the image.
const pitchZoneTwoZones = Rect.fromLTRB(0, 0, 0.5, 1);
const volumeZoneTwoZones = Rect.fromLTRB(0.5, 0, 1, 1);
const pitchZoneSingle = Rect.fromLTRB(0, 0, 1, 1);

/// App state: connects the camera (or touch pad), the theremin engine and
/// the audio output.
class ThereminController extends ChangeNotifier {
  ThereminController({required this.cameraBackend, required this.tone});

  final CameraBackend? cameraBackend;
  final ToneOutput tone;

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

  /// Whether the camera accepted the exposure lock (null = not tried yet).
  bool? exposureLockWorked;

  /// Latest camera image, oriented as shown on screen.
  LumaImage? frame;

  /// Raw brightness (0–255) of the pitch and volume zones.
  double pitchLevel = 0;
  double volumeLevel = 0;

  /// Calibrated control values (0–1).
  double pitchControl = 0;
  double volumeControl = 0;

  ZoneCalibration pitchCalibration = const ZoneCalibration();
  ZoneCalibration volumeCalibration = const ZoneCalibration();
  bool calibrated = false;

  bool calibrating = false;
  double calibrationProgress = 0;
  String? calibrationMessage;
  CalibrationRecorder? _pitchRecorder;
  CalibrationRecorder? _volumeRecorder;

  Timer? _audioTimer;
  int _cameraGeneration = 0;
  bool _disposed = false;

  Future<void> initialize() async {
    try {
      await tone.init();
      tone.setWave(_settings.wave);
    } catch (e) {
      audioError =
          'No sound output available. Check that speakers or headphones '
          'are connected, then restart the app. ($e)';
    }
    final backend = cameraBackend;
    if (backend != null) {
      try {
        cameras = await backend.listCameras();
      } catch (e) {
        cameraError = 'Could not list cameras: $e';
      }
      if (cameras.isNotEmpty) {
        await selectCamera(cameras[backend.preferredCameraIndex(cameras)]);
      } else {
        cameraError ??= 'No camera found. Use the touch pad instead.';
      }
    }
    initialized = true;
    _notify();
  }

  /// Switches to [option], or to the touch pad when null.
  Future<void> selectCamera(
    CameraOption? option, {
    bool keepCalibration = false,
  }) async {
    final generation = ++_cameraGeneration;
    await cameraBackend?.stop();
    camera = option;
    frame = null;
    cameraError = null;
    exposureLockWorked = null;
    if (!keepCalibration) {
      calibrated = false;
      pitchCalibration = const ZoneCalibration();
      volumeCalibration = const ZoneCalibration();
    }
    if (option == null) {
      // Touch pad starts silent until touched.
      _setControls(pitch: 0.5, volume: 0);
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
    volumeLevel = twoZones ? shown.meanIn(volumeZoneTwoZones) : 0;
    if (calibrating) {
      _pitchRecorder?.add(pitchLevel);
      _volumeRecorder?.add(volumeLevel);
    }
    _setControls(
      pitch: pitchCalibration.normalize(pitchLevel),
      volume: twoZones ? volumeCalibration.normalize(volumeLevel) : null,
    );
    _notify();
  }

  void _setControls({required double pitch, double? volume}) {
    pitchControl = pitch;
    volumeControl = volume ?? 1;
    engine.setControls(pitchControl: pitch, volumeControl: volume);
  }

  /// Touch pad input: [position] in fractions of the pad. Left→right raises
  /// the pitch, bottom→top raises the volume.
  void touch(Offset position) {
    if (!usingTouch) return;
    final x = position.dx.clamp(0.0, 1.0);
    final loudness = 1 - position.dy.clamp(0.0, 1.0);
    // Undo the camera-oriented inversions so the pad always feels the same.
    _setControls(
      pitch: _settings.invertPitch ? 1 - x : x,
      volume: _settings.invertVolume ? 1 - loudness : loudness,
    );
    _notify();
  }

  void releaseTouch() {
    if (!usingTouch) return;
    _setControls(pitch: pitchControl, volume: _settings.invertVolume ? 1 : 0);
    _notify();
  }

  Future<void> togglePlaying() => playing ? stopSound() : startSound();

  Future<void> startSound() async {
    if (playing || audioError != null) return;
    playing = true;
    await tone.start();
    var last = clock.now();
    _audioTimer = Timer.periodic(const Duration(milliseconds: 10), (_) {
      final now = clock.now();
      engine.step(now.difference(last).inMicroseconds / 1e6);
      last = now;
      tone.update(frequency: engine.frequency, volume: engine.volume);
    });
    _notify();
  }

  Future<void> stopSound() async {
    if (!playing) return;
    playing = false;
    _audioTimer?.cancel();
    _audioTimer = null;
    await tone.stop();
    _notify();
  }

  void updateSettings(ThereminSettings next) {
    final previous = _settings;
    _settings = next;
    engine.settings = next;
    if (next.wave != previous.wave) tone.setWave(next.wave);
    if (next.lockExposure != previous.lockExposure) {
      unawaited(_applyExposureLock(next.lockExposure));
    }
    if (next.twoZones != previous.twoZones || next.mirror != previous.mirror) {
      // Zones now see different light; the old calibration no longer fits.
      calibrated = false;
      pitchCalibration = const ZoneCalibration();
      volumeCalibration = const ZoneCalibration();
    }
    // Re-evaluate the current input with the new settings.
    if (usingTouch) {
      engine.setControls(
        pitchControl: pitchControl,
        volumeControl: volumeControl,
      );
    } else {
      _setControls(
        pitch: pitchControl,
        volume: next.twoZones ? volumeControl : null,
      );
    }
    _notify();
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
    _volumeRecorder = CalibrationRecorder();
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
    final volume = _volumeRecorder!.result();
    _pitchRecorder = null;
    _volumeRecorder = null;
    if (pitch == null || (_settings.twoZones && volume == null)) {
      calibrationMessage =
          'The light barely changed. Make sure light reaches the camera, '
          'then sweep your hand from covering it to fully away.';
    } else {
      pitchCalibration = pitch;
      if (volume != null) volumeCalibration = volume;
      calibrated = true;
      calibrationMessage = 'Calibrated.';
    }
    _notify();
  }

  /// Releases the camera and silences audio (e.g. app sent to background).
  Future<void> pause() async {
    await stopSound();
    _cameraGeneration++;
    await cameraBackend?.stop();
  }

  /// Re-opens the camera after [pause].
  Future<void> resume() async {
    if (camera != null) await selectCamera(camera, keepCalibration: true);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _audioTimer?.cancel();
    _cameraGeneration++;
    unawaited(cameraBackend?.stop());
    unawaited(tone.dispose());
    super.dispose();
  }
}
