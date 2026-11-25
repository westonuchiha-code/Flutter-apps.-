// Renders each music video style's song: the full song (WAV + MP3), its
// song map, and a 30-second take (MP3) of the bars the video take films.
//   dart run bin/style_takes.dart <out> [style ...]
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:album/dsp.dart';
import 'package:album/style_songs.dart';
import 'package:chip_synth/chip_synth.dart';
import 'package:mp3_kit/mp3_kit.dart';

Future<void> main(List<String> args) async {
  final out = args.isNotEmpty ? args.first : 'out';
  final only = args.skip(1).toSet();
  Directory(out).createSync(recursive: true);
  await Future.wait([
    for (final t in styleTracks())
      if (only.isEmpty || only.contains(t.style))
        Isolate.run(() => _one(out, t.style)),
  ]);
}

Int16List _pcm(Float32List a) {
  final p = Int16List(a.length);
  for (var i = 0; i < a.length; i++) {
    p[i] = (a[i] * 32767).round().clamp(-32768, 32767);
  }
  return p;
}

void _one(String out, String style) {
  final t = styleTracks().firstWhere((x) => x.style == style);
  final watch = Stopwatch()..start();
  final audio = t.render();
  final map = {
    ...t.map(),
    'take': [t.from, t.to],
  };
  File('$out/$style.wav').writeAsBytesSync(encodeWav16(audio, sr.round()));
  File('$out/$style.songmap.json').writeAsStringSync(jsonEncode(map));
  final tags = Mp3Tags(
    title: t.title,
    artist: 'The Allophones',
    album: 'Music video styles',
  );
  File('$out/$style.mp3').writeAsBytesSync(encodeMp3(_pcm(audio), tags: tags));
  // The take: the bars the video take films (bar = 240 / map bpm).
  final bar = 240 / (map['bpm'] as num);
  final s0 = (t.from * bar * sr).round() * 2;
  final s1 = ((t.to * bar + 0.5) * sr).round() * 2;
  final cut = Float32List.fromList(
    audio.sublist(s0, s1.clamp(0, audio.length)),
  );
  final f = (0.25 * sr).round();
  for (var i = 0; i < f; i++) {
    for (final o in [i * 2, cut.length - 2 - i * 2]) {
      cut[o] *= i / f;
      cut[o + 1] *= i / f;
    }
  }
  File('$out/$style-take.mp3').writeAsBytesSync(
    encodeMp3(
      _pcm(cut),
      tags: Mp3Tags(title: '${t.title} (take)', artist: 'The Allophones'),
    ),
  );
  stdout.writeln(
    '$style: ${(audio.length / 2 / sr).toStringAsFixed(1)} s, take ${(cut.length / 2 / sr).toStringAsFixed(1)} s (${watch.elapsed.inSeconds} s)',
  );
}
