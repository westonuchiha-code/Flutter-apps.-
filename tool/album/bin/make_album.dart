// Renders "Twelve-Bit Science" to WAV and MP3 (320 kbps, tagged, our own
// mp3_kit encoder) files in OUT (default: ./out):
//   <n> - <title>.wav/.mp3 and, for songs, "<n> - <title> (Instrumental)".
//   dart run bin/make_album.dart [out] [track numbers...]
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:album/album.dart';
import 'package:album/dsp.dart';
import 'package:album/song.dart';
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
    // Instrumental only (owner's choice: the chip raps are out; the beats,
    // loops and the DJ's scratches stay). VOCALS=1 renders the old way.
    final vocals = Platform.environment['VOCALS'] == '1';
    jobs.add(Isolate.run(() => _render(out, n, title, !vocals)));
  }
  await Future.wait(jobs);
}

void _render(String out, int n, String title, bool instrumental) {
  final t = tracks(vocals: !instrumental)[n - 1];
  final watch = Stopwatch()..start();
  final audio = t.$2();
  final base = '${n.toString().padLeft(2, '0')} - $title';
  final name = '$base.wav';
  final wav = encodeWav16(audio, sr.round());
  File('$out/$name').writeAsBytesSync(wav);
  final mp3 = encodeMp3(
    Int16List.sublistView(wav, 44),
    tags: Mp3Tags(
      title: title,
      artist: 'The Allophones',
      album: 'Twelve-Bit Science',
      track: '$n',
      year: '2026',
    ),
  );
  File('$out/$base.mp3').writeAsBytesSync(mp3);
  // The song's map, for the music video director.
  final song = songs.where((s) => s.title == title).firstOrNull;
  if (song != null) {
    File(
      '$out/$base.songmap.json',
    ).writeAsStringSync(jsonEncode(songMapJson(song)));
  }
  stdout.writeln(
    '$name  ${(audio.length / 2 / sr).toStringAsFixed(1)} s  (${watch.elapsed.inSeconds} s)',
  );
}
