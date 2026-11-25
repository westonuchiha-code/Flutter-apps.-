// Diagnostics: a song's beat, vocals and DJ as raw (unlevelled) WAV stems.
//   dart run bin/stems.dart <out> <song index 0-7>
import 'dart:io';

import 'package:album/album.dart';
import 'package:album/dsp.dart';
import 'package:album/song.dart';
import 'package:chip_synth/chip_synth.dart';

void main(List<String> args) {
  final s = songs[int.parse(args[1])];
  for (final stem in ['beat', 'vocals', 'dj']) {
    final a = renderSong(s, stems: {stem}, raw: true);
    for (var i = 0; i < a.length; i++) {
      a[i] = (a[i] * 0.5).clamp(-1, 1);
    }
    File(
      '${args[0]}/stem_$stem.wav',
    ).writeAsBytesSync(encodeWav16(a, sr.round()));
  }
}
