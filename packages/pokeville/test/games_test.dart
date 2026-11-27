// Pokéville part B: finding Pokémon saves and moving Pokémon between them
// and Pokéville, on saves built by poke_saves' test helpers (and, with
// POKE_SAMPLES=/home/user/cross-save, on temp copies of the owner's real
// saves: that folder is only read).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:poke_saves/poke_saves.dart' as ps;
import 'package:poke_saves/testing.dart';
import 'package:pokeville/pokeville.dart';

import 'fixtures.dart';

void main() {
  late Directory temp;
  late String dir; // Pokéville
  late String saves;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pokeville_games');
    saves = makeGames(temp.path);
    dir = p.join(temp.path, 'pokeville');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  String savePath(String sub, String name) => p.join(saves, sub, name);
  ps.PokeSave onDiskSave(String sub, String name) {
    final path = savePath(sub, name);
    return ps.PokeSave.open(
      File(path).readAsBytesSync(),
      fileName: p.basename(path),
    )!;
  }

  BoxData onDisk() =>
      PokeBoxStore.parse(File(p.join(dir, 'box.json')).readAsStringSync())!;

  Future<PokevilleController> opened({SaveGuard? guard}) async {
    final c = PokevilleController(
      PokevilleFolder(dir, runner: runHere),
      games: PokeGames([saves]),
      guard: guard ?? SaveGuard.none(),
      animate: false,
    );
    await c.open();
    return c;
  }

  int gameIndex(PokevilleController c, String name) =>
      c.gameSaves.indexWhere((g) => g.fileName == name);

  List<String> backupsNow() {
    final d = Directory(p.join(dir, backupsFolder));
    return d.existsSync()
        ? [for (final f in d.listSync()) p.basename(f.path)]
        : const [];
  }

  test('finds the Pokémon saves, and nothing else', () {
    final found = findGameSaves([saves, p.join(temp.path, 'nowhere')]);
    expect(found.map((g) => g.fileName), [red, crystal, leaf]);
    expect(found.map((g) => g.game), ['Red', 'Crystal', 'LeafGreen']);
    expect(found.map((g) => g.trainer), ['ASH', 'Kris', 'Wlaf']);
    expect(found.map((g) => g.console), ['gb', 'gbc', 'gba']);
    expect(found.map((g) => g.title).first, 'Pokémon Red');
    expect(found.map((g) => g.count), [1, 1, 1]);
    expect(found[0].species, [1]);
    expect(isSaveCandidate('x.SRM'), isTrue);
    expect(isSaveCandidate('x.srm.box-new'), isFalse);
    expect(isSaveCandidate('x.srm.box-backup-1'), isFalse);
  });

  test('RetroArch on Windows: the saves folder from retroarch.cfg', () {
    expect(resolveRetroArchDir(r':\saves', 'C:/RA', 'saves'), 'C:/RA/saves');
    expect(resolveRetroArchDir('', 'C:/RA', 'saves'), p.join('C:/RA', 'saves'));
    expect(resolveRetroArchDir('D:/S', 'C:/RA', 'saves'), 'D:/S');
    expect(parseRetroArchCfg('# x\nsavefile_directory = ":\\saves"\n'), {
      'savefile_directory': r':\saves',
    });
    final ra = Directory(p.join(temp.path, 'RetroArch'))..createSync();
    File(p.join(ra.path, 'retroarch.cfg'))
        .writeAsStringSync('savefile_directory = ":\\my saves"\n');
    Directory(p.join(ra.path, 'my saves')).createSync();
    expect(retroArchSaveDirs(env: {'APPDATA': temp.path}), [
      p.join(ra.path, 'my saves'),
    ]);
  });

  test(
    'the Games list: Pokéville, then each game (chip, trainer, count)',
    () async {
      final c = await opened();
      c.menu();
      expect(c.menuRows.map((r) => r.title), [
        'Pokéville',
        'Pokémon Red',
        'Pokémon Crystal',
        'Pokémon LeafGreen',
      ]);
      expect(c.menuRows.map((r) => r.chip), ['', 'gb', 'gbc', 'gba']);
      expect(c.menuRows[1].detail, 'ASH · 1 Pokémon');
      c.menuSelect(1);
      await c.confirm();
      expect(c.onGame, isTrue);
      expect((c.cols, c.rows, c.slotCount), (5, 4, 20));
      expect(c.pageCount, 13, reason: 'the party, then 12 boxes');
      expect(c.page, 1, reason: 'a game opens on Box 1');
      expect(c.pageTitle(0), 'PARTY');
      expect(c.pageMon(1, 0)!.name, 'Bulbasaur');
      expect(c.total, 1);
      expect(c.turnPage(1), isTrue);
      expect(c.page, 2);
      await c.showSource(gameIndex(c, leaf));
      expect((c.cols, c.rows, c.pageCount), (6, 5, 15));
      await c.showSource(gameIndex(c, red));
      expect(c.page, 1, reason: 'a different game starts on its first box');
      await c.showSource(-1);
      expect(c.onGame, isFalse);
      expect((c.cols, c.rows), (6, 5));
      expect(c.owned, containsAll([1, 152, 252]));
    },
  );

  test(
    'game -> Pokéville: the file first, then the save; box.json like the PC',
    () async {
      final c = await opened();
      final before = File(savePath('Gambatte', red)).readAsBytesSync();
      await c.showSource(gameIndex(c, red));
      c.select(0);
      await c.confirm();
      expect(c.held!.fromGame, isTrue);
      expect(c.heldWhere, startsWith('Red '));
      await c.showSource(-1);
      c.select(5);
      await c.confirm();
      expect(c.holding, isFalse, reason: c.notice);
      final s = PokeBoxStore.slot(onDisk(), 0, 5);
      expect(s['file'], matches(RegExp(r'^mons/\d{8}-\d{6}-\d{6}\.pk1$')));
      final mon = s['mon'] as Map<String, dynamic>;
      expect(mon['name'], 'Bulbasaur');
      expect(mon['from_save'], red);
      expect(
        mon['from'],
        'Box 1',
        reason: 'a blank test save has no box names',
      );
      expect(mon['format'], 'pk1');
      expect(mon['v'], 3);
      // the file is exactly what PKHeX writes (poke_saves' bytes)
      final file = File(PokeBoxStore.absolute(dir, '${s['file']}'));
      expect(file.readAsBytesSync(), bulbasaurPk1Stored(before));
      // the game no longer has it, the old save is backed up, nothing left over
      expect(onDiskSave('Gambatte', red).boxes[0].count, 0);
      final bk = backupsNow();
      expect(bk.single, startsWith('$red.box-backup-'));
      expect(
        File(p.join(dir, backupsFolder, bk.single)).readAsBytesSync(),
        before,
      );
      expect(
        File('${savePath('Gambatte', red)}.box-new').existsSync(),
        isFalse,
      );
      expect(c.gameSaves[gameIndex(c, red)].count, 0);
    },
  );

  test('Pokéville -> game: converted, the file goes to mons/sent', () async {
    final c = await opened();
    // Meowth (pk2, the PC's example) into Red: Time Capsule to pk1
    final meowth = '${PokeBoxStore.slot(onDisk(), 0, 0)['file']}';
    c.select(0);
    await c.confirm();
    await c.showSource(gameIndex(c, red));
    c.select(7);
    await c.confirm();
    expect(c.holding, isFalse, reason: c.notice);
    expect(c.notice, contains('converted from pk2 to pk1'));
    expect(PokeBoxStore.isEmpty(onDisk(), 0, 0), isTrue);
    expect(File(PokeBoxStore.absolute(dir, meowth)).existsSync(), isFalse);
    expect(
      File(p.join(dir, 'mons', 'sent', p.basename(meowth))).existsSync(),
      isTrue,
    );
    final red2 = onDiskSave('Gambatte', red);
    expect(red2.check(), '');
    expect(red2.boxes[0].count, 2);
    expect(red2.boxMon(0, 1)!.species, 52, reason: 'no gaps: after Bulbasaur');
    expect(c.pageMon(1, 1)!.name, 'Meowth');
  });

  test("refused as PKHeX refuses; the save isn't touched", () async {
    final c = await opened();
    final before = File(savePath('Gambatte', red)).readAsBytesSync();
    // a GBA Pokémon to a Game Boy game
    await c.showSource(gameIndex(c, leaf));
    c.select(0);
    await c.confirm();
    await c.showSource(gameIndex(c, red));
    c.select(3);
    await c.confirm();
    expect(c.notice, "Treecko doesn't exist in Red");
    expect(c.holding, isTrue, reason: 'still carried: try somewhere else');
    expect(File(savePath('Gambatte', red)).readAsBytesSync(), before);
    expect(backupsNow(), isEmpty);
    // a spot that's taken
    c.select(0);
    await c.confirm();
    expect(c.notice, "Pick an empty spot in the game's box");
    // Game Boy -> GBA
    expect(c.cancel(), isTrue);
    c.select(0);
    await c.confirm(); // Bulbasaur
    await c.showSource(gameIndex(c, leaf));
    c.select(10);
    await c.confirm();
    expect(c.notice, startsWith('Game Boy Pokémon can'));
    // into a taken Pokéville spot
    await c.showSource(-1);
    c.select(0);
    await c.confirm();
    expect(c.notice, 'Pick an empty spot in Pokéville');
  });

  test('inside a game: Game Boy boxes have no gaps; a swap', () async {
    final c = await opened();
    await c.showSource(gameIndex(c, crystal));
    c.select(0);
    await c.confirm();
    c.turnPage(1);
    c.select(9);
    await c.confirm();
    expect(c.holding, isFalse, reason: c.notice);
    final s = onDiskSave('Gambatte', crystal);
    expect(s.boxes[0].count, 0);
    expect(s.boxMon(1, 0)!.species, 152, reason: 'moved up to the front');
    expect(c.pageMon(2, 0)!.name, 'Chikorita');
    expect(backupsNow(), hasLength(1));
  });

  test('game -> another game: converted, both saves backed up', () async {
    final c = await opened();
    await c.showSource(gameIndex(c, red));
    c.select(0);
    await c.confirm();
    await c.showSource(gameIndex(c, crystal));
    c.select(1);
    await c.confirm();
    expect(c.holding, isFalse, reason: c.notice);
    expect(onDiskSave('Gambatte', red).boxes[0].count, 0);
    final cr = onDiskSave('Gambatte', crystal);
    expect(cr.boxMon(0, 1)!.species, 1);
    expect(cr.boxMon(0, 1)!.ext, 'pk2');
    expect(backupsNow(), hasLength(2));
  });

  test('a save that changed on disk is read again, nothing moves', () async {
    final c = await opened();
    await c.showSource(gameIndex(c, red));
    c.select(0);
    await c.confirm();
    // a sync brings a new Red in meanwhile
    final changed = withMon(
      File(savePath('Gambatte', red)).readAsBytesSync(),
      bulbasaurPk1(),
      'pk1',
      1,
    );
    File(savePath('Gambatte', red)).writeAsBytesSync(changed);
    await c.showSource(-1);
    c.select(5);
    await c.confirm();
    expect(c.notice, changedOnDiskText);
    expect(c.holding, isFalse);
    expect(PokeBoxStore.isEmpty(onDisk(), 0, 5), isTrue);
    expect(
      Directory(p.join(dir, 'mons')).listSync().whereType<File>(),
      hasLength(3),
      reason: 'no new file left behind',
    );
    expect(File(savePath('Gambatte', red)).readAsBytesSync(), changed);
    expect(backupsNow(), isEmpty);
  });

  test('box.json changed on disk before a move: refused, read again', () async {
    final c = await opened();
    await c.showSource(gameIndex(c, red));
    c.select(0);
    await c.confirm();
    final f = File(p.join(dir, 'box.json'));
    f.writeAsStringSync('${f.readAsStringSync()}\n');
    await c.showSource(-1);
    c.select(5);
    await c.confirm();
    expect(c.notice, contains('changed on disk'));
    expect(onDiskSave('Gambatte', red).boxes[0].count, 1);
  });

  test('Android: asks first (NOT YET first), a yes counts 2 minutes', () async {
    var now = DateTime(2026, 11, 26, 12);
    final c = await opened(guard: SaveGuard.ask(now: () => now));
    await c.showSource(gameIndex(c, red));
    c.select(0);
    await c.confirm();
    await c.showSource(-1);
    c.select(5);
    await c.confirm();
    final q = c.asking!;
    expect(
      q.lines.first,
      'Close RetroArch fully first (not just Home). Is it closed?',
    );
    expect(q.index, 0);
    expect(ClosedQuestion.answers.first, 'NOT YET');
    await c.confirm(); // NOT YET
    expect(c.asking, isNull);
    expect(c.notice, startsWith('Nothing was changed'));
    expect(onDiskSave('Gambatte', red).boxes[0].count, 1);
    expect(c.holding, isTrue);
    await c.confirm();
    expect(c.step(1, 0), isTrue);
    await c.confirm(); // YES
    expect(c.holding, isFalse);
    expect(onDiskSave('Gambatte', red).boxes[0].count, 0);
    // within 2 minutes: no question
    c.select(5);
    await c.confirm();
    await c.showSource(gameIndex(c, red));
    c.select(0);
    await c.confirm();
    expect(c.asking, isNull);
    expect(onDiskSave('Gambatte', red).boxes[0].count, 1);
    now = now.add(const Duration(minutes: 3));
    c.select(0);
    await c.confirm();
    c.select(4);
    await c.confirm();
    expect(c.asking, isNotNull, reason: 'asked again after 2 minutes');
    expect(c.cancel(), isTrue, reason: 'B = NOT YET');
    await Future<void>.delayed(Duration.zero);
    expect(c.asking, isNull);
  });

  test('Windows / Linux: a running emulator refuses; unknown asks', () async {
    final c = await opened(guard: SaveGuard.processes(check: _retroArchOpen));
    await c.showSource(gameIndex(c, red));
    c.select(0);
    await c.confirm();
    await c.showSource(-1);
    c.select(5);
    await c.confirm();
    expect(c.notice, 'Close RetroArch first: it has this save open');
    expect(onDiskSave('Gambatte', red).boxes[0].count, 1);
    final d = await opened(guard: SaveGuard.processes(check: _cantTell));
    await d.showSource(gameIndex(d, red));
    d.select(0);
    await d.confirm();
    await d.showSource(-1);
    d.select(5);
    await d.confirm();
    expect(d.asking, isNotNull);
    expect(
      ownerRunning('/x/RetroArch/saves/a.srm', ['retroarch.exe']),
      'Close RetroArch first: it has this save open',
    );
    expect(ownerRunning('/x/RetroArch/saves/a.srm', ['mgba.exe']), '');
    expect(
      ownerRunning('/elsewhere/a.srm', ['mgba']),
      'Close mGBA first: it has this save open',
    );
  });

  test('the transfer: waits for the save, skippable, ~2 s', () async {
    final c = PokevilleController(
      PokevilleFolder(dir, runner: runHere),
      games: PokeGames([saves]),
      guard: SaveGuard.none(),
    );
    await c.open();
    await c.showSource(gameIndex(c, red));
    c.select(0);
    await c.confirm();
    await c.showSource(-1);
    c.select(5);
    await c.confirm();
    final t = c.transfer!;
    expect(t.toBox, isTrue);
    expect(t.console, 'gb');
    expect(t.label, 'RED · ASH');
    expect(t.result, 1);
    var s = 0.0;
    while (c.transfer != null && s < 5) {
      c.advanceTransfer(1 / 60);
      s += 1 / 60;
    }
    expect(s, inInclusiveRange(1.5, 2.2));
    // skipping (A) ends it at once once the save has changed
    c.select(5);
    await c.confirm();
    await c.showSource(gameIndex(c, red));
    c.select(0);
    await c.confirm();
    expect(c.transferring, isTrue);
    expect(c.step(1, 0), isFalse, reason: 'buttons wait');
    await c.confirm();
    expect(c.transfer, isNull);
    // waiting at the cable's end until done
    final w = Transfer(
      mon: const Mon({'name': 'Pidgey'}),
      console: 'gba',
      toBox: false,
      gameName: 'Emerald',
      label: 'EMERALD',
    );
    for (var i = 0; i < 300; i++) {
      w.advance(1 / 60);
    }
    expect(w.t, Transfer.holdT);
    w.done(false, 'nope');
    for (var i = 0; i < 30; i++) {
      w.advance(1 / 60);
    }
    expect(w.words.$1, 'PIDGEY came back. nope');
    w.skip();
    w.skip();
    expect(w.playing, isFalse);
  });

  group('real saves', () {
    final root = Platform.environment['POKE_SAMPLES'];
    final skip = root == null || !Directory(root).existsSync()
        ? 'POKE_SAMPLES not set'
        : null;
    test(
      'every game: out to Pokéville and back, on temp copies',
      skip: skip,
      () async {
        // copies only: nothing is ever written into POKE_SAMPLES
        final real = Directory.systemTemp.createTempSync('pokeville_real');
        addTearDown(() => real.deleteSync(recursive: true));
        final ra = p.join(real.path, 'saves');
        copyTree(p.join(root!, 'saves', 'retroarch'), ra);
        final box = p.join(real.path, 'pokeville');
        copyTree(p.join(root, 'pokeville'), box);
        final found = findGameSaves([ra]);
        expect(found.map((g) => g.game).toSet(), {
          'Red',
          'Blue',
          'Yellow',
          'Gold',
          'Silver',
          'Crystal',
          'LeafGreen',
          'Emerald',
        });
        final c = PokevilleController(
          PokevilleFolder(box, runner: runHere),
          games: PokeGames([ra]),
          guard: SaveGuard.none(),
          animate: false,
        );
        await c.open();
        for (var i = 0; i < c.gameSaves.length; i++) {
          final g = c.gameSaves[i];
          final before = File(g.path).readAsBytesSync();
          await c.showSource(i);
          // the first box Pokémon
          var at = (-1, -1);
          for (var b = 1; b < c.pageCount && at.$1 < 0; b++) {
            for (var s = 0; s < c.slotCount; s++) {
              if (c.pageMon(b, s) != null) {
                at = (b, s);
                break;
              }
            }
          }
          if (at.$1 < 0) continue;
          final name = c.pageMon(at.$1, at.$2)!.name;
          final pk = ps.PokeSave.open(
            before,
            fileName: g.fileName,
          )!.boxMon(at.$1 - 1, at.$2)!;
          c.goToPage(at.$1);
          c.select(at.$2);
          await c.confirm();
          await c.showSource(-1);
          final (eb, es) = PokeBoxStore.firstEmpty(c.data)!;
          c.goToPage(eb);
          c.select(es);
          await c.confirm();
          expect(c.holding, isFalse, reason: '${g.game}: ${c.notice}');
          final slot = PokeBoxStore.slot(c.data, eb, es);
          expect(Mon.of(slot)!.name, name);
          expect(Mon.of(slot)!.fromSave, g.fileName);
          expect(
            File(PokeBoxStore.absolute(box, '${slot['file']}'))
                .readAsBytesSync(),
            pk.bytes,
            reason: '${g.game}: the file PKHeX would write',
          );
          final out = ps.PokeSave.open(
            File(g.path).readAsBytesSync(),
            fileName: g.fileName,
          )!;
          expect(out.check(), '', reason: g.game);
          expect(
            out.boxes[at.$1 - 1].count,
            ps.PokeSave.open(before)!.boxes[at.$1 - 1].count - 1,
          );
          // and back into the same game
          c.select(es);
          await c.confirm();
          await c.showSource(i);
          c.goToPage(at.$1);
          final back = c.slotCount - 1;
          c.select(back);
          if (c.pageMon(at.$1, back) != null) continue; // a full GBA box
          await c.confirm();
          expect(c.holding, isFalse, reason: '${g.game} back: ${c.notice}');
          final again = ps.PokeSave.open(
            File(g.path).readAsBytesSync(),
            fileName: g.fileName,
          )!;
          expect(again.check(), '', reason: g.game);
          expect(
            again.boxes.fold(0, (n, b) => n + b.count),
            ps.PokeSave.open(before)!.boxes.fold(0, (n, b) => n + b.count),
            reason: '${g.game}: every Pokémon is back',
          );
        }
        // the backups are in Pokéville's "save backups", one per change
        expect(
          Directory(p.join(box, backupsFolder)).listSync(),
          hasLength(greaterThanOrEqualTo(found.length)),
        );
      },
    );
  });
}

String? _retroArchOpen(String path) => ownerRunning(path, ['retroarch.exe']);

String? _cantTell(String path) => null;

/// The .pk1 PKHeX writes for the Bulbasaur in [save] (box 0, slot 0).
Uint8List bulbasaurPk1Stored(Uint8List save) =>
    ps.PokeSave.open(save)!.boxMon(0, 0)!.bytes;
