import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:chip_synth/chip_synth.dart';

/// Performance controls are captured this many times per second.
const controlRate = 100;

/// A sound change during a recording, at a control frame index.
class SpecChange {
  const SpecChange(this.frame, this.spec);
  final int frame;
  final SoundSpec spec;
}

/// A recorded performance: the theremin's pitch, loudness and shape over
/// time, plus the sound settings. Audio is rendered from this on demand, so
/// a take can be re-voiced with a different chip later.
class Take {
  Take({
    required this.id,
    required this.name,
    required this.created,
    required this.hz,
    required this.level,
    required this.timbre,
    required this.specs,
  });

  final String id;
  final String name;
  final DateTime created;
  final Float32List hz;
  final Float32List level;
  final Float32List timbre;

  /// Sound changes, ordered; the first is at frame 0.
  final List<SpecChange> specs;

  int get frames => hz.length;
  Duration get duration =>
      Duration(microseconds: frames * 1000000 ~/ controlRate);

  SoundSpec get sound => specs.first.spec;

  Take copyWith({String? name, SoundSpec? sound}) => Take(
    id: id,
    name: name ?? this.name,
    created: created,
    hz: hz,
    level: level,
    timbre: timbre,
    specs: sound == null ? specs : [SpecChange(0, sound)],
  );

  static String _encode(Float32List data) => base64Encode(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );

  static Float32List _decode(String text) {
    final bytes = base64Decode(text);
    return Float32List.fromList(
      bytes.buffer.asFloat32List(bytes.offsetInBytes, bytes.lengthInBytes ~/ 4),
    );
  }

  Map<String, Object> toJson() => {
    'version': 1,
    'id': id,
    'name': name,
    'created': created.toIso8601String(),
    'hz': _encode(hz),
    'level': _encode(level),
    'timbre': _encode(timbre),
    'specs': [
      for (final s in specs) {'frame': s.frame, 'spec': s.spec.toJson()},
    ],
  };

  factory Take.fromJson(Map<String, Object?> j) => Take(
    id: j['id']! as String,
    name: j['name']! as String,
    created: DateTime.parse(j['created']! as String),
    hz: _decode(j['hz']! as String),
    level: _decode(j['level']! as String),
    timbre: _decode(j['timbre']! as String),
    specs: [
      for (final s in (j['specs']! as List).cast<Map<String, Object?>>())
        SpecChange(
          (s['frame']! as num).toInt(),
          SoundSpec.fromJson((s['spec']! as Map).cast<String, Object?>()),
        ),
    ],
  );
}

/// Collects controls while recording.
class TakeRecorder {
  TakeRecorder(SoundSpec initial) : _specs = [SpecChange(0, initial)];

  final _hz = <double>[];
  final _level = <double>[];
  final _timbre = <double>[];
  final List<SpecChange> _specs;

  int get frames => _hz.length;
  Duration get duration =>
      Duration(microseconds: frames * 1000000 ~/ controlRate);

  void add({
    required double hz,
    required double level,
    required double timbre,
    required SoundSpec spec,
  }) {
    if (spec != _specs.last.spec) _specs.add(SpecChange(frames, spec));
    _hz.add(hz);
    _level.add(level);
    _timbre.add(timbre);
  }

  Take finish({required String id, required String name, DateTime? now}) =>
      Take(
        id: id,
        name: name,
        created: now ?? DateTime.now(),
        hz: Float32List.fromList(_hz),
        level: Float32List.fromList(_level),
        timbre: Float32List.fromList(_timbre),
        specs: List.of(_specs),
      );
}

/// Renders [take] to interleaved stereo samples, plus [tail] seconds of
/// silence so echoes can ring out.
Float32List renderTake(
  Take take, {
  double sampleRate = 48000,
  double tail = 2,
}) {
  final perFrame = sampleRate / controlRate;
  final totalFrames = (take.frames * perFrame + tail * sampleRate).round();
  final out = Float32List(totalFrames * 2);
  final engine = SynthEngine(sampleRate);
  var specIndex = 0;
  engine.configure(take.specs.first.spec);
  var written = 0;
  var control = 0;
  while (written < totalFrames) {
    if (control < take.frames) {
      while (specIndex + 1 < take.specs.length &&
          take.specs[specIndex + 1].frame <= control) {
        specIndex++;
        engine.configure(take.specs[specIndex].spec);
      }
      engine.setControls(
        take.hz[control],
        take.level[control],
        take.timbre[control],
      );
    } else {
      engine.setControls(
        take.frames == 0 ? 220 : take.hz[take.frames - 1],
        0,
        0.5,
      );
    }
    final end = math.min(totalFrames, ((control + 1) * perFrame).round());
    engine.render(out, end - written, offset: written);
    written = end;
    control++;
  }
  return out;
}

/// Renders [take] to a WAV file's bytes (run this in a background isolate).
Uint8List renderTakeWav(Take take, {int sampleRate = 48000}) => encodeWav16(
  renderTake(take, sampleRate: sampleRate.toDouble()),
  sampleRate,
);
