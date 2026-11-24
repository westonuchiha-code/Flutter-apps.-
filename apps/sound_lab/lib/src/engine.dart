import 'dart:math' as math;
import 'dart:typed_data';

import 'package:chip_synth/chip_synth.dart';
import 'package:fx_kit/fx_kit.dart';

const labRate = 48000;

/// Samples sent to the UI for the scope (mono).
const scopeSize = 1024;

/// A sample played chromatically: [root] is the note at original pitch.
class SamplePlayer {
  SamplePlayer(this.data, this.root);
  final Float32List data;
  final int root;
  final _pos = List<double>.filled(maxVoices, -1);
  final _rate = List<double>.filled(maxVoices, 1);
  final _env = List<double>.filled(maxVoices, 0);
  final _down = List<bool>.filled(maxVoices, false);

  static double _hz(int note) => 440 * math.pow(2, (note - 69) / 12).toDouble();

  void setTouch(int i, Touch t) {
    if (t.down && !_down[i]) {
      _pos[i] = 0;
      _env[i] = 0;
    }
    _down[i] = t.down;
    _rate[i] = t.hz / _hz(root);
  }

  void render(Float32List out, int frames, double attack, double release) {
    final up = 1 - math.exp(-1 / (math.max(0.001, attack) * labRate * 0.3));
    final down = math.exp(-1 / (math.max(0.005, release) * labRate * 0.25));
    for (var v = 0; v < maxVoices; v++) {
      if (_pos[v] < 0) continue;
      for (var f = 0; f < frames; f++) {
        final p = _pos[v];
        final i0 = p.floor();
        if (i0 >= data.length - 1) {
          _pos[v] = -1;
          break;
        }
        _env[v] = _down[v] ? _env[v] + (1 - _env[v]) * up : _env[v] * down;
        if (!_down[v] && _env[v] < 1e-4) {
          _pos[v] = -1;
          break;
        }
        // Short fade near the end of the sample (no click).
        final tail = math.min(1.0, (data.length - 1 - p) / 64);
        final s =
            (data[i0] + (data[i0 + 1] - data[i0]) * (p - i0)) *
            _env[v] *
            tail *
            0.7;
        out[f * 2] += s;
        out[f * 2 + 1] += s;
        _pos[v] = p + _rate[v];
      }
    }
  }
}

/// Everything that makes the sound: source → effects → limiter.
/// Lives in the audio isolate (and is also used to render files).
class LabEngine {
  LabEngine({this.sampleRate = labRate})
    : synth = PolySynth(sampleRate.toDouble()),
      chain = FxChain(sampleRate.toDouble());

  final int sampleRate;
  final PolySynth synth;
  final FxChain chain;
  SamplePlayer? sampler;
  bool useSample = false;
  PolySpec _spec = const PolySpec();
  List<EffectSpec>? _fx;

  final _scope = Float32List(scopeSize);
  int _scopePos = 0;
  int _sinceEmit = 0;

  void configure(PolySpec spec, List<EffectSpec> fx) {
    if (!identical(spec, _spec) && spec != _spec) {
      // Echo/reverb live in the effect chain here, not in the synth.
      synth.configure(spec.copyWith(delayMix: 0, reverbMix: 0));
      _spec = spec;
    }
    if (!identical(fx, _fx)) {
      chain.configure(fx);
      _fx = fx;
    }
  }

  void setTouches(List<Touch> touches) {
    for (var i = 0; i < maxVoices && i < touches.length; i++) {
      if (useSample) {
        sampler?.setTouch(i, touches[i]);
        synth.setTouch(i, const Touch());
      } else {
        synth.setTouch(i, touches[i]);
      }
    }
  }

  void render(Float32List out, int frames, [void Function(Object?)? emit]) {
    if (useSample) {
      out.fillRange(0, frames * 2, 0);
      sampler?.render(out, frames, _spec.attack, _spec.release);
    } else {
      synth.render(out, frames);
    }
    chain.process(out, frames);
    for (var i = 0; i < frames * 2; i++) {
      final x = out[i];
      out[i] = x.abs() < 0.8
          ? x
          : x.sign * (0.8 + 0.2 * _tanh((x.abs() - 0.8) / 0.2));
    }
    if (emit != null) {
      for (var f = 0; f < frames; f++) {
        _scope[_scopePos] = (out[f * 2] + out[f * 2 + 1]) * 0.5;
        _scopePos = (_scopePos + 1) % scopeSize;
      }
      _sinceEmit += frames;
      if (_sinceEmit >= sampleRate ~/ 25) {
        _sinceEmit = 0;
        final snap = Float32List(scopeSize);
        for (var i = 0; i < scopeSize; i++) {
          snap[i] = _scope[(_scopePos + i) % scopeSize];
        }
        emit(snap);
      }
    }
  }

  static double _tanh(double x) {
    final e = math.exp(2 * x);
    return (e - 1) / (e + 1);
  }
}

/// What the offline renderer needs.
class LabSnapshot {
  const LabSnapshot({
    required this.spec,
    required this.fx,
    required this.table,
    required this.sample,
    required this.sampleRoot,
    required this.useSample,
  });

  final PolySpec spec;
  final List<EffectSpec> fx;
  final Wavetable? table;
  final Float32List? sample;
  final int sampleRoot;
  final bool useSample;

  LabEngine engine() {
    final e = LabEngine()
      ..useSample = useSample
      ..configure(spec, fx);
    e.synth.wavetable = table;
    if (sample != null) e.sampler = SamplePlayer(sample!, sampleRoot);
    return e;
  }
}

/// Renders a note held for [hold] seconds plus [tail] seconds of release
/// and effect tail. Returns interleaved stereo.
Float32List renderNote(
  LabSnapshot s,
  int note, {
  double hold = 1.5,
  double tail = 1.5,
}) {
  final e = s.engine();
  final hz = 440 * math.pow(2, (note - 69) / 12).toDouble();
  final total = ((hold + tail) * labRate).round();
  final holdFrames = (hold * labRate).round();
  final out = Float32List(total * 2);
  final touches = List<Touch>.filled(maxVoices, const Touch());
  touches[0] = Touch(down: true, hz: hz, y: 0.8);
  e.setTouches(touches);
  const block = 512;
  final tmp = Float32List(block * 2);
  for (var at = 0; at < total; at += block) {
    if (at >= holdFrames && touches[0].down) {
      touches[0] = Touch(hz: hz, y: 0.8);
      e.setTouches(touches);
    }
    final n = math.min(block, total - at);
    e.render(tmp, n);
    out.setRange(at * 2, (at + n) * 2, tmp);
  }
  return out;
}

/// Runs a whole sample through the effects (plus [tail] seconds).
Float32List processSample(LabSnapshot s, {double tail = 2}) {
  final data = s.sample!;
  final e = LabEngine()..configure(s.spec, s.fx);
  final total = data.length + (tail * labRate).round();
  final out = Float32List(total * 2);
  const block = 512;
  final tmp = Float32List(block * 2);
  for (var at = 0; at < total; at += block) {
    final n = math.min(block, total - at);
    for (var f = 0; f < n; f++) {
      final i = at + f;
      final v = i < data.length ? data[i] : 0.0;
      tmp[f * 2] = v;
      tmp[f * 2 + 1] = v;
    }
    e.chain.process(tmp, n);
    out.setRange(at * 2, (at + n) * 2, tmp);
  }
  return out;
}
