/// Where this device keeps what it syncs, all inside the menu's own
/// `XMB Frontend` folder (shared storage: Android 11+ lets no app reach
/// another app's private folder, so every emulator is pointed here).
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'cross_save.dart';

/// Folders under `XMB Frontend/`.
class XmbFolders {
  const XmbFolders(this.root);

  /// `<storage>/XMB Frontend`.
  final String root;

  String get roms => p.join(root, 'ROMs');
  String get bios => p.join(root, 'BIOS');
  String get raSaves => p.join(root, 'Saves', 'RetroArch');
  String get raStates => p.join(root, 'States', 'RetroArch');
  String get duckCards => p.join(root, 'Saves', 'DuckStation', 'memcards');

  /// PPSSPP's memory stick (point PPSSPP here once).
  String get ppssppStick => p.join(root, 'Saves', 'PPSSPP');
  String get pspSaves => p.join(ppssppStick, 'PSP', 'SAVEDATA');

  /// Dolphin's saves, laid out like Dolphin's own user folder (and the
  /// PC's `Dolphin\User`): `GC/<USA|EUR|JAP>/Card A/*.gci` and
  /// `Wii/title/<hi>/<lo>/data/...`. Dolphin for Android can't be pointed
  /// here (Android 11+ keeps its user folder in its own app storage), so
  /// the player copies `GC` and `Wii` between the two (see the set-up).
  String get dolphin => p.join(root, 'Saves', 'Dolphin');
  String get dolphinGc => p.join(dolphin, 'GC');
  String get dolphinWii => p.join(dolphin, 'Wii', 'title');
  String get pokeville => p.join(root, 'Pokeville');
  String get comics => p.join(root, 'Comics');
  String get backups => p.join(root, 'Backups');
  String get raConfig => p.join(root, 'RetroArch', 'retroarch.cfg');

  /// The repo's folders this device syncs (PROTOCOL.md's layout).
  List<SyncMap> get maps => [
    SyncMap(
      'saves/retroarch',
      raSaves,
      exts: const [
        'srm', 'rtc', 'sav', 'mcd', 'mcr', 'eep', 'fla', 'sra', 'mpk', 'bin', //
      ],
    ),
    SyncMap('saves/duckstation/memcards', duckCards, exts: const ['mcd']),
    SyncMap('saves/ppsspp/SAVEDATA', pspSaves),
    // As the PC (CrossSave.gd): GCI folder cards or whole-card .raw files
    // (SRAM.raw is settings: never synced, see skipParts); Wii titles'
    // save folders without the system titles and channels' content.
    SyncMap('saves/dolphin/GC', dolphinGc, exts: const ['gci', 'raw']),
    SyncMap(
      'saves/dolphin/Wii/title',
      dolphinWii,
      skipDirs: const ['00000001', 'content'],
    ),
    SyncMap('pokeville', pokeville, skipDirs: const ['sent', 'save backups']),
  ];

  void create() {
    for (final d in [
      bios,
      raSaves,
      raStates,
      duckCards,
      pspSaves,
      dolphinGc,
      dolphinWii,
      pokeville,
      comics,
      backups,
      p.dirname(raConfig),
    ]) {
      Directory(d).createSync(recursive: true);
    }
  }
}

/// RetroArch settings the menu sets (the rest stay RetroArch's).
Map<String, String> retroArchSettings(XmbFolders f) => {
  // Saves in one folder per core, as on the PC (and in the repo).
  'savefile_directory': f.raSaves,
  'sort_savefiles_enable': 'true',
  'sort_savefiles_by_content_enable': 'false',
  'savefiles_in_content_dir': 'false',
  'savestate_directory': f.raStates,
  'sort_savestates_enable': 'true',
  'savestates_in_content_dir': 'false',
  'system_directory': f.bios,
  // Select + Start quits the game and comes back to the menu.
  'input_quit_gamepad_combo': '4',
  'quit_press_twice': 'false',
  'config_save_on_exit': 'true',
};

/// [existing] retroarch.cfg text with [keys] set (other lines kept).
String mergeRetroArchCfg(String existing, Map<String, String> keys) {
  final left = {...keys};
  final out = <String>[];
  for (final line in existing.split('\n')) {
    final m = RegExp(r'^\s*([A-Za-z0-9_]+)\s*=').firstMatch(line);
    final k = m?.group(1);
    if (k != null && left.containsKey(k)) {
      out.add('$k = "${left.remove(k)}"');
    } else if (line.isNotEmpty) {
      out.add(line);
    }
  }
  if (left.isNotEmpty && out.isEmpty) {
    out.add('# Set by XMB Frontend; RetroArch keeps its other settings here.');
  }
  for (final e in left.entries) {
    out.add('${e.key} = "${e.value}"');
  }
  return '${out.join('\n')}\n';
}

/// Writes the menu's RetroArch settings file (keeping what RetroArch added).
void writeRetroArchConfig(XmbFolders f) {
  final file = File(f.raConfig);
  final old = file.existsSync() ? file.readAsStringSync() : '';
  file
    ..createSync(recursive: true)
    ..writeAsStringSync(mergeRetroArchCfg(old, retroArchSettings(f)));
}

/// 'retroid' on the Retroid Pocket, else 'phone' (PROTOCOL.md's names).
String deviceName(String model) =>
    model.toLowerCase().contains('retroid') ? 'retroid' : 'phone';
