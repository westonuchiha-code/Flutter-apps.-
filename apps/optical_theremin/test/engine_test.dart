import 'package:flutter_test/flutter_test.dart';
import 'package:optical_theremin/src/core/calibration.dart';
import 'package:optical_theremin/src/core/music.dart';
import 'package:optical_theremin/src/core/settings.dart';
import 'package:optical_theremin/src/core/theremin_engine.dart';

void main() {
  group('ZoneCalibration', () {
    test('normalizes and clamps', () {
      const cal = ZoneCalibration(dark: 20, bright: 120);
      expect(cal.normalize(20), 0);
      expect(cal.normalize(70), 0.5);
      expect(cal.normalize(500), 1);
      expect(cal.normalize(0), 0);
    });
  });

  group('CalibrationRecorder', () {
    test('records range with margins', () {
      final rec = CalibrationRecorder()
        ..add(100)
        ..add(20)
        ..add(220);
      final cal = rec.result()!;
      expect(cal.dark, closeTo(30, 1e-9));
      expect(cal.bright, closeTo(210, 1e-9));
    });

    test('rejects a tiny light change', () {
      final rec = CalibrationRecorder()
        ..add(100)
        ..add(105);
      expect(rec.result(), isNull);
      expect(CalibrationRecorder().result(), isNull);
    });
  });

  group('ThereminEngine', () {
    const base = ThereminSettings(
      lowNote: 48,
      highNote: 72,
      invertPitch: false,
      glideMs: 0,
      masterVolume: 1,
    );

    test('maps control to the note range', () {
      final engine = ThereminEngine(base);
      engine.setControls(pitchControl: 0);
      engine.step(0.01);
      expect(engine.midi, 48);
      engine.setControls(pitchControl: 1);
      engine.step(0.01);
      expect(engine.midi, 72);
      engine.setControls(pitchControl: 0.5);
      engine.step(0.01);
      expect(engine.midi, 60);
      expect(engine.frequency, closeTo(midiToHz(60), 1e-9));
    });

    test('inverted pitch: darker is higher', () {
      final engine = ThereminEngine(base.copyWith(invertPitch: true));
      engine.setControls(pitchControl: 0);
      engine.step(0.01);
      expect(engine.midi, 72);
    });

    test('snaps to the scale', () {
      final engine = ThereminEngine(base.copyWith(scale: ScaleType.major));
      engine.setControls(pitchControl: 13.2 / 24); // MIDI 61.2 -> D (62)
      expect(engine.targetMidi, 62);
    });

    test('glide approaches the target smoothly', () {
      final engine = ThereminEngine(base.copyWith(glideMs: 100));
      engine.setControls(pitchControl: 0); // first call jumps
      expect(engine.midi, 48);
      engine.setControls(pitchControl: 1);
      engine.step(0.1); // one time constant -> ~63%
      expect(engine.midi, closeTo(48 + 24 * 0.632, 0.1));
      for (var i = 0; i < 100; i++) {
        engine.step(0.01);
      }
      expect(engine.midi, closeTo(72, 0.01));
    });

    test('volume control, curve and silence gate', () {
      final engine = ThereminEngine(base.copyWith(masterVolume: 0.5));
      engine.setControls(pitchControl: 0.5, volumeControl: 1);
      for (var i = 0; i < 50; i++) {
        engine.step(0.01);
      }
      expect(engine.volume, closeTo(0.5, 1e-3));

      engine.setControls(pitchControl: 0.5, volumeControl: 0.5);
      for (var i = 0; i < 50; i++) {
        engine.step(0.01);
      }
      expect(engine.volume, closeTo(0.125, 1e-3)); // 0.5² × 0.5

      engine.setControls(pitchControl: 0.5, volumeControl: 0.02);
      for (var i = 0; i < 50; i++) {
        engine.step(0.01);
      }
      expect(engine.volume, closeTo(0, 1e-3));
    });

    test('without a volume control the master volume is used', () {
      final engine = ThereminEngine(base.copyWith(masterVolume: 0.7));
      engine.setControls(pitchControl: 0.5);
      for (var i = 0; i < 50; i++) {
        engine.step(0.01);
      }
      expect(engine.volume, closeTo(0.7, 1e-3));
    });
  });
}
