// The synth engine: a chip voice plus the sound driver (frame-rate register
// updates, vibrato, arpeggio), the machine's output stage and effects.
// Pure Dart: runs in the live audio isolate and in the offline renderer.
import 'dart:math' as math;
import 'dart:typed_data';

import 'catalog.dart';
import 'chips.dart';
import 'dsp.dart';

/// Arpeggio patterns (semitone offsets cycled every few frames).
const arpPatterns = <String, List<int>>{
  'off': [0],
  'octave': [0, 12],
  'major': [0, 4, 7],
  'minor': [0, 3, 7],
  'power': [0, 7, 12],
  'sus4': [0, 5, 7],
  'dim': [0, 3, 6],
};

const arpLabels = {
  'off': 'Off',
  'octave': 'Octave',
  'major': 'Major chord',
  'minor': 'Minor chord',
  'power': 'Power chord',
  'sus4': 'Sus4 chord',
  'dim': 'Diminished',
};

/// Everything that defines the sound (not the performance).
class SoundSpec {
  const SoundSpec({
    this.chipId = 'gb',
    this.patchId = 'pulse',
    this.vibratoCents = 0,
    this.vibratoRate = 6,
    this.arp = 'off',
    this.arpFrames = 2,
    this.echoMix = 0,
    this.echoMs = 300,
    this.echoFeedback = 0.4,
    this.crushBits = 0,
    this.crushHold = 1,
    this.master = 0.8,
  });

  final String chipId;
  final String patchId;

  /// Vibrato depth in cents (0 = off) and speed in Hz.
  final double vibratoCents;
  final double vibratoRate;

  /// Key of [arpPatterns] and frames per arpeggio step.
  final String arp;
  final int arpFrames;

  /// Echo wet level (0 = off), delay time and feedback.
  final double echoMix;
  final double echoMs;
  final double echoFeedback;

  /// Bit depth (0 = off) and sample-hold factor of the bitcrusher.
  final int crushBits;
  final int crushHold;

  final double master;

  SoundSpec copyWith({
    String? chipId,
    String? patchId,
    double? vibratoCents,
    double? vibratoRate,
    String? arp,
    int? arpFrames,
    double? echoMix,
    double? echoMs,
    double? echoFeedback,
    int? crushBits,
    int? crushHold,
    double? master,
  }) => SoundSpec(
    chipId: chipId ?? this.chipId,
    patchId: patchId ?? this.patchId,
    vibratoCents: vibratoCents ?? this.vibratoCents,
    vibratoRate: vibratoRate ?? this.vibratoRate,
    arp: arp ?? this.arp,
    arpFrames: arpFrames ?? this.arpFrames,
    echoMix: echoMix ?? this.echoMix,
    echoMs: echoMs ?? this.echoMs,
    echoFeedback: echoFeedback ?? this.echoFeedback,
    crushBits: crushBits ?? this.crushBits,
    crushHold: crushHold ?? this.crushHold,
    master: master ?? this.master,
  );

  Map<String, Object> toJson() => {
    'chip': chipId,
    'patch': patchId,
    'vibCents': vibratoCents,
    'vibRate': vibratoRate,
    'arp': arp,
    'arpFrames': arpFrames,
    'echoMix': echoMix,
    'echoMs': echoMs,
    'echoFb': echoFeedback,
    'crushBits': crushBits,
    'crushHold': crushHold,
    'master': master,
  };

  factory SoundSpec.fromJson(Map<String, Object?> j) {
    double d(String k, double fallback) =>
        (j[k] as num?)?.toDouble() ?? fallback;
    int i(String k, int fallback) => (j[k] as num?)?.toInt() ?? fallback;
    const defaults = SoundSpec();
    return SoundSpec(
      chipId: j['chip'] as String? ?? defaults.chipId,
      patchId: j['patch'] as String? ?? defaults.patchId,
      vibratoCents: d('vibCents', defaults.vibratoCents),
      vibratoRate: d('vibRate', defaults.vibratoRate),
      arp: arpPatterns.containsKey(j['arp']) ? j['arp']! as String : 'off',
      arpFrames: i('arpFrames', defaults.arpFrames),
      echoMix: d('echoMix', defaults.echoMix),
      echoMs: d('echoMs', defaults.echoMs),
      echoFeedback: d('echoFb', defaults.echoFeedback),
      crushBits: i('crushBits', defaults.crushBits),
      crushHold: i('crushHold', defaults.crushHold),
      master: d('master', defaults.master),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SoundSpec &&
      other.chipId == chipId &&
      other.patchId == patchId &&
      other.vibratoCents == vibratoCents &&
      other.vibratoRate == vibratoRate &&
      other.arp == arp &&
      other.arpFrames == arpFrames &&
      other.echoMix == echoMix &&
      other.echoMs == echoMs &&
      other.echoFeedback == echoFeedback &&
      other.crushBits == crushBits &&
      other.crushHold == crushHold &&
      other.master == master;

  @override
  int get hashCode => Object.hash(
    chipId,
    patchId,
    vibratoCents,
    vibratoRate,
    arp,
    arpFrames,
    echoMix,
    echoMs,
    echoFeedback,
    crushBits,
    crushHold,
    master,
  );
}

/// Renders stereo audio from performance controls.
class SynthEngine {
  SynthEngine(this.sampleRate)
    : _echoL = Float32List(sampleRate.toInt()),
      _echoR = Float32List(sampleRate.toInt());

  final double sampleRate;

  /// Loudness every sound is normalized to (RMS).
  static const targetRms = 0.22;
  static final Map<String, double> _norms = {};

  SoundSpec _spec = const SoundSpec();
  late ChipInfo _chip = chipById(_spec.chipId);
  late PatchInfo _patch = _chip.patch(_spec.patchId);
  ChipVoice? _voice;
  late HighPass _hp;
  late LowPass _lp;
  double _norm = 1;

  double _hz = 220;
  double _level = 0;
  double _timbre = 0.5;

  double _framePos = 0;
  int _frame = 0;
  double _vibPhase = 0;

  final Float32List _echoL, _echoR;
  int _echoPos = 0;
  int _holdCount = 0;
  double _held = 0;

  /// Recent mono output for an oscilloscope display.
  final Float32List scope = Float32List(512);
  int _scopePos = 0;

  SoundSpec get spec => _spec;

  void configure(SoundSpec spec) {
    final newVoice =
        _voice == null ||
        spec.chipId != _spec.chipId ||
        spec.patchId != _spec.patchId;
    _spec = spec;
    if (newVoice) {
      _chip = chipById(spec.chipId);
      _patch = _chip.patch(spec.patchId);
      _voice = _chip.create(_patch.id, sampleRate);
      _hp = HighPass(_chip.highPassHz, sampleRate);
      _lp = LowPass(_chip.lowPassHz, sampleRate);
      _norm = normalization(_chip, _patch, sampleRate);
      _framePos = 0;
      _onFrame();
    }
  }

  /// Sets the performance: pitch in Hz, loudness and shape (0–1).
  void setControls(double hz, double level, double timbre) {
    _hz = hz;
    _level = level;
    _timbre = timbre;
  }

  /// Gain that brings [patch] to [targetRms]; measured once per sound.
  static double normalization(ChipInfo chip, PatchInfo patch, double rate) {
    return _norms.putIfAbsent('${chip.id}/${patch.id}/$rate', () {
      final voice = chip.create(patch.id, rate);
      final hp = HighPass(chip.highPassHz, rate);
      final lp = LowPass(chip.lowPassHz, rate);
      final hz = 220 * math.pow(2, patch.transpose / 12).toDouble();
      final total = (rate * 0.5).toInt();
      final skip = (rate * 0.1).toInt();
      final perFrame = rate / chip.fps;
      var sum = 0.0;
      var next = 0.0;
      for (var i = 0; i < total; i++) {
        if (i >= next) {
          voice.latch(hz, 1, 0.5);
          next += perFrame;
        }
        final y = lp.process(hp.process(voice.next()));
        if (i >= skip) sum += y * y;
      }
      final rms = math.sqrt(sum / (total - skip));
      return rms < 1e-6 ? 1 : (targetRms / rms).clamp(0.2, 12.0);
    });
  }

  void _onFrame() {
    _frame++;
    var semis = _patch.transpose.toDouble();
    final arp = arpPatterns[_spec.arp] ?? const [0];
    if (arp.length > 1) {
      final step = (_frame ~/ math.max(1, _spec.arpFrames)) % arp.length;
      semis += arp[step];
    }
    var cents = 0.0;
    if (_spec.vibratoCents > 0) {
      // Frame-stepped triangle vibrato, as sound drivers did it.
      _vibPhase += _spec.vibratoRate / _chip.fps;
      _vibPhase -= _vibPhase.floorToDouble();
      cents = _spec.vibratoCents * (4 * (_vibPhase - 0.5).abs() - 1);
    }
    final hz = _hz * math.pow(2, semis / 12) * centsToRatio(cents);
    _voice!.latch(hz.clamp(20.0, 12000.0), _level, _timbre);
  }

  /// Renders [frames] stereo frames into [out] (interleaved L, R).
  void render(Float32List out, int frames, {int offset = 0}) {
    final voice = _voice;
    if (voice == null) {
      configure(_spec);
      return render(out, frames, offset: offset);
    }
    final frameStep = _chip.fps / sampleRate;
    final s = _spec;
    final crushLevels = s.crushBits > 0 ? (1 << s.crushBits) / 2 : 0.0;
    final echoLen = (s.echoMs / 1000 * sampleRate).round().clamp(
      1,
      _echoL.length - 1,
    );
    for (var i = 0; i < frames; i++) {
      _framePos += frameStep;
      if (_framePos >= 1) {
        _framePos -= 1;
        _onFrame();
      }
      var x = _lp.process(_hp.process(voice.next())) * _norm;

      if (s.crushBits > 0 || s.crushHold > 1) {
        if (_holdCount <= 0) {
          _held = crushLevels > 0
              ? (x * crushLevels).roundToDouble() / crushLevels
              : x;
          _holdCount = s.crushHold;
        }
        _holdCount--;
        x = _held;
      }

      var l = x, r = x;
      if (s.echoMix > 0) {
        var read = _echoPos - echoLen;
        if (read < 0) read += _echoL.length;
        final dl = _echoL[read];
        final dr = _echoR[read];
        // Ping-pong: each repeat swaps sides.
        _echoL[_echoPos] = x + dr * s.echoFeedback;
        _echoR[_echoPos] = dl * s.echoFeedback;
        l += dl * s.echoMix;
        r += dr * s.echoMix;
      } else {
        _echoL[_echoPos] = 0;
        _echoR[_echoPos] = 0;
      }
      if (++_echoPos >= _echoL.length) _echoPos = 0;

      l = softClip(l * s.master * 1.4);
      r = softClip(r * s.master * 1.4);
      out[(offset + i) * 2] = l;
      out[(offset + i) * 2 + 1] = r;
      scope[_scopePos] = (l + r) * 0.5;
      if (++_scopePos >= scope.length) _scopePos = 0;
    }
  }

  /// The scope buffer in time order.
  Float32List scopeSnapshot() {
    final n = scope.length;
    final out = Float32List(n);
    for (var i = 0; i < n; i++) {
      out[i] = scope[(_scopePos + i) % n];
    }
    return out;
  }
}
