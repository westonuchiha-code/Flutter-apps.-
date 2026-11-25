// A vocal test: renders bars [from, to) of a song as an MP3 (and WAV), with
// the delivery settings being tried.
//   dart run bin/sample.dart <out.mp3> <song index 0-7> <from bar> <to bar>
//     [flow=line|word] [lift=1.0] [level=2.2]
import 'dart:io';
import 'dart:typed_data';

import 'package:album/album.dart';
import 'package:album/dsp.dart';
import 'package:album/rap.dart';
import 'package:album/song.dart';
import 'package:mp3_kit/mp3_kit.dart';

void main(List<String> args) {
  final song = songs[int.parse(args[1])];
  final from = int.parse(args[2]), to = int.parse(args[3]);
  for (final a in args.skip(4)) {
    final [k, v] = a.split('=');
    switch (k) {
      case 'flow':
        flow = v;
      case 'lift':
        pitchLift = double.parse(v);
      case 'level':
        vocalLevel = double.parse(v);
    }
  }
  final all = renderSong(song);
  final s0 = (from * song.barSeconds * sr).round() * 2;
  final s1 = ((to * song.barSeconds + 0.6) * sr).round() * 2;
  final cut = Float32List.fromList(all.sublist(s0, s1.clamp(0, all.length)));
  // Fade the edges.
  final f = (0.3 * sr).round();
  for (var i = 0; i < f; i++) {
    for (final o in [i * 2, cut.length - 2 - i * 2]) {
      cut[o] *= i / f;
      cut[o + 1] *= i / f;
    }
  }
  final pcm = Int16List(cut.length);
  for (var i = 0; i < cut.length; i++) {
    pcm[i] = (cut[i] * 32767).round().clamp(-32768, 32767);
  }
  File(args[0]).writeAsBytesSync(
    encodeMp3(pcm, tags: Mp3Tags(title: '${song.title} (vocal test)')),
  );
  stdout.writeln(
    'wrote ${args[0]} (${(cut.length / 2 / sr).toStringAsFixed(1)} s)',
  );
}
