/// Where emulators keep memory cards on each platform (the PC version's
/// MemoryCards.default_dirs, widened to Linux and Android), plus the
/// folders the user adds. Only folders that exist are read.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Paths that differ per machine, so the lists can be tested anywhere.
class Places {
  const Places({
    required this.home,
    required this.documents,
    this.appData = '',
    this.storage = '',
  });

  /// The user's home folder.
  final String home;

  /// Documents (Windows/Linux) or the shared Documents folder (Android).
  final String documents;

  /// %APPDATA% on Windows.
  final String appData;

  /// Android's shared storage root (/storage/emulated/0).
  final String storage;
}

abstract final class CardFolders {
  /// Saves from the internet, apart from the emulators' own.
  static String downloads(Places at) =>
      p.join(at.documents, 'Downloaded Saves');

  /// Where Export puts save files.
  static String exports(Places at) =>
      p.join(at.documents, 'Memory Card Exports');

  /// Every place an emulator's cards may be, for [platform]
  /// ('windows', 'linux', 'android').
  static List<String> known(String platform, Places at) {
    final h = at.home;
    final out = <String>[];
    switch (platform) {
      case 'windows':
        final docs = at.documents, appData = at.appData;
        out.addAll([
          p.join(docs, 'PCSX2', 'memcards'),
          p.join(docs, 'DuckStation', 'memcards'),
          p.join(docs, 'Dolphin Emulator', 'GC'),
          if (appData.isNotEmpty) p.join(appData, 'Dolphin Emulator', 'GC'),
          if (appData.isNotEmpty) p.join(appData, 'RetroArch', 'saves'),
          if (appData.isNotEmpty) p.join(appData, 'RetroArch', 'system', 'dc'),
          r'C:\RetroArch-Win64\saves',
          r'C:\RetroArch-Win64\system\dc',
        ]);
      case 'linux':
        const flat = '.var/app';
        out.addAll([
          p.join(h, '.config', 'PCSX2', 'memcards'),
          p.join(h, flat, 'net.pcsx2.PCSX2', 'config', 'PCSX2', 'memcards'),
          p.join(h, '.local', 'share', 'duckstation', 'memcards'),
          p.join(
            h,
            flat,
            'org.duckstation.DuckStation',
            'data',
            'duckstation',
            'memcards',
          ),
          p.join(h, '.local', 'share', 'dolphin-emu', 'GC'),
          p.join(
            h,
            flat,
            'org.DolphinEmu.dolphin-emu',
            'data',
            'dolphin-emu',
            'GC',
          ),
          p.join(h, '.config', 'retroarch', 'saves'),
          p.join(h, '.config', 'retroarch', 'system', 'dc'),
          p.join(
            h,
            flat,
            'org.libretro.RetroArch',
            'config',
            'retroarch',
            'saves',
          ),
          p.join(h, '.config', 'rpcs3', 'dev_hdd0', 'home'),
          p.join(h, '.config', 'rpcs3', 'dev_usb000', 'PS3', 'SAVEDATA'),
          p.join(
            h,
            flat,
            'net.rpcs3.RPCS3',
            'config',
            'rpcs3',
            'dev_hdd0',
            'home',
          ),
        ]);
      case 'android':
        final s = at.storage;
        String data(String pkg, String rest) =>
            p.join(s, 'Android', 'data', pkg, 'files', rest);
        out.addAll([
          p.join(s, 'RetroArch', 'saves'),
          p.join(s, 'RetroArch', 'system', 'dc'),
          data('com.retroarch', 'saves'),
          data('com.retroarch.aarch64', 'saves'),
          p.join(s, 'duckstation', 'memcards'),
          p.join(s, 'DuckStation', 'memcards'),
          data('com.github.stenzek.duckstation', 'memcards'),
          data('xyz.aethersx2.android', 'memcards'),
          p.join(s, 'NetherSX2', 'memcards'),
          p.join(s, 'dolphin-emu', 'GC'),
          data('org.dolphinemu.dolphinemu', 'GC'),
          p.join(s, 'Flycast', 'data'),
          p.join(s, 'Yabasanshiro', 'backup'),
        ]);
    }
    out.add(downloads(at));
    return out;
  }

  /// [known] plus [added], the ones that exist, each once.
  static List<String> toRead(String platform, Places at, List<String> added) {
    final out = <String>[];
    final seen = <String>{};
    for (final d in [...known(platform, at), ...added]) {
      final key = p.normalize(d).toLowerCase();
      if (d.isNotEmpty && Directory(d).existsSync() && seen.add(key))
        out.add(d);
    }
    return out;
  }
}
