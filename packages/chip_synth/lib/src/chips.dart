// Real-time emulations of retro sound chips, driven continuously by the
// theremin. Each chip follows its hardware behaviour:
//  * pitch is quantized to what the chip's frequency/divider registers can
//    produce (so slides step, and some notes are slightly off - on purpose),
//  * volume uses the chip's own volume steps (4-bit linear, log, 2 dB, ...),
//  * registers are written once per video frame by the engine (see
//    engine.dart), like a game's sound driver,
//  * output goes through the machine's typical output filtering.
// Wavetables marked "designed" are original designs in the style of the
// hardware, not copies of ROM data.
import 'dart:math' as math;
import 'dart:typed_data';

import 'dsp.dart';

/// One playing sound on a chip.
abstract class ChipVoice {
  ChipVoice(this.sampleRate) : subRate = sampleRate * oversample;

  final double sampleRate;

  /// Sub-sample rate used by oversampled chips.
  final double subRate;

  /// Writes the chip registers for this frame. [hz] is the wanted pitch,
  /// [level] the wanted loudness (0–1) and [timbre] the shape control (0–1).
  void latch(double hz, double level, double timbre);

  /// One sub-sample of raw chip output (roughly -1..1).
  double sub() => 0;

  /// One output sample; by default the average of [oversample] sub-samples.
  double next() {
    var sum = 0.0;
    for (var i = 0; i < oversample; i++) {
      sum += sub();
    }
    return sum / oversample;
  }
}

/// 4-bit volume register value for a 0–1 level.
int vol4(double level) => (level * 15).round().clamp(0, 15);

// ---------------------------------------------------------------------------
// Nintendo Game Boy (DMG APU)
// ---------------------------------------------------------------------------

const _gbDuties = <List<double>>[
  [0, 0, 0, 0, 0, 0, 0, 1], // 12.5 %
  [1, 0, 0, 0, 0, 0, 0, 1], // 25 %
  [1, 0, 0, 0, 0, 1, 1, 1], // 50 %
  [0, 1, 1, 1, 1, 1, 1, 0], // 75 %
];

/// Pulse channel: 11-bit period, f = 131072 / (2048 - x), 4 duty cycles.
class GbPulse extends ChipVoice {
  GbPulse(super.sampleRate, {this.fixedDuty});

  final int? fixedDuty;
  final _osc = TableOsc(_gbDuties[2]);
  final _tables = [for (final d in _gbDuties) Float64List.fromList(d)];
  double _amp = 0;

  static double quantize(double hz) {
    final x = (2048 - 131072 / hz).round().clamp(0, 2047);
    return 131072 / (2048 - x);
  }

  @override
  void latch(double hz, double level, double timbre) {
    _osc.setFrequency(quantize(hz), subRate);
    _osc.table = _tables[fixedDuty ?? (timbre * 3.999).floor()];
    _amp = vol4(level) / 15;
  }

  @override
  double sub() => (_osc.tick() * 2 - 1) * _amp;
}

/// Designed 32-step 4-bit wavetables (shared by the Game Boy wave channel and
/// the Namco-style wavetable chip).
final List<List<double>> designedWaves = [
  wave4bit((p) => math.sin(2 * math.pi * p)), // sine
  wave4bit((p) => 1 - 4 * (p - 0.5).abs()), // triangle
  wave4bit((p) => 2 * p - 1), // saw
  wave4bit(
    (p) => 0.6 * math.sin(2 * math.pi * p) + 0.4 * math.sin(4 * math.pi * p),
  ), // organ
  wave4bit((p) => p < 0.25 ? 1 : -1), // hollow pulse
  wave4bit(
    (p) =>
        0.5 * math.sin(2 * math.pi * p) +
        0.3 * math.sin(6 * math.pi * p) +
        0.2 * math.sin(10 * math.pi * p),
  ), // reedy
  wave4bit((p) => math.sin(2 * math.pi * p + 2.5 * math.sin(2 * math.pi * p))),
  // growl
  wave4bit((p) => (2 * p - 1) * (p < 0.5 ? 1 : -0.5)), // jagged
];

/// Wave channel: 32 4-bit samples, f = 65536 / (2048 - x), and only four
/// volume settings (mute, 25 %, 50 %, 100 %).
class GbWave extends ChipVoice {
  GbWave(super.sampleRate, {this.fixedWave});

  final int? fixedWave;
  final _osc = TableOsc(designedWaves[0]);
  late final _tables = [for (final w in designedWaves) Float64List.fromList(w)];
  double _amp = 0;

  @override
  void latch(double hz, double level, double timbre) {
    final x = (2048 - 65536 / hz).round().clamp(0, 2047);
    _osc.setFrequency(65536 / (2048 - x), subRate);
    _osc.table =
        _tables[fixedWave ?? (timbre * (_tables.length - 0.001)).floor()];
    const shifts = [0.0, 0.25, 0.5, 1.0];
    _amp = shifts[(level * 3).round().clamp(0, 3)];
  }

  @override
  double sub() => (_osc.tick() / 7.5 - 1) * _amp;
}

/// Noise channel: 15-bit LFSR (or 7-bit for a metallic buzz), clocked at
/// 524288 / r / 2^(s+1) Hz.
class GbNoise extends ChipVoice {
  GbNoise(super.sampleRate);

  final _long = LfsrNoise(bits: 15, taps: [0, 1]);
  final _short = LfsrNoise(bits: 7, taps: [0, 1]);
  bool _useShort = false;
  double _amp = 0;

  @override
  void latch(double hz, double level, double timbre) {
    final want = hz * 8;
    var best = double.infinity;
    var clock = 0.0;
    for (var r = 0; r < 8; r++) {
      for (var s = 0; s < 14; s++) {
        final c = 524288 / (r == 0 ? 0.5 : r) / (1 << (s + 1));
        final err = (math.log(c / want)).abs();
        if (err < best) {
          best = err;
          clock = c;
        }
      }
    }
    _long.setClock(clock, subRate);
    _short.setClock(clock, subRate);
    _useShort = timbre > 0.5;
    _amp = vol4(level) / 15;
  }

  @override
  double sub() {
    final a = _long.tick();
    final b = _short.tick();
    return ((_useShort ? b : a) == 0 ? 1 : -1) * _amp;
  }
}

// ---------------------------------------------------------------------------
// Nintendo Entertainment System (Ricoh 2A03)
// ---------------------------------------------------------------------------

const _nesCpu = 1789773.0;
const _nesDuties = <List<double>>[
  [0, 1, 0, 0, 0, 0, 0, 0],
  [0, 1, 1, 0, 0, 0, 0, 0],
  [0, 1, 1, 1, 1, 0, 0, 0],
  [1, 0, 0, 1, 1, 1, 1, 1],
];

/// Pulse channel: 11-bit timer, f = CPU / (16 (t + 1)), non-linear mixer.
class NesPulse extends ChipVoice {
  NesPulse(super.sampleRate);

  final _osc = TableOsc(_nesDuties[2]);
  final _tables = [for (final d in _nesDuties) Float64List.fromList(d)];
  int _vol = 0;

  @override
  void latch(double hz, double level, double timbre) {
    final t = (_nesCpu / (16 * hz) - 1).round().clamp(8, 2047);
    _osc.setFrequency(_nesCpu / (16 * (t + 1)), subRate);
    _osc.table = _tables[(timbre * 3.999).floor()];
    _vol = vol4(level);
  }

  @override
  double sub() {
    final p = _osc.tick() * _vol;
    // 2A03 pulse mixer curve, scaled so full volume is about 1.
    return p == 0 ? 0 : 95.88 / (8128 / p + 100) / 0.1494 * 2;
  }
}

/// Triangle channel: 32 steps, f = CPU / (32 (t + 1)). It has no volume
/// control - only on or off, and when off it freezes where it is.
class NesTriangle extends ChipVoice {
  NesTriangle(super.sampleRate);

  final _osc = TableOsc([
    for (var i = 15; i >= 0; i--) i.toDouble(),
    for (var i = 0; i < 16; i++) i.toDouble(),
  ]);
  bool _on = false;
  double _held = 0;

  @override
  void latch(double hz, double level, double timbre) {
    final t = (_nesCpu / (32 * hz) - 1).round().clamp(2, 2047);
    _osc.setFrequency(_nesCpu / (32 * (t + 1)), subRate);
    _on = level > 0.02;
  }

  @override
  double sub() {
    if (_on) _held = _osc.tick();
    return 159.79 / (1 / (_held / 8227) + 100) / 0.2464 * 2;
  }
}

/// Noise channel: 16 fixed periods, long or short ("metallic") mode.
class NesNoise extends ChipVoice {
  NesNoise(super.sampleRate);

  static const _periods = [
    4,
    8,
    16,
    32,
    64,
    96,
    128,
    160,
    202,
    254,
    380,
    508,
    762,
    1016,
    2034,
    4068, //
  ];
  final _long = LfsrNoise(bits: 15, taps: [0, 1]);
  final _short = LfsrNoise(bits: 15, taps: [0, 6]);
  bool _useShort = false;
  int _vol = 0;

  @override
  void latch(double hz, double level, double timbre) {
    final want = hz * 32;
    var best = 0;
    for (var i = 1; i < _periods.length; i++) {
      if ((math.log(_nesCpu / _periods[i] / want)).abs() <
          (math.log(_nesCpu / _periods[best] / want)).abs()) {
        best = i;
      }
    }
    final clock = _nesCpu / _periods[best];
    _long.setClock(clock, subRate);
    _short.setClock(clock, subRate);
    _useShort = timbre > 0.5;
    _vol = vol4(level);
  }

  @override
  double sub() {
    final a = _long.tick();
    final b = _short.tick();
    final bit = _useShort ? b : a;
    final n = bit == 0 ? _vol : 0;
    return n == 0 ? 0 : 159.79 / (1 / (n / 12241) + 100) / 0.1744 * 2;
  }
}

// ---------------------------------------------------------------------------
// Commodore 64 (MOS 6581 SID), PAL clock
// ---------------------------------------------------------------------------

const _sidClock = 985248.0;

enum SidPatch { saw, pwm, sync, ring, filterBass, noise }

/// One SID voice (plus a second oscillator for sync/ring) through the SID's
/// resonant multimode filter and 4-bit master volume.
class SidVoice extends ChipVoice {
  SidVoice(super.sampleRate, this.patch);

  final SidPatch patch;
  double _p1 = 0, _p2 = 0, _i1 = 0, _i2 = 0;
  double _pw = 0.5;
  double _pwmPhase = 0;
  double _amp = 0;
  final _noise = LfsrNoise(bits: 23, taps: [0, 5], seed: 0x7ffff8);
  double _noiseValue = 0;
  // State-variable filter.
  double _low = 0, _band = 0, _f = 0.1, _damp = 1;
  bool _filtered = false;
  bool _bandPass = false;

  static double quantize(double hz) {
    final reg = (hz * 16777216 / _sidClock).round().clamp(1, 65535);
    return reg * _sidClock / 16777216;
  }

  @override
  void latch(double hz, double level, double timbre) {
    final f = quantize(hz);
    _i1 = f / subRate;
    _amp = vol4(level) / 15; // the famous 4-bit master volume
    double cutoff = 0;
    double res = 0;
    switch (patch) {
      case SidPatch.saw:
        _filtered = true;
        cutoff = 200 + timbre * timbre * 9000;
        res = 0.55;
      case SidPatch.pwm:
        _filtered = false;
        // PWM driven per frame by the sound driver.
        _pwmPhase += 1 / 50.125 * 0.7;
        final centre = 0.08 + timbre * 0.4;
        _pw = (centre + 0.12 * math.sin(2 * math.pi * _pwmPhase)).clamp(
          0.02,
          0.98,
        );
      case SidPatch.sync:
        _filtered = false;
        _i2 = quantize(hz * (1 + timbre * 5)) / subRate;
      case SidPatch.ring:
        _filtered = false;
        _i2 = quantize(hz * (1.5 + timbre * 3.3)) / subRate;
      case SidPatch.filterBass:
        _filtered = true;
        _pw = 0.5;
        cutoff = 120 + timbre * timbre * 4000;
        res = 0.85;
      case SidPatch.noise:
        _filtered = true;
        _bandPass = true;
        cutoff = 300 + timbre * 6000;
        res = 0.7;
        _noise.setClock(f * 16, subRate);
    }
    if (_filtered) {
      _f = 2 * math.sin(math.pi * math.min(cutoff, 16000) / subRate);
      _damp = 2 - 1.9 * res;
    }
  }

  @override
  double sub() {
    final wrapped = (_p1 += _i1) >= 1;
    if (wrapped) _p1 -= 1;
    double v;
    switch (patch) {
      case SidPatch.saw:
        v = _p1 * 2 - 1;
      case SidPatch.pwm:
      case SidPatch.filterBass:
        v = _p1 < _pw ? 1 : -1;
      case SidPatch.sync:
        _p2 += _i2;
        if (_p2 >= 1) _p2 -= _p2.floorToDouble();
        if (wrapped) _p2 = 0; // hard sync
        v = _p2 * 2 - 1;
      case SidPatch.ring:
        _p2 += _i2;
        if (_p2 >= 1) _p2 -= _p2.floorToDouble();
        final tri = 1 - 4 * (_p1 - 0.5).abs();
        v = _p2 < 0.5 ? tri : -tri; // ring modulation flips the triangle
      case SidPatch.noise:
        _noise.tick();
        _noiseValue = ((_noise.register >> 14) & 0xff) / 127.5 - 1;
        v = _noiseValue;
    }
    if (_filtered) {
      // The 6581 filter is slightly overdriven.
      final input = softClip(v * 1.3);
      _low += _f * _band;
      final high = input - _low - _damp * _band;
      _band += _f * high;
      v = _bandPass ? _band : _low;
    }
    return v * _amp;
  }
}

// ---------------------------------------------------------------------------
// General Instrument AY-3-8910 (ZX Spectrum 128 clock)
// ---------------------------------------------------------------------------

const _ayClock = 1773400.0;

/// AY logarithmic volume table (normalized).
const ayVolume = [
  0.0, 0.0137, 0.0205, 0.0291, 0.0423, 0.0618, 0.0847, 0.1369, //
  0.1691, 0.2647, 0.3527, 0.4499, 0.5704, 0.6873, 0.8482, 1.0,
];

enum AyPatch { square, buzz, syncBuzz, noise }

/// AY tone/noise mixer with the hardware envelope. "Buzz" patches use the
/// envelope at audio rate (the classic buzzer bass); in envelope mode the
/// chip ignores the volume register, so loudness is only on/off.
class AyVoice extends ChipVoice {
  AyVoice(super.sampleRate, this.patch);

  final AyPatch patch;
  final _tone = TableOsc([1, 0]);
  final _noise = LfsrNoise(bits: 17, taps: [0, 3]);
  double _envPhase = 0, _envInc = 0;
  bool _envTriangle = false;
  bool _noiseOn = false;
  bool _gate = false;
  double _amp = 0;

  @override
  void latch(double hz, double level, double timbre) {
    _gate = level > 0.02;
    _amp = ayVolume[vol4(level)];
    switch (patch) {
      case AyPatch.square:
        final tp = (_ayClock / (16 * hz)).round().clamp(1, 4095);
        _tone.setFrequency(_ayClock / (16 * tp), subRate);
        _noiseOn = timbre > 0.25;
        final np = (31 - (timbre - 0.25) / 0.75 * 30).round().clamp(1, 31);
        _noise.setClock(_ayClock / (16 * np), subRate);
      case AyPatch.buzz:
        _envTriangle = timbre > 0.5;
        final ep = (_ayClock / ((_envTriangle ? 512 : 256) * hz)).round().clamp(
          1,
          65535,
        );
        _envInc = _ayClock / (16 * ep) / 16 / subRate;
      case AyPatch.syncBuzz:
        final ep = (_ayClock / (256 * hz)).round().clamp(1, 65535);
        _envInc = _ayClock / (16 * ep) / 16 / subRate;
        final ratio = 1 + (timbre * 7).round();
        final tp = (_ayClock / (16 * hz * ratio)).round().clamp(1, 4095);
        _tone.setFrequency(_ayClock / (16 * tp), subRate);
      case AyPatch.noise:
        final np = (_ayClock / (16 * hz * 8)).round().clamp(1, 31);
        _noise.setClock(_ayClock / (16 * np), subRate);
    }
  }

  double _envLevel() {
    _envPhase += _envInc;
    if (_envPhase >= 1) _envPhase -= _envPhase.floorToDouble();
    final step = (_envPhase * 16).floor().clamp(0, 15);
    if (!_envTriangle) return ayVolume[15 - step];
    // Triangle shape: down then up over two envelope periods.
    final half = (_envPhase * 2) % 1;
    final s = (half * 16).floor().clamp(0, 15);
    return ayVolume[_envPhase < 0.5 ? 15 - s : s];
  }

  @override
  double sub() {
    switch (patch) {
      case AyPatch.square:
        final t = _tone.tick();
        final n = _noise.tick();
        final on = _noiseOn ? (t > 0 && n == 1) : t > 0;
        return (on ? 1 : -1) * _amp;
      case AyPatch.buzz:
        final e = _envLevel();
        return _gate ? e * 2 - 1 : 0;
      case AyPatch.syncBuzz:
        final e = _envLevel();
        final t = _tone.tick();
        return _gate && t > 0 ? e : 0;
      case AyPatch.noise:
        return (_noise.tick() == 1 ? 1 : -1) * _amp;
    }
  }
}

// ---------------------------------------------------------------------------
// Texas Instruments SN76489 (Sega Master System / Game Gear)
// ---------------------------------------------------------------------------

const _snClock = 3579545.0;

/// SN76489 volume: 2 dB per step.
double snVolume(int v) =>
    v == 0 ? 0 : math.pow(10, -2 * (15 - v) / 20).toDouble();

enum SnPatch { square, buzzBass, noise }

/// 10-bit tone dividers (f = clock / 32N; nothing below ~109 Hz, so low notes
/// fold up an octave), periodic noise for buzzy bass, white noise.
class SnVoice extends ChipVoice {
  SnVoice(super.sampleRate, this.patch);

  final SnPatch patch;
  final _square = TableOsc([1, 0]);
  final _periodic = TableOsc([1, ...List.filled(15, 0.0)]);
  final _noise = LfsrNoise(bits: 16, taps: [0, 3]);
  double _amp = 0;

  @override
  void latch(double hz, double level, double timbre) {
    _amp = snVolume(vol4(level));
    switch (patch) {
      case SnPatch.square:
        var f = hz;
        while (f < _snClock / (32 * 1023)) {
          f *= 2;
        }
        final n = (_snClock / (32 * f)).round().clamp(1, 1023);
        _square.setFrequency(_snClock / (32 * n), subRate);
      case SnPatch.buzzBass:
        final n = (_snClock / (32 * 16 * hz)).round().clamp(1, 1023);
        _periodic.setStepRate(_snClock / (32 * n), subRate);
      case SnPatch.noise:
        final n = (_snClock / (32 * hz * 8)).round().clamp(1, 1023);
        _noise.setClock(_snClock / (32 * n), subRate);
    }
  }

  @override
  double sub() => switch (patch) {
    SnPatch.square => (_square.tick() * 2 - 1) * _amp,
    SnPatch.buzzBass => (_periodic.tick() * 2 - 1) * _amp,
    SnPatch.noise => (_noise.tick() * 2 - 1) * _amp,
  };
}

// ---------------------------------------------------------------------------
// Atari 2600 (TIA)
// ---------------------------------------------------------------------------

const _tiaClock = 31399.5; // NTSC audio clock (colour clock / 114)

List<double> _lfsrPattern(int bits, List<int> taps) {
  final n = LfsrNoise(bits: bits, taps: taps, seed: (1 << bits) - 1);
  final length = (1 << bits) - 1;
  return [
    for (var i = 0; i < length; i++)
      () {
        n.step();
        return n.bit.toDouble();
      }(),
  ];
}

/// TIA waveform patterns (one period each). The pattern advances once per
/// divided clock, so f = 31400 / (N + 1) / length, with only 32 dividers.
final Map<String, List<double>> tiaPatterns = {
  'square': [1, 0],
  'lead': [1, 1, 1, 0, 0, 0],
  'buzz': _lfsrPattern(4, [0, 1]),
  'bass': [...List.filled(13, 1.0), ...List.filled(18, 0.0)],
  'poly5': _lfsrPattern(5, [0, 2]),
  'noise': _lfsrPattern(9, [0, 4]),
};

class TiaVoice extends ChipVoice {
  TiaVoice(super.sampleRate, {this.fixedPattern});

  /// null: the shape control picks the waveform.
  final String? fixedPattern;
  late final _tables = {
    for (final e in tiaPatterns.entries) e.key: Float64List.fromList(e.value),
  };
  final _osc = TableOsc([1, 0]);
  double _amp = 0;

  static const _shapeOrder = [
    'square',
    'lead',
    'bass',
    'buzz',
    'poly5',
    'noise',
  ];

  @override
  void latch(double hz, double level, double timbre) {
    final name =
        fixedPattern ??
        _shapeOrder[(timbre * (_shapeOrder.length - 0.001)).floor()];
    final table = _tables[name]!;
    if (!identical(_osc.table, table)) {
      _osc
        ..table = table
        ..phase = 0;
    }
    final length = table.length;
    final divider = (_tiaClock / (hz * length) - 1).round().clamp(0, 31);
    _osc.setStepRate(_tiaClock / (divider + 1), subRate);
    _amp = vol4(level) / 15;
  }

  @override
  double sub() => (_osc.tick() * 2 - 1) * _amp;
}

// ---------------------------------------------------------------------------
// Namco WSG (Pac-Man style 3-voice wavetable chip)
// ---------------------------------------------------------------------------

class WsgVoice extends ChipVoice {
  WsgVoice(super.sampleRate, {this.fixedWave, this.siren = false});

  final int? fixedWave;
  final bool siren;
  late final _tables = [for (final w in designedWaves) Float64List.fromList(w)];
  final _osc = TableOsc(designedWaves[0]);
  double _amp = 0;
  int _frame = 0;

  @override
  void latch(double hz, double level, double timbre) {
    var f = hz;
    if (siren) {
      // The siren effect: a fast frame-stepped pitch sweep.
      _frame++;
      final depth = 0.04 + timbre * 0.2;
      f *= 1 + depth * (((_frame % 16) / 8) - 1).abs();
    }
    // 20-bit frequency register at 96 kHz.
    final reg = (f * 1048576 / 96000).round().clamp(1, 1048575);
    _osc.setFrequency(reg * 96000 / 1048576, subRate);
    _osc.table =
        _tables[fixedWave ?? (timbre * (_tables.length - 0.001)).floor()];
    _amp = vol4(level) / 15;
  }

  @override
  double sub() => (_osc.tick() / 7.5 - 1) * _amp;
}

// ---------------------------------------------------------------------------
// Yamaha YM2612 (Sega Genesis / Mega Drive) 4-operator FM
// ---------------------------------------------------------------------------

const _fmRate = 53267.0; // FM sample clock (7.67 MHz / 144)

/// One operator's settings.
class FmOp {
  const FmOp({
    this.mul = 1,
    this.level = 1,
    this.attack = 0.005,
    this.decay = 0.3,
    this.sustain = 1,
    this.release = 0.08,
    this.detuneCents = 0,
  });

  final double mul;

  /// Output level (0–1) before the shape control and volume.
  final double level;
  final double attack, decay, sustain, release, detuneCents;
}

class FmPatch {
  const FmPatch({
    required this.algorithm,
    required this.ops,
    this.feedback = 0,
  });

  final int algorithm;
  final List<FmOp> ops;
  final double feedback;

  /// Which operators are carriers (heard) for each algorithm.
  static const carriers = <List<bool>>[
    [false, false, false, true],
    [false, false, false, true],
    [false, false, false, true],
    [false, false, false, true],
    [false, true, false, true],
    [false, true, true, true],
    [false, true, true, true],
    [true, true, true, true],
  ];
}

const fmPatches = {
  'brass': FmPatch(
    algorithm: 4,
    feedback: 0.35,
    ops: [
      FmOp(mul: 1, level: 0.75, attack: 0.04),
      FmOp(mul: 1, attack: 0.03),
      FmOp(mul: 2, level: 0.35, attack: 0.05),
      FmOp(mul: 1, level: 0.8, attack: 0.04),
    ],
  ),
  'epiano': FmPatch(
    algorithm: 4,
    ops: [
      FmOp(mul: 1, level: 0.55, decay: 1.2, sustain: 0.4),
      FmOp(mul: 1, decay: 2.5, sustain: 0.6),
      FmOp(mul: 14, level: 0.3, decay: 0.25, sustain: 0.05),
      FmOp(mul: 1, level: 0.6, decay: 1.5, sustain: 0.5),
    ],
  ),
  'bass': FmPatch(
    algorithm: 4,
    feedback: 0.6,
    ops: [
      FmOp(mul: 1, level: 0.8, decay: 0.4, sustain: 0.5),
      FmOp(mul: 1),
      FmOp(mul: 3, level: 0.4, decay: 0.15, sustain: 0.2),
      FmOp(mul: 0.5, level: 0.7),
    ],
  ),
  'bell': FmPatch(
    algorithm: 4,
    ops: [
      FmOp(mul: 3.5, level: 0.6, decay: 2, sustain: 0.3),
      FmOp(mul: 1, decay: 3, sustain: 0.5),
      FmOp(mul: 7, level: 0.4, decay: 1, sustain: 0.2),
      FmOp(mul: 2, level: 0.5, decay: 2.5, sustain: 0.4),
    ],
  ),
  'growl': FmPatch(
    algorithm: 0,
    feedback: 0.9,
    ops: [
      FmOp(mul: 1, level: 0.7),
      FmOp(mul: 2, level: 0.5),
      FmOp(mul: 1, level: 0.6),
      FmOp(mul: 1),
    ],
  ),
};

class FmVoice extends ChipVoice {
  FmVoice(super.sampleRate, this.patch);

  final FmPatch patch;
  static final Float64List _sine = Float64List.fromList([
    // 10-bit sine table with the chip's limited precision.
    for (var i = 0; i < 1024; i++)
      (math.sin(2 * math.pi * (i + 0.5) / 1024) * 4096).round() / 4096,
  ]);

  final _phase = Float64List(4);
  final _inc = Float64List(4);
  final _env = Float64List(4);
  final _opLevel = Float64List(4);
  final _stage = List<int>.filled(4, 3); // 0 attack, 1 decay, 2 sustain, 3 off
  double _fb1 = 0, _fb2 = 0;
  bool _gate = false;
  double _carrierAmp = 0;

  double _qfreq(double hz) {
    // fnum (11-bit) + block (3-bit): f = fnum * 53267 / 2^(21 - block).
    for (var block = 0; block < 8; block++) {
      final fnum = (hz * (1 << (21 - block)) / _fmRate).round();
      if (fnum < 2048) return fnum * _fmRate / (1 << (21 - block));
    }
    return 2047 * _fmRate / (1 << 14);
  }

  @override
  void latch(double hz, double level, double timbre) {
    final base = _qfreq(hz);
    final carriers = FmPatch.carriers[patch.algorithm];
    for (var i = 0; i < 4; i++) {
      final op = patch.ops[i];
      _inc[i] = base * op.mul * centsToRatio(op.detuneCents) / sampleRate;
      // Shape control = modulator brightness. Levels use 0.75 dB TL steps.
      final raw = carriers[i]
          ? op.level
          : op.level * (0.1 + 1.6 * timbre * timbre);
      _opLevel[i] = _tlQuantize(raw.clamp(0.0, 1.0));
    }
    // Loudness = carrier total level, also in 0.75 dB steps.
    final gate = level > 0.02;
    if (gate && !_gate) {
      for (var i = 0; i < 4; i++) {
        _stage[i] = 0;
      }
    }
    _gate = gate;
    _carrierAmp = gate ? _tlQuantize(level) : _carrierAmp;
  }

  static double _tlQuantize(double amp) {
    if (amp <= 0) return 0;
    final tl = (-20 * math.log(amp) / math.ln10 / 0.75).round().clamp(0, 127);
    return math.pow(10, -tl * 0.75 / 20).toDouble();
  }

  double _op(int i, double modulation) {
    final p = _phase[i] + modulation;
    final idx = ((p - p.floorToDouble()) * 1024).toInt() & 1023;
    _phase[i] += _inc[i];
    if (_phase[i] >= 1) _phase[i] -= 1;
    return _sine[idx] * _env[i] * _opLevel[i];
  }

  void _stepEnvelopes() {
    final dt = 1 / sampleRate;
    for (var i = 0; i < 4; i++) {
      final op = patch.ops[i];
      if (!_gate) {
        _env[i] -= _env[i] * dt / op.release * 4;
        if (_env[i] < 1e-4) _env[i] = 0;
        continue;
      }
      switch (_stage[i]) {
        case 0:
          _env[i] += dt / op.attack;
          if (_env[i] >= 1) {
            _env[i] = 1;
            _stage[i] = 1;
          }
        case 1:
          _env[i] += (op.sustain - _env[i]) * dt / op.decay * 3;
          if ((_env[i] - op.sustain).abs() < 1e-3) _stage[i] = 2;
        default:
          break;
      }
    }
  }

  @override
  double next() {
    _stepEnvelopes();
    const m = 1.5; // modulation depth (cycles) at full modulator level
    final fb = (_fb1 + _fb2) * 0.5 * patch.feedback * 0.8;
    final o1 = _op(0, fb);
    _fb2 = _fb1;
    _fb1 = o1;
    double out;
    switch (patch.algorithm) {
      case 0:
        out = _op(3, _op(2, _op(1, o1 * m) * m) * m);
      case 1:
        final o2 = _op(1, 0);
        out = _op(3, _op(2, (o1 + o2) * m) * m);
      case 2:
        final o3 = _op(2, _op(1, 0) * m);
        out = _op(3, (o1 + o3) * m);
      case 3:
        final o2 = _op(1, o1 * m);
        final o3 = _op(2, 0);
        out = _op(3, (o2 + o3) * m);
      case 4:
        final o2 = _op(1, o1 * m);
        final o4 = _op(3, _op(2, 0) * m);
        out = (o2 + o4) * 0.5;
      case 5:
        out = (_op(1, o1 * m) + _op(2, o1 * m) + _op(3, o1 * m)) / 3;
      case 6:
        out = (_op(1, o1 * m) + _op(2, 0) + _op(3, 0)) / 3;
      default:
        out = (o1 + _op(1, 0) + _op(2, 0) + _op(3, 0)) / 4;
    }
    // 9-bit DAC.
    return (out * _carrierAmp * 256).roundToDouble() / 256;
  }
}

// ---------------------------------------------------------------------------
// Texas Instruments TMS5220 speech chip (LPC), sung by the theremin
// ---------------------------------------------------------------------------

/// TMS5220 pitch table: pitch periods in 8 kHz samples. Only these pitches
/// exist, so the chip sings slightly out of tune.
const tmsPitchPeriods = [
  15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, //
  33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 44, 46, 48, 50, 52, 53, 56, 58, 60,
  62, 65, 68, 70, 72, 76, 78, 80, 84, 86, 91, 94, 98, 101, 105, 109, 114, 118,
  122, 127, 132, 137, 142, 148, 153, 159,
];

/// Vowel formants (F1, F2, F3 in Hz), dark to bright: u, o, a, e, i.
const _vowels = [
  [300.0, 870.0, 2240.0],
  [570.0, 840.0, 2410.0],
  [730.0, 1090.0, 2440.0],
  [530.0, 1840.0, 2480.0],
  [270.0, 2290.0, 3010.0],
];

class SpeechVoice extends ChipVoice {
  SpeechVoice(super.sampleRate, {this.whisper = false});

  final bool whisper;
  static const _rate = 8000.0;
  final _random = math.Random(5220);
  int _period = 100;
  int _pos = 0;
  double _energy = 0;
  final _formants = [600.0, 1200.0, 2500.0];
  final _target = [600.0, 1200.0, 2500.0];
  final _y1 = Float64List(3), _y2 = Float64List(3);
  double _clock = 0;
  double _held = 0;

  @override
  void latch(double hz, double level, double timbre) {
    final want = _rate / hz;
    var best = tmsPitchPeriods.first;
    for (final p in tmsPitchPeriods) {
      if ((p - want).abs() < (best - want).abs()) best = p;
    }
    _period = best;
    _energy = vol4(level) / 15;
    final x = timbre * (_vowels.length - 1);
    final i = x.floor().clamp(0, _vowels.length - 2);
    final t = x - i;
    for (var k = 0; k < 3; k++) {
      _target[k] = _vowels[i][k] * (1 - t) + _vowels[i + 1][k] * t;
    }
  }

  // Chirp-like glottal excitation (designed, in the spirit of the chip's
  // excitation ROM).
  static final Float64List _chirp = Float64List.fromList([
    for (var i = 0; i < 40; i++)
      math.sin(i * 0.9) * math.exp(-i / 7) * (i == 0 ? 0.5 : 1),
  ]);

  double _sample8k() {
    // Formants glide between frames (the chip interpolates its parameters).
    for (var k = 0; k < 3; k++) {
      _formants[k] += (_target[k] - _formants[k]) * 0.01;
    }
    double x;
    if (whisper) {
      x = _random.nextDouble() * 2 - 1;
    } else {
      x = _pos < _chirp.length ? _chirp[_pos] : 0;
      if (++_pos >= _period) _pos = 0;
    }
    for (var k = 0; k < 3; k++) {
      const bw = [80.0, 100.0, 140.0];
      final r = math.exp(-math.pi * bw[k] / _rate);
      final a1 = 2 * r * math.cos(2 * math.pi * _formants[k] / _rate);
      final a2 = -r * r;
      final y = x * (1 - r) + a1 * _y1[k] + a2 * _y2[k];
      _y2[k] = _y1[k];
      _y1[k] = y;
      x = y;
    }
    final out = (x * (whisper ? 40 : 120) * _energy).clamp(-1.0, 1.0);
    // 8-bit DAC.
    return (out * 127).roundToDouble() / 127;
  }

  @override
  double next() {
    _clock += _rate / sampleRate;
    while (_clock >= 1) {
      _clock -= 1;
      _held = _sample8k();
    }
    return _held;
  }
}
