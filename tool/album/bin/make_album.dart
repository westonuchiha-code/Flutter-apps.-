// Renders "Twelve-Bit Science" to WAV files in OUT (default: ./out):
//   <n> - <title>.wav and, for songs, "<n> - <title> (Instrumental).wav".
//   dart run bin/make_album.dart [out] [track numbers...]
import 'dart:io';
import 'dart:isolate';

import 'package:album/album.dart';
import 'package:album/dsp.dart';
import 'package:chip_synth/chip_synth.dart';

Future<void> main(List<String> args) async {
  final out = args.isNotEmpty ? args.first : 'out';
  final only = {for (final a in args.skip(1)) int.parse(a)};
  Directory(out).createSync(recursive: true);
  final list = tracks();
  final jobs = <Future<void>>[];
  for (var i = 0; i < list.length; i++) {
    final n = i + 1;
    if (only.isNotEmpty && !only.contains(n)) continue;
    final title = list[i].$1;
    final isSong = songs.any((s) => s.title == title);
    jobs.add(Isolate.run(() => _render(out, n, title, false)));
    if (isSong) jobs.add(Isolate.run(() => _render(out, n, title, true)));
  }
  await Future.wait(jobs);
  if (only.isEmpty) File('$out/Lyrics.txt').writeAsStringSync(lyricSheet());
}

void _render(String out, int n, String title, bool instrumental) {
  final t = tracks(vocals: !instrumental)[n - 1];
  final watch = Stopwatch()..start();
  final audio = t.$2();
  final name =
      '${n.toString().padLeft(2, '0')} - $title${instrumental ? ' (Instrumental)' : ''}.wav';
  File('$out/$name').writeAsBytesSync(encodeWav16(audio, sr.round()));
  stdout.writeln(
    '$name  ${(audio.length / 2 / sr).toStringAsFixed(1)} s  (${watch.elapsed.inSeconds} s)',
  );
}
