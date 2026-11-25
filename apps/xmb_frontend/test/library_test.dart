import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:xmb_frontend/src/launch.dart';
import 'package:xmb_frontend/src/library/scanner.dart';
import 'package:xmb_frontend/src/library/systems.dart';
import 'package:xmb_frontend/src/state.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('xmb_roms'));
  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  File put(String rel, [String text = 'x']) {
    final f = File(p.join(root.path, rel))..createSync(recursive: true);
    f.writeAsStringSync(text);
    return f;
  }

  test('titles drop region tags but keep the disc number', () {
    expect(cleanTitle('Super Mario World (USA) [!]'), 'Super Mario World');
    expect(
      cleanTitle('Final Fantasy VII (USA) (Disc 2)'),
      'Final Fantasy VII (Disc 2)',
    );
    expect(
      cleanTitle('Pokemon_Emerald_USA_GBA-TRM'),
      'Pokemon Emerald USA GBA-TRM',
    );
    expect(isDemoName('Jampack Vol. 1 (USA)'), isTrue);
    expect(isDemoName('Demolition Racer (USA)'), isFalse);
    expect(isDemoName('Spyro (USA) (Demo)'), isTrue);
  });

  test('scans console folders like the PC: strict types, sheets, depth', () {
    put('Game Boy/Pokemon - Red Version (USA, Europe).gb');
    put('Game Boy/Pokemon - Crystal Version (USA, Europe).gbc'); // wrong folder
    put('Game Boy Color/Pokemon - Crystal Version (USA, Europe).gbc');
    put('Game Boy Advance/Pokemon_Emerald_USA_GBA-TRM.gba');
    put('Game Boy Advance/Pokemon_Emerald_USA_GBA-TRM.png'); // its art
    put('Game Boy Advance/notes.txt');
    put('Game Boy Advance/.hidden/Secret.gba');
    put('SNES/a/b/c/TooDeep.sfc'); // 3 folders deep: skipped
    put('SNES/a/b/Deep.sfc');
    // A two-track cue: the .bin tracks hide behind it.
    put(
      'PS1/Game (USA).cue',
      'FILE "Game (USA) (Track 1).bin" BINARY\n'
          'FILE "Game (USA) (Track 2).bin" BINARY\n',
    );
    put('PS1/Game (USA) (Track 1).bin', 'xxxxxxxxxx');
    put('PS1/Game (USA) (Track 2).bin', 'yyyyy');
    // Multi-disc: the m3u stands for both discs.
    put(
      'PS1/FF7/Final Fantasy VII.m3u',
      'Final Fantasy VII (Disc 1).chd\nFinal Fantasy VII (Disc 2).chd\n',
    );
    put('PS1/FF7/Final Fantasy VII (Disc 1).chd');
    put('PS1/FF7/Final Fantasy VII (Disc 2).chd');
    put('Demo Discs/PS1/Jampack Vol 1 (USA).chd');
    final games = scanLibrary(root.path);
    final titles = {for (final g in games) g.title};
    expect(
      titles,
      containsAll([
        'Pokemon - Red Version',
        'Pokemon - Crystal Version',
        'Pokemon Emerald USA GBA-TRM',
        'Deep',
        'Game',
        'Final Fantasy VII',
        'Jampack Vol 1',
      ]),
    );
    expect(titles, isNot(contains('TooDeep')));
    expect(titles, isNot(contains('Secret')));
    expect(games.where((g) => g.title.contains('Disc')), isEmpty);
    expect(games.where((g) => g.path.endsWith('.bin')), isEmpty);
    // The Crystal ROM in the Game Boy folder is ignored (strict types).
    expect(games.where((g) => g.system == 'gb').length, 1);
    final cue = games.firstWhere((g) => g.title == 'Game');
    expect(
      cue.size,
      'FILE "Game (USA) (Track 1).bin" BINARY\n'.length * 0 + cue.size,
    );
    expect(cue.size, greaterThanOrEqualTo(15)); // tracks counted
    final emerald = games.firstWhere((g) => g.system == 'gba');
    expect(emerald.art, endsWith('.png'));
    expect(emerald.saveName, 'Pokemon_Emerald_USA_GBA-TRM');
    expect(emerald.id, 'gba:pokemon_emerald_usa_gba-trm.gba');
    expect(games.firstWhere((g) => g.title == 'Jampack Vol 1').demo, isTrue);
    // JSON round trip (the library is cached between runs).
    final back = Game.fromJson(emerald.toJson());
    expect(back.id, emerald.id);
    expect(back.art, emerald.art);
  });

  test('console folders are made with the PC names', () {
    makeConsoleFolders(root.path);
    for (final s in systems) {
      expect(Directory(p.join(root.path, s.folder)).existsSync(), isTrue);
    }
    expect(
      Directory(p.join(root.path, 'Demo Discs', 'PS1')).existsSync(),
      isTrue,
    );
  });

  test('emulator choice follows what is installed', () {
    final ps1 = systemById('ps1')!;
    expect(chooseRunner(ps1, {}), isNull);
    final ra = chooseRunner(ps1, {'com.retroarch'})!;
    expect(ra.runner, Runner.retroarch);
    expect(ra.core, 'swanstation');
    final ds = chooseRunner(ps1, {
      'com.retroarch',
      'com.github.stenzek.duckstation',
    })!;
    expect(ds.runner, Runner.duckstation);
    expect(
      chooseRunner(
        ps1,
        {'com.retroarch', 'com.github.stenzek.duckstation'},
        preferRetroArch: true,
        core: 'pcsx_rearmed',
      )!.core,
      'pcsx_rearmed',
    );
    // The 64-bit RetroArch build wins over the Play Store one.
    expect(
      chooseRunner(systemById('gba')!, {
        'com.retroarch',
        'com.retroarch.aarch64',
      })!.package,
      'com.retroarch.aarch64',
    );
  });

  test('intents carry what each emulator reads', () {
    const g = Game(
      system: 'gba',
      path: '/storage/emulated/0/ROMs/Game Boy Advance/Emerald.gba',
      title: 'Emerald',
      size: 1,
    );
    final ra = launchSpec(
      g,
      const LaunchChoice(
        Runner.retroarch,
        'com.retroarch.aarch64',
        core: 'mgba',
      ),
    );
    expect(
      ra.activity,
      'com.retroarch.browser.retroactivity.RetroActivityFuture',
    );
    expect(ra.extras['ROM'], g.path);
    expect(
      ra.extras['LIBRETRO'],
      '/data/data/com.retroarch.aarch64/cores/mgba_libretro_android.so',
    );
    expect(
      ra.extras['CONFIGFILE'],
      '/storage/emulated/0/Android/data/com.retroarch.aarch64/files/retroarch.cfg',
    );
    final psp = launchSpec(
      g,
      const LaunchChoice(Runner.ppsspp, 'org.ppsspp.ppsspp'),
    );
    expect(psp.dataPath, g.path);
    expect(psp.action, 'android.intent.action.VIEW');
    final ds = launchSpec(
      g,
      const LaunchChoice(Runner.duckstation, 'com.github.stenzek.duckstation'),
    );
    expect(ds.extras['bootPath'], g.path);
    expect(ds.toMap()['package'], 'com.github.stenzek.duckstation');
  });

  test('state: pins, history, play time, JSON', () {
    final s = MenuState()
      ..romsDir = '/roms'
      ..games = const [
        Game(system: 'gb', path: '/roms/Game Boy/A.gb', title: 'A', size: 1),
        Game(system: 'gb', path: '/roms/Game Boy/B.gb', title: 'B', size: 1),
        Game(
          system: 'gba',
          path: '/roms/Game Boy Advance/C.gba',
          title: 'C',
          size: 1,
        ),
      ];
    s.togglePin('gb:b.gb');
    s.started('gba:c.gba', 1000);
    s.returned(1000 + 125000);
    expect(s.played['gba:c.gba']!.seconds, 125);
    expect(s.played['gba:c.gba']!.sessions, 1);
    s.started('gb:a.gb', 5000);
    s.returned(8000); // 3 s: didn't really start
    expect(s.played['gb:a.gb']!.seconds, 0);
    // Pinned first, then most recent.
    expect([for (final g in s.front()) g.title], ['B', 'A', 'C']);
    s.toggleHidden('gb:a.gb');
    expect(s.visibleGames.length, 2);
    s.sortBy = SortBy.recent;
    final back = MenuState()..load(s.toJson());
    expect(back.pins, ['gb:b.gb']);
    expect(back.played['gba:c.gba']!.seconds, 125);
    expect(back.hidden, {'gb:a.gb'});
    expect(back.sortBy, SortBy.recent);
    expect(back.games.length, 3);
    expect(formatSize(380 << 20), '380 MB');
    expect(formatPlayTime(5 * 3600), '5 hours');
    final now = DateTime(2026, 11, 25, 9);
    expect(
      playedAgo(DateTime(2026, 11, 24, 20).millisecondsSinceEpoch, now),
      'Played yesterday',
    );
  });
}
