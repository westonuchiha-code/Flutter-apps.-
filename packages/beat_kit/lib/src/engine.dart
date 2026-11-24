import 'dart:math' as math;
import 'dart:typed_data';

import 'pad.dart';
import 'transport.dart';

const padCount = 16;
const maxSteps = 32;

// ---- Commands (sent from the UI isolate) ----

sealed class BeatCommand {
  const BeatCommand();
}

/// Mono samples at the engine rate (null clears the pad).
class SetSample extends BeatCommand {
  const SetSample(this.pad, this.data);
  final int pad;
  final Float32List? data;
}

class SetPad extends BeatCommand {
  const SetPad(this.pad, this.settings);
  final int pad;
  final PadSettings settings;
}

/// One bit mask per pad (bit n = step n) and the pattern length.
class SetPattern extends BeatCommand {
  const SetPattern(this.masks, this.steps);
  final List<int> masks;
  final int steps;
}

class SetTempo extends BeatCommand {
  const SetTempo(this.bpm, this.swing);
  final double bpm, swing;
}

class SetPlaying extends BeatCommand {
  const SetPlaying(this.playing);
  final bool playing;
}

class Trigger extends BeatCommand {
  const Trigger(this.pad);
  final int pad;
}

class Release extends BeatCommand {
  const Release(this.pad);
  final int pad;
}

class SetMaster extends BeatCommand {
  const SetMaster(this.gain);
  final double gain;
}

/// A loop layer: [data] plays looped, its first frame on bars where
/// `bar % (data.length / barFrames) == startBar % ...`.
class AddLayer extends BeatCommand {
  const AddLayer(this.id, this.data, this.startBar, {this.gain = 1});
  final int id;
  final Float32List data;
  final int startBar;
  final double gain;
}

class SetLayer extends BeatCommand {
  const SetLayer(this.id, {required this.gain, required this.muted});
  final int id;
  final double gain;
  final bool muted;
}

class RemoveLayer extends BeatCommand {
  const RemoveLayer(this.id);
  final int id;
}

// ---- Events (sent back to the UI) ----

/// A step started. [frame] is the song frame (since play) it starts at.
class StepEvent {
  const StepEvent(this.step, this.songStep, this.frame);

  /// Position in the pattern.
  final int step;

  /// Steps since play (bar = songStep ~/ 16).
  final int songStep;
  final int frame;

  int get bar => songStep ~/ Transport.stepsPerBar;
  bool get isBarStart => songStep % Transport.stepsPerBar == 0;
}

/// Pads that started or stopped sounding (bit masks), for lighting pads.
class PadActivity {
  const PadActivity(this.active);
  final int active;
}

// ---- Engine ----

class _Voice {
  _Voice(
    this.pad,
    this.data,
    this.lo,
    this.hi,
    this.rate,
    this.forward,
    this.gainL,
    this.gainR,
    this.mode,
  ) : pos = forward ? lo : hi - 1;

  final int pad;
  final Float32List data;
  final double lo, hi; // region in sample frames
  final double rate;
  final bool forward;
  final double gainL, gainR;
  final PadMode mode;
  double pos;
  bool releasing = false;
  double fade = 1;
  bool done = false;
}

class _Layer {
  _Layer(this.id, this.data, this.startBar, this.gain);
  final int id;
  final Float32List data;
  final int startBar;
  double gain;
  bool muted = false;
}

/// Mixes pads, sequencer and loop layers into interleaved stereo floats.
/// Lives in the audio isolate; everything is sample-accurate.
class BeatEngine {
  BeatEngine({this.sampleRate = 48000});

  final int sampleRate;
  final samples = List<Float32List?>.filled(padCount, null);
  final pads = List<PadSettings>.filled(padCount, const PadSettings());
  List<int> masks = List.filled(padCount, 0);
  int steps = 16;
  Transport transport = const Transport();
  bool playing = false;
  double master = 0.8;

  final _voices = <_Voice>[];
  final _layers = <_Layer>[];
  int _songFrame = 0;
  int _songStep = -1;
  int _lastActive = 0;
  int _triggered = 0;

  /// Fade length for cuts and releases (no clicks).
  static const _fadeFrames = 96;

  /// Fade at sample/trim edges and loop seams (short, keeps attacks).
  static const _edgeFrames = 24;
  static const _maxVoices = 32;

  int get songFrame => _songFrame;

  void handle(BeatCommand c) {
    switch (c) {
      case SetSample(:final pad, :final data):
        _cut(pad);
        samples[pad] = data;
      case SetPad(:final pad, :final settings):
        pads[pad] = settings;
      case SetPattern(:final masks, :final steps):
        this.masks = List.of(masks);
        this.steps = steps.clamp(1, maxSteps);
      case SetTempo(:final bpm, :final swing):
        transport = Transport(
          bpm: bpm.clamp(30, 300),
          swing: swing.clamp(0, 0.5),
          sampleRate: sampleRate,
        );
      case SetPlaying(:final playing):
        if (playing && !this.playing) {
          _songFrame = 0;
          _songStep = -1;
        }
        if (!playing) {
          for (final v in _voices) {
            v.releasing = true;
          }
        }
        this.playing = playing;
      case Trigger(:final pad):
        _trigger(pad, fromUser: true);
      case Release(:final pad):
        for (final v in _voices) {
          if (v.pad == pad && v.mode != PadMode.oneShot) v.releasing = true;
        }
      case SetMaster(:final gain):
        master = gain.clamp(0, 1);
      case AddLayer(:final id, :final data, :final startBar, :final gain):
        _layers.add(_Layer(id, data, startBar, gain));
      case SetLayer(:final id, :final gain, :final muted):
        for (final l in _layers) {
          if (l.id == id) {
            l
              ..gain = gain
              ..muted = muted;
          }
        }
      case RemoveLayer(:final id):
        _layers.removeWhere((l) => l.id == id);
    }
  }

  void _cut(int pad) {
    for (final v in _voices) {
      if (v.pad == pad) v.releasing = true;
    }
  }

  void _trigger(int pad, {bool fromUser = false}) {
    final data = samples[pad];
    if (data == null || data.isEmpty) return;
    final s = pads[pad];
    // Tapping a looping pad again stops it.
    if (fromUser && s.mode == PadMode.loop) {
      final looping = _voices.any(
        (v) => v.pad == pad && v.mode == PadMode.loop && !v.releasing,
      );
      if (looping) {
        _cut(pad);
        return;
      }
    }
    _cut(pad); // one voice per pad
    final lo = (s.start * data.length).clamp(0, data.length - 1).toDouble();
    final hi = (s.end * data.length).clamp(lo + 1, data.length).toDouble();
    final angle = (s.pan.clamp(-1, 1) + 1) * math.pi / 4; // equal power
    final g = s.volume;
    _triggered |= 1 << pad;
    if (_voices.length >= _maxVoices) _voices.removeAt(0);
    _voices.add(
      _Voice(
        pad,
        data,
        lo,
        hi,
        math.pow(2, s.pitch / 12).toDouble(),
        !s.reverse,
        g * math.cos(angle),
        g * math.sin(angle),
        s.mode,
      ),
    );
  }

  /// Fills [out] (interleaved stereo) with [frames] frames.
  void render(Float32List out, int frames, [void Function(Object? e)? emit]) {
    out.fillRange(0, frames * 2, 0);
    var at = 0;
    while (at < frames) {
      var chunk = frames - at;
      if (playing) {
        final next = _songStep + 1;
        final until = transport.stepStart(next) - _songFrame;
        if (until <= 0) {
          _songStep = next;
          final step = next % steps;
          for (var p = 0; p < padCount; p++) {
            if ((masks[p] >> step) & 1 == 1) _trigger(p);
          }
          emit?.call(StepEvent(step, next, _songFrame));
          continue;
        }
        chunk = math.min(chunk, until);
      }
      _mixVoices(out, at, chunk);
      if (playing) {
        _mixLayers(out, at, chunk);
        _songFrame += chunk;
      }
      at += chunk;
    }
    _voices.removeWhere((v) => v.done);
    final g = master;
    for (var i = 0; i < frames * 2; i++) {
      final x = out[i] * g;
      // Gentle limiter: transparent below ~0.8, never hard-clips.
      out[i] = x.abs() < 0.8
          ? x
          : x.sign * (0.8 + 0.2 * _tanh((x.abs() - 0.8) / 0.2));
    }
    var active = _triggered;
    _triggered = 0;
    for (final v in _voices) {
      if (!v.releasing) active |= 1 << v.pad;
    }
    if (active != _lastActive) {
      _lastActive = active;
      emit?.call(PadActivity(active));
    }
  }

  static double _tanh(double x) {
    final e = math.exp(2 * x);
    return (e - 1) / (e + 1);
  }

  void _mixVoices(Float32List out, int at, int n) {
    for (final v in _voices) {
      if (v.done) continue;
      final d = v.data;
      final step = v.forward ? v.rate : -v.rate;
      for (var i = 0; i < n; i++) {
        if (v.forward ? v.pos >= v.hi - 1 : v.pos < v.lo) {
          if (v.mode == PadMode.loop && !v.releasing) {
            v.pos = v.forward ? v.lo : v.hi - 1;
          } else {
            v.done = true;
            break;
          }
        }
        final p = v.pos;
        final i0 = p.floor();
        final frac = p - i0;
        final a = d[i0];
        final b = i0 + 1 < d.length ? d[i0 + 1] : a;
        var s = a + (b - a) * frac;
        // Fade near region edges (trim points, loop seam).
        final edge = math.min(p - v.lo, v.hi - 1 - p) / v.rate;
        if (edge < _edgeFrames) s *= math.max(0, edge + 1) / (_edgeFrames + 1);
        if (v.releasing) {
          v.fade -= 1 / _fadeFrames;
          if (v.fade <= 0) {
            v.done = true;
            break;
          }
          s *= v.fade;
        }
        final o = (at + i) * 2;
        out[o] += s * v.gainL;
        out[o + 1] += s * v.gainR;
        v.pos = p + step;
      }
    }
  }

  void _mixLayers(Float32List out, int at, int n) {
    final bar = transport.barFrames;
    for (final l in _layers) {
      if (l.muted || l.gain <= 0) continue;
      final len = l.data.length;
      final bars = math.max(1, (len / bar).round());
      final offset = (l.startBar % bars) * bar;
      final g = l.gain * 0.7071; // centred
      for (var i = 0; i < n; i++) {
        final idx = (_songFrame + i - offset) % len;
        final s = l.data[idx] * g;
        final o = (at + i) * 2;
        out[o] += s;
        out[o + 1] += s;
      }
    }
  }
}
