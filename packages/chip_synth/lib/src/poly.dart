// Polyphonic touch synth: up to [maxVoices] fingers, each its own voice,
// through shared effects. Two engines: an analog-style subtractive synth and
// the retro chip voices from catalog.dart. Pure Dart (runs in an isolate).
import 'dart:math' as math;
import 'dart:typed_data';

import 'catalog.dart';
import 'chips.dart';
import 'dsp.dart';

const maxVoices = 6;

enum EngineKind { analog, chip }

enum Osc { saw, square, triangle, sine }

/// What the vertical position on the pad controls.
enum YTarget { filter, volume, both }

/// Every sound setting of the touch synth.
class PolySpec {
  const PolySpec({
    this.engine = EngineKind.analog,
    this.osc1 = Osc.saw,
    this.osc2 = Osc.square,
    this.osc2Mix = 0.4,
    this.detune = 7,
    this.sub = 0.3,
    this.noise = 0,
    this.cutoff = 0.35,
    this.resonance = 0.35,
    this.yTarget = YTarget.filter,
    this.attack = 0.01,
    this.release = 0.35,
    this.glideMs = 30,
    this.chipId = 'sid',
    this.patchId = 'saw',
    this.vibratoCents = 0,
    this.vibratoRate = 5.5,
    this.drive = 0,
    this.delayMix = 0.2,
    this.delayMs = 320,
    this.delayFeedback = 0.35,
    this.reverbMix = 0.25,
    this.master = 0.8,
  });

  final EngineKind engine;

  // Analog engine.
  final Osc osc1, osc2;
  final double osc2Mix; // 0–1
  final double detune; // cents
  final double sub; // sub-octave square level 0–1
  final double noise; // 0–1
  final double cutoff; // 0–1 (filter base)
  final double resonance; // 0–1
  final YTarget yTarget;
  final double attack, release; // seconds
  final double glideMs;

  // Chip engine.
  final String chipId, patchId;

  // Shared effects.
  final double vibratoCents, vibratoRate;
  final double drive; // 0–1
  final double delayMix, delayMs, delayFeedback;
  final double reverbMix;
  final double master;

  PolySpec copyWith({
    EngineKind? engine,
    Osc? osc1,
    Osc? osc2,
    double? osc2Mix,
    double? detune,
    double? sub,
    double? noise,
    double? cutoff,
    double? resonance,
    YTarget? yTarget,
    double? attack,
    double? release,
    double? glideMs,
    String? chipId,
    String? patchId,
    double? vibratoCents,
    double? vibratoRate,
    double? drive,
    double? delayMix,
    double? delayMs,
    double? delayFeedback,
    double? reverbMix,
    double? master,
  }) => PolySpec(
    engine: engine ?? this.engine,
    osc1: osc1 ?? this.osc1,
    osc2: osc2 ?? this.osc2,
    osc2Mix: osc2Mix ?? this.osc2Mix,
    detune: detune ?? this.detune,
    sub: sub ?? this.sub,
    noise: noise ?? this.noise,
    cutoff: cutoff ?? this.cutoff,
    resonance: resonance ?? this.resonance,
    yTarget: yTarget ?? this.yTarget,
    attack: attack ?? this.attack,
    release: release ?? this.release,
    glideMs: glideMs ?? this.glideMs,
    chipId: chipId ?? this.chipId,
    patchId: patchId ?? this.patchId,
    vibratoCents: vibratoCents ?? this.vibratoCents,
    vibratoRate: vibratoRate ?? this.vibratoRate,
    drive: drive ?? this.drive,
    delayMix: delayMix ?? this.delayMix,
    delayMs: delayMs ?? this.delayMs,
    delayFeedback: delayFeedback ?? this.delayFeedback,
    reverbMix: reverbMix ?? this.reverbMix,
    master: master ?? this.master,
  );

  Map<String, Object> toJson() => {
    'engine': engine.name,
    'osc1': osc1.name,
    'osc2': osc2.name,
    'osc2Mix': osc2Mix,
    'detune': detune,
    'sub': sub,
    'noise': noise,
    'cutoff': cutoff,
    'resonance': resonance,
    'yTarget': yTarget.name,
    'attack': attack,
    'release': release,
    'glideMs': glideMs,
    'chip': chipId,
    'patch': patchId,
    'vibCents': vibratoCents,
    'vibRate': vibratoRate,
    'drive': drive,
    'delayMix': delayMix,
    'delayMs': delayMs,
    'delayFb': delayFeedback,
    'reverb': reverbMix,
    'master': master,
  };

  factory PolySpec.fromJson(Map<String, Object?> j) {
    const d = PolySpec();
    double n(String k, double f) => (j[k] as num?)?.toDouble() ?? f;
    T e<T extends Enum>(List<T> values, String k, T f) =>
        values.firstWhere((v) => v.name == j[k], orElse: () => f);
    return PolySpec(
      engine: e(EngineKind.values, 'engine', d.engine),
      osc1: e(Osc.values, 'osc1', d.osc1),
      osc2: e(Osc.values, 'osc2', d.osc2),
      osc2Mix: n('osc2Mix', d.osc2Mix),
      detune: n('detune', d.detune),
      sub: n('sub', d.sub),
      noise: n('noise', d.noise),
      cutoff: n('cutoff', d.cutoff),
      resonance: n('resonance', d.resonance),
      yTarget: e(YTarget.values, 'yTarget', d.yTarget),
      attack: n('attack', d.attack),
      release: n('release', d.release),
      glideMs: n('glideMs', d.glideMs),
      chipId: j['chip'] as String? ?? d.chipId,
      patchId: j['patch'] as String? ?? d.patchId,
      vibratoCents: n('vibCents', d.vibratoCents),
      vibratoRate: n('vibRate', d.vibratoRate),
      drive: n('drive', d.drive),
      delayMix: n('delayMix', d.delayMix),
      delayMs: n('delayMs', d.delayMs),
      delayFeedback: n('delayFb', d.delayFeedback),
      reverbMix: n('reverb', d.reverbMix),
      master: n('master', d.master),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PolySpec && _same(toJson(), other.toJson());

  static bool _same(Map<String, Object> a, Map<String, Object> b) {
    for (final k in a.keys) {
      if (a[k] != b[k]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(toJson().values);
}

/// Ready-made starting points.
const polyPresets = <String, PolySpec>{
  'Lead': PolySpec(),
  'Fat Pad': PolySpec(
    osc1: Osc.saw,
    osc2: Osc.saw,
    osc2Mix: 0.5,
    detune: 14,
    sub: 0.2,
    cutoff: 0.3,
    resonance: 0.2,
    attack: 0.35,
    release: 1.2,
    glideMs: 60,
    vibratoCents: 8,
    vibratoRate: 4.5,
    delayMix: 0.25,
    reverbMix: 0.5,
  ),
  'Acid Bass': PolySpec(
    osc1: Osc.square,
    osc2: Osc.saw,
    osc2Mix: 0.2,
    detune: 3,
    sub: 0.5,
    cutoff: 0.15,
    resonance: 0.8,
    attack: 0.005,
    release: 0.15,
    glideMs: 80,
    drive: 0.5,
    delayMix: 0.1,
    reverbMix: 0.1,
  ),
  'Glass Bell': PolySpec(
    osc1: Osc.sine,
    osc2: Osc.triangle,
    osc2Mix: 0.5,
    detune: 1200,
    sub: 0,
    cutoff: 0.8,
    resonance: 0.1,
    yTarget: YTarget.volume,
    attack: 0.002,
    release: 1.5,
    glideMs: 10,
    delayMix: 0.3,
    delayMs: 450,
    reverbMix: 0.6,
  ),
  'Chip Lead': PolySpec(
    engine: EngineKind.chip,
    chipId: 'nes',
    patchId: 'pulse',
    vibratoCents: 20,
    vibratoRate: 6,
    delayMix: 0.25,
    reverbMix: 0.15,
  ),
};

/// One finger on the pad.
class Touch {
  const Touch({this.down = false, this.hz = 220, this.y = 0.5});
  final bool down;
  final double hz;

  /// 0 (bottom) – 1 (top).
  final double y;
}

/// A voice: produces mono samples from its touch.
abstract class _Voice {
  double env = 0;
  bool get silent;
  void setTouch(Touch t);
  double next();
}

/// Anti-aliasing correction for saw/square edges (PolyBLEP).
double _blep(double t, double dt) {
  if (t < dt) {
    final x = t / dt;
    return x + x - x * x - 1;
  }
  if (t > 1 - dt) {
    final x = (t - 1) / dt;
    return x * x + x + x + 1;
  }
  return 0;
}

double _osc(Osc o, double phase, double inc) {
  switch (o) {
    case Osc.saw:
      return 2 * phase - 1 - _blep(phase, inc);
    case Osc.square:
      var v = phase < 0.5 ? 1.0 : -1.0;
      v += _blep(phase, inc);
      v -= _blep((phase + 0.5) % 1, inc);
      return v;
    case Osc.triangle:
      return 1 - 4 * (phase - 0.5).abs();
    case Osc.sine:
      return math.sin(2 * math.pi * phase);
  }
}

class _AnalogVoice extends _Voice {
  _AnalogVoice(this.sr, this.specRef);
  final double sr;
  final PolySpec Function() specRef;
  final _rnd = math.Random();

  double _hz = 220, _targetHz = 220, _y = 0.5;
  bool _down = false;
  double _p1 = 0, _p2 = 0, _ps = 0;
  // TPT state-variable filter state.
  double _ic1 = 0, _ic2 = 0;
  double vibrato = 1;

  @override
  bool get silent => !_down && env < 1e-4;

  @override
  void setTouch(Touch t) {
    if (t.down && !_down && env < 1e-3) _hz = t.hz; // fresh note: no glide
    _targetHz = t.hz;
    _y = t.y;
    _down = t.down;
  }

  @override
  double next() {
    final s = specRef();
    // Glide.
    final glide = s.glideMs <= 0 ? 1.0 : 1 - math.exp(-1000 / (s.glideMs * sr));
    _hz += (_targetHz - _hz) * glide;
    // Envelope (attack linear-ish, release exponential).
    if (_down) {
      env +=
          (1 - env) *
          (1 - math.exp(-1 / (math.max(0.001, s.attack) * sr * 0.3)));
    } else {
      env *= math.exp(-1 / (math.max(0.005, s.release) * sr * 0.25));
    }
    final hz = _hz * vibrato;
    final inc1 = hz / sr;
    final inc2 = hz * math.pow(2, s.detune / 1200) / sr;
    final incS = hz / 2 / sr;
    _p1 = (_p1 + inc1) % 1;
    _p2 = (_p2 + inc2) % 1;
    _ps = (_ps + incS) % 1;
    var x =
        _osc(s.osc1, _p1, inc1) * (1 - s.osc2Mix * 0.5) +
        _osc(s.osc2, _p2, inc2) * s.osc2Mix +
        _osc(Osc.square, _ps, incS) * s.sub * 0.7 +
        (_rnd.nextDouble() * 2 - 1) * s.noise * 0.5;

    // Filter: cutoff from the base knob, opened by the finger height.
    final yFilter = s.yTarget != YTarget.volume ? _y : 0.6;
    final c = (s.cutoff * 0.6 + yFilter * 0.55).clamp(0.0, 1.0);
    final fc = 40 * math.pow(400, c).toDouble(); // 40 Hz – 16 kHz
    final g = math.tan(math.pi * math.min(fc, sr * 0.45) / sr);
    final k = 2 - 1.9 * s.resonance;
    final a1 = 1 / (1 + g * (g + k));
    final v3 = x - _ic2;
    final v1 = a1 * _ic1 + g * a1 * v3;
    final v2 = _ic2 + g * v1;
    _ic1 = 2 * v1 - _ic1;
    _ic2 = 2 * v2 - _ic2;
    x = v2;

    final yVol = s.yTarget != YTarget.filter ? 0.15 + 0.85 * _y : 1.0;
    return x * env * yVol * 0.35;
  }
}

class _ChipPolyVoice extends _Voice {
  _ChipPolyVoice(this.sr, String chipId, String patchId)
    : chip = chipById(chipId) {
    patch = chip.patch(patchId);
    voice = chip.create(patch.id, sr);
    hp = HighPass(chip.highPassHz, sr);
    lp = LowPass(chip.lowPassHz, sr);
    norm = _norm(chip, patch, sr);
  }

  final double sr;
  final ChipInfo chip;
  late final PatchInfo patch;
  late final ChipVoice voice;
  late final HighPass hp;
  late final LowPass lp;
  late final double norm;
  double vibrato = 1;
  double _framePos = 0;
  double _hz = 220, _y = 0.5;
  bool _down = false;
  double releaseSec = 0.3;

  static final Map<String, double> _norms = {};
  static double _norm(ChipInfo c, PatchInfo p, double sr) =>
      _norms.putIfAbsent('${c.id}/${p.id}/$sr', () {
        final v = c.create(p.id, sr);
        final hp = HighPass(c.highPassHz, sr), lp = LowPass(c.lowPassHz, sr);
        final hz = 220 * math.pow(2, p.transpose / 12).toDouble();
        var sum = 0.0;
        final n = (sr * 0.4).toInt();
        for (var i = 0; i < n; i++) {
          if (i % (sr / c.fps).round() == 0) v.latch(hz, 1, 0.5);
          final y = lp.process(hp.process(v.next()));
          if (i > n ~/ 4) sum += y * y;
        }
        final rms = math.sqrt(sum / (n - n ~/ 4));
        return rms < 1e-6 ? 1 : (0.2 / rms).clamp(0.2, 12.0);
      });

  @override
  bool get silent => !_down && env < 1e-3;

  @override
  void setTouch(Touch t) {
    _hz = t.hz;
    _y = t.y;
    _down = t.down;
  }

  @override
  double next() {
    // Register writes happen once per video frame, like a sound driver.
    _framePos += chip.fps / sr;
    if (_framePos >= 1) {
      _framePos -= 1;
      if (_down) {
        env = 1;
      } else {
        env = math.max(0, env - 1 / (releaseSec * chip.fps + 1));
      }
      final hz = _hz * math.pow(2, patch.transpose / 12) * vibrato;
      voice.latch(hz.clamp(20.0, 12000.0), env, _y);
    }
    return lp.process(hp.process(voice.next())) * norm * 0.5;
  }
}

/// Freeverb-style stereo reverb (small and cheap).
class _Reverb {
  _Reverb(double sr) {
    final scale = sr / 44100;
    for (final len in const [1116, 1188, 1277, 1356]) {
      _combsL.add(_Comb((len * scale).round()));
      _combsR.add(_Comb(((len + 23) * scale).round()));
    }
    for (final len in const [556, 441]) {
      _apL.add(_Allpass((len * scale).round()));
      _apR.add(_Allpass(((len + 23) * scale).round()));
    }
  }

  final _combsL = <_Comb>[], _combsR = <_Comb>[];
  final _apL = <_Allpass>[], _apR = <_Allpass>[];

  (double, double) process(double x) {
    var l = 0.0, r = 0.0;
    for (final c in _combsL) {
      l += c.process(x);
    }
    for (final c in _combsR) {
      r += c.process(x);
    }
    for (final a in _apL) {
      l = a.process(l);
    }
    for (final a in _apR) {
      r = a.process(r);
    }
    return (l * 0.25, r * 0.25);
  }
}

class _Comb {
  _Comb(int n) : _buf = Float32List(n);
  final Float32List _buf;
  int _i = 0;
  double _store = 0;

  double process(double x) {
    final y = _buf[_i];
    _store = y * 0.8 + _store * 0.2; // damping
    _buf[_i] = x + _store * 0.84; // room size
    if (++_i >= _buf.length) _i = 0;
    return y;
  }
}

class _Allpass {
  _Allpass(int n) : _buf = Float32List(n);
  final Float32List _buf;
  int _i = 0;

  double process(double x) {
    final b = _buf[_i];
    final y = -x + b;
    _buf[_i] = x + b * 0.5;
    if (++_i >= _buf.length) _i = 0;
    return y;
  }
}

/// The whole instrument: voices + shared effects → stereo.
class PolySynth {
  PolySynth(this.sampleRate)
    : _delayL = Float32List((sampleRate * 1.2).toInt()),
      _delayR = Float32List((sampleRate * 1.2).toInt()),
      _reverb = _Reverb(sampleRate);

  final double sampleRate;
  PolySpec _spec = const PolySpec();
  final List<_Voice?> _voices = List.filled(maxVoices, null);
  final List<Touch> _touches = List.filled(maxVoices, const Touch());
  final Float32List _delayL, _delayR;
  int _dPos = 0;
  final _Reverb _reverb;
  double _lfo = 0;

  PolySpec get spec => _spec;

  void configure(PolySpec s) {
    final engineChanged =
        s.engine != _spec.engine ||
        s.chipId != _spec.chipId ||
        s.patchId != _spec.patchId;
    _spec = s;
    if (engineChanged) {
      for (var i = 0; i < maxVoices; i++) {
        _voices[i] = null;
      }
    }
  }

  /// Sets finger [i] (0–5).
  void setTouch(int i, Touch t) {
    _touches[i] = t;
    var v = _voices[i];
    if (v == null && t.down) {
      v = _voices[i] = _spec.engine == EngineKind.analog
          ? _AnalogVoice(sampleRate, () => _spec)
          : _ChipPolyVoice(sampleRate, _spec.chipId, _spec.patchId);
    }
    v?.setTouch(t);
  }

  /// Number of voices currently sounding.
  int get activeVoices => _voices.where((v) => v != null && !v.silent).length;

  void render(Float32List out, int frames, {int offset = 0}) {
    final s = _spec;
    final dLen = (s.delayMs / 1000 * sampleRate).round().clamp(
      1,
      _delayL.length - 1,
    );
    final driveGain = 1 + s.drive * 6;
    for (var f = 0; f < frames; f++) {
      // Shared vibrato LFO.
      _lfo += s.vibratoRate / sampleRate;
      if (_lfo >= 1) _lfo -= 1;
      final vib = s.vibratoCents > 0
          ? math
                .pow(2, s.vibratoCents / 1200 * math.sin(2 * math.pi * _lfo))
                .toDouble()
          : 1.0;
      var x = 0.0;
      for (var i = 0; i < maxVoices; i++) {
        final v = _voices[i];
        if (v == null) continue;
        if (v is _AnalogVoice) v.vibrato = vib;
        if (v is _ChipPolyVoice) {
          v
            ..vibrato = vib
            ..releaseSec = s.release;
        }
        x += v.next();
      }
      if (s.drive > 0) x = softClip(x * driveGain) / math.sqrt(driveGain);

      var l = x, r = x;
      // Ping-pong delay.
      var read = _dPos - dLen;
      if (read < 0) read += _delayL.length;
      final dl = _delayL[read], dr = _delayR[read];
      _delayL[_dPos] = x + dr * s.delayFeedback;
      _delayR[_dPos] = dl * s.delayFeedback;
      if (++_dPos >= _delayL.length) _dPos = 0;
      l += dl * s.delayMix;
      r += dr * s.delayMix;
      // Reverb.
      if (s.reverbMix > 0) {
        final (rl, rr) = _reverb.process(x * 0.5);
        l += rl * s.reverbMix;
        r += rr * s.reverbMix;
      }
      out[(offset + f) * 2] = softClip(l * s.master * 1.5);
      out[(offset + f) * 2 + 1] = softClip(r * s.master * 1.5);
    }
    // Free voices that finished their release.
    for (var i = 0; i < maxVoices; i++) {
      final v = _voices[i];
      if (v != null && v.silent && !_touches[i].down) _voices[i] = null;
    }
  }
}
