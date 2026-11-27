/// "Get Emulators": which app to get from Google Play for each kind of
/// game, and what the menu needs set in it afterwards.
library;

import 'package:cross_save/cross_save.dart';
import 'package:path/path.dart' as p;

import '../files_path.dart';
import '../launch.dart';
import 'systems.dart';

class EmulatorGuide {
  const EmulatorGuide(this.runner, this.playPackage, this.forWhat);
  final Runner runner;

  /// The package Google Play lists (one of [runnerPackages]).
  final String playPackage;

  /// One line: what it plays here.
  final String forWhat;
}

const emulatorGuides = [
  EmulatorGuide(Runner.retroarch, 'com.retroarch', 'Nintendo, Sega, arcade'),
  EmulatorGuide(
    Runner.duckstation,
    'com.github.stenzek.duckstation',
    'PS1, saves match the PC',
  ),
  EmulatorGuide(Runner.ppsspp, 'org.ppsspp.ppsspp', 'PSP'),
  EmulatorGuide(Runner.dolphin, 'org.dolphinemu.dolphinemu', 'GameCube'),
];

/// Google Play's app, else its web page (any browser).
List<String> playUrls(String package) => [
  'market://details?id=$package',
  'https://play.google.com/store/apps/details?id=$package',
];

/// Whether any build of [r] is installed.
bool hasRunner(Runner r, Set<String> installed) =>
    runnerPackages[r]!.any(installed.contains);

/// The names RetroArch's Core Downloader lists the cores under.
const coreNames = {
  'mesen': 'Nintendo - NES / Famicom (Mesen)',
  'fceumm': 'Nintendo - NES / Famicom (FCEUmm)',
  'nestopia': 'Nintendo - NES / Famicom (Nestopia)',
  'snes9x': 'Nintendo - SNES / SFC (Snes9x - Current)',
  'mupen64plus_next': 'Nintendo - Nintendo 64 (Mupen64Plus-Next)',
  'gambatte': 'Nintendo - Game Boy / Color (Gambatte)',
  'mgba': 'Nintendo - Game Boy Advance (mGBA)',
  'genesis_plus_gx': 'Sega - MS/GG/MD/CD (Genesis Plus GX)',
  'yabause': 'Sega - Saturn (Yabause)',
  'mednafen_saturn': 'Sega - Saturn (Beetle Saturn)',
  'flycast': 'Sega - Dreamcast/NAOMI (Flycast)',
  'swanstation': 'Sony - PlayStation (SwanStation)',
  'pcsx_rearmed': 'Sony - PlayStation (PCSX ReARMed)',
  'mame': 'Arcade (MAME)',
  'mame2003_plus': 'Arcade (MAME 2003-Plus)',
  'fbneo': 'Arcade (FinalBurn Neo)',
};

/// The RetroArch cores to download, in the menu's order: per core (the
/// one each console uses, [chosen] overriding the first), the consoles
/// it plays. Consoles another emulator plays first (PS1: DuckStation) are
/// left out unless [preferRetroArch] names them.
List<({String core, String name, List<String> consoles})> coresNeeded({
  Map<String, String> chosen = const {},
  Set<String> preferRetroArch = const {},
}) {
  final out = <({String core, String name, List<String> consoles})>[];
  for (final s in systems) {
    if (s.cores.isEmpty || !s.runners.contains(Runner.retroarch)) continue;
    if (s.runners.first != Runner.retroarch &&
        !preferRetroArch.contains(s.id)) {
      continue;
    }
    final core = chosen[s.id] ?? s.cores.first;
    final i = out.indexWhere((c) => c.core == core);
    if (i < 0) {
      out.add((core: core, name: coreNames[core] ?? core, consoles: [s.short]));
    } else {
      out[i].consoles.add(s.short);
    }
  }
  return out;
}

/// The "Set It Up" steps for [r], with folders as My Files shows them.
List<String> setUpLines(
  Runner r,
  XmbFolders f, {
  bool ownRetroArchConfig = false,
  Map<String, String> cores = const {},
  Set<String> preferRetroArch = const {},
}) => switch (r) {
  Runner.retroarch => [
    if (ownRetroArchConfig)
      "Settings › RetroArch Settings is on RetroArch's own: switch it back "
          "to the menu's, or set RetroArch's save folder to "
          '${filesPath(f.raSaves)} yourself.'
    else
      'Saves: nothing to set. The menu starts RetroArch with its own '
          'settings file (${filesPath(f.raConfig)}), so saves go to '
          '${filesPath(f.raSaves)}, sorted by core as on the PC.',
    'Cores: open RetroArch once, then Main Menu › Online Updater › Core '
        'Downloader, and download:',
    for (final c in coresNeeded(
      chosen: cores,
      preferRetroArch: preferRetroArch,
    ))
      '   ${c.name}  (${c.consoles.join(', ')})',
    'BIOS files (Sega CD, Saturn, Dreamcast) go in ${filesPath(f.bios)}.',
    'Then try a game, or Settings › Emulators › a console › Test Launch.',
  ],
  Runner.duckstation => [
    'In DuckStation: Settings › Memory Cards.',
    'Memory card folder: choose ${filesPath(f.duckCards)}',
    'Memory Card 1 type: Separate Card Per Game (Title), as on the PC.',
    'If it asks for a data folder when it first opens, choose '
        '${filesPath(p.dirname(f.duckCards))} (its memcards folder is then '
        'the one above).',
    'It asks for a PlayStation BIOS file once; you can keep it in '
        '${filesPath(f.bios)}.',
  ],
  Runner.ppsspp => [
    'In PPSSPP: Settings › System › Memory Stick folder (Change Memory '
        'Stick folder).',
    'Choose ${filesPath(f.ppssppStick)}',
    'PPSSPP makes PSP › SAVEDATA inside it: those saves cross over.',
  ],
  Runner.dolphin => [
    'Nothing to set: the menu starts GameCube games in Dolphin.',
    "GameCube saves don't cross over from Android yet: Dolphin keeps them "
        'in its own folder. (Cross saves here: RetroArch, DuckStation, '
        'PPSSPP and Pokéville.)',
  ],
};
