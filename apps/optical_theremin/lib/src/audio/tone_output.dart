import 'package:flutter_soloud/flutter_soloud.dart';

import '../core/settings.dart';

/// Continuous tone with live pitch and volume control.
abstract class ToneOutput {
  Future<void> init();
  Future<void> start();
  Future<void> stop();
  void setWave(Wave wave);
  void update({required double frequency, required double volume});
  Future<void> dispose();
}

/// [ToneOutput] backed by the SoLoud audio engine (Android, Windows, Linux).
class SoLoudToneOutput implements ToneOutput {
  final SoLoud _soloud = SoLoud.instance;
  AudioSource? _source;
  SoundHandle? _handle;
  Wave _wave = Wave.sine;

  static WaveForm _toWaveForm(Wave wave) => switch (wave) {
    Wave.sine => WaveForm.sin,
    Wave.triangle => WaveForm.triangle,
    // Band-limited variants sound smoother than the raw saw/square.
    Wave.saw => WaveForm.fSaw,
    Wave.square => WaveForm.fSquare,
  };

  @override
  Future<void> init() async {
    if (!_soloud.isInitialized) {
      // A small buffer keeps the delay between hand and sound short.
      await _soloud.init(bufferSize: 1024);
    }
    _source ??= await _soloud.loadWaveform(_toWaveForm(_wave), false, 1, 0);
  }

  @override
  Future<void> start() async {
    final source = _source;
    if (source == null || _handle != null) return;
    _handle = _soloud.play(source, volume: 0);
  }

  @override
  Future<void> stop() async {
    final handle = _handle;
    _handle = null;
    if (handle == null) return;
    _soloud.fadeVolume(handle, 0, const Duration(milliseconds: 40));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await _soloud.stop(handle);
  }

  @override
  void setWave(Wave wave) {
    _wave = wave;
    final source = _source;
    if (source != null) _soloud.setWaveform(source, _toWaveForm(wave));
  }

  @override
  void update({required double frequency, required double volume}) {
    final source = _source;
    final handle = _handle;
    if (source == null || handle == null) return;
    _soloud.setWaveformFreq(source, frequency);
    _soloud.setVolume(handle, volume);
  }

  @override
  Future<void> dispose() async {
    await stop();
    final source = _source;
    _source = null;
    if (source != null) await _soloud.disposeSource(source);
  }
}
