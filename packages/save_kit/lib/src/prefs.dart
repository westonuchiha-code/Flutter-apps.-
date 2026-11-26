/// Small pieces around the cards (ported from the PC's CardOwners.gd,
/// CardNames.gd, CardFavorites.gd): which emulator has a card open, the
/// names given to cards in this app, and the saves with a gold star.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'model.dart';
import 'store.dart';

/// Which emulator keeps a card in its memory. While it runs the card can't
/// be changed: it would write its own copy back over the change.
abstract final class CardOwners {
  static const emulators = [
    ('pcsx2', 'PCSX2'),
    ('duckstation', 'DuckStation'),
    ('retroarch', 'RetroArch'),
    ('rmg', 'RMG'),
    ('dolphin', 'Dolphin'),
    ('rpcs3', 'RPCS3'),
    ('ppsspp', 'PPSSPP'),
    ('flycast', 'Flycast'),
    ('redream', 'Redream'),
    ('mupen', 'Mupen64Plus'),
    ('yabause', 'Yabause'),
    ('mednafen', 'Mednafen'),
  ];
  static const cantTell =
      "Can't tell whether the emulator is closed, so nothing was changed";

  /// For CardStore.ownerRunning on Windows and Linux (Android can't list
  /// other apps: the host says what it started instead).
  static String inUse(String path) {
    final names = processNames();
    return names == null ? cantTell : reason(path, names);
  }

  /// The running programs' names (lower case), or null if they can't be
  /// read here.
  static List<String>? processNames() {
    try {
      if (Platform.isWindows) {
        final r = Process.runSync('tasklist.exe', ['/NH', '/FO', 'CSV']);
        if (r.exitCode != 0) return null;
        return [
          for (final line in '${r.stdout}'.split('\n'))
            if (line.startsWith('"')) line.split('"')[1].toLowerCase(),
        ];
      }
      if (Platform.isLinux) {
        return [
          for (final d in Directory('/proc').listSync().whereType<Directory>())
            if (int.tryParse(p.basename(d.path)) != null)
              () {
                try {
                  return File(
                    p.join(d.path, 'comm'),
                  ).readAsStringSync().trim().toLowerCase();
                } catch (_) {
                  return '';
                }
              }(),
        ].where((s) => s.isNotEmpty).toList();
      }
    } catch (_) {}
    return null;
  }

  static String reason(String path, List<String> running) {
    if (running.isEmpty) return cantTell;
    for (final (key, name) in owners(path)) {
      if (running.any((r) => r.startsWith(key))) {
        return 'Close $name first: it has this memory card open';
      }
    }
    return '';
  }

  /// The emulator named in the card's path; a card kept elsewhere could be
  /// anyone's, so all of them count.
  static List<(String, String)> owners(String path) {
    final folders = p
        .dirname(path.replaceAll(r'\', '/'))
        .toLowerCase()
        .split('/');
    final hits = [
      for (final e in emulators)
        if (folders.any((f) => f.startsWith(e.$1))) e,
    ];
    return hits.isNotEmpty ? hits : emulators;
  }
}

Map<String, Object?> _readJson(String file) {
  try {
    final f = File(file);
    if (!f.existsSync()) return {};
    final j = jsonDecode(f.readAsStringSync());
    return j is Map<String, Object?> ? j : {};
  } catch (_) {
    return {};
  }
}

/// Rename gives a card a name in this app. The file keeps its own:
/// emulators find cards by file name.
abstract final class CardNames {
  static const nameMax = 32;

  static void apply(List<MemoryCard> cards, String file) {
    final names = _readJson(file);
    for (final c in cards) {
      final n = '${names[c.key().toLowerCase()] ?? ''}';
      if (n.isNotEmpty) c.name = n;
    }
  }

  /// An empty name goes back to the file's own.
  static String setNameFor(
    MemoryCard card,
    String name,
    String file,
    CardSafety safety,
  ) {
    final no = safety.refusal(file);
    if (no.isNotEmpty) return no;
    final names = _readJson(file);
    var clean = name.trim();
    if (clean.length > nameMax) clean = clean.substring(0, nameMax);
    final key = (card.home.isNotEmpty ? card.home : card.key()).toLowerCase();
    if (clean.isEmpty) {
      names.remove(key);
    } else {
      names[key] = clean;
    }
    try {
      File(file)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(jsonEncode(names));
      return '';
    } catch (_) {
      return "Couldn't save that name";
    }
  }
}

/// The saves with a gold star: never deleted, formatted away or
/// overwritten; backing up and moving are fine. If the list can't be read
/// it protects everything, rather than nothing.
class CardFavorites {
  CardFavorites(this.file, this.safety);
  final String file;
  final CardSafety safety;
  String error = '';
  final _on = <String>{};

  static const unreadable =
      "Your favorites list can't be read, so nothing was deleted or replaced";
  static const _temp = '.new';

  /// A folder of .gci can repeat a name, so there the file is the save.
  static String keyOf(MemoryCard card, CardSave s) {
    final which = card.isFolder && s.file.isNotEmpty
        ? s.file.toLowerCase()
        : s.id;
    return '${card.key().replaceAll(r'\', '/').toLowerCase()}|$which';
  }

  void reload() {
    error = '';
    _on.clear();
    var from = File(file);
    if (!from.existsSync()) {
      from = File(file + _temp); // stopped halfway through saving
      if (!from.existsSync()) return;
    }
    try {
      final j = jsonDecode(from.readAsStringSync());
      if (j is! Map) throw const FormatException();
      _on.addAll(j.keys.map((k) => '$k'));
    } catch (_) {
      error = unreadable;
    }
  }

  bool has(MemoryCard card, CardSave s) => _on.contains(keyOf(card, s));

  void mark(List<MemoryCard> cards) {
    reload();
    for (final c in cards) {
      for (final s in c.saves) {
        s.favorite = has(c, s);
      }
    }
  }

  /// '' = saved.
  String setFor(List<CardSave> saves, bool on) {
    final keys = [
      for (final s in saves)
        if (s.card != null) keyOf(s.card!, s),
    ];
    return _change(on ? keys : const [], on ? const [] : keys);
  }

  /// A moved favorite is still one.
  String carry(List<String> from, List<String> to) => _change(to, from);

  String _change(List<String> add, List<String> drop) {
    final no = safety.refusal(file);
    if (no.isNotEmpty) return no;
    reload();
    if (error.isNotEmpty) return error;
    _on
      ..removeAll(drop)
      ..addAll(add);
    final text = jsonEncode({for (final k in _on) k: true});
    try {
      Directory(p.dirname(file)).createSync(recursive: true);
      final temp = File(file + _temp)..writeAsStringSync(text, flush: true);
      if (temp.readAsStringSync() != text) {
        return "Couldn't save your favorites";
      }
      final f = File(file);
      if (f.existsSync()) f.deleteSync();
      temp.renameSync(file);
      return '';
    } catch (_) {
      return "Couldn't save your favorites";
    }
  }
}
