import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_recorder/flutter_recorder.dart';

import 'wav.dart';

/// Microphone sound processing choices (Android; others ignore it).
enum MicSource {
  unprocessed('Raw (no phone processing)', AndroidInputPreset.unprocessed),
  generic('Phone default', AndroidInputPreset.generic),
  camcorder('Camcorder', AndroidInputPreset.camcorder),
  voice('Voice (noise reduction)', AndroidInputPreset.voiceRecognition);

  const MicSource(this.label, this.android);
  final String label;
  final AndroidInputPreset android;

  static MicSource byName(String? n) =>
      values.firstWhere((m) => m.name == n, orElse: () => unprocessed);
}

/// Running peak/level meter for incoming float samples (pure; tested).
class PeakTracker {
  PeakTracker(this.framesPerPeak);

  final int framesPerPeak;
  final peaks = BytesBuilderF32();
  double _bucket = 0;
  int _inBucket = 0;
  int frames = 0;

  /// Peak of the last chunk, 0..1.
  double level = 0;

  /// Whether the signal hit full scale since the last [resetClip].
  bool clipped = false;

  void add(Float32List samples) {
    var chunkPeak = 0.0;
    for (final s in samples) {
      final v = s.abs();
      if (v > chunkPeak) chunkPeak = v;
      if (v > _bucket) _bucket = v;
      if (++_inBucket == framesPerPeak) {
        peaks.addOne(_bucket);
        _bucket = 0;
        _inBucket = 0;
      }
    }
    frames += samples.length;
    level = chunkPeak;
    if (chunkPeak >= 0.999) clipped = true;
  }

  void resetClip() => clipped = false;
}

enum MicState { idle, starting, recording, paused, stopping }

/// Records the microphone to a 16-bit mono WAV file, streaming to disk.
class MicRecorder extends ChangeNotifier {
  MicRecorder({this.peaksPerSecond = 100});

  final int peaksPerSecond;
  static const _channel = MethodChannel('audio_kit');

  MicState state = MicState.idle;
  String? error;
  PeakTracker? _tracker;
  WavFileWriter? _writer;
  StreamSubscription<AudioDataContainer>? _sub;
  Future<void> _writes = Future.value();
  int _sampleRate = 48000;
  final markers = <double>[];
  final _notifyWatch = Stopwatch();

  /// Peaks of everything recorded so far (one per 1/[peaksPerSecond] s).
  Float32List get peaks => _tracker?.peaks.view ?? Float32List(0);

  /// Last input peak, 0..1.
  double get level => _tracker?.level ?? 0;
  bool get clipped => _tracker?.clipped ?? false;
  void resetClip() => _tracker?.resetClip();

  double get seconds => (_tracker?.frames ?? 0) / _sampleRate;
  int get sampleRate => _sampleRate;

  /// Android asks the user; other platforms report true (Windows can still
  /// block the mic in its privacy settings, which shows up as an error).
  static Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return true;
    return await _channel.invokeMethod<bool>('requestMic') ?? false;
  }

  Future<bool> start(
    File file, {
    int sampleRate = 48000,
    MicSource source = MicSource.unprocessed,
  }) async {
    if (state != MicState.idle) return false;
    error = null;
    markers.clear();
    state = MicState.starting;
    notifyListeners();
    try {
      if (!await requestPermission()) {
        throw Exception('Microphone permission was not given.');
      }
      _sampleRate = sampleRate;
      _tracker = PeakTracker(math.max(1, sampleRate ~/ peaksPerSecond));
      _writer = await WavFileWriter.create(
        file,
        WavFormat(sampleRate: sampleRate),
      );
      _writes = Future.value();
      final rec = Recorder.instance;
      await rec.init(
        format: PCMFormat.f32le,
        sampleRate: sampleRate,
        channels: RecorderChannels.mono,
        androidInputPreset: source.android,
      );
      _sub = rec.uint8ListStream.listen(_onData);
      rec.start();
      rec.startStreamingData();
      state = MicState.recording;
      _notifyWatch.start();
      notifyListeners();
      return true;
    } catch (e) {
      error = Platform.isWindows
          ? '$e\nIf the microphone is blocked, allow it in Windows Settings > '
                'Privacy & security > Microphone.'
          : '$e';
      await _teardown();
      await _writer?.close();
      _writer = null;
      state = MicState.idle;
      notifyListeners();
      return false;
    }
  }

  void _onData(AudioDataContainer data) {
    if (state != MicState.recording) return;
    // The plugin reuses its buffer: copy before using it later.
    final raw = Uint8List.fromList(data.rawData);
    final samples = Float32List.view(raw.buffer, 0, raw.length ~/ 4);
    _tracker!.add(samples);
    final pcm = floatToPcm16(samples);
    final writer = _writer!;
    _writes = _writes.then((_) => writer.add(pcm));
    if (_notifyWatch.elapsedMilliseconds >= 33) {
      _notifyWatch.reset();
      notifyListeners();
    }
  }

  void pause() {
    if (state != MicState.recording) return;
    state = MicState.paused;
    notifyListeners();
  }

  void resume() {
    if (state != MicState.paused) return;
    state = MicState.recording;
    notifyListeners();
  }

  /// Drops a marker at the current time.
  void addMarker() {
    if (state == MicState.recording || state == MicState.paused) {
      markers.add(seconds);
      notifyListeners();
    }
  }

  Future<void> _teardown() async {
    await _sub?.cancel();
    _sub = null;
    final rec = Recorder.instance;
    try {
      if (rec.isDeviceInitialized()) {
        rec.stopStreamingData();
        rec.stop();
        rec.deinit();
      }
    } catch (_) {}
  }

  /// Stops and finishes the file. Returns its info (null if not recording).
  Future<WavInfo?> stop() async {
    final writer = _writer;
    if (writer == null ||
        (state != MicState.recording && state != MicState.paused)) {
      return null;
    }
    state = MicState.stopping;
    notifyListeners();
    await _teardown();
    await _writes;
    final info = await writer.close();
    _writer = null;
    state = MicState.idle;
    _notifyWatch
      ..stop()
      ..reset();
    notifyListeners();
    return info;
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }
}
