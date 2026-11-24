import 'dart:math' as math;
import 'dart:typed_data';

import 'params.dart';

const _pct = '%';

/// Every effect the library has.
enum EffectKind {
  filter('Filter', [
    ParamDef(
      'mode',
      'Type',
      0,
      2,
      0,
      step: 1,
      choices: ['Low-pass', 'High-pass', 'Band-pass'],
    ),
    ParamDef('cutoff', 'Cutoff', 20, 20000, 2000, unit: 'Hz', log: true),
    ParamDef('resonance', 'Resonance', 0, 1, 0.2, unit: _pct),
  ]),
  eq('EQ', [
    ParamDef('low', 'Low', -15, 15, 0, unit: 'dB'),
    ParamDef('mid', 'Mid', -15, 15, 0, unit: 'dB'),
    ParamDef(
      'midFreq',
      'Mid frequency',
      200,
      5000,
      1000,
      unit: 'Hz',
      log: true,
    ),
    ParamDef('high', 'High', -15, 15, 0, unit: 'dB'),
  ]),
  drive('Drive', [
    ParamDef('drive', 'Drive', 0, 36, 12, unit: 'dB'),
    ParamDef('tone', 'Tone', 800, 18000, 6000, unit: 'Hz', log: true),
    ParamDef('level', 'Output', -24, 6, -6, unit: 'dB'),
    ParamDef('mix', 'Mix', 0, 1, 1, unit: _pct),
  ]),
  bitcrush('Bitcrush', [
    ParamDef('bits', 'Bits', 1, 16, 8, step: 1),
    ParamDef('downsample', 'Sample-rate divide', 1, 40, 4, step: 1),
    ParamDef('mix', 'Mix', 0, 1, 1, unit: _pct),
  ]),
  compressor('Compressor', [
    ParamDef('threshold', 'Threshold', -60, 0, -18, unit: 'dB'),
    ParamDef('ratio', 'Ratio', 1, 20, 4, log: true),
    ParamDef('attack', 'Attack', 0.1, 100, 5, unit: 'ms', log: true),
    ParamDef('release', 'Release', 10, 1000, 120, unit: 'ms', log: true),
    ParamDef('makeup', 'Makeup', 0, 24, 4, unit: 'dB'),
  ]),
  chorus('Chorus', [
    ParamDef('rate', 'Rate', 0.05, 5, 0.6, unit: 'Hz', log: true),
    ParamDef('depth', 'Depth', 0, 10, 3, unit: 'ms'),
    ParamDef('mix', 'Mix', 0, 1, 0.5, unit: _pct),
  ]),
  phaser('Phaser', [
    ParamDef('rate', 'Rate', 0.05, 5, 0.4, unit: 'Hz', log: true),
    ParamDef('depth', 'Depth', 0, 1, 0.7, unit: _pct),
    ParamDef('feedback', 'Feedback', 0, 0.9, 0.5, unit: _pct),
    ParamDef('mix', 'Mix', 0, 1, 0.5, unit: _pct),
  ]),
  tremolo('Tremolo', [
    ParamDef('rate', 'Rate', 0.1, 20, 5, unit: 'Hz', log: true),
    ParamDef('depth', 'Depth', 0, 1, 0.6, unit: _pct),
    ParamDef('stereo', 'Auto-pan', 0, 1, 0, unit: _pct),
  ]),
  ringmod('Ring mod', [
    ParamDef('freq', 'Frequency', 1, 4000, 220, unit: 'Hz', log: true),
    ParamDef('mix', 'Mix', 0, 1, 0.5, unit: _pct),
  ]),
  echo('Echo', [
    ParamDef('time', 'Time', 10, 2000, 350, unit: 'ms', log: true),
    ParamDef('feedback', 'Repeats', 0, 0.95, 0.4, unit: _pct),
    ParamDef('damp', 'Darken', 0, 1, 0.3, unit: _pct),
    ParamDef('pingpong', 'Ping-pong', 0, 1, 1, step: 1, choices: ['Off', 'On']),
    ParamDef('mix', 'Mix', 0, 1, 0.3, unit: _pct),
  ]),
  reverb('Reverb', [
    ParamDef('size', 'Size', 0, 1, 0.6, unit: _pct),
    ParamDef('damp', 'Damping', 0, 1, 0.4, unit: _pct),
    ParamDef('mix', 'Mix', 0, 1, 0.3, unit: _pct),
  ]);

  const EffectKind(this.label, this.params);
  final String label;
  final List<ParamDef> params;

  ParamDef param(String id) => params.firstWhere((p) => p.id == id);

  static EffectKind? byName(Object? n) {
    for (final k in values) {
      if (k.name == n) return k;
    }
    return null;
  }
}

/// An effect in a chain: its kind, knob values and on/off.
class EffectSpec {
  EffectSpec(this.kind, {Map<String, double>? values, this.on = true, int? id})
    : values = {
        for (final p in kind.params) p.id: p.clamp(values?[p.id] ?? p.def),
      },
      id = id ?? _nextId++;

  static int _nextId = 1;

  /// Identity within a chain (keeps the running effect when reordered).
  final int id;
  final EffectKind kind;
  final Map<String, double> values;
  final bool on;

  double operator [](String p) => values[p] ?? kind.param(p).def;

  EffectSpec withValue(String p, double v) =>
      EffectSpec(kind, values: {...values, p: v}, on: on, id: id);

  EffectSpec withOn(bool v) => EffectSpec(kind, values: values, on: v, id: id);

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'on': on,
    'values': values,
  };

  static EffectSpec? fromJson(Object? j) {
    if (j is! Map) return null;
    final kind = EffectKind.byName(j['kind']);
    if (kind == null) return null;
    final raw = j['values'];
    return EffectSpec(
      kind,
      on: j['on'] != false,
      values: {
        if (raw is Map)
          for (final e in raw.entries)
            if (e.key is String && e.value is num)
              e.key as String: (e.value as num).toDouble(),
      },
    );
  }
}

/// A running effect. Processes interleaved stereo in place.
abstract class Effect {
  Effect(this.sr);
  final double sr;
  late EffectSpec spec;

  void set(EffectSpec s) => spec = s;
  void process(Float32List buf, int frames);

  static Effect create(EffectSpec s, double sr) {
    final e = switch (s.kind) {
      EffectKind.filter => FilterFx(sr),
      EffectKind.eq => EqFx(sr),
      EffectKind.drive => DriveFx(sr),
      EffectKind.bitcrush => BitcrushFx(sr),
      EffectKind.compressor => CompressorFx(sr),
      EffectKind.chorus => ChorusFx(sr),
      EffectKind.phaser => PhaserFx(sr),
      EffectKind.tremolo => TremoloFx(sr),
      EffectKind.ringmod => RingModFx(sr),
      EffectKind.echo => EchoFx(sr),
      EffectKind.reverb => ReverbFx(sr),
    };
    return e..set(s);
  }
}

double _tanh(double x) {
  if (x > 9) return 1;
  if (x < -9) return -1;
  final e = math.exp(2 * x);
  return (e - 1) / (e + 1);
}

/// State-variable filter (topology-preserving), cutoff glides (no zipper).
class FilterFx extends Effect {
  FilterFx(super.sr);
  final _ic1 = [0.0, 0.0], _ic2 = [0.0, 0.0];
  double? _fc;

  @override
  void process(Float32List buf, int frames) {
    final target = spec['cutoff'].clamp(20, sr * 0.45).toDouble();
    final mode = spec['mode'].round();
    final k = 2 - 1.96 * spec['resonance'];
    var fc = _fc ?? target;
    for (var start = 0; start < frames; start += 32) {
      fc += (target - fc) * 0.25;
      final g = math.tan(math.pi * fc / sr);
      final a1 = 1 / (1 + g * (g + k));
      final end = math.min(frames, start + 32);
      for (var c = 0; c < 2; c++) {
        var ic1 = _ic1[c], ic2 = _ic2[c];
        for (var f = start; f < end; f++) {
          final i = f * 2 + c;
          final x = buf[i];
          final v3 = x - ic2;
          final v1 = a1 * ic1 + g * a1 * v3;
          final v2 = ic2 + g * v1;
          ic1 = 2 * v1 - ic1;
          ic2 = 2 * v2 - ic2;
          buf[i] = switch (mode) {
            0 => v2,
            1 => x - k * v1 - v2,
            _ => v1 * k,
          };
        }
        _ic1[c] = ic1;
        _ic2[c] = ic2;
      }
    }
    _fc = fc;
  }
}

/// RBJ biquad (direct form 1), one per channel.
class Biquad {
  double b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0;
  final _x1 = [0.0, 0.0], _x2 = [0.0, 0.0], _y1 = [0.0, 0.0], _y2 = [0.0, 0.0];

  void _set(
    double nb0,
    double nb1,
    double nb2,
    double a0,
    double na1,
    double na2,
  ) {
    b0 = nb0 / a0;
    b1 = nb1 / a0;
    b2 = nb2 / a0;
    a1 = na1 / a0;
    a2 = na2 / a0;
  }

  void lowShelf(double sr, double f, double db) {
    final a = math.pow(10, db / 40).toDouble();
    final w = 2 * math.pi * f / sr, cw = math.cos(w);
    final al = math.sin(w) / 2 * math.sqrt(2);
    final sa = 2 * math.sqrt(a) * al;
    _set(
      a * ((a + 1) - (a - 1) * cw + sa),
      2 * a * ((a - 1) - (a + 1) * cw),
      a * ((a + 1) - (a - 1) * cw - sa),
      (a + 1) + (a - 1) * cw + sa,
      -2 * ((a - 1) + (a + 1) * cw),
      (a + 1) + (a - 1) * cw - sa,
    );
  }

  void highShelf(double sr, double f, double db) {
    final a = math.pow(10, db / 40).toDouble();
    final w = 2 * math.pi * f / sr, cw = math.cos(w);
    final al = math.sin(w) / 2 * math.sqrt(2);
    final sa = 2 * math.sqrt(a) * al;
    _set(
      a * ((a + 1) + (a - 1) * cw + sa),
      -2 * a * ((a - 1) + (a + 1) * cw),
      a * ((a + 1) + (a - 1) * cw - sa),
      (a + 1) - (a - 1) * cw + sa,
      2 * ((a - 1) - (a + 1) * cw),
      (a + 1) - (a - 1) * cw - sa,
    );
  }

  void peak(double sr, double f, double db, double q) {
    final a = math.pow(10, db / 40).toDouble();
    final w = 2 * math.pi * f / sr, cw = math.cos(w);
    final al = math.sin(w) / (2 * q);
    _set(1 + al * a, -2 * cw, 1 - al * a, 1 + al / a, -2 * cw, 1 - al / a);
  }

  double run(int c, double x) {
    final y = b0 * x + b1 * _x1[c] + b2 * _x2[c] - a1 * _y1[c] - a2 * _y2[c];
    _x2[c] = _x1[c];
    _x1[c] = x;
    _y2[c] = _y1[c];
    _y1[c] = y;
    return y;
  }
}

class EqFx extends Effect {
  EqFx(super.sr);
  final _low = Biquad(), _mid = Biquad(), _high = Biquad();

  @override
  void set(EffectSpec s) {
    super.set(s);
    _low.lowShelf(sr, 150, s['low']);
    _mid.peak(sr, s['midFreq'], s['mid'], 0.9);
    _high.highShelf(sr, math.min(5000, sr * 0.4), s['high']);
  }

  @override
  void process(Float32List buf, int frames) {
    for (var f = 0; f < frames; f++) {
      for (var c = 0; c < 2; c++) {
        final i = f * 2 + c;
        buf[i] = _high.run(c, _mid.run(c, _low.run(c, buf[i])));
      }
    }
  }
}

class DriveFx extends Effect {
  DriveFx(super.sr);
  final _lp = [0.0, 0.0];

  @override
  void process(Float32List buf, int frames) {
    final pre = dbToGain(spec['drive']);
    final out = dbToGain(spec['level']);
    final mix = spec['mix'];
    final a = 1 - math.exp(-2 * math.pi * spec['tone'] / sr);
    for (var f = 0; f < frames; f++) {
      for (var c = 0; c < 2; c++) {
        final i = f * 2 + c;
        final dry = buf[i];
        _lp[c] += (_tanh(dry * pre) - _lp[c]) * a;
        buf[i] = dry * (1 - mix) + _lp[c] * out * mix;
      }
    }
  }
}

class BitcrushFx extends Effect {
  BitcrushFx(super.sr);
  final _held = [0.0, 0.0];
  int _count = 0;

  @override
  void process(Float32List buf, int frames) {
    final levels = math.pow(2, spec['bits'] - 1).toDouble();
    final hold = spec['downsample'].round();
    final mix = spec['mix'];
    for (var f = 0; f < frames; f++) {
      if (_count <= 0) {
        for (var c = 0; c < 2; c++) {
          _held[c] = (buf[f * 2 + c] * levels).round() / levels;
        }
        _count = hold;
      }
      _count--;
      for (var c = 0; c < 2; c++) {
        final i = f * 2 + c;
        buf[i] = buf[i] * (1 - mix) + _held[c] * mix;
      }
    }
  }
}

class CompressorFx extends Effect {
  CompressorFx(super.sr);
  double _gr = 0; // gain reduction in dB (smoothed)

  /// Current gain reduction in dB (for a meter).
  double get reduction => _gr;

  @override
  void process(Float32List buf, int frames) {
    final thr = spec['threshold'], ratio = spec['ratio'];
    final att = math.exp(-1 / (spec['attack'] / 1000 * sr));
    final rel = math.exp(-1 / (spec['release'] / 1000 * sr));
    final makeup = spec['makeup'];
    final thrLin = dbToGain(thr);
    final makeupGain = dbToGain(makeup);
    for (var f = 0; f < frames; f++) {
      final l = buf[f * 2], r = buf[f * 2 + 1];
      final peak = math.max(l.abs(), r.abs());
      // Below the threshold no log is needed.
      final want = peak > thrLin
          ? (gainToDb(peak) - thr) * (1 - 1 / ratio)
          : 0.0;
      final coeff = want > _gr ? att : rel;
      _gr = want + (_gr - want) * coeff;
      final g = _gr < 1e-4 ? makeupGain : dbToGain(makeup - _gr);
      buf[f * 2] = l * g;
      buf[f * 2 + 1] = r * g;
    }
  }
}

/// Fractional-delay line.
class _Delay {
  _Delay(int size) : data = Float32List(size);
  final Float32List data;
  int pos = 0;

  void write(double x) {
    data[pos] = x;
    if (++pos >= data.length) pos = 0;
  }

  /// Sample written [d] samples ago (d >= 1, fractional).
  double read(double d) {
    var p = pos - d;
    while (p < 0) {
      p += data.length;
    }
    final i0 = p.floor();
    final i1 = (i0 + 1) % data.length;
    final t = p - i0;
    return data[i0 % data.length] * (1 - t) + data[i1] * t;
  }
}

class ChorusFx extends Effect {
  ChorusFx(super.sr)
    : _d = [_Delay((sr * 0.06).ceil()), _Delay((sr * 0.06).ceil())];
  final List<_Delay> _d;
  double _phase = 0;

  @override
  void process(Float32List buf, int frames) {
    final inc = spec['rate'] / sr;
    final depth = spec['depth'] / 1000 * sr;
    final base = 0.012 * sr;
    final mix = spec['mix'];
    for (var f = 0; f < frames; f++) {
      _phase = (_phase + inc) % 1;
      for (var c = 0; c < 2; c++) {
        final i = f * 2 + c;
        final x = buf[i];
        final lfo = math.sin(2 * math.pi * (_phase + c * 0.25));
        final wet = _d[c].read(base + depth * (0.5 + 0.5 * lfo) + 1);
        _d[c].write(x);
        buf[i] = x * (1 - mix * 0.5) + wet * mix;
      }
    }
  }
}

class PhaserFx extends Effect {
  PhaserFx(super.sr);
  static const _stages = 6;
  final _x1 = List.generate(2, (_) => Float64List(_stages));
  final _y1 = List.generate(2, (_) => Float64List(_stages));
  final _fb = [0.0, 0.0];
  double _phase = 0;

  @override
  void process(Float32List buf, int frames) {
    final inc = spec['rate'] / sr;
    final depth = spec['depth'];
    final fb = spec['feedback'];
    final mix = spec['mix'];
    final coeff = [0.0, 0.0];
    for (var f = 0; f < frames; f++) {
      _phase = (_phase + inc) % 1;
      if (f % 16 == 0) {
        for (var c = 0; c < 2; c++) {
          final lfo = 0.5 + 0.5 * math.sin(2 * math.pi * (_phase + c * 0.25));
          final hz = 180 * math.pow(2, lfo * depth * 5).toDouble();
          final t = math.tan(math.pi * math.min(hz, sr * 0.45) / sr);
          coeff[c] = (t - 1) / (t + 1);
        }
      }
      for (var c = 0; c < 2; c++) {
        final i = f * 2 + c;
        final x = buf[i];
        var y = x + _fb[c] * fb;
        final a = coeff[c];
        final xs = _x1[c], ys = _y1[c];
        for (var s = 0; s < _stages; s++) {
          final out = a * y + xs[s] - a * ys[s];
          xs[s] = y;
          ys[s] = out;
          y = out;
        }
        _fb[c] = y;
        buf[i] = x * (1 - mix * 0.5) + y * mix * 0.7;
      }
    }
  }
}

class TremoloFx extends Effect {
  TremoloFx(super.sr);
  double _phase = 0;

  @override
  void process(Float32List buf, int frames) {
    final inc = spec['rate'] / sr;
    final depth = spec['depth'];
    final pan = spec['stereo'];
    for (var f = 0; f < frames; f++) {
      _phase = (_phase + inc) % 1;
      for (var c = 0; c < 2; c++) {
        // Right channel is moved towards the opposite phase (auto-pan).
        final lfo = math.sin(2 * math.pi * (_phase + c * 0.5 * pan));
        buf[f * 2 + c] *= 1 - depth * (0.5 + 0.5 * lfo);
      }
    }
  }
}

class RingModFx extends Effect {
  RingModFx(super.sr);
  double _phase = 0;

  @override
  void process(Float32List buf, int frames) {
    final inc = spec['freq'] / sr;
    final mix = spec['mix'];
    for (var f = 0; f < frames; f++) {
      _phase = (_phase + inc) % 1;
      final m = math.sin(2 * math.pi * _phase);
      for (var c = 0; c < 2; c++) {
        final i = f * 2 + c;
        buf[i] = buf[i] * (1 - mix) + buf[i] * m * mix;
      }
    }
  }
}

class EchoFx extends Effect {
  EchoFx(super.sr)
    : _d = [_Delay((sr * 2.1).ceil()), _Delay((sr * 2.1).ceil())];
  final List<_Delay> _d;
  final _lp = [0.0, 0.0];
  double? _time; // samples, glides to the target (no clicks)

  @override
  void process(Float32List buf, int frames) {
    final target = spec['time'] / 1000 * sr;
    final fb = spec['feedback'];
    final mix = spec['mix'];
    final pingPong = spec['pingpong'] >= 0.5;
    final damp = 1 - spec['damp'] * 0.85; // one-pole coefficient
    var t = _time ?? target;
    final glide = 1 - math.exp(-1 / (0.05 * sr));
    for (var f = 0; f < frames; f++) {
      t += (target - t) * glide;
      final wl = _d[0].read(t), wr = _d[1].read(t);
      _lp[0] += (wl - _lp[0]) * damp;
      _lp[1] += (wr - _lp[1]) * damp;
      final l = buf[f * 2], r = buf[f * 2 + 1];
      if (pingPong) {
        _d[0].write((l + r) * 0.5 + _lp[1] * fb);
        _d[1].write(_lp[0] * fb);
      } else {
        _d[0].write(l + _lp[0] * fb);
        _d[1].write(r + _lp[1] * fb);
      }
      buf[f * 2] = l + wl * mix;
      buf[f * 2 + 1] = r + wr * mix;
    }
    _time = t;
  }
}

/// Freeverb-style reverb (8 combs + 4 all-passes per side).
class ReverbFx extends Effect {
  ReverbFx(super.sr) {
    final scale = sr / 44100;
    for (var c = 0; c < 2; c++) {
      final spread = c * 23;
      _combs.add([
        for (final n in _combTune) Float32List(((n + spread) * scale).round()),
      ]);
      _aps.add([
        for (final n in _apTune) Float32List(((n + spread) * scale).round()),
      ]);
      _combPos.add(List.filled(8, 0));
      _apPos.add(List.filled(4, 0));
      _combLp.add(List.filled(8, 0.0));
    }
  }

  static const _combTune = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617];
  static const _apTune = [556, 441, 341, 225];
  final _combs = <List<Float32List>>[];
  final _aps = <List<Float32List>>[];
  final _combPos = <List<int>>[];
  final _apPos = <List<int>>[];
  final _combLp = <List<double>>[];

  @override
  void process(Float32List buf, int frames) {
    final room = 0.7 + spec['size'] * 0.28;
    final damp = spec['damp'] * 0.4;
    final mix = spec['mix'];
    for (var f = 0; f < frames; f++) {
      final input = (buf[f * 2] + buf[f * 2 + 1]) * 0.015;
      for (var c = 0; c < 2; c++) {
        var out = 0.0;
        final combs = _combs[c], pos = _combPos[c], lp = _combLp[c];
        for (var k = 0; k < 8; k++) {
          final b = combs[k];
          final y = b[pos[k]];
          lp[k] = y * (1 - damp) + lp[k] * damp;
          b[pos[k]] = input + lp[k] * room;
          if (++pos[k] >= b.length) pos[k] = 0;
          out += y;
        }
        final aps = _aps[c], ap = _apPos[c];
        for (var k = 0; k < 4; k++) {
          final b = aps[k];
          final y = b[ap[k]];
          b[ap[k]] = out + y * 0.5;
          if (++ap[k] >= b.length) ap[k] = 0;
          out = y - out;
        }
        final i = f * 2 + c;
        buf[i] = buf[i] * (1 - mix * 0.5) + out * 3 * mix;
      }
    }
  }
}
