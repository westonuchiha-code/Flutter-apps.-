/// Start game handed over from the standalone Save Manager app: it has no
/// game library, so on Android it sends the save's console and title to
/// the menu (an explicit intent to MainActivity), and the menu finds the
/// game the same way its Memory Card row does.
library;

import 'package:save_kit/save_kit.dart';

import 'library/scanner.dart';

/// The save manager's consoles (save_kit's), by this library's system ids.
const saveSystems = {
  'ps1': 'PS1',
  'n64': 'N64',
  'saturn': 'SATURN',
  'dreamcast': 'DC',
  'gamecube': 'GC',
};

/// What the Save Manager asked to start (the intent's extras, as
/// MainActivity hands them over).
class SaveStartRequest {
  const SaveStartRequest({
    required this.system,
    this.title = '',
    this.serial = '',
    this.file = '',
  });

  /// From the extras map; null when it isn't a start request.
  static SaveStartRequest? fromMap(Map<Object?, Object?>? m) {
    if (m == null) return null;
    final system = '${m['start_game_system'] ?? ''}'.trim();
    if (system.isEmpty) return null;
    return SaveStartRequest(
      system: system,
      title: '${m['start_game_title'] ?? ''}'.trim(),
      serial: '${m['start_game_serial'] ?? ''}'.trim(),
      file: '${m['start_game_file'] ?? ''}'.trim(),
    );
  }

  /// save_kit's console ('PS1', 'GC'...).
  final String system;

  /// The save's game: matched title, the card's name for one-card-per-game
  /// consoles, or the save's own first title line (GameCube, Dreamcast).
  final String title;

  /// 'SLUS-20946' style, when the save has one.
  final String serial;

  /// The save's file (a .gci, the card), for messages.
  final String file;

  /// What to call it in a message.
  String get name => title.isNotEmpty
      ? title
      : file.isNotEmpty
      ? file
      : 'that save';
}

/// The library game [r] is for, or null: the Memory Card row's matching
/// (save_kit's identify: same console, then [MemoryCards.matchKey] of the
/// title; the library has no serials yet, so [SaveStartRequest.serial]
/// isn't compared), also trying each ROM's file name (a RetroArch card is
/// named after it, region and all). Accents are folded first, so a
/// save's "Pokémon" finds a ROM's "Pokemon".
Game? gameForSave(List<Game> games, SaveStartRequest r) {
  final key = _key(r.title);
  if (key.isEmpty) return null;
  Game? byFile;
  for (final g in games) {
    if (saveSystems[g.system] != r.system) continue;
    if (_key(g.title) == key) return g;
    if (byFile == null && _key(g.saveName) == key) byFile = g;
  }
  return byFile;
}

String _key(String title) => MemoryCards.matchKey(_fold(title));

const _plain = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', //
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', //
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', //
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', //
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ñ': 'n', 'ç': 'c', //
};

String _fold(String s) {
  final out = StringBuffer();
  for (final c in s.toLowerCase().split('')) {
    out.write(_plain[c] ?? c);
  }
  return out.toString();
}

/// The toast when nothing matches.
String noGameText(SaveStartRequest r) =>
    'No game in the library matches ${r.name}';
