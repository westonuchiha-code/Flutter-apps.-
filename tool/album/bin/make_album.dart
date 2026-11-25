// Renders "Twelve-Bit Science" to WAV and MP3 (320 kbps, tagged, our own
// mp3_kit encoder) files in OUT (default: ./out):
//   <n> - <title>.wav/.mp3 and, for songs, "<n> - <title> (Instrumental)".
//   dart run bin/make_album.dart [out] [track numbers...]
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:album/album.dart';
import 'package:album/dsp.dart';
import 'package:chip_synth/chip_synth.dart';
import 'package:mp3_kit/mp3_kit.dart';

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
  final base =
      '${n.toString().padLeft(2, '0')} - $title${instrumental ? ' (Instrumental)' : ''}';
  final name = '$base.wav';
  final wav = encodeWav16(audio, sr.round());
  File('$out/$name').writeAsBytesSync(wav);
  final mp3 = encodeMp3(
    Int16List.sublistView(wav, 44),
    tags: Mp3Tags(
      title: instrumental ? '$title (Instrumental)' : title,
      artist: 'The Allophones',
      album: instrumental
          ? 'Twelve-Bit Science (Instrumentals)'
          : 'Twelve-Bit Science',
      track: '$n',
      year: '2026',
    ),
  );
  File('$out/$base.mp3').writeAsBytesSync(mp3);
  stdout.writeln(
    '$name  ${(audio.length / 2 / sr).toStringAsFixed(1)} s  (${watch.elapsed.inSeconds} s)',
  );
}
