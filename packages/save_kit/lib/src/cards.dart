/// Every save from every card of the eight consoles, newest first, named
/// and matched to the library's games (ported from the PC's
/// MemoryCards.gd). Read only. The folders to look in come from the app
/// (they differ on Windows, Linux and Android).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'card_image.dart';
import 'formats/dreamcast.dart';
import 'formats/gamecube.dart';
import 'formats/n64.dart';
import 'formats/neogeo.dart';
import 'formats/ps1.dart';
import 'formats/ps2.dart';
import 'formats/ps3.dart';
import 'formats/saturn.dart';
import 'model.dart';

/// A game the library knows (for naming saves and play time).
typedef LibraryGame = ({String id, String title, String system, String serial});

/// Play history per game id.
typedef PlayStats = ({int seconds, int sessions, int last});

abstract final class MemoryCards {
  static const cardExt = [
    'mcd', 'mcr', 'mc', 'srm', 'ps2', 'mc2', 'bin', 'vmu', 'raw', 'gcp', //
    'mpk', 'pak', 'cpk', 'bkr', 'bcr', 'sav', 'mem', 'gci',
  ];

  /// RetroArch sorts saves by core; Dolphin goes saves/.../GC/USA/Card A.
  static const depth = 6;

  /// Saves from the internet, apart from the emulators' own.
  static const downloads = 'Downloaded Saves';
  static const downloadsWas = 'Memory Card Test Saves';

  /// These consoles often keep one card per game, named after it...
  static const ownCard = ['PS1', 'N64', 'SATURN', 'NEO GEO'];

  /// ...unless the name is one of a shared card's.
  static final shared = RegExp(
    r'^(test |ps1 card|pcsx-card|vmu|gc card|mcd|mempak|internal|backup|memcard|memorycard)',
    caseSensitive: false,
  );

  /// Every card and every save under [dirs], saves matched to [games].
  static ({List<MemoryCard> cards, List<CardSave> saves}) readAll(
    List<String> dirs, {
    List<LibraryGame> games = const [],
    Map<String, PlayStats> played = const {},
    Map<String, String> names = const {},
  }) {
    final cards = readCards(dirs);
    final saves = [for (final c in cards) ...c.saves];
    for (final s in saves) {
      identify(s, games, names, played);
    }
    saves.sort(
      (a, b) => a.modified != b.modified
          ? b.modified.compareTo(a.modified)
          : a.id.compareTo(b.id),
    );
    return (cards: cards, saves: saves);
  }

  /// By console, then by name. Looks inside sub-folders.
  static List<MemoryCard> readCards(List<String> dirs) {
    final out = <MemoryCard>[];
    final seen = <String>{};
    for (final d in dirs) {
      _walk(d, 0, seen, out);
    }
    _tellApart(out);
    out.sort(
      (a, b) => a.system != b.system
          ? CardSystems.rank(a.system).compareTo(CardSystems.rank(b.system))
          : a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return out;
  }

  /// Where it lives: two cards can share a name (DuckStation's Jersey
  /// Devil and RetroArch's).
  static String place(MemoryCard c) {
    if (c.system == 'PS3') return 'RPCS3';
    var dir = (c.isFolder ? c.path : p.dirname(c.path)).replaceAll(r'\', '/');
    if (c.isFolder && c.system == 'GC') dir = p.dirname(dir);
    while (MemoryCard.plainFolders.contains(p.basename(dir).toLowerCase())) {
      dir = p.dirname(dir);
    }
    return p.basename(dir);
  }

  static bool isDownload(MemoryCard c) {
    final path = '${c.path.replaceAll(r'\', '/')}/';
    return path.contains('/$downloads/') || path.contains('/$downloadsWas/');
  }

  /// Card 1 and card 2 of one game carry the game's name: those get their
  /// number too.
  static void _tellApart(List<MemoryCard> cards) {
    final alike = <String, List<MemoryCard>>{};
    for (final c in cards) {
      alike.putIfAbsent('${c.system}|${c.name}|${place(c)}', () => []).add(c);
    }
    for (final group in alike.values) {
      if (group.length < 2) continue;
      String ending(MemoryCard c) {
        final base = p.basenameWithoutExtension(c.path);
        final i = base.lastIndexOf('_');
        return i >= 0 ? base.substring(i + 1) : '';
      }

      final numbers = {
        for (final c in group)
          if (int.tryParse(ending(c)) != null) ending(c),
      };
      for (var i = 0; i < group.length; i++) {
        final c = group[i];
        c.name +=
            ', card ${numbers.length == group.length ? ending(c) : i + 1}';
      }
    }
  }

  static void _walk(
    String dir,
    int level,
    Set<String> seen,
    List<MemoryCard> out,
  ) {
    // Android 11+ refuses even a look into another app's private folder
    // (Android/data/...): such a folder is skipped, never the whole scan.
    try {
      _walkIn(dir, level, seen, out);
    } on FileSystemException {
      return;
    }
  }

  static void _walkIn(
    String dir,
    int level,
    Set<String> seen,
    List<MemoryCard> out,
  ) {
    final d = Directory(dir);
    if (level > depth || !d.existsSync() || !seen.add(dir.toLowerCase())) {
      return;
    }
    if (File(p.join(dir, Ps2Card.folderMark)).existsSync()) {
      out.add(
        Ps2Card.parseFolder(dir, cardName(p.basename(dir)))..isFolder = true,
      );
      return;
    }
    if (Ps3Card.isSavedata(dir)) {
      final ps3 = MemoryCard()
        ..modified = d.statSync().modified.millisecondsSinceEpoch ~/ 1000;
      out.add(Ps3Card.parseFolder(dir, ps3));
      return;
    }
    List<FileSystemEntity> entries;
    try {
      entries = d.listSync();
    } catch (_) {
      return;
    }
    var hasGci = false;
    for (final f in entries.whereType<File>()) {
      final ext = p.extension(f.path).replaceFirst('.', '').toLowerCase();
      if (ext == 'gci') {
        hasGci = true;
      } else if (cardExt.contains(ext)) {
        out.addAll(readFile(f.path));
      }
    }
    if (hasGci) {
      final parent = p.basename(p.dirname(dir));
      final downloaded = parent == downloads || parent == downloadsWas;
      final card = MemoryCard()
        ..path = dir
        ..name = downloaded
            ? p.basename(dir)
            : cardName('$parent ${p.basename(dir)}'.trim())
        ..modified = d.statSync().modified.millisecondsSinceEpoch ~/ 1000;
      out.add(GcCard.parseFolder(dir, card));
    }
    for (final sub in entries.whereType<Directory>()) {
      _walk(sub.path, level + 1, seen, out);
    }
  }

  /// Empty = not a memory card (a saves folder holds other things too).
  static List<MemoryCard> readFile(String path) {
    final f = File(path);
    final int size;
    try {
      size = f.lengthSync();
    } catch (_) {
      return [];
    }
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    if (!CardImage.worthReading(size, ext)) return [];
    final Uint8List data;
    try {
      data = f
          .readAsBytesSync(); // held as short as possible: the emulator may want it
    } catch (_) {
      return [];
    }
    final when = f.statSync().modified.millisecondsSinceEpoch ~/ 1000;
    final parts = CardImage.find(data, ext);
    final base = cardName(p.basenameWithoutExtension(path));
    if (parts.isEmpty && CardImage.isBlankPs2(data, ext)) {
      return [
        MemoryCard()
          ..system = 'PS2'
          ..name = base
          ..path = path
          ..modified = when
          ..span = data.length
          ..unformatted = true
          ..error = 'not formatted', // nothing but Format may use it
      ];
    }
    return [
      for (var i = 0; i < parts.length; i++)
        parse(
          CardImage.take(
            data,
            MemoryCard()
              ..system = parts[i].system
              ..offset = parts[i].offset
              ..span = parts[i].span
              ..gzip = parts[i].gzip,
          ),
          MemoryCard()
            ..system = parts[i].system
            ..offset = parts[i].offset
            ..span = parts[i].span
            ..gzip = parts[i].gzip
            ..name = parts.length > 1 ? '$base, pak ${i + 1}' : base
            ..path = path
            ..modified = when,
        ),
    ];
  }

  /// A card from bytes already in hand (the write side reads them fresh).
  static MemoryCard parse(Uint8List bytes, MemoryCard card) {
    var read = card;
    switch (card.system) {
      case 'PS1':
        read = Ps1Card.parse(bytes, card.name, card.path, card.modified);
      case 'PS2':
        read = Ps2Card.parse(bytes, card.name, card.path, card.modified);
      case 'DC':
        VmuCard.parse(bytes, card);
      case 'GC':
        GcCard.parse(bytes, card);
      case 'N64':
        PakCard.parse(bytes, card);
      case 'SATURN':
        SaturnCard.parse(bytes, card);
      case 'NEO GEO':
        NeoCard.parse(bytes, card);
    }
    return read
      ..offset = card.offset
      ..span = card.span
      ..gzip = card.gzip;
  }

  /// "Mcd001" -> "PS2 Card 1", "Jersey Devil (USA)_1" -> "Jersey Devil"
  static String cardName(String file) {
    RegExpMatch? m(String re) =>
        RegExp(re, caseSensitive: false).firstMatch(file);
    final pcsx2 = m(r'^mcd0*(\d+)$');
    if (pcsx2 != null) return 'PS2 Card ${pcsx2.group(1)}';
    final sharedCard = m(r'^shared_card_(\d+)$');
    if (sharedCard != null) return 'PS1 Card ${sharedCard.group(1)}';
    final vmu = m(r'^vmu_save_([a-d][12])$');
    if (vmu != null) return 'VMU ${vmu.group(1)!.toUpperCase()}';
    final gc = m(r'^memorycard([ab])\.(\w+)$');
    if (gc != null) {
      return 'GC Card ${gc.group(1)!.toUpperCase()} (${gc.group(2)!.toUpperCase()})';
    }
    var s = file.replaceFirst(RegExp(r'_\d$'), '');
    s = s.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
    return s.isNotEmpty ? s : file;
  }

  /// The English name PCSX2's GameIndex.yaml has for each serial.
  static Map<String, String> indexNames(String path, List<String> serials) {
    final f = File(path);
    if (path.isEmpty || serials.isEmpty || !f.existsSync()) return {};
    final text = f.readAsStringSync();
    return {
      for (final s in serials)
        if (indexName(text, s).isNotEmpty) s: indexName(text, s),
    };
  }

  static String indexName(String text, String serial) {
    final at = text.startsWith('$serial:') ? 0 : text.indexOf('\n$serial:');
    if (at < 0) return '';
    var name = '';
    var lineAt = text.indexOf('\n', at + 1);
    for (var i = 0; i < 40 && lineAt >= 0; i++) {
      final end = text.indexOf('\n', lineAt + 1);
      var line = text.substring(lineAt + 1, end >= 0 ? end : text.length);
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
      if (line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('#')) {
        break;
      }
      if (line.startsWith('  name-en:')) return _unquote(line.substring(10));
      if (line.startsWith('  name:')) name = _unquote(line.substring(7));
      lineAt = end;
    }
    return name;
  }

  static String _unquote(String s) {
    final t = s.trim();
    return t.length >= 2 && t.startsWith('"') && t.endsWith('"')
        ? t.substring(1, t.length - 1)
        : t;
  }

  /// "Saru Get You - Million Monkeys" and "Saru! Get You! Million Monkeys"
  /// give the same key.
  static String matchKey(String title) {
    final words = <String>[];
    var word = StringBuffer();
    for (final c in '${title.toLowerCase()} '.runes) {
      final ok =
          (c >= 0x61 && c <= 0x7A) || (c >= 0x30 && c <= 0x39) || c > 127;
      if (ok) {
        word.writeCharCode(c);
      } else if (c != 0x27) {
        final w = word.toString();
        if (w.isNotEmpty && !const ['the', 'a', 'an'].contains(w)) words.add(w);
        word = StringBuffer();
      }
    }
    words.sort();
    return words.join(' ');
  }

  static void identify(
    CardSave s,
    List<LibraryGame> games,
    Map<String, String> names,
    Map<String, PlayStats> played,
  ) {
    var known = names[s.serial] ?? '';
    final card = s.card;
    if (known.isEmpty &&
        ownCard.contains(s.system) &&
        card != null &&
        !isDownload(card) &&
        !shared.hasMatch(card.name)) {
      // A downloaded card is named for what's on it, not for one game.
      known = card.name.split(', pak ').first.split(', card ').first;
    } else if (known.isEmpty &&
        (s.system == 'DC' || s.system == 'GC') &&
        s.titleLines.isNotEmpty) {
      known = s.titleLines.first; // what those saves call their game
    } else if (known.isEmpty && s.system == 'PS3') {
      known = s.ps3Title;
    }
    final key = matchKey(known);
    LibraryGame? hit;
    for (final g in games) {
      if (g.system != s.system) continue;
      if (s.serial.isNotEmpty && g.serial == s.serial) {
        hit = g;
        break;
      }
      if (hit == null && key.isNotEmpty && matchKey(g.title) == key) hit = g;
    }
    s.game = known;
    if (hit == null) return;
    s.game = s.system == 'PS3' ? Ps3Card.clean(hit.title) : hit.title;
    s.gameId = hit.id;
    final pl = played[s.gameId];
    if (pl != null) {
      s.playedS = pl.seconds;
      s.sessions = pl.sessions;
      s.lastPlayed = pl.last;
    }
  }
}
