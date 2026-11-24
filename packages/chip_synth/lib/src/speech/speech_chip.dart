// Three classic speech chips sharing one formant engine. Each keeps its own
// sample rate, parameter update rate, excitation, number precision, pitch
// steps and output filter: they are recreations from public descriptions of
// the hardware, not copies of the chips' internal speech data.
import 'dart:math' as math;
import 'dart:typed_data';

import '../chips.dart' show tmsPitchPeriods;
import '../dsp.dart';
import 'phonemes.dart';
import 'text.dart';

enum SpeechChip {
  tms5220(
    'TI TMS5220',
    'LPC speech, 8 kHz, 25 ms frames with smooth steps, 16 loudness steps, '
        'the TMS pitch table, chirp excitation, 8-bit output.',
    8000,
    25,
    3800,
  ),
  sp0256(
    'GI SP0256',
    'Allophone chip, 10 kHz, 10 ms frames that jump (no smoothing), '
        'pulse excitation, 8-bit filter numbers, 7-bit output.',
    10000,
    10,
    4500,
  ),
  votrax(
    'Votrax SC-01',
    'Analog formant filters, smooth glides, only 4 pitch steps; the clock '
        'sets pitch, voice size and speed together.',
    20000,
    5,
    5000,
  );

  const SpeechChip(
    this.label,
    this.about,
    this.rate,
    this.frameMs,
    this.lowPassHz,
  );
  final String label;
  final String about;

  /// Internal sample rate (Hz).
  final int rate;

  /// How often the chip takes new settings.
  final int frameMs;

  /// The machine's output filter.
  final double lowPassHz;

  static SpeechChip byName(Object? n) =>
      values.firstWhere((c) => c.name == n, orElse: () => tms5220);
}

enum Contour {
  flat('Flat (robot)'),
  statement('Statement'),
  question('Question');

  const Contour(this.label);
  final String label;
}

class SpeechSettings {
  const SpeechSettings({
    this.chip = SpeechChip.tms5220,
    this.pitch = 110,
    this.speed = 1,
    this.contour = Contour.statement,
    this.whisper = false,
  });

  final SpeechChip chip;

  /// Base voice pitch in Hz (on the Votrax: the clock, which also changes
  /// voice size and speed).
  final double pitch;

  /// 0.5 (slow) .. 2 (fast).
  final double speed;
  final Contour contour;
  final bool whisper;

  SpeechSettings copyWith({
    SpeechChip? chip,
    double? pitch,
    double? speed,
    Contour? contour,
    bool? whisper,
  }) => SpeechSettings(
    chip: chip ?? this.chip,
    pitch: pitch ?? this.pitch,
    speed: speed ?? this.speed,
    contour: contour ?? this.contour,
    whisper: whisper ?? this.whisper,
  );

  Map<String, Object?> toJson() => {
    'chip': chip.name,
    'pitch': pitch,
    'speed': speed,
    'contour': contour.name,
    'whisper': whisper,
  };

  factory SpeechSettings.fromJson(Object? j) {
    if (j is! Map) return const SpeechSettings();
    return SpeechSettings(
      chip: SpeechChip.byName(j['chip']),
      pitch: ((j['pitch'] as num?) ?? 110).toDouble().clamp(50, 400),
      speed: ((j['speed'] as num?) ?? 1).toDouble().clamp(0.4, 2.5),
      contour: Contour.values.firstWhere(
        (c) => c.name == j['contour'],
        orElse: () => Contour.statement,
      ),
      whisper: j['whisper'] == true,
    );
  }
}

/// Target settings for a stretch of speech.
class _Seg {
  _Seg(
    this.f,
    this.voice,
    this.noise,
    this.noiseHz,
    this.ms, {
    this.hold = false,
    this.wordStart = false,
  });
  final List<double> f; // F1..F3
  final double voice, noise, noiseHz, ms;
  final bool hold;
  final bool wordStart;
  int frames = 0; // in chip samples
}

/// TMS5220 energy table (16 steps; the last code means "stop").
const _tmsEnergy = [0, 1, 2, 3, 4, 6, 8, 11, 16, 23, 33, 47, 63, 85, 114];

/// Speaks phoneme sequences on an emulated speech chip.
class SpeechSynth {
  SpeechSynth(this.outRate);

  final double outRate;
  SpeechSettings settings = const SpeechSettings();

  final _segs = <_Seg>[];
  int _seg = 0, _segPos = 0, _total = 1, _elapsed = 0;
  bool _holding = false;
  double? _singHz;

  // Current and target parameters: F1..F3, voice, noise, noiseHz.
  final _cur = Float64List(6), _from = Float64List(6), _to = Float64List(6);
  int _framePos = 1 << 30;
  int _frameLen = 200;
  int _pitchPos = 0;
  int _period = 80;
  final _rnd = math.Random(5220);
  int _lfsr = 0x1fff;
  final _y1 = Float64List(4), _y2 = Float64List(4);
  double _clock = 0;
  double _held = 0;
  HighPass _hp = HighPass(90, 48000);
  LowPass _lp = LowPass(3800, 48000);
  SpeechChip? _filtersFor;

  /// Chip samples that hit full scale (tests check this stays rare).
  int clipped = 0;

  bool get busy => _seg < _segs.length;

  /// Index of the word being spoken (-1 before the first).
  int wordIndex = -1;
  bool get holding => _holding && busy;

  /// Says [words] with [s].
  void speak(List<SpokenWord> words, SpeechSettings s) {
    settings = s;
    _singHz = null;
    _holding = false;
    _load([
      for (final w in words) ...[
        ..._segments(w.phonemes, s, wordStart: true),
        if (w.pauseAfter.isNotEmpty) ..._segments([w.pauseAfter], s),
      ],
    ]);
  }

  /// Sings one word at [hz]; its last vowel holds until [releaseWord].
  void singWord(SpokenWord w, double hz, SpeechSettings s) {
    settings = s;
    _singHz = hz;
    final segs = _segments(w.phonemes, s, wordStart: true);
    var last = -1;
    for (var i = 0; i < segs.length; i++) {
      if (segs[i].voice > 0.9 || (segs[i].voice > 0 && segs[i].noise == 0)) {
        last = i;
      }
    }
    if (last >= 0) {
      final v = segs[last];
      segs[last] = _Seg(
        v.f,
        v.voice,
        v.noise,
        v.noiseHz,
        v.ms,
        hold: true,
        wordStart: v.wordStart,
      );
    }
    _holding = true;
    _load(segs);
  }

  /// Changes the sung pitch (e.g. sliding to another key).
  void setSingPitch(double hz) => _singHz = hz;

  void releaseWord() => _holding = false;

  void stop() {
    _segs.clear();
    _seg = 0;
    _holding = false;
  }

  void _load(List<_Seg> segs) {
    final chip = settings.chip;
    final speed =
        settings.speed * (chip == SpeechChip.votrax ? settings.pitch / 110 : 1);
    for (final s in segs) {
      s.frames = math.max(1, (s.ms / speed / 1000 * chip.rate).round());
    }
    _segs
      ..clear()
      ..addAll(segs);
    _seg = 0;
    _segPos = 0;
    _elapsed = 0;
    wordIndex = segs.isNotEmpty && segs.first.wordStart ? 0 : -1;
    _total = math.max(1, segs.fold(0, (a, s) => a + s.frames));
    _frameLen = (chip.frameMs / 1000 * chip.rate).round();
    _framePos = _frameLen; // take new settings right away
    if (_filtersFor != chip) {
      _filtersFor = chip;
      _hp = HighPass(80, outRate);
      _lp = LowPass(chip.lowPassHz, outRate);
    }
  }

  /// Phonemes → target segments.
  static List<_Seg> _segments(
    List<String> codes,
    SpeechSettings s, {
    bool wordStart = false,
  }) {
    final out = <_Seg>[];
    var first = wordStart;
    for (var i = 0; i < codes.length; i++) {
      final p = phonemes[codes[i]];
      if (p == null) continue;
      // The next vowel's shape (for H and stop releases).
      Phoneme? nextVowel;
      for (var k = i + 1; k < codes.length; k++) {
        final q = phonemes[codes[k]];
        if (q != null && q.isVowel) {
          nextVowel = q;
          break;
        }
      }
      final f = [p.f1, p.f2, p.f3];
      final nf = nextVowel == null
          ? f
          : [nextVowel.f1, nextVowel.f2, nextVowel.f3];
      final voice = s.whisper ? 0.0 : p.voice;
      // Whispering turns the voice into breath through the same shape.
      final breath = s.whisper ? p.voice * 0.7 : 0.0;
      _Seg seg(
        List<double> ff,
        double v,
        double n,
        double nHz,
        double ms, {
        bool asp = false,
      }) {
        final x = _Seg(
          ff,
          v,
          n + (asp ? 0 : breath),
          asp ? 0 : nHz,
          ms,
          wordStart: first,
        );
        first = false;
        return x;
      }

      switch (p.kind) {
        case PhonemeKind.vowel:
        case PhonemeKind.approximant:
        case PhonemeKind.nasal:
          out.add(seg(f, voice, 0, 0, p.ms));
        case PhonemeKind.diphthong:
          final g = phonemes[p.glideTo]!;
          out
            ..add(seg(f, voice, 0, 0, p.ms * 0.55))
            ..add(seg([g.f1, g.f2, g.f3], voice, 0, 0, p.ms * 0.45));
        case PhonemeKind.fricative:
          if (p.noiseHz == 0) {
            // H: breath shaped like the vowel that follows.
            out.add(seg(nf, 0, p.noise, 0, p.ms, asp: true));
          } else {
            out.add(seg(f, voice, p.noise, p.noiseHz, p.ms));
          }
        case PhonemeKind.stop:
          out
            ..add(seg(f, p.voicedStop ? voice * 0.25 : 0, 0, 0, p.ms * 0.55))
            ..add(seg(f, 0, p.noise, p.burstHz, 15));
          if (!p.voicedStop) {
            out.add(seg(nf, 0, p.noise * 0.5, 0, 35, asp: true));
          }
        case PhonemeKind.affricate:
          out
            ..add(seg(f, p.voicedStop ? voice * 0.25 : 0, 0, 0, 40))
            ..add(seg(f, 0, p.noise, p.burstHz, 10))
            ..add(seg(f, voice, p.noise, p.noiseHz, p.ms - 50));
        case PhonemeKind.pause:
          out.add(seg(f, 0, 0, 0, p.ms));
      }
    }
    return out;
  }

  double _pitchNow() {
    final s = settings;
    final sing = _singHz;
    if (sing != null) return sing;
    final t = _elapsed / _total;
    final shape = switch (s.contour) {
      Contour.flat => 1.0,
      Contour.statement => 1.12 - 0.27 * t,
      Contour.question => t < 0.7 ? 1.0 - 0.08 * t : 0.95 + (t - 0.7) * 1.6,
    };
    return s.pitch * shape;
  }

  /// Chip pitch steps: TMS table, SP0256 whole samples, Votrax 4 levels.
  /// The chip's pitch period (in chip samples) for [hz].
  int periodFor(double hz) {
    final chip = settings.chip;
    final want = chip.rate / hz;
    switch (chip) {
      case SpeechChip.tms5220:
        var best = tmsPitchPeriods.first;
        for (final p in tmsPitchPeriods) {
          if ((p - want).abs() < (best - want).abs()) best = p;
        }
        return best;
      case SpeechChip.sp0256:
        return want.round().clamp(16, 255);
      case SpeechChip.votrax:
        // Inflection is only 2 bits: the clock (base pitch) times 4 steps.
        final base = _singHz ?? settings.pitch;
        final ratio = (hz / base).clamp(0.85, 1.3);
        const steps = [0.9, 1.0, 1.1, 1.2];
        var k = 0;
        for (var i = 1; i < 4; i++) {
          if ((steps[i] - ratio).abs() < (steps[k] - ratio).abs()) k = i;
        }
        return (chip.rate / (base * steps[k])).round().clamp(20, 2000);
    }
  }

  double _energyStep(double e) {
    switch (settings.chip) {
      case SpeechChip.tms5220:
        final want = e * 114;
        var best = 0;
        for (final v in _tmsEnergy) {
          if ((v - want).abs() < (best - want).abs()) best = v;
        }
        return best / 114;
      case SpeechChip.sp0256:
        return (e * 31).round() / 31;
      case SpeechChip.votrax:
        return (e * 15).round() / 15;
    }
  }

  void _newFrame() {
    _framePos = 0;
    final chip = settings.chip;
    final s = _seg < _segs.length ? _segs[_seg] : null;
    // Votrax: the clock moves the formants too (bigger or smaller "head").
    final scale = chip == SpeechChip.votrax
        ? (_singHz ?? settings.pitch) / 110
        : 1.0;
    final target = s == null
        ? [_cur[0], _cur[1], _cur[2], 0.0, 0.0, _cur[5]]
        : [
            s.f[0] * scale,
            s.f[1] * scale,
            s.f[2] * scale,
            _energyStep(
              s.voice *
                  _shapeNorm(s.f[0] * scale, s.f[1] * scale, s.f[2] * scale),
            ),
            _energyStep(s.noise),
            s.noiseHz,
          ];
    for (var k = 0; k < 6; k++) {
      _from[k] = _cur[k];
      _to[k] = target[k];
    }
    if (chip == SpeechChip.sp0256) {
      // No interpolation: settings jump each frame.
      for (var k = 0; k < 6; k++) {
        _cur[k] = _to[k];
      }
    }
  }

  /// How much louder than an "AH" this vocal-tract shape makes the voice;
  /// the chips' stored loudness already allowed for it, so we divide it out.
  double _shapeNorm(double f1, double f2, double f3) {
    final rate = settings.chip.rate.toDouble();
    double peakGain(double a, double b, double c) {
      var best = 0.0;
      for (final w in [a, b]) {
        var g = 1.0;
        for (final (f, bw) in [(a, 90.0), (b, 110.0), (c, 170.0)]) {
          final ff = f.clamp(50, rate * 0.45);
          final r = math.exp(-math.pi * bw / rate);
          final a1 = 2 * r * math.cos(2 * math.pi * ff / rate);
          final a2 = -r * r;
          final om = 2 * math.pi * w.clamp(50, rate * 0.45) / rate;
          // |1 - a1 e^-jw - a2 e^-2jw|
          final re = 1 - a1 * math.cos(om) - a2 * math.cos(2 * om);
          final im = a1 * math.sin(om) + a2 * math.sin(2 * om);
          g *= (1 - a1 - a2).abs() / math.sqrt(re * re + im * im);
        }
        best = math.max(best, g);
      }
      return best;
    }

    final ref = peakGain(640, 1190, 2390);
    final g = peakGain(f1, f2, f3);
    return math.pow(ref / g, 0.7).clamp(0.2, 1.0).toDouble();
  }

  double _resonate(int k, double x, double hz, double bw) {
    final rate = settings.chip.rate.toDouble();
    final f = hz.clamp(50, rate * 0.45);
    final r = math.exp(-math.pi * bw / rate);
    var a1 = 2 * r * math.cos(2 * math.pi * f / rate);
    var a2 = -r * r;
    switch (settings.chip) {
      case SpeechChip.tms5220:
        a1 = (a1 * 512).round() / 512; // 10-bit coefficients
        a2 = (a2 * 512).round() / 512;
      case SpeechChip.sp0256:
        a1 = (a1 * 128).round() / 128; // 8-bit coefficients
        a2 = (a2 * 128).round() / 128;
      case SpeechChip.votrax:
        break;
    }
    final y = (1 - a1 - a2) * x + a1 * _y1[k] + a2 * _y2[k];
    _y2[k] = _y1[k];
    _y1[k] = y;
    return y;
  }

  // Chirp-like glottal pulse (the same designed pulse as the theremin's
  // speech voice).
  static final Float64List _chirp = Float64List.fromList([
    for (var i = 0; i < 40; i++)
      math.sin(i * 0.9) * math.exp(-i / 7) * (i == 0 ? 0.5 : 1),
  ]);

  double get _pulseScale => math.sqrt(_period / (settings.chip.rate / 110));

  double _glottal() {
    final p = _pitchPos;
    switch (settings.chip) {
      // Pulse chips: bigger pulses for lower voices, so loudness stays the
      // same at any pitch (the chips' energy setting did this).
      case SpeechChip.tms5220:
        return p < _chirp.length ? _chirp[p] * 2.2 * _pulseScale : 0;
      case SpeechChip.sp0256:
        return p == 0 ? 6.0 * _pulseScale : 0; // one pulse per period
      case SpeechChip.votrax:
        // Rising ramp then a sharp drop, in 16 steps.
        final ph = p / _period;
        return ((ph < 0.7 ? ph / 0.7 : (1 - ph) / 0.3) * 15).round() /
                15 *
                1.6 -
            0.5;
    }
  }

  /// Level per chip so the three sound about equally loud.
  double get _voiceGain => switch (settings.chip) {
    SpeechChip.tms5220 => 0.12,
    SpeechChip.sp0256 => 0.105,
    SpeechChip.votrax => 0.36,
  };

  double get _breathGain => switch (settings.chip) {
    SpeechChip.tms5220 => 0.35,
    SpeechChip.sp0256 => 0.6,
    SpeechChip.votrax => 0.8,
  };

  double _noise() {
    if (settings.chip == SpeechChip.tms5220) {
      // 13-bit LFSR, ±1 like the chip's unvoiced excitation.
      final bit = ((_lfsr >> 0) ^ (_lfsr >> 3)) & 1;
      _lfsr = (_lfsr >> 1) | (bit << 12);
      return bit == 1 ? 1.0 : -1.0;
    }
    return _rnd.nextDouble() * 2 - 1;
  }

  double _chipSample() {
    final chip = settings.chip;
    if (_framePos >= _frameLen) _newFrame();
    final t = (_framePos + 1) / _frameLen;
    _framePos++;
    switch (chip) {
      case SpeechChip.tms5220:
        // Interpolates in 8 steps across the frame.
        final step = ((t * 8).ceil() / 8).clamp(0.0, 1.0);
        for (var k = 0; k < 6; k++) {
          _cur[k] = _from[k] + (_to[k] - _from[k]) * step;
        }
      case SpeechChip.votrax:
        for (var k = 0; k < 6; k++) {
          _cur[k] += (_to[k] - _cur[k]) * 0.004; // analog glide (~12 ms)
        }
      case SpeechChip.sp0256:
        break;
    }
    if (busy) {
      final seg = _segs[_seg];
      final hold = seg.hold && _holding;
      if (!hold) {
        _segPos++;
        _elapsed++;
        if (_segPos >= seg.frames) {
          _seg++;
          _segPos = 0;
          if (_seg < _segs.length && _segs[_seg].wordStart) wordIndex++;
        }
      }
    }
    if (++_pitchPos >= _period) {
      _pitchPos = 0;
      _period = periodFor(_pitchNow());
    }
    final voice = _cur[3], noise = _cur[4], noiseHz = _cur[5];
    final n = _noise();
    // Voice and breath go through the formants; hiss has its own filter.
    var x = _glottal() * voice + (noiseHz == 0 ? n * noise * _breathGain : 0);
    x = _resonate(0, x, _cur[0], 90);
    x = _resonate(1, x, _cur[1], 110);
    x = _resonate(2, x, _cur[2], 170);
    // Headroom: the loudest vowels stay below full scale.
    var out = x * _voiceGain;
    if (noiseHz > 0 && noise > 0) {
      out += _resonate(3, n * noise, noiseHz, noiseHz * 0.6) * 0.18;
    }
    if (out.abs() > 1) clipped++;
    // Rare overloads (a high voice landing on a low resonance) round off
    // gently instead of clipping hard.
    if (out.abs() > 0.9) {
      final over = out.abs() - 0.9;
      out = out.sign * (0.9 + 0.1 * over / (over + 0.1));
    }
    // The chip's DAC.
    return switch (chip) {
      SpeechChip.tms5220 => (out * 127).roundToDouble() / 127,
      SpeechChip.sp0256 => (out * 63).roundToDouble() / 63,
      SpeechChip.votrax => out,
    };
  }

  /// Fills [out] (mono, at [outRate]).
  void render(Float32List out, int frames, {int offset = 0}) {
    final ratio = settings.chip.rate / outRate;
    for (var i = 0; i < frames; i++) {
      _clock += ratio;
      while (_clock >= 1) {
        _clock -= 1;
        _held = _chipSample();
      }
      out[offset + i] = _lp.process(_hp.process(_held));
    }
  }
}

/// Renders [words] to mono samples at [rate] (plus a short tail).
Float32List renderSpeech(
  List<SpokenWord> words,
  SpeechSettings s, {
  double rate = 48000,
}) {
  final synth = SpeechSynth(rate)..speak(words, s);
  final chunks = <Float32List>[];
  var total = 0;
  const block = 1024;
  var tail = (0.15 * rate).round();
  while (tail > 0) {
    final b = Float32List(block);
    synth.render(b, block);
    chunks.add(b);
    total += block;
    if (!synth.busy) tail -= block;
    if (total > rate * 120) break; // two minutes at most
  }
  final out = Float32List(total);
  var at = 0;
  for (final c in chunks) {
    out.setAll(at, c);
    at += c.length;
  }
  return out;
}
