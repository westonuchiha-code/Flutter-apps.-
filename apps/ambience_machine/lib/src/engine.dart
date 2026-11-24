import 'dart:math' as math;
import 'dart:typed_data';

import 'package:chip_synth/chip_synth.dart';
import 'package:fx_kit/fx_kit.dart';

import 'scene.dart';

const ambRate = 48000;

/// Control-rate block: drift, gains and notes update this often.
const _block = 64;

// ---- Commands ----

sealed class AmbCommand {
  const AmbCommand();
}

/// Mono samples (at [ambRate]) for layers whose sampleKey is [key].
class SetSample extends AmbCommand {
  const SetSample(this.key, this.data);
  final String key;
  final Float32List data;
}

/// Shows [scene]. Same id: edits it in place. New id: crossfades over [fade]s.
class SetScene extends AmbCommand {
  const SetScene(this.scene, {this.fade = 6});
  final SceneSpec scene;
  final double fade;
}

class SetPlaying extends AmbCommand {
  const SetPlaying(this.playing, {this.fade = 2});
  final bool playing;
  final double fade;
}

class SetMaster extends AmbCommand {
  const SetMaster(this.gain);
  final double gain;
}

/// Stops after [seconds] (fading out over the last minute); null cancels.
class SetSleep extends AmbCommand {
  const SetSleep(this.seconds);
  final double? seconds;
}

// ---- Events ----

/// Current loudness of each layer (by id), about 10 times a second.
class LevelsEvent {
  const LevelsEvent(this.levels, this.sleepLeft);
  final Map<int, double> levels;

  /// Seconds until the sleep timer stops playback (null = no timer).
  final double? sleepLeft;
}

/// Playback stopped by itself (sleep timer).
class StoppedEvent {
  const StoppedEvent();
}

// ---- Building blocks ----

/// A smooth random wander in -1..1 (new target every [period] seconds,
/// eased in between).
class Drift {
  Drift(int seed) : _r = math.Random(seed) {
    _to = _next();
  }

  final math.Random _r;
  double _from = 0, _to = 0, _t = 0;
  double value = 0;

  double _next() => _r.nextDouble() * 2 - 1;

  void advance(double seconds, double period) {
    _t += seconds / math.max(0.05, period);
    while (_t >= 1) {
      _t -= 1;
      _from = _to;
      _to = _next();
    }
    final s = 0.5 - 0.5 * math.cos(math.pi * _t);
    value = _from + (_to - _from) * s;
  }
}

abstract class _Source {
  /// Adds [frames] of stereo sound to [out] (already zeroed).
  void render(Float32List out, int frames, double pitchRatio);
}

/// Loops a sample forever with a crossfade at the seam.
class SampleLoop extends _Source {
  SampleLoop(this.data, this.pitch)
    : xf = math
          .min(data.length ~/ 4, (1.5 * ambRate).round())
          .clamp(1, 1 << 30);

  final Float32List data;
  final double pitch;

  /// Crossfade length; the loop is `data.length - xf` long.
  final int xf;
  double pos = 0;

  int get loopLength => math.max(1, data.length - xf);

  double _at(double p) {
    final i0 = p.floor();
    final a = data[i0.clamp(0, data.length - 1)];
    final b = data[(i0 + 1).clamp(0, data.length - 1)];
    return a + (b - a) * (p - i0);
  }

  /// Seamless loop: the start is blended with the tail that follows the end.
  double valueAt(double p) {
    if (p < xf) {
      final t = p / xf;
      return _at(p) * math.sqrt(t) + _at(p + loopLength) * math.sqrt(1 - t);
    }
    return _at(p);
  }

  @override
  void render(Float32List out, int frames, double pitchRatio) {
    if (data.length < 4) return;
    final rate = math.pow(2, pitch / 12) * pitchRatio;
    final len = loopLength;
    for (var f = 0; f < frames; f++) {
      final s = valueAt(pos) * 0.8;
      out[f * 2] += s;
      out[f * 2 + 1] += s;
      pos += rate;
      if (pos >= len) pos -= len;
    }
  }
}

/// Plays slow random notes from a scale on a synth sound.
class NoteCloud extends _Source {
  NoteCloud(this.layer, int seed) : _r = math.Random(seed) {
    final preset = layer.sound.isEmpty ? null : _tryPreset(layer.sound);
    final spec = preset == null || preset.synth.isEmpty
        ? const PolySpec(
            osc1: Osc.triangle,
            osc2Mix: 0.2,
            cutoff: 0.5,
            attack: 1.2,
            release: 2.5,
          )
        : PolySpec.fromJson(preset.synth);
    final engine = preset?.source == SourceKind.chip
        ? EngineKind.chip
        : EngineKind.analog;
    synth.configure(spec.copyWith(engine: engine, delayMix: 0, reverbMix: 0));
    if (preset != null &&
        preset.source == SourceKind.wavetable &&
        preset.waves.isNotEmpty) {
      synth.wavetable = Wavetable.fromCycles(preset.waves);
    }
    if (preset != null && preset.fx.isNotEmpty) {
      fx = FxChain(ambRate.toDouble())..configure(preset.fx);
    }
    _wait = _r.nextDouble() * 2 * ambRate;
  }

  static SoundPreset? _tryPreset(Map<String, Object?> j) {
    try {
      return SoundPreset.fromJson(j);
    } catch (_) {
      return null;
    }
  }

  LayerSpec layer;
  final math.Random _r;
  final synth = PolySynth(ambRate.toDouble());
  FxChain? fx;
  double _wait = 0;
  final _note = List<int>.filled(maxVoices, -1);
  final _offIn = List<double>.filled(maxVoices, 0);
  final _age = List<int>.filled(maxVoices, 0);
  int _clock = 0;

  /// Notes started so far.
  int notesStarted = 0;
  final _tmp = Float32List(_block * 2);

  static double _hz(int n) => 440 * math.pow(2, (n - 69) / 12).toDouble();

  int _pickNote() {
    final steps = layer.scale.steps;
    final degree = _r.nextInt(steps.length * layer.octaves);
    return layer.root +
        (degree ~/ steps.length) * 12 +
        steps[degree % steps.length];
  }

  @override
  void render(Float32List out, int frames, double pitchRatio) {
    _wait -= frames;
    if (_wait <= 0 && layer.density > 0) {
      var slot = _note.indexOf(-1);
      if (slot < 0) {
        // Steal the oldest note.
        slot = 0;
        for (var i = 1; i < maxVoices; i++) {
          if (_age[i] < _age[slot]) slot = i;
        }
      }
      _note[slot] = _pickNote();
      notesStarted++;
      _age[slot] = ++_clock;
      _offIn[slot] = layer.noteLength * (0.5 + _r.nextDouble()) * ambRate;
      // Exponential gaps: notes come irregularly, like rain on a roof.
      final mean = 60 / layer.density * ambRate;
      _wait = -math.log(1 - _r.nextDouble() * 0.999) * mean;
    }
    for (var i = 0; i < maxVoices; i++) {
      final n = _note[i];
      if (n < 0) {
        synth.setTouch(i, const Touch());
        continue;
      }
      _offIn[i] -= frames;
      final down = _offIn[i] > 0;
      synth.setTouch(i, Touch(down: down, hz: _hz(n) * pitchRatio, y: 0.7));
      if (!down) _note[i] = -1;
    }
    final tmp = Float32List.sublistView(_tmp, 0, frames * 2);
    synth.render(tmp, frames);
    fx?.process(tmp, frames);
    for (var i = 0; i < frames * 2; i++) {
      out[i] += tmp[i];
    }
  }
}

/// Generated textures (no samples needed).
class NoiseTexture extends _Source {
  NoiseTexture(this.type, int seed)
    : _r = math.Random(seed),
      _motion = Drift(seed + 7),
      _gust = Drift(seed + 13);

  final NoiseType type;
  final math.Random _r;
  final Drift _motion, _gust;
  final _lp = [0.0, 0.0],
      _lp2 = [0.0, 0.0],
      _hp = [0.0, 0.0],
      _brown = [0.0, 0.0];
  final _ic1 = [0.0, 0.0], _ic2 = [0.0, 0.0];
  double _swell = 0;
  // Rain drops: up to 8 decaying pings.
  final _dropPhase = Float64List(8),
      _dropInc = Float64List(8),
      _dropAmp = Float64List(8);
  final _dropDecay = Float64List(8), _dropPan = Float64List(8);

  double _white() => _r.nextDouble() * 2 - 1;

  @override
  void render(Float32List out, int frames, double pitchRatio) {
    final secs = frames / ambRate;
    switch (type) {
      case NoiseType.wind:
        _motion.advance(secs, 4);
        _gust.advance(secs, 7);
        final fc = (300 + 500 * (_motion.value + 1)) * pitchRatio;
        final g = math.tan(math.pi * fc / ambRate);
        const k = 1.2;
        final a1 = 1 / (1 + g * (g + k));
        final level = 0.35 + 0.35 * (_gust.value + 1);
        for (var f = 0; f < frames; f++) {
          for (var c = 0; c < 2; c++) {
            final v3 = _white() - _ic2[c];
            final v1 = a1 * _ic1[c] + g * a1 * v3;
            final v2 = _ic2[c] + g * v1;
            _ic1[c] = 2 * v1 - _ic1[c];
            _ic2[c] = 2 * v2 - _ic2[c];
            out[f * 2 + c] += v1 * level;
          }
        }
      case NoiseType.rain:
        for (var f = 0; f < frames; f++) {
          // New drop now and then (~35 per second).
          if (_r.nextDouble() < 35 / ambRate) {
            var d = 0;
            for (var i = 1; i < 8; i++) {
              if (_dropAmp[i] < _dropAmp[d]) d = i;
            }
            _dropPhase[d] = 0;
            _dropInc[d] =
                (1500 + _r.nextDouble() * 3500) * pitchRatio / ambRate;
            _dropAmp[d] = 0.05 + _r.nextDouble() * 0.15;
            _dropDecay[d] = math.exp(
              -1 / ((0.004 + _r.nextDouble() * 0.01) * ambRate),
            );
            _dropPan[d] = _r.nextDouble();
          }
          var dl = 0.0, dr = 0.0;
          for (var i = 0; i < 8; i++) {
            if (_dropAmp[i] < 1e-4) continue;
            final s = math.sin(2 * math.pi * _dropPhase[i]) * _dropAmp[i];
            _dropPhase[i] += _dropInc[i];
            _dropAmp[i] *= _dropDecay[i];
            dl += s * (1 - _dropPan[i]);
            dr += s * _dropPan[i];
          }
          for (var c = 0; c < 2; c++) {
            final w = _white();
            _hp[c] += (w - _hp[c]) * 0.18; // remove lows
            final hiss = (w - _hp[c]) * 0.12;
            out[f * 2 + c] += hiss + (c == 0 ? dl : dr);
          }
        }
      case NoiseType.waves:
        _motion.advance(secs, 10);
        for (var f = 0; f < frames; f++) {
          _swell += (1 / (9 + 3 * _motion.value)) / ambRate;
          if (_swell >= 1) _swell -= 1;
          final env =
              0.12 +
              0.88 * math.pow(0.5 - 0.5 * math.cos(2 * math.pi * _swell), 2);
          final a = 0.02 + 0.12 * env * pitchRatio.clamp(0.5, 2);
          for (var c = 0; c < 2; c++) {
            _lp[c] += (_white() - _lp[c]) * a;
            _lp2[c] += (_lp[c] - _lp2[c]) * a;
            out[f * 2 + c] += _lp2[c] * env * 1.6;
          }
        }
      case NoiseType.rumble:
        for (var f = 0; f < frames; f++) {
          for (var c = 0; c < 2; c++) {
            _brown[c] = _brown[c] * 0.996 + _white() * 0.04;
            _lp[c] += (_brown[c] - _lp[c]) * 0.02 * pitchRatio;
            out[f * 2 + c] += _lp[c] * 1.2;
          }
        }
    }
  }
}

class _Layer {
  _Layer(this.spec, Map<String, Float32List> samples) {
    _build(samples);
  }

  LayerSpec spec;
  _Source? source;
  late final Drift dVol = Drift(spec.id * 31 + 1);
  late final Drift dPan = Drift(spec.id * 31 + 2);
  late final Drift dTone = Drift(spec.id * 31 + 3);
  late final Drift dPitch = Drift(spec.id * 31 + 4);
  double gain = 0;
  bool removing = false;
  double level = 0;
  final _lp = [0.0, 0.0], _lp2 = [0.0, 0.0];

  void _build(Map<String, Float32List> samples) {
    source = switch (spec.kind) {
      LayerKind.sample =>
        samples[spec.sampleKey] == null
            ? null
            : SampleLoop(samples[spec.sampleKey]!, spec.pitch),
      LayerKind.synth => NoteCloud(spec, spec.id),
      LayerKind.noise => NoiseTexture(spec.noise, spec.id),
    };
  }

  /// Applies edits; rebuilds the source only when it really changed.
  void update(LayerSpec s, Map<String, Float32List> samples) {
    final old = spec;
    spec = s;
    final rebuild = switch (s.kind) {
      LayerKind.sample =>
        source == null || s.pitch != old.pitch || s.sampleKey != old.sampleKey,
      LayerKind.synth =>
        !identical(s.sound, old.sound) &&
            s.sound.toString() != old.sound.toString(),
      LayerKind.noise => s.noise != old.noise,
    };
    if (rebuild) {
      _build(samples);
    } else if (source is NoteCloud) {
      (source! as NoteCloud).layer = s;
    }
  }

  void sampleArrived(String key, Map<String, Float32List> samples) {
    if (spec.kind == LayerKind.sample && spec.sampleKey == key) _build(samples);
  }

  /// Adds this layer's block into [mix].
  void render(Float32List mix, Float32List tmp, int frames) {
    final s = spec;
    final secs = frames / ambRate;
    // 0 → a wander every ~90 s; 1 → every ~3 s.
    final period = 90 * math.pow(1 / 30, s.driftSpeed).toDouble();
    dVol.advance(secs, period);
    dPan.advance(secs, period * 1.3);
    dTone.advance(secs, period * 0.8);
    dPitch.advance(secs, period * 1.7);
    final d = s.drift;
    final target = removing || s.muted
        ? 0.0
        : s.volume * s.volume * (1 - d * 0.75 * (0.5 + 0.5 * dVol.value));
    final start = gain;
    if (removing) {
      // Removed layers fade out evenly over one second.
      gain = math.max(0, gain - frames / ambRate);
    } else {
      // ~0.4 s smoothing: no jumps when knobs move or layers come in.
      gain += (target - gain) * (1 - math.exp(-frames / (0.4 * ambRate)));
    }
    final src = source;
    if (src == null || (start < 1e-5 && gain < 1e-5)) {
      level = 0;
      return;
    }
    tmp.fillRange(0, frames * 2, 0);
    src.render(
      tmp,
      frames,
      math.pow(2, d * 0.35 * dPitch.value / 12).toDouble(),
    );
    // Tone: two one-pole low-passes, cutoff 150 Hz .. open, drifting.
    final cutoff =
        (150 * math.pow(130, s.tone) * math.pow(2, d * 1.5 * dTone.value))
            .clamp(60, ambRate * 0.45)
            .toDouble();
    final a = 1 - math.exp(-2 * math.pi * cutoff / ambRate);
    final pan = (s.pan + d * 0.6 * dPan.value).clamp(-1.0, 1.0);
    final angle = (pan + 1) * math.pi / 4;
    final gl = math.cos(angle) * math.sqrt2, gr = math.sin(angle) * math.sqrt2;
    var sum = 0.0;
    for (var f = 0; f < frames; f++) {
      final g = start + (gain - start) * (f + 1) / frames;
      for (var c = 0; c < 2; c++) {
        final i = f * 2 + c;
        _lp[c] += (tmp[i] - _lp[c]) * a;
        _lp2[c] += (_lp[c] - _lp2[c]) * a;
        final v = _lp2[c] * g * (c == 0 ? gl : gr);
        mix[i] += v;
        sum += v * v;
      }
    }
    level = math.sqrt(sum / (frames * 2));
  }
}

class _Scene {
  _Scene(this.spec, Map<String, Float32List> samples, {required this.gain})
    : chain = FxChain(ambRate.toDouble())..configure(spec.fx),
      layers = [for (final l in spec.layers) _Layer(l, samples)];

  SceneSpec spec;
  final FxChain chain;
  final List<_Layer> layers;
  double gain;
  double target = 1;
  double step = 0;

  void update(SceneSpec s, Map<String, Float32List> samples) {
    spec = s;
    chain.configure(s.fx);
    final byId = {for (final l in s.layers) l.id: l};
    for (final l in layers) {
      final next = byId.remove(l.spec.id);
      if (next == null) {
        l.removing = true;
      } else {
        l.update(next, samples);
      }
    }
    for (final l in byId.values) {
      layers.add(_Layer(l, samples));
    }
  }
}

/// Mixes everything. Lives in the audio isolate; also renders exports.
class AmbienceEngine {
  final samples = <String, Float32List>{};
  final _scenes = <_Scene>[];
  bool playing = false;
  double _play = 0, _playTarget = 0, _playStep = 0;
  double master = 0.8;
  double? _sleepLeft; // frames
  int _sinceLevels = 0;
  final _sceneBuf = Float32List(_block * 2);
  final _layerBuf = Float32List(_block * 2);

  void handle(AmbCommand c) {
    switch (c) {
      case SetSample(:final key, :final data):
        samples[key] = data;
        for (final s in _scenes) {
          for (final l in s.layers) {
            l.sampleArrived(key, samples);
          }
        }
      case SetScene(:final scene, :final fade):
        final current = _scenes.where((s) => s.target > 0).lastOrNull;
        if (current != null && current.spec.id == scene.id) {
          current.update(scene, samples);
        } else {
          final frames = math.max(1.0, fade * ambRate);
          for (final s in _scenes) {
            s
              ..target = 0
              ..step = s.gain / frames;
          }
          final fresh = _Scene(scene, samples, gain: current == null ? 1 : 0)
            ..target = 1
            ..step = 1 / frames;
          _scenes.add(fresh);
        }
      case SetPlaying(:final playing, :final fade):
        this.playing = playing;
        _playTarget = playing ? 1 : 0;
        _playStep = 1 / math.max(1, fade * ambRate);
        if (!playing) _sleepLeft = null;
      case SetMaster(:final gain):
        master = gain.clamp(0, 1);
      case SetSleep(:final seconds):
        _sleepLeft = seconds == null ? null : seconds * ambRate;
    }
  }

  static double _towards(double v, double target, double step) =>
      v < target ? math.min(target, v + step) : math.max(target, v - step);

  /// Fills [out] (interleaved stereo).
  void render(Float32List out, int frames, [void Function(Object?)? emit]) {
    out.fillRange(0, frames * 2, 0);
    for (var at = 0; at < frames; at += _block) {
      final n = math.min(_block, frames - at);
      final p0 = _play;
      _play = _towards(_play, _playTarget, _playStep * n);
      var sleepGain = 1.0;
      final left = _sleepLeft;
      if (left != null) {
        _sleepLeft = left - n;
        sleepGain = (left / (60.0 * ambRate)).clamp(0, 1).toDouble();
        if (_sleepLeft! <= 0) {
          _sleepLeft = null;
          playing = false;
          _play = 0;
          _playTarget = 0;
          emit?.call(const StoppedEvent());
        }
      }
      if (p0 <= 0 && _play <= 0) continue;
      for (final s in _scenes) {
        final g0 = s.gain;
        s.gain = _towards(s.gain, s.target, s.step * n);
        _sceneBuf.fillRange(0, n * 2, 0);
        for (final l in s.layers) {
          l.render(_sceneBuf, _layerBuf, n);
        }
        s.chain.process(_sceneBuf, n);
        for (var f = 0; f < n; f++) {
          final t = (f + 1) / n;
          final g =
              (g0 + (s.gain - g0) * t) *
              (p0 + (_play - p0) * t) *
              master *
              sleepGain;
          out[(at + f) * 2] += _sceneBuf[f * 2] * g;
          out[(at + f) * 2 + 1] += _sceneBuf[f * 2 + 1] * g;
        }
      }
      // Drop scenes that finished fading out and layers that were removed.
      _scenes.removeWhere((s) => s.target == 0 && s.gain <= 0);
      for (final s in _scenes) {
        s.layers.removeWhere((l) => l.removing && l.gain <= 0);
      }
    }
    for (var i = 0; i < frames * 2; i++) {
      final x = out[i];
      out[i] = x.abs() < 0.8
          ? x
          : x.sign * (0.8 + 0.2 * _tanh((x.abs() - 0.8) / 0.2));
    }
    _sinceLevels += frames;
    if (emit != null && _sinceLevels >= ambRate ~/ 10) {
      _sinceLevels = 0;
      final current = _scenes.where((s) => s.target > 0).lastOrNull;
      emit(
        LevelsEvent({
          if (current != null)
            for (final l in current.layers) l.spec.id: l.level * _play,
        }, _sleepLeft == null ? null : _sleepLeft! / ambRate),
      );
    }
  }

  static double _tanh(double x) {
    final e = math.exp(2 * x);
    return (e - 1) / (e + 1);
  }
}

/// Renders [seconds] of [scene] (fading in and out) to 16-bit stereo PCM.
Int16List renderAmbience(
  SceneSpec scene,
  Map<String, Float32List> samples,
  double seconds,
) {
  final e = AmbienceEngine();
  samples.forEach((k, v) => e.handle(SetSample(k, v)));
  e
    ..handle(SetScene(scene, fade: 0))
    ..handle(const SetPlaying(true, fade: 3));
  final total = (seconds * ambRate).round();
  final fadeOutAt = total - 3 * ambRate;
  final out = Int16List(total * 2);
  const block = 1024;
  final tmp = Float32List(block * 2);
  for (var at = 0; at < total; at += block) {
    if (at >= fadeOutAt && e.playing) {
      e.handle(const SetPlaying(false, fade: 3));
    }
    final n = math.min(block, total - at);
    e.render(tmp, n);
    for (var i = 0; i < n * 2; i++) {
      out[at * 2 + i] = (tmp[i].clamp(-1.0, 1.0) * 32767).round();
    }
  }
  return out;
}
