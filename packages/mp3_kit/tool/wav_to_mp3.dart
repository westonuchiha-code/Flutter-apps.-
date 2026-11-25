// Encodes the album's WAVs to tagged 320 kbps MP3s, a few at a time.
//   dart run tool/wav_to_mp3.dart <wav folder> <out folder>
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:mp3_kit/mp3_kit.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final files =
      Directory(args[0])
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.wav'))
          .map((f) => f.path)
          .toList()
        ..sort((a, b) {
          // Songs before instrumentals.
          final ia = a.contains('(Instrumental)') ? 1 : 0;
          final ib = b.contains('(Instrumental)') ? 1 : 0;
          return ia != ib ? ia - ib : a.compareTo(b);
        });
  final out = args[1];
  final cores = math.max(1, Platform.numberOfProcessors - 1);
  for (var i = 0; i < files.length; i += cores) {
    await Future.wait([
      for (final f in files.skip(i).take(cores))
        Isolate.run(() => _one(f, out)),
    ]);
  }
}

void _one(String path, String out) {
  final b = File(path).readAsBytesSync();
  final d = ByteData.sublistView(b);
  var pos = 12;
  late Int16List pcm;
  while (pos + 8 <= b.length) {
    final id = String.fromCharCodes(b, pos, pos + 4);
    final n = d.getUint32(pos + 4, Endian.little);
    if (id == 'data') {
      pcm = Int16List.fromList(Int16List.sublistView(b, pos + 8, pos + 8 + n));
    }
    pos += 8 + n + (n & 1);
  }
  final name = p.basenameWithoutExtension(path);
  final m = RegExp(r'^(\d+) - (.*)$').firstMatch(name)!;
  final inst = name.contains('(Instrumental)');
  final mp3 = encodeMp3(
    pcm,
    tags: Mp3Tags(
      title: m.group(2),
      artist: 'The Allophones',
      album: inst ? 'Twelve-Bit Science (Instrumentals)' : 'Twelve-Bit Science',
      track: '${int.parse(m.group(1)!)}',
      year: '2026',
    ),
  );
  File(p.join(out, '$name.mp3')).writeAsBytesSync(mp3);
  stdout.writeln('done $name');
}
