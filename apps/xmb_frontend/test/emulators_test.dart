import 'package:cross_save/cross_save.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xmb_frontend/src/launch.dart';
import 'package:xmb_frontend/src/library/emulators.dart';
import 'package:xmb_frontend/src/library/systems.dart';

void main() {
  test('every emulator has a Play package the menu detects', () {
    expect(emulatorGuides.map((g) => g.runner).toSet(), Runner.values.toSet());
    for (final g in emulatorGuides) {
      expect(runnerPackages[g.runner], contains(g.playPackage));
    }
    expect(playUrls('org.ppsspp.ppsspp'), [
      'market://details?id=org.ppsspp.ppsspp',
      'https://play.google.com/store/apps/details?id=org.ppsspp.ppsspp',
    ]);
    expect(hasRunner(Runner.retroarch, {'com.retroarch.aarch64'}), isTrue);
    expect(hasRunner(Runner.dolphin, {'com.retroarch'}), isFalse);
  });

  test('the RetroArch cores to download: one line per core, named', () {
    final cores = coresNeeded();
    final ids = cores.map((c) => c.core).toList();
    expect(ids.toSet().length, ids.length);
    // PS1 plays in DuckStation first, so no PS1 core unless asked.
    expect(ids, isNot(contains('swanstation')));
    final gx = cores.firstWhere((c) => c.core == 'genesis_plus_gx');
    expect(gx.consoles, ['SMS', 'Genesis', 'GG', 'Sega CD']);
    for (final c in cores) {
      expect(c.name, isNot(c.core), reason: 'no display name for ${c.core}');
    }
    // Every RetroArch console's first core is covered.
    for (final s in systems) {
      if (s.runners.first == Runner.retroarch) {
        expect(ids, contains(s.cores.first));
      }
    }
    final ps1 = coresNeeded(
      preferRetroArch: {'ps1'},
      chosen: {'nes': 'fceumm'},
    ).map((c) => c.core);
    expect(ps1, containsAll(['swanstation', 'fceumm']));
    expect(ps1, isNot(contains('mesen')));
  });

  test('set-up steps name the folders as My Files shows them', () {
    const f = XmbFolders('/storage/emulated/0/XMB Frontend');
    final duck = setUpLines(Runner.duckstation, f).join('\n');
    expect(
      duck,
      contains(
        'Internal storage › XMB Frontend › Saves › DuckStation › memcards',
      ),
    );
    final psp = setUpLines(Runner.ppsspp, f).join('\n');
    expect(psp, contains('Internal storage › XMB Frontend › Saves › PPSSPP'));
    final gc = setUpLines(Runner.dolphin, f).join('\n');
    expect(
      gc,
      contains('Internal storage › XMB Frontend › Saves › Dolphin › GC'),
    );
    expect(
      gc,
      contains(
        'Internal storage › XMB Frontend › Saves › Dolphin › Wii › title',
      ),
    );
    expect(gc, contains('GCI Folder'));
    expect(gc, isNot(contains("don't cross over")));
    final ra = setUpLines(Runner.retroarch, f).join('\n');
    expect(
      ra,
      contains('Internal storage › XMB Frontend › RetroArch › retroarch.cfg'),
    );
    expect(ra, contains('Nintendo - Game Boy Advance (mGBA)'));
    expect(
      setUpLines(Runner.retroarch, f, ownRetroArchConfig: true).first,
      contains("RetroArch's own"),
    );
  });
}
