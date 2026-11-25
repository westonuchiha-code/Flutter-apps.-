import 'dart:io';

import 'package:path/path.dart' as p;

import 'systems.dart';

/// One game found in the ROMs folder.
class Game {
  const Game({
    required this.system,
    required this.path,
    required this.title,
    required this.size,
    this.art,
    this.demo = false,
  });

  final String system;

  /// Full path to the file to start (a .m3u for multi-disc games).
  final String path;
  final String title;

  /// Bytes, with the tracks a cue sheet lists.
  final int size;

  /// A picture beside the game with the same name (Game.png / Game.jpg).
  final String? art;
  final bool demo;

  /// Stable id: the system and the file name (the same on every device as
  /// long as the ROM files are named the same).
  String get id => '$system:${p.basename(path).toLowerCase()}';

  /// The ROM's file name without extension: what RetroArch names saves by.
  String get saveName => p.basenameWithoutExtension(path);

  Map<String, Object?> toJson() => {
    'system': system,
    'path': path,
    'title': title,
    'size': size,
    if (art != null) 'art': art,
    if (demo) 'demo': true,
  };

  factory Game.fromJson(Map j) => Game(
    system: j['system'] as String,
    path: j['path'] as String,
    title: j['title'] as String,
    size: (j['size'] as num?)?.toInt() ?? 0,
    art: j['art'] as String?,
    demo: j['demo'] == true,
  );
}

/// "Super Mario World (USA) [!]" → "Super Mario World"; disc numbers stay.
String cleanTitle(String fileName) {
  var t = fileName;
  for (final m in RegExp(r'\s*[\(\[]([^\)\]]*)[\)\]]').allMatches(fileName)) {
    final inner = m.group(1)!.toLowerCase();
    if (!(inner.startsWith('disc') ||
        inner.startsWith('disk') ||
        inner.startsWith('cd'))) {
      t = t.replaceFirst(m.group(0)!, '');
    }
  }
  t = t.replaceAll('_', ' ').trim();
  return t.isEmpty ? fileName : t;
}

final _demo = RegExp(
  r'\((demo|kiosk|sample|trial|taikenban|preview|demo disc)[^)]*\)'
  r'|playstation underground|official (u\.s\. )?playstation magazine'
  r'|jam ?pac?k|playable preview|interactive cd sampler|demo (disc|disk|cd)'
  r'|dreamcast magazine|official dreamcast|sega flash|net yaroze',
  caseSensitive: false,
);

/// Demo discs by their Redump tags and well-known series names (not just
/// "demo": Demolition Racer is a game).
bool isDemoName(String name) => _demo.hasMatch(name);

/// Files a .cue / .ccd / .gdi / .m3u points at (full paths).
List<String> sheetRefs(String sheet) {
  final ext = p.extension(sheet).toLowerCase().replaceFirst('.', '');
  final base = p.dirname(sheet);
  final out = <String>[];
  String text;
  try {
    text = File(sheet).readAsStringSync();
  } catch (_) {
    return out;
  }
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    var name = '';
    if (ext == 'cue' || ext == 'ccd') {
      if (line.toUpperCase().startsWith('FILE')) {
        final q1 = line.indexOf('"'), q2 = line.lastIndexOf('"');
        name = q1 >= 0 && q2 > q1
            ? line.substring(q1 + 1, q2)
            : (line.split(' ').length > 1 ? line.split(' ')[1] : '');
      }
    } else if (ext == 'gdi') {
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length >= 5) name = parts[4].replaceAll('"', '');
    } else if (ext == 'm3u') {
      if (line.isNotEmpty && !line.startsWith('#')) name = line;
    }
    if (name.isNotEmpty) {
      out.add(p.normalize(p.join(base, name.replaceAll('\\', '/'))));
    }
  }
  return out;
}

void _collect(Directory dir, List<String> exts, List<String> out, int depth) {
  if (depth > maxDepth || !dir.existsSync()) return;
  final List<FileSystemEntity> items;
  try {
    items = dir.listSync(followLinks: false);
  } catch (_) {
    return;
  }
  for (final e in items) {
    final name = p.basename(e.path);
    if (name.startsWith('.')) continue;
    if (e is File) {
      final ext = p.extension(name).toLowerCase().replaceFirst('.', '');
      if (exts.contains(ext)) out.add(e.path);
    } else if (e is Directory) {
      _collect(e, exts, out, depth + 1);
    }
  }
}

/// Game files under a console folder (and sub-folders, [maxDepth] deep).
/// Disc tracks a .cue/.gdi/.m3u/.ccd lists are left out so each game shows
/// once.
List<String> gameFiles(String dir, List<String> exts) {
  final all = <String>[];
  _collect(Directory(dir), exts, all, 0);
  final used = <String>{};
  for (final f in all) {
    final ext = p.extension(f).toLowerCase();
    if (const ['.cue', '.gdi', '.m3u', '.ccd'].contains(ext)) {
      for (final r in sheetRefs(f)) {
        used.add(r.toLowerCase());
      }
    }
  }
  return [
    for (final f in all)
      if (!used.contains(p.normalize(f).toLowerCase())) f,
  ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
}

int _sizeOf(String path) {
  var total = 0;
  try {
    total = File(path).lengthSync();
    final ext = p.extension(path).toLowerCase();
    if (const ['.cue', '.gdi', '.m3u', '.ccd'].contains(ext)) {
      for (final r in sheetRefs(path)) {
        final f = File(r);
        if (f.existsSync()) total += _sizeOf(r);
      }
    }
  } catch (_) {}
  return total;
}

String? _artFor(String path) {
  final base = p.withoutExtension(path);
  for (final e in const ['.png', '.jpg', '.jpeg', '.webp']) {
    if (File('$base$e').existsSync()) return '$base$e';
  }
  return null;
}

Game _game(GameSystem s, String path, {bool demo = false}) => Game(
  system: s.id,
  path: path,
  title: cleanTitle(p.basenameWithoutExtension(path)),
  size: _sizeOf(path),
  art: _artFor(path),
  demo: demo || isDemoName(p.basename(path)),
);

/// Every game in [romsDir], console by console. Runs in the background
/// (top-level, plain data in and out).
List<Game> scanLibrary(String romsDir) {
  final out = <Game>[];
  for (final s in systems) {
    for (final f in gameFiles(p.join(romsDir, s.folder), s.exts)) {
      out.add(_game(s, f));
    }
    if (demoSystems.contains(s.id)) {
      for (final f in gameFiles(
        p.join(romsDir, demoFolder, s.folder),
        s.exts,
      )) {
        out.add(_game(s, f, demo: true));
      }
    }
  }
  return out;
}

/// The same, as JSON (for runInBackground).
List<Map<String, Object?>> scanLibraryJson(String romsDir) => [
  for (final g in scanLibrary(romsDir)) g.toJson(),
];

/// Makes the empty console folders (and the demo disc folders).
void makeConsoleFolders(String romsDir) {
  for (final s in systems) {
    Directory(p.join(romsDir, s.folder)).createSync(recursive: true);
  }
  for (final id in demoSystems) {
    Directory(p.join(romsDir, demoFolder, systemById(id)!.folder))
        .createSync(recursive: true);
  }
}
