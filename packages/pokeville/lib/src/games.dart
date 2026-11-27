// Pokéville part B: the owner's Gen 1-3 game saves, ported from the PC's
// PokeSaves.gd (finding them), PkHelper / pkhelper's Program.cs (changing
// them) and PokeBoxScreen.gd's jobs. Pure Dart on top of package:poke_saves
// (which does what PKHeX does there). Every function here that touches files
// is top-level, so it can run in a background isolate.
//
// A game save is only ever changed like the PC's helper does it
// (WriteSafely): the file must still be exactly what was read (else nothing
// is written: a sync or the emulator changed it), the new save is written to
// `<save>.box-new`, read back, opened and checked (checksums, and that the
// change landed, by counts: Game Boy boxes have no gaps), the old save is
// copied to `<Pokéville>/save backups/<name>.box-backup-<time>`, and only
// then the new one is swapped in. The order of a move never loses a Pokémon:
//   game -> Pokéville: the Pokémon's file is written (and read back) first,
//     then it is taken out of the game; box.json last.
//   Pokéville -> game: the game save is changed first, then the file goes to
//     mons/sent/ (kept, just in case) and box.json last.
//   game -> another game: the other game gets it first, then it leaves this
//     one.
// A crash between the steps leaves a Pokémon in two places, never in none.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:poke_saves/poke_saves.dart' as ps;
import 'package:save_kit/save_kit.dart' show CardOwners;

import 'store.dart';

/// The consoles' chips in the Games list (PokeBoxScreen.gd's CHIPS).
const consoleChips = {
  'gb': ('GB', 0xFF8B8F88),
  'gbc': ('GBC', 0xFF7B5CD6),
  'gba': ('GBA', 0xFF5B4FC4),
};

/// The console a game of [generation] draws as (PokeTransfer.console_for).
String consoleFor(int generation) => switch (generation) {
  1 => 'gb',
  2 => 'gbc',
  3 => 'gba',
  _ => 'gbc',
};

/// A Pokémon game save found on this device (the helper's `scan` answer).
class GameSave {
  const GameSave({
    required this.path,
    required this.game,
    required this.trainer,
    required this.generation,
    required this.boxes,
    required this.inBoxes,
    required this.party,
    required this.species,
  });

  final String path;

  /// "Gold", "LeafGreen", ...
  final String game;
  final String trainer;
  final int generation;
  final int boxes;
  final int inBoxes;
  final int party;

  /// Species in its boxes and party (eggs left out): the Box Dex.
  final List<int> species;

  String get fileName => p.basename(path);

  /// gb / gbc / gba.
  String get console => consoleFor(generation);

  /// "Pokémon Gold".
  String get title => 'Pokémon $game';

  /// Every Pokémon in it (the Games list's count).
  int get count => inBoxes + party;

  /// What a scan finds in [save] at [path].
  factory GameSave.of(String path, ps.PokeSave save) {
    var n = 0;
    final species = <int>{};
    for (final b in save.boxes) {
      for (final m in b.slots) {
        if (m == null) continue;
        n++;
        if (!m.isEgg) species.add(m.species);
      }
    }
    final party = save.party;
    for (final m in party) {
      if (m.species != 0 && !m.isEgg) species.add(m.species);
    }
    return GameSave(
      path: path,
      game: save.gameName,
      trainer: save.trainer,
      generation: save.generation,
      boxes: save.boxCount,
      inBoxes: n,
      party: party.length,
      species: species.toList()..sort(),
    );
  }
}

// ---- finding them (PokeSaves.gd) --------------------------------------------

/// Save file types the Game Boy / GBA cores write.
const saveExts = ['srm', 'sav'];

/// Names that are never a save to show: our own backups and temp files,
/// Cross-Save's conflict copies and temp files.
const notSaves = ['.box-backup-', '.box-new', '.from-repo-', '.xs-new'];

const _maxFiles = 4000;
const _maxDepth = 7;

/// Could [name] be a Game Boy / GBA save?
bool isSaveCandidate(String name) {
  final low = name.toLowerCase();
  if (notSaves.any(low.contains)) return false;
  return saveExts.contains(p.extension(low).replaceFirst('.', ''));
}

/// Every `.srm` / `.sav` under [roots] (7 folders deep at most) that
/// poke_saves opens as a Pokémon game, sorted by generation, game and path.
/// Folders that don't exist are skipped. (Top-level: runs in the
/// background.)
List<GameSave> findGameSaves(List<String> roots) {
  final files = <String>[];
  final seen = <String>{};
  void walk(Directory d, int depth) {
    if (depth > _maxDepth || files.length >= _maxFiles) return;
    final List<FileSystemEntity> list;
    try {
      list = d.listSync(followLinks: false)
        ..sort((a, b) => a.path.compareTo(b.path));
    } on Object {
      return;
    }
    for (final e in list) {
      if (e is File && isSaveCandidate(p.basename(e.path))) {
        if (seen.add(p.normalize(e.absolute.path))) files.add(e.path);
      }
    }
    for (final e in list) {
      if (e is Directory && !p.basename(e.path).startsWith('.')) {
        walk(e, depth + 1);
      }
    }
  }

  for (final r in roots) {
    if (r.trim().isEmpty) continue;
    final d = Directory(r);
    if (d.existsSync()) walk(d, 0);
  }
  final out = <GameSave>[];
  for (final f in files) {
    try {
      final len = File(f).lengthSync();
      if (len < 0x2000 || len > 64 * 1024 * 1024) continue;
      final save = ps.PokeSave.open(
        File(f).readAsBytesSync(),
        fileName: p.basename(f),
      );
      if (save != null) out.add(GameSave.of(f, save));
    } on Object {
      // not a save, or one that can't be read: skip it
    }
  }
  out.sort((a, b) {
    final g = a.generation.compareTo(b.generation);
    if (g != 0) return g;
    final n = a.game.compareTo(b.game);
    return n != 0 ? n : a.path.compareTo(b.path);
  });
  return out;
}

/// The bytes of [path] (null when it can't be read). Top-level.
Uint8List? readSaveBytes(String path) {
  try {
    return File(path).readAsBytesSync();
  } on Object {
    return null;
  }
}

/// RetroArch's saves folder on Windows, as the PC menu finds it
/// (RetroArchScanner.gd: the usual install folders, then retroarch.cfg's
/// savefile_directory, `:\` meaning RetroArch's own folder). [env] is the
/// environment (tests). Folders that don't exist are left out.
List<String> retroArchSaveDirs({Map<String, String>? env}) {
  final e = env ?? Platform.environment;
  final roots = [
    'C:/RetroArch-Win64',
    'C:/RetroArch',
    'C:/Program Files/RetroArch',
    'C:/Program Files (x86)/RetroArch',
    'C:/RetroBat/emulators/retroarch',
    if ((e['APPDATA'] ?? '').isNotEmpty)
      p.join(e['APPDATA']!.replaceAll(r'\', '/'), 'RetroArch'),
  ];
  final out = <String>[];
  for (final root in roots) {
    final cfg = File(p.join(root, 'retroarch.cfg'));
    if (!File(p.join(root, 'retroarch.exe')).existsSync() &&
        !cfg.existsSync()) {
      continue;
    }
    var dir = p.join(root, 'saves');
    try {
      final v = parseRetroArchCfg(
        cfg.existsSync() ? cfg.readAsStringSync() : '',
      )['savefile_directory'];
      if (v != null) dir = resolveRetroArchDir(v, root, 'saves', env: e);
    } on Object {
      // keep the default
    }
    if (Directory(dir).existsSync() && !out.contains(dir)) out.add(dir);
  }
  return out;
}

/// retroarch.cfg's `key = "value"` lines.
Map<String, String> parseRetroArchCfg(String text) {
  final out = <String, String>{};
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('#') || !line.contains('=')) continue;
    final i = line.indexOf('=');
    var v = line.substring(i + 1).trim();
    if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
      v = v.substring(1, v.length - 1);
    }
    out[line.substring(0, i).trim()] = v;
  }
  return out;
}

/// A retroarch.cfg folder value: "" / "default" = [sub] in [root], `:\x`
/// = x in [root], `~/x` = x in the user's folder.
String resolveRetroArchDir(
  String value,
  String root,
  String sub, {
  Map<String, String>? env,
}) {
  final v = value.replaceAll(r'\', '/');
  if (v.isEmpty || v == 'default') return p.join(root, sub);
  if (v == ':' || v.startsWith(':/')) {
    return v.length <= 2 ? root : p.join(root, v.substring(2));
  }
  if (v.startsWith('~/')) {
    final e = env ?? Platform.environment;
    final home = e['USERPROFILE'] ?? e['HOME'] ?? '';
    return p.join(home.replaceAll(r'\', '/'), v.substring(2));
  }
  return v;
}

// ---- emulators (PokeSaves.gd's in_use) ----------------------------------------

/// Programs that keep a save open and write their own copy back over a
/// change.
const saveEmulators = [
  ('retroarch', 'RetroArch'),
  ('mgba', 'mGBA'),
  ('sameboy', 'SameBoy'),
  ('bgb', 'BGB'),
  ('visualboy', 'VisualBoyAdvance'),
  ('vba', 'VisualBoyAdvance'),
];

/// The emulator a save's folder names ("RetroArch" for the menu's own
/// folders), else null.
String? emulatorNamed(String path) {
  final low = path.replaceAll(r'\', '/').toLowerCase();
  for (final (key, name) in saveEmulators) {
    if (low.contains(key)) return name;
  }
  return null;
}

/// '' when none of [running] has the save at [path] open, else why it can't
/// be changed now (the emulator whose folder holds it, or any of them for a
/// save kept somewhere else).
String ownerRunning(String path, List<String> running) {
  final low = path.replaceAll(r'\', '/').toLowerCase();
  final named = saveEmulators.any((e) => low.contains(e.$1));
  for (final (key, name) in saveEmulators) {
    if (named && !low.contains(key)) continue;
    if (running.any((r) => r.startsWith(key))) {
      return 'Close $name first: it has this save open';
    }
  }
  return '';
}

/// Windows / Linux: '' when no emulator has [path] open, why not when one
/// does, null when the running programs can't be listed. Top-level.
String? emulatorRunning(String path) {
  final names = CardOwners.processNames();
  if (names == null || names.isEmpty) return null;
  return ownerRunning(path, names);
}

// ---- changing a save (pkhelper's take / put / move / send) -------------------

/// The folder (in Pokéville) game saves are copied into before a change,
/// as on the PC. Cross-Save leaves it out.
const backupsFolder = 'save backups';

/// Pokémon moved back into a game keep their file here (mons/sent).
const sentFolder = 'sent';

/// What a change gave back.
class GameChange {
  const GameChange.fail(this.error)
    : save = null,
      save2 = null,
      file = '',
      mon = null,
      reason = '',
      changedOnDisk = false;
  const GameChange.changed(this.error)
    : save = null,
      save2 = null,
      file = '',
      mon = null,
      reason = '',
      changedOnDisk = true;
  const GameChange.ok({
    this.save,
    this.save2,
    this.file = '',
    this.mon,
    this.reason = '',
  }) : error = '',
       changedOnDisk = false;

  /// '' when it worked.
  final String error;
  bool get ok => error.isEmpty;

  /// The save wasn't what was read any more: nothing was changed.
  final bool changedOnDisk;

  /// The new bytes of the save changed (send: the one it came from).
  final Uint8List? save;

  /// send: the new bytes of the save it went to.
  final Uint8List? save2;

  /// take: the Pokémon's file in Pokéville (relative, `/`).
  final String file;

  /// The Pokémon's summary (take: with `from_save` and `from`).
  final Map<String, dynamic>? mon;

  /// put / send: "converted from pk1 to pk2" (or "fits as it is").
  final String reason;
}

/// Said when a save isn't what was read any more.
const changedOnDiskText =
    'The save changed since it was read (a sync, or the game), so nothing '
    'was changed. It has been read again.';

class _Refused implements Exception {
  _Refused(this.why);
  final String why;
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _two(int v) => v.toString().padLeft(2, '0');

/// `yyyyMMdd-HHmmss` (local time), as the PC names files.
String fileStamp(DateTime t) =>
    '${t.year}${_two(t.month)}${_two(t.day)}-'
    '${_two(t.hour)}${_two(t.minute)}${_two(t.second)}';

/// A fresh name (without extension) for a Pokémon coming into Pokéville:
/// `mons/<yyyyMMdd-HHmmss>-<6 random digits>` (PokeBoxStore.new_base).
String newMonBase(DateTime now, math.Random rnd) =>
    '${PokeBoxStore.mons}/${fileStamp(now)}-'
    '${rnd.nextInt(1000000).toString().padLeft(6, '0')}';

int _countBox(ps.PokeSave s, int box) => s.boxes[box].count;

int _countAll(ps.PokeSave s) => s.boxes.fold(0, (n, b) => n + b.count);

int _countSpecies(ps.PokeSave s, int species) {
  var n = 0;
  for (final b in s.boxes) {
    for (final m in b.slots) {
      if (m?.species == species) n++;
    }
  }
  return n;
}

/// Reads the save and checks it is still [expected]; opens it.
ps.PokeSave _openExpected(String path, Uint8List expected) {
  final Uint8List now;
  try {
    now = File(path).readAsBytesSync();
  } on Object catch (e) {
    throw _Refused("couldn't read the save ($e)");
  }
  if (!_same(now, expected)) throw _Changed();
  final s = ps.PokeSave.open(now, fileName: p.basename(path));
  if (s == null) throw _Refused("that isn't a Pokémon save any more");
  return s;
}

class _Changed implements Exception {}

/// pkhelper's WriteSafely: [data] to `<path>.box-new`, read back, opened,
/// checked ([landed] says the change is there), the old save ([old]) copied
/// into [backups], then swapped in. Returns the backup's path. Throws
/// [_Refused] (nothing changed) when any step fails.
String writeSaveSafely(
  String path,
  Uint8List old,
  Uint8List data,
  String backups,
  bool Function(ps.PokeSave again) landed, {
  DateTime? now,
}) {
  final tmp = File('$path.box-new');
  void dropTmp() {
    try {
      if (tmp.existsSync()) tmp.deleteSync();
    } on Object {
      // the next write replaces it
    }
  }

  try {
    tmp.writeAsBytesSync(data, flush: true);
    final back = tmp.readAsBytesSync();
    final again = ps.PokeSave.open(back, fileName: p.basename(path));
    if (!_same(back, data) ||
        again == null ||
        again.check().isNotEmpty ||
        !landed(again)) {
      dropTmp();
      throw _Refused(
        "the changed save didn't read back right, nothing was written",
      );
    }
  } on _Refused {
    rethrow;
  } on Object catch (e) {
    dropTmp();
    throw _Refused("couldn't write the save ($e)");
  }
  // the file must not have changed while we worked
  final Uint8List still;
  try {
    still = File(path).readAsBytesSync();
  } on Object catch (e) {
    dropTmp();
    throw _Refused("couldn't read the save ($e)");
  }
  if (!_same(still, old)) {
    dropTmp();
    throw _Changed();
  }
  String backup;
  try {
    Directory(backups).createSync(recursive: true);
    final t = now ?? DateTime.now();
    final stamp = '${fileStamp(t)}-${t.millisecond.toString().padLeft(3, '0')}';
    backup = p.join(backups, '${p.basename(path)}.box-backup-$stamp');
    for (var n = 2; File(backup).existsSync(); n++) {
      backup = p.join(backups, '${p.basename(path)}.box-backup-$stamp-$n');
    }
    File(backup).writeAsBytesSync(old, flush: true);
    if (!_same(File(backup).readAsBytesSync(), old)) {
      throw const FileSystemException("the backup didn't read back the same");
    }
  } on Object catch (e) {
    dropTmp();
    throw _Refused("couldn't back the save up first, nothing was changed ($e)");
  }
  try {
    tmp.renameSync(path); // replaces the save (Windows too)
  } on Object catch (e) {
    dropTmp();
    throw _Refused("couldn't swap the new save in ($e)");
  }
  return backup;
}

Map<String, dynamic> _summary(ps.Mon m) => Map<String, dynamic>.from(m.summary);

/// Arguments of [takeFromGame].
typedef TakeArgs = ({
  String save,
  Uint8List expected,
  int box,
  int slot,
  String pokeville,
  String backups,
  int stamp, // ms since epoch (the file's name)
  int seed,
});

/// Game -> Pokéville: the Pokémon in [TakeArgs.box] / slot goes into a new
/// `mons/<stamp>.pkN` (written and read back first), then leaves the save.
/// box.json is the caller's (it places [GameChange.file]).
GameChange takeFromGame(TakeArgs a) {
  File? out;
  try {
    final s = _openExpected(a.save, a.expected);
    final t = s.take(a.box, a.slot);
    if (!t.ok) return GameChange.fail(t.error);
    final pk = t.mon!;
    final time = DateTime.fromMillisecondsSinceEpoch(a.stamp);
    final rnd = math.Random(a.seed);
    var rel = '${newMonBase(time, rnd)}.${pk.ext}';
    while (File(PokeBoxStore.absolute(a.pokeville, rel)).existsSync()) {
      rel = '${newMonBase(time, rnd)}.${pk.ext}';
    }
    out = File(PokeBoxStore.absolute(a.pokeville, rel));
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(pk.bytes, flush: true);
    final back = ps.Mon.fromFile(out.readAsBytesSync(), ext: pk.ext);
    if (back == null || back.species != pk.species || back.pid != pk.pid) {
      out.deleteSync();
      return const GameChange.fail('could not store that Pokémon safely');
    }
    final inBox = _countBox(s, a.box), same = _countSpecies(s, pk.species);
    writeSaveSafely(
      a.save,
      a.expected,
      t.save!,
      a.backups,
      (g) =>
          _countBox(g, a.box) == inBox - 1 &&
          _countSpecies(g, pk.species) == same - 1,
    );
    final mon = _summary(pk)
      ..['from_save'] = p.basename(a.save)
      ..['from'] = s.boxName(a.box).trim().isEmpty
          ? 'Box ${a.box + 1}'
          : s.boxName(a.box);
    return GameChange.ok(save: t.save, file: rel, mon: mon);
  } on _Changed {
    _delete(out);
    return const GameChange.changed(changedOnDiskText);
  } on _Refused catch (e) {
    _delete(out);
    return GameChange.fail(e.why);
  } on Object catch (e) {
    _delete(out);
    return GameChange.fail('$e');
  }
}

void _delete(File? f) {
  try {
    if (f != null && f.existsSync()) f.deleteSync();
  } on Object {
    // left behind: a spare copy, never a lost one
  }
}

/// Arguments of [putIntoGame].
typedef PutArgs = ({
  String save,
  Uint8List expected,
  int box,
  int slot,
  String pokeville,
  String file, // box.json's `file`
  String backups,
});

/// Pokéville -> game: the stored Pokémon goes into the save (converted the
/// way PKHeX converts; refused as PKHeX refuses), then its file moves to
/// mons/sent/. box.json is the caller's (it clears the slot).
GameChange putIntoGame(PutArgs a) {
  try {
    final s = _openExpected(a.save, a.expected);
    final path = PokeBoxStore.absolute(a.pokeville, a.file);
    final f = File(path);
    if (!f.existsSync()) {
      return const GameChange.fail(
        "that Pokémon's file isn't in Pokéville's mons folder",
      );
    }
    final bytes = f.readAsBytesSync();
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    final r = s.put(a.box, a.slot, bytes, ext: ext);
    if (!r.ok) return GameChange.fail(r.error);
    final species = r.mon!.species;
    final inBox = _countBox(s, a.box), same = _countSpecies(s, species);
    writeSaveSafely(
      a.save,
      a.expected,
      r.save!,
      a.backups,
      (g) =>
          _countBox(g, a.box) == inBox + 1 &&
          _countSpecies(g, species) == same + 1,
    );
    // kept, just in case (as on the PC)
    try {
      final sent = Directory(p.join(a.pokeville, PokeBoxStore.mons, sentFolder))
        ..createSync(recursive: true);
      var to = p.join(sent.path, p.basename(path));
      for (var n = 2; File(to).existsSync(); n++) {
        to = p.join(
          sent.path,
          '${p.basenameWithoutExtension(path)}-$n${p.extension(path)}',
        );
      }
      f.renameSync(to);
    } on Object {
      // the Pokémon is in the game; its old file just stays where it was
    }
    final reason = r.reason == 'fits as it is' ? '' : r.reason;
    return GameChange.ok(save: r.save, mon: _summary(r.mon!), reason: reason);
  } on _Changed {
    return const GameChange.changed(changedOnDiskText);
  } on _Refused catch (e) {
    return GameChange.fail(e.why);
  } on Object catch (e) {
    return GameChange.fail('$e');
  }
}

/// Arguments of [moveInGame].
typedef MoveArgs = ({
  String save,
  Uint8List expected,
  int box,
  int slot,
  int box2,
  int slot2,
  String backups,
});

/// Inside one save (onto a Pokémon = swap).
GameChange moveInGame(MoveArgs a) {
  try {
    final s = _openExpected(a.save, a.expected);
    final r = s.move(a.box, a.slot, a.box2, a.slot2);
    if (!r.ok) return GameChange.fail(r.error);
    final species = r.mon!.species;
    final total = _countAll(s), same = _countSpecies(s, species);
    writeSaveSafely(
      a.save,
      a.expected,
      r.save!,
      a.backups,
      (g) => _countAll(g) == total && _countSpecies(g, species) == same,
    );
    return GameChange.ok(save: r.save, mon: _summary(r.mon!));
  } on _Changed {
    return const GameChange.changed(changedOnDiskText);
  } on _Refused catch (e) {
    return GameChange.fail(e.why);
  } on Object catch (e) {
    return GameChange.fail('$e');
  }
}

/// Arguments of [sendToGame].
typedef SendArgs = ({
  String from,
  Uint8List fromExpected,
  int box,
  int slot,
  String to,
  Uint8List toExpected,
  int box2,
  int slot2,
  String backups,
});

/// Straight from one game's box into another game's (converted): the other
/// game gets it first, then it leaves this one (pkhelper's send).
GameChange sendToGame(SendArgs a) {
  try {
    final from = _openExpected(a.from, a.fromExpected);
    final to = _openExpected(a.to, a.toExpected);
    final t = from.take(a.box, a.slot);
    if (!t.ok) return GameChange.fail(t.error);
    final pk = t.mon!;
    final r = to.put(a.box2, a.slot2, pk.bytes, ext: pk.ext);
    if (!r.ok) return GameChange.fail(r.error);
    final conv = r.mon!.species;
    final inB = _countAll(to), sameB = _countSpecies(to, conv);
    writeSaveSafely(
      a.to,
      a.toExpected,
      r.save!,
      a.backups,
      (g) => _countAll(g) == inB + 1 && _countSpecies(g, conv) == sameB + 1,
    );
    final inA = _countAll(from), sameA = _countSpecies(from, pk.species);
    try {
      writeSaveSafely(
        a.from,
        a.fromExpected,
        t.save!,
        a.backups,
        (g) =>
            _countAll(g) == inA - 1 &&
            _countSpecies(g, pk.species) == sameA - 1,
      );
    } on Object catch (e) {
      final why = e is _Refused ? e.why : 'it changed meanwhile';
      return GameChange.fail(
        'It went to ${to.gameName}, but couldn\'t be taken out of '
        '${from.gameName} ($why): it is in both now',
      );
    }
    final reason = r.reason == 'fits as it is' ? '' : r.reason;
    return GameChange.ok(
      save: t.save,
      save2: r.save,
      mon: _summary(r.mon!),
      reason: reason,
    );
  } on _Changed {
    return const GameChange.changed(changedOnDiskText);
  } on _Refused catch (e) {
    return GameChange.fail(e.why);
  } on Object catch (e) {
    return GameChange.fail('$e');
  }
}

// ---- nicknames and held items (pkhelper's nick / item / nickfile / itemfile)

/// Arguments of [editInGame]: exactly one of [nickname] ('' takes it off)
/// and [item] (the game's item number, 0 = none).
typedef EditArgs = ({
  String save,
  Uint8List expected,
  int box, // -1: the party
  int slot,
  String? nickname,
  int? item,
  String backups,
});

/// A nickname or held item for a Pokémon in a game save (box, or the party
/// with box -1), written the safe way (as the helper's `nick` / `item`:
/// the save must be unchanged, the new one is read back and checked, the
/// old one backed up, then swapped in).
GameChange editInGame(EditArgs a) {
  try {
    final s = _openExpected(a.save, a.expected);
    final r = a.nickname != null
        ? s.setNickname(a.box, a.slot, a.nickname!)
        : s.setItem(a.box, a.slot, a.item ?? 0);
    if (!r.ok) return GameChange.fail(r.error);
    final want = r.mon!;
    final total = _countAll(s), party = s.party.length;
    writeSaveSafely(a.save, a.expected, r.save!, a.backups, (g) {
      final m = g.monAt(a.box, a.slot);
      return m != null &&
          _countAll(g) == total &&
          g.party.length == party &&
          m.species == want.species &&
          m.nickname == want.nickname &&
          m.heldItem == want.heldItem;
    });
    return GameChange.ok(save: r.save, mon: _summary(want));
  } on _Changed {
    return const GameChange.changed(changedOnDiskText);
  } on _Refused catch (e) {
    return GameChange.fail(e.why);
  } on Object catch (e) {
    return GameChange.fail('$e');
  }
}

/// Arguments of [editPokevilleFile].
typedef FileEditArgs = ({
  String pokeville,
  String file, // box.json's `file`
  String? nickname,
  int? item,
});

/// A nickname or held item for a Pokémon in Pokéville: its mons/ file is
/// rewritten as the PC's helper rewrites it (`nickfile` / `itemfile`): the
/// new bytes to `<file>.new`, read back and checked, the old file kept as
/// `<file>.bak`, then swapped in. box.json is the caller's (it takes the
/// new summary, [GameChange.mon]). Only Gen 1-3 files (.pk1 .pk2 .pk3).
GameChange editPokevilleFile(FileEditArgs a) {
  final path = PokeBoxStore.absolute(a.pokeville, a.file);
  final tmp = File('$path.new');
  try {
    final f = File(path);
    if (!f.existsSync()) {
      return const GameChange.fail(
        "that Pokémon's file isn't in Pokéville's mons folder",
      );
    }
    final bytes = f.readAsBytesSync();
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    final m = ps.Mon.fromFile(bytes, ext: ext);
    if (m == null) {
      return GameChange.fail(
        '${ext.toUpperCase()} Pokémon are changed on the PC (they need PKHeX)',
      );
    }
    final e = a.nickname != null
        ? m.withNickname(a.nickname!)
        : m.withItem(a.item ?? 0);
    if (!e.ok) return GameChange.fail(e.error);
    final want = e.mon!;
    final data = want.bytes;
    tmp.writeAsBytesSync(data, flush: true);
    final back = tmp.readAsBytesSync();
    final again = ps.Mon.fromFile(back, ext: ext);
    if (!_same(back, data) ||
        again == null ||
        again.species != want.species ||
        again.nickname != want.nickname ||
        again.heldItem != want.heldItem) {
      _delete(tmp);
      return const GameChange.fail(
        "the changed Pokémon didn't read back right, nothing was written",
      );
    }
    if (!_same(f.readAsBytesSync(), bytes)) {
      _delete(tmp);
      return const GameChange.changed(
        "That Pokémon's file changed meanwhile (a sync came in), so nothing "
        'was changed',
      );
    }
    f.copySync('$path.bak');
    tmp.renameSync(path); // replaces it (Windows too)
    return GameChange.ok(file: a.file, mon: _summary(again));
  } on Object catch (e) {
    _delete(tmp);
    return GameChange.fail('$e');
  }
}
