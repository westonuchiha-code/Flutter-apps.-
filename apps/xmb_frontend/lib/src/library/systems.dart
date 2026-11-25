/// The consoles the Android menu plays, matching the PC's ConsoleScanner
/// (same folder names and file types, so one ROMs folder works on both).
library;

/// What starts a console's games on Android.
enum Runner {
  retroarch('RetroArch'),
  ppsspp('PPSSPP'),
  duckstation('DuckStation'),
  dolphin('Dolphin');

  const Runner(this.label);
  final String label;
}

class GameSystem {
  const GameSystem({
    required this.id,
    required this.folder,
    required this.title,
    required this.short,
    required this.exts,
    required this.runners,
    this.cores = const [],
    this.note,
  });

  final String id;

  /// Folder name inside the ROMs folder (as on the PC).
  final String folder;
  final String title;

  /// Short name for lists ("PS1", "GBA").
  final String short;

  /// File types (lower case, no dot). Strict per folder, like the PC.
  final List<String> exts;

  /// In order of preference; the first one installed is used.
  final List<Runner> runners;

  /// RetroArch cores, preferred first. They must match the PC's cores for
  /// cross saves (RetroArch keeps saves in a folder per core).
  final List<String> cores;
  final String? note;
}

const systems = <GameSystem>[
  GameSystem(
    id: 'nes',
    folder: 'NES',
    title: 'NES',
    short: 'NES',
    exts: ['nes', 'fds', 'unf', 'zip', '7z'],
    runners: [Runner.retroarch],
    cores: ['mesen', 'fceumm', 'nestopia'],
  ),
  GameSystem(
    id: 'snes',
    folder: 'SNES',
    title: 'Super Nintendo',
    short: 'SNES',
    exts: ['sfc', 'smc', 'zip', '7z'],
    runners: [Runner.retroarch],
    cores: ['snes9x'],
  ),
  GameSystem(
    id: 'n64',
    folder: 'N64',
    title: 'Nintendo 64',
    short: 'N64',
    exts: ['n64', 'z64', 'v64', 'zip', '7z'],
    runners: [Runner.retroarch],
    cores: ['mupen64plus_next'],
  ),
  GameSystem(
    id: 'gb',
    folder: 'Game Boy',
    title: 'Game Boy',
    short: 'GB',
    exts: ['gb', 'zip', '7z'],
    runners: [Runner.retroarch],
    cores: ['gambatte'],
  ),
  GameSystem(
    id: 'gbc',
    folder: 'Game Boy Color',
    title: 'Game Boy Color',
    short: 'GBC',
    exts: ['gbc', 'zip', '7z'],
    runners: [Runner.retroarch],
    cores: ['gambatte'],
  ),
  GameSystem(
    id: 'gba',
    folder: 'Game Boy Advance',
    title: 'Game Boy Advance',
    short: 'GBA',
    exts: ['gba', 'zip', '7z'],
    runners: [Runner.retroarch],
    cores: ['mgba'],
  ),
  GameSystem(
    id: 'sms',
    folder: 'Master System',
    title: 'Master System',
    short: 'SMS',
    exts: ['sms', 'zip', '7z'],
    runners: [Runner.retroarch],
    cores: ['genesis_plus_gx'],
  ),
  GameSystem(
    id: 'genesis',
    folder: 'Genesis',
    title: 'Genesis / Mega Drive',
    short: 'Genesis',
    exts: ['md', 'gen', 'smd', 'bin', 'zip', '7z'],
    runners: [Runner.retroarch],
    cores: ['genesis_plus_gx'],
  ),
  GameSystem(
    id: 'gamegear',
    folder: 'Game Gear',
    title: 'Game Gear',
    short: 'GG',
    exts: ['gg', 'zip', '7z'],
    runners: [Runner.retroarch],
    cores: ['genesis_plus_gx'],
  ),
  GameSystem(
    id: 'segacd',
    folder: 'Sega CD',
    title: 'Sega CD',
    short: 'Sega CD',
    exts: ['cue', 'chd', 'iso', 'm3u'],
    runners: [Runner.retroarch],
    cores: ['genesis_plus_gx'],
    note: "Needs a Sega CD BIOS (bios_CD_U.bin) in RetroArch's system folder.",
  ),
  GameSystem(
    id: 'saturn',
    folder: 'Saturn',
    title: 'Sega Saturn',
    short: 'Saturn',
    exts: ['cue', 'chd', 'ccd', 'm3u'],
    runners: [Runner.retroarch],
    cores: ['yabause', 'mednafen_saturn'],
  ),
  GameSystem(
    id: 'dreamcast',
    folder: 'Dreamcast',
    title: 'Dreamcast',
    short: 'DC',
    exts: ['gdi', 'chd', 'cdi', 'm3u'],
    runners: [Runner.retroarch],
    cores: ['flycast'],
  ),
  GameSystem(
    id: 'gamecube',
    folder: 'GameCube',
    title: 'GameCube',
    short: 'GC',
    exts: ['iso', 'gcm', 'rvz', 'ciso', 'gcz'],
    runners: [Runner.dolphin],
  ),
  GameSystem(
    id: 'ps1',
    folder: 'PS1',
    title: 'PlayStation',
    short: 'PS1',
    exts: ['cue', 'chd', 'pbp', 'm3u', 'iso'],
    // DuckStation first, as on the PC (its per-game memory cards match).
    runners: [Runner.duckstation, Runner.retroarch],
    cores: ['swanstation', 'pcsx_rearmed'],
  ),
  GameSystem(
    id: 'psp',
    folder: 'PSP',
    title: 'PSP',
    short: 'PSP',
    exts: ['iso', 'cso', 'chd', 'pbp'],
    runners: [Runner.ppsspp],
  ),
  GameSystem(
    id: 'arcade',
    folder: 'Arcade',
    title: 'Arcade (MAME)',
    short: 'Arcade',
    exts: ['zip', '7z'],
    runners: [Runner.retroarch],
    cores: ['mame', 'mame2003_plus', 'fbneo'],
  ),
];

GameSystem? systemById(String id) {
  for (final s in systems) {
    if (s.id == id) return s;
  }
  return null;
}

/// Demo discs live in `Demo Discs/<console folder>` (as on the PC).
const demoFolder = 'Demo Discs';
const demoSystems = ['ps1', 'dreamcast', 'saturn'];

/// Folders deep under a console folder that are still searched.
const maxDepth = 2;
