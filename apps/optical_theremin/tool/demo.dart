// Renders a short demo of several chips playing a theremin-style phrase.
// Run: dart run tool/demo.dart out.wav
import 'dart:io';
import 'dart:math' as math;

import 'package:optical_theremin/src/core/music.dart';
import 'package:optical_theremin/src/recording/take.dart';
import 'package:optical_theremin/src/synth/engine.dart';

void main(List<String> args) {
  const sounds = [
    SoundSpec(chipId: 'gb', patchId: 'pulse', vibratoCents: 25, echoMix: 0.3),
    SoundSpec(chipId: 'nes', patchId: 'pulse', arp: 'minor', arpFrames: 2),
    SoundSpec(chipId: 'sid', patchId: 'saw', echoMix: 0.35, echoMs: 380),
    SoundSpec(chipId: 'sid', patchId: 'sync', vibratoCents: 15),
    SoundSpec(chipId: 'ay', patchId: 'syncbuzz'),
    SoundSpec(chipId: 'fm', patchId: 'brass', vibratoCents: 20, echoMix: 0.25),
    SoundSpec(chipId: 'fm', patchId: 'growl', crushBits: 5),
    SoundSpec(chipId: 'wsg', patchId: 'wave', echoMix: 0.3),
    SoundSpec(chipId: 'tia', patchId: 'shift'),
    SoundSpec(chipId: 'speech', patchId: 'vowels', echoMix: 0.3),
  ];
  // A phrase: (MIDI note, seconds). The pitch glides between notes.
  const phrase = [(57, 0.5), (64, 0.6), (62, 0.35), (60, 0.35), (64, 0.9)];
  final rec = TakeRecorder(sounds.first);
  var glideMidi = 57.0;
  for (final sound in sounds) {
    var t = 0.0;
    for (final (note, seconds) in phrase) {
      final frames = (seconds * controlRate).round();
      for (var i = 0; i < frames; i++) {
        glideMidi += (note - glideMidi) * 0.25;
        final total = t + i / controlRate;
        // Swell in, fade out at the end of the phrase; sweep the shape.
        final level = math.min(1.0, total * 4) *
            (total > 2.4 ? math.max(0.0, 1 - (total - 2.4) * 3) : 1.0);
        rec.add(
          hz: midiToHz(glideMidi),
          level: level,
          timbre: (total / 2.7).clamp(0.0, 1.0),
          spec: sound,
        );
      }
      t += seconds;
    }
    // A short gap between sounds.
    for (var i = 0; i < 30; i++) {
      rec.add(hz: midiToHz(glideMidi), level: 0, timbre: 0, spec: sound);
    }
  }
  final take = rec.finish(id: 'demo', name: 'Demo');
  final out = args.isEmpty ? 'demo.wav' : args.first;
  File(out).writeAsBytesSync(renderTakeWav(take));
  stdout.writeln('Wrote $out (${take.duration.inSeconds} s)');
}
