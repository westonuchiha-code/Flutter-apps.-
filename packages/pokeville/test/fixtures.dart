// Test folders: a copy of the PC's trimmed example Pokéville
// (test/fixtures/example-pokeville: box.json + 3 .pk2 files), optionally
// with more Pokémon added for fuller shots, and a fake sprite fetcher that
// draws coloured placeholders (tests never touch the network).
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pokeville/pokeville.dart';
import 'package:poke_saves/poke_saves.dart' as ps;
import 'package:poke_saves/testing.dart';

import 'dart:convert';

/// A built save with [pk] put into box 0 (null: empty).
Uint8List withMon(Uint8List save, Uint8List? pk, String ext, [int slot = 0]) {
  if (pk == null) return save;
  final r = ps.PokeSave.open(save)!.put(0, slot, pk, ext: ext);
  if (!r.ok) throw StateError(r.error);
  return r.save!;
}

const red = 'Pokemon - Red Version (USA, Europe).srm';
const crystal = 'Pokemon - Crystal Version (USA, Europe).srm';
const leaf = 'Pokemon - Leaf Green Version.srm';

/// [root]/pokeville (the PC's example) and [root]/saves with Red (a
/// Bulbasaur), Crystal (a Chikorita) and LeafGreen (a Treecko), plus files
/// that aren't saves to show.
String makeGames(String root, {bool more = false}) {
  makePokeville(root, more: more);
  final saves = p.join(root, 'saves');
  void put(String rel, List<int> bytes) => File(p.join(saves, rel))
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);
  var r = withMon(gen1Save(), bulbasaurPk1(), 'pk1');
  var c = withMon(crystalSave(), chikoritaPk2(), 'pk2');
  var l = withMon(gen3Save(code: 1), treeckoPk3(), 'pk3');
  if (more) {
    for (var i = 1; i < 7; i++) {
      r = withMon(r, bulbasaurPk1(), 'pk1', i);
      c = i.isEven
          ? withMon(c, chikoritaPk2(), 'pk2', i)
          : withMon(c, bulbasaurPk1(), 'pk1', i);
      l = withMon(l, treeckoPk3(), 'pk3', i * 3);
    }
  }
  put(p.join('Gambatte', red), r);
  put(p.join('Gambatte', crystal), c);
  put(p.join('mGBA', leaf), l);
  // not saves to show
  put(p.join('Gambatte', 'Tetris.srm'), Uint8List(0x2000));
  put(p.join('Gambatte', '$red.box-backup-20261126-101010-000'), gen1Save());
  put(
    p.join('Gambatte', 'Pokemon - Red.from-repo-20261126-101010.srm'),
    gen1Save(),
  );
  put(p.join('mGBA', 'notes.txt'), utf8.encode('hello'));
  return saves;
}

final exampleDir = p.join('test', 'fixtures', 'example-pokeville');

void copyTree(String from, String to) {
  Directory(to).createSync(recursive: true);
  for (final e in Directory(from).listSync(recursive: true)) {
    final rel = p.relative(e.path, from: from);
    if (e is Directory) {
      Directory(p.join(to, rel)).createSync(recursive: true);
    } else if (e is File) {
      File(p.join(to, rel)).parent.createSync(recursive: true);
      e.copySync(p.join(to, rel));
    }
  }
}

/// A copy of the example Pokéville in [root]/pokeville; [more] adds a
/// fuller Box 1, a shiny in Box 2 and an egg (written the way the PC
/// would: float numbers, a mons/ file each).
String makePokeville(String root, {bool more = false}) {
  final dir = p.join(root, 'pokeville');
  copyTree(exampleDir, dir);
  if (!more) return dir;
  final f = File(p.join(dir, 'box.json'));
  final data = PokeBoxStore.parse(f.readAsStringSync())!;
  var n = 0;
  void add(int box, int slot, Map<String, dynamic> mon) {
    final file =
        'mons/20261125-1200${(n++).toString().padLeft(2, '0')}-000000.pk2';
    File(PokeBoxStore.absolute(dir, file)).writeAsBytesSync(List.filled(73, 0));
    PokeBoxStore.place(data, box, slot, file, {
      'ability': '',
      'ball': 'Poke Ball',
      'egg': false,
      'form': 0.0,
      'format': 'pk2',
      'gender': 0.0,
      'generation': 2.0,
      'item': '',
      'level': 20.0,
      'moves': ['Tackle', 'Growl'],
      'nickname': '',
      'origin': 'Crystal',
      'ot': 'Dude',
      'pid': 0.0,
      'shiny': false,
      'stats': [50.0, 50.0, 50.0, 50.0, 50.0, 50.0],
      'v': 2.0,
      ...mon,
    });
  }

  const box1 = [
    (125, 'Electabuzz', ['Electric']),
    (57, 'Primeape', ['Fighting']),
    (88, 'Grimer', ['Poison']),
    (246, 'Larvitar', ['Rock', 'Ground']),
    (128, 'Tauros', ['Normal']),
    (104, 'Cubone', ['Ground']),
    (111, 'Rhyhorn', ['Ground', 'Rock']),
    (193, 'Yanma', ['Bug', 'Flying']),
    (35, 'Clefairy', ['Fairy']),
    (54, 'Psyduck', ['Water']),
    (213, 'Shuckle', ['Bug', 'Rock']),
    (179, 'Mareep', ['Electric']),
    (81, 'Magnemite', ['Electric', 'Steel']),
    (74, 'Geodude', ['Rock', 'Ground']),
    (123, 'Scyther', ['Bug', 'Flying']),
    (218, 'Slugma', ['Fire']),
    (158, 'Totodile', ['Water']),
    (63, 'Abra', ['Psychic']),
  ];
  for (var i = 0; i < box1.length; i++) {
    final (sp, name, types) = box1[i];
    add(0, 4 + i, {
      'species': sp.toDouble(),
      'name': name,
      'types': types,
      'gender': (i % 3).toDouble(),
    });
  }
  add(0, 23, {'species': 175.0, 'name': 'Togepi', 'egg': true, 'level': 1.0});
  add(1, 1, {
    'species': 130.0,
    'name': 'Gyarados',
    'nickname': 'Guts',
    'shiny': true,
    'level': 28.0,
    'types': ['Water', 'Flying'],
    'moves': ['Dragon Rage', 'Surf', 'Bite', 'Icy Wind'],
    'stats': [95.0, 125.0, 79.0, 60.0, 100.0, 81.0],
    'item': 'Mystic Water',
  });
  f.writeAsStringSync(PokeBoxStore.encode(data));
  return dir;
}

/// Draws a 96×96 placeholder "sprite" per species: a coloured blob with a
/// darker edge and eyes, so shots show where pictures go.
Future<Uint8List?> fakeFetcher(Uri url) async {
  final name = p.basenameWithoutExtension(url.path);
  final species = int.tryParse(name) ?? 0;
  final shiny = url.path.contains('/shiny/');
  final pic = img.Image(width: 96, height: 96, numChannels: 4);
  final h = (species * 47) % 360;
  final c = _hsv(h.toDouble(), shiny ? 0.35 : 0.6, 0.9);
  final e = _hsv(h.toDouble(), 0.8, 0.45);
  img.fillCircle(pic, x: 48, y: 54, radius: 30, color: e);
  img.fillCircle(pic, x: 48, y: 54, radius: 27, color: c);
  img.fillCircle(
    pic,
    x: 38,
    y: 48,
    radius: 4,
    color: img.ColorRgba8(30, 30, 60, 255),
  );
  img.fillCircle(
    pic,
    x: 58,
    y: 48,
    radius: 4,
    color: img.ColorRgba8(30, 30, 60, 255),
  );
  return Uint8List.fromList(img.encodePng(pic));
}

img.Color _hsv(double h, double s, double v) {
  final c = v * s;
  final x = c * (1 - ((h / 60) % 2 - 1).abs());
  final m = v - c;
  final (r, g, b) = switch (h ~/ 60) {
    0 => (c, x, 0.0),
    1 => (x, c, 0.0),
    2 => (0.0, c, x),
    3 => (0.0, x, c),
    4 => (x, 0.0, c),
    _ => (c, 0.0, x),
  };
  int to(double f) => ((f + m) * 255).round();
  return img.ColorRgba8(to(r), to(g), to(b), 255);
}
