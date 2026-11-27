// Check's A: the edit menu, the nickname keyboard and the held item list,
// for Pokémon in Pokéville (their mons/ file + box.json) and in a game save
// (the safe write: backup, temp, read back, swap), and the party page. On
// built saves and the PC's example Pokéville (and, with
// POKE_SAMPLES=/home/user/cross-save, on temp copies of the owner's real
// saves and Pokéville: that folder is only read).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:poke_saves/poke_saves.dart' as ps;
import 'package:pokeville/pokeville.dart';

import 'fixtures.dart';

void main() {
  late Directory temp;
  late String dir;
  late String saves;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pokeville_edit');
    saves = makeGames(temp.path);
    dir = p.join(temp.path, 'pokeville');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  BoxData onDisk() =>
      PokeBoxStore.parse(File(p.join(dir, 'box.json')).readAsStringSync())!;
  String savePath(String sub, String name) => p.join(saves, sub, name);
  ps.PokeSave onDiskSave(String sub, String name) => ps.PokeSave.open(
    File(savePath(sub, name)).readAsBytesSync(),
    fileName: name,
  )!;

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

  /// Types [name] on the on-screen keyboard with the d-pad (A on each key).
  Future<void> padType(PokevilleController c, String name) async {
    for (final ch in name.split('')) {
      var row = -1, col = -1;
      for (var r = 0; r < PokevilleController.kbRows.length; r++) {
        final i = PokevilleController.kbRows[r].indexOf(ch.toUpperCase());
        if (i >= 0) {
          row = r;
          col = i;
          break;
        }
      }
      expect(row, greaterThanOrEqualTo(0), reason: ch);
      final lower = ch != ch.toUpperCase();
      if (lower != c.kbLower) c.check(); // Y: abc / ABC
      while (c.kbRow != row) {
        c.step(0, 1);
      }
      while (c.kbCol != col) {
        c.step(1, 0);
      }
      await c.confirm();
    }
  }

  test(
    'Pokéville: rename with the pad keyboard, the file and box.json',
    () async {
      final c = await opened();
      final file = '${PokeBoxStore.slot(onDisk(), 0, 0)['file']}';
      final path = PokeBoxStore.absolute(dir, file);
      final before = File(path).readAsBytesSync();
      c.select(0); // Meowth "D․I․Z․"
      c.check();
      await c.confirm();
      expect(c.editStep, EditStep.menu);
      expect(c.editWhere, 'Pokéville');
      await c.confirm(); // Nickname
      expect(c.editStep, EditStep.keyboard);
      expect(c.kbText, 'D․I․Z․');
      while (c.kbText.isNotEmpty) {
        expect(c.cancel(), isTrue); // B: a letter less
      }
      await padType(c, 'Kitty');
      // OK: the last row's last key
      c.step(0, PokevilleController.kbRows.length - c.kbRow);
      while (PokevilleController.kbKeys[c.kbCol] != 'OK') {
        c.step(1, 0);
      }
      await c.confirm();
      expect(c.editStep, EditStep.none, reason: c.notice);
      expect(c.notice, 'Kitty: nickname saved');
      final m = ps.Mon.fromFile(File(path).readAsBytesSync(), ext: 'pk2')!;
      expect(m.nickname, 'Kitty');
      expect(File('$path.bak').readAsBytesSync(), before, reason: 'kept');
      expect(File('$path.new').existsSync(), isFalse);
      final mon = PokeBoxStore.slot(onDisk(), 0, 0)['mon'] as Map;
      expect(mon['nickname'], 'Kitty');
      expect(mon['name'], 'Meowth');
      expect(c.shown!.nickname, 'Kitty');
      // and back: the same bytes as before
      await c.confirm();
      await c.confirm();
      while (c.kbText.isNotEmpty) {
        c.kbBackspace();
      }
      c.typeText('D․I․Z․');
      await c.typedName(c.kbText);
      expect(File(path).readAsBytesSync(), before);
      expect(
        (PokeBoxStore.slot(onDisk(), 0, 0)['mon'] as Map)['nickname'],
        'D․I․Z․',
      );
    },
  );

  test(
    'the keyboard refuses what the game can\'t write, and 11 letters',
    () async {
      final c = await opened();
      c.select(0);
      c.check();
      await c.confirm();
      await c.confirm();
      while (c.kbText.isNotEmpty) {
        c.kbBackspace();
      }
      // Gold/Silver/Crystal have no plain apostrophe
      expect(c.kbCanType("'"), isFalse);
      expect(c.kbCanType('’'), isTrue);
      expect(c.kbCanType('+'), isTrue);
      c.typeText("A'");
      expect(c.kbText, 'A');
      expect(c.notice, "Pokéville can't write '");
      c.typeText('BCDEFGHIJKL');
      expect(c.kbText, 'ABCDEFGHIJ');
      expect(c.notice, '10 letters at most');
      // the device's keyboard: what can't be written is taken out, not saved
      await c.typedName('Zoë');
      expect(c.editStep, EditStep.keyboard);
      expect(c.kbText, 'Zo');
      expect(c.notice, contains("can't write ë"));
      // Type asks the screen for the device's keyboard
      final id = c.typeRequestId;
      await c.kbTap(PokevilleController.kbRows.length, 3);
      expect(c.typeRequestId, id + 1);
      // B backs out: letters first, then to the menu, then out
      while (c.kbText.isNotEmpty) {
        c.cancel();
      }
      c.cancel();
      expect(c.editStep, EditStep.menu);
      c.cancel();
      expect(c.editStep, EditStep.none);
      expect(c.view, PokeView.check);
    },
  );

  test('Pokéville: held item from the list, and taken back', () async {
    final c = await opened();
    final file = '${PokeBoxStore.slot(onDisk(), 0, 0)['file']}';
    final path = PokeBoxStore.absolute(dir, file);
    final before = File(path).readAsBytesSync();
    c.select(0);
    c.check();
    await c.confirm();
    c.step(0, 1);
    await c.confirm(); // Held item
    expect(c.editStep, EditStep.items);
    expect(c.editItems, ps.heldItemChoices(2));
    expect(c.editItems.length, 193, reason: "the PC's Crystal list");
    // the example's summary still says the PC's old "Grepa Berry" for
    // Crystal's item 173 (Berry): the file is what counts
    final had = ps.Mon.fromFile(before, ext: 'pk2')!.heldItem;
    expect(c.editItems.map((e) => e.name), contains('Berry'));
    c.turnPage(-1); // LB: 10 up
    c.turnPage(-1);
    c.turnPage(-1);
    final i = c.editItems.indexWhere((e) => e.name == 'Leftovers');
    await c.itemTap(i); // highlights
    expect(c.editStep, EditStep.items);
    await c.itemTap(i); // gives
    expect(c.notice, 'D․I․Z․ now holds Leftovers');
    expect(
      (PokeBoxStore.slot(onDisk(), 0, 0)['mon'] as Map)['item'],
      'Leftovers',
    );
    await c.confirm();
    c.step(0, 1);
    await c.confirm();
    expect(c.editItems[c.itemIndex].name, 'Leftovers');
    await c.itemTap(c.editItems.indexWhere((e) => e.id == had));
    await c.confirm();
    expect(File(path).readAsBytesSync(), before);
  });

  test('Gen 1 holds nothing; Eggs and newer Pokémon are refused', () async {
    final c = await opened();
    await c.showSource(gameIndex(c, red));
    c.select(0);
    c.check();
    await c.confirm();
    c.step(0, 1);
    await c.confirm();
    expect(c.notice, "Gen 1 Pokémon can't hold items");
    expect(c.editStep, EditStep.menu);
    c.cancel();
    c.cancel();
    // an Egg and a pk8 in Pokéville
    await c.showSource(-1);
    final next = PokeBoxStore.copy(c.data);
    PokeBoxStore.place(next, 1, 0, 'mons/egg.pk2', {
      'name': 'Togepi',
      'egg': true,
      'format': 'pk2',
    });
    PokeBoxStore.place(next, 1, 1, 'mons/x.pk8', {
      'name': 'Pikachu',
      'format': 'pk8',
    });
    await PokevilleFolder(dir, runner: runHere).write(next);
    await c.reload();
    c.goToPage(1);
    c.select(0);
    c.check();
    await c.confirm();
    expect(c.notice, "Eggs can't be renamed or hold items");
    c.step(0, 1);
    await c.confirm();
    expect(c.notice, OnThePc.edit('pk8'));
    expect(c.editing, isFalse);
  });

  test('a game: nickname and item through the safe write', () async {
    final now = DateTime(2026, 11, 27, 12);
    final c = await opened(guard: SaveGuard.ask(now: () => now));
    await c.showSource(gameIndex(c, crystal));
    c.select(0); // Chikorita "Leafy"
    c.check();
    await c.confirm();
    expect(c.editWhere, 'Crystal');
    await c.confirm();
    while (c.kbText.isNotEmpty) {
      c.kbBackspace();
    }
    await c.typedName('Chiko');
    expect(c.asking, isNotNull, reason: 'the emulator-closed question');
    await c.answer(1);
    expect(c.editStep, EditStep.none, reason: c.notice);
    final s = onDiskSave('Gambatte', crystal);
    expect(s.check(), '');
    expect(s.boxMon(0, 0)!.nickname, 'Chiko');
    expect(c.pageMon(1, 0)!.nickname, 'Chiko');
    final backups = Directory(p.join(dir, backupsFolder)).listSync();
    expect(backups, hasLength(1));
    expect(
      File('${savePath('Gambatte', crystal)}.box-new').existsSync(),
      isFalse,
    );
    // an empty name puts the species name back
    await c.confirm();
    await c.confirm();
    while (c.kbText.isNotEmpty) {
      c.kbBackspace();
    }
    await c.typedName('');
    expect(onDiskSave('Gambatte', crystal).boxMon(0, 0)!.isNicknamed, isFalse);
    expect(c.notice, 'Chikorita: nickname taken off');
    // an item
    await c.confirm();
    c.step(0, 1);
    await c.confirm();
    await c.itemTap(c.editItems.indexWhere((e) => e.name == 'Leftovers'));
    await c.confirm();
    expect(onDiskSave('Gambatte', crystal).boxMon(0, 0)!.itemName, 'Leftovers');
  });

  test('a game changed on disk: nothing written, read again', () async {
    final c = await opened();
    await c.showSource(gameIndex(c, crystal));
    c.select(0);
    c.check();
    await c.confirm();
    await c.confirm();
    // a sync brings a new save meanwhile
    final path = savePath('Gambatte', crystal);
    final changed = ps.PokeSave.open(File(path).readAsBytesSync())!
        .setItem(0, 0, 0x92)
        .save!;
    File(path).writeAsBytesSync(changed);
    await c.typedName('Nope');
    expect(c.notice, changedOnDiskText);
    expect(c.editing, isFalse);
    expect(File(path).readAsBytesSync(), changed);
  });

  test('the party page: first, before Box 1; shown, not moved', () async {
    final c = await opened();
    await c.showSource(gameIndex(c, crystal));
    expect(c.page, 1);
    expect(c.turnPage(-1), isTrue);
    expect(c.onParty, isTrue);
    expect(c.pageTitle(0), 'PARTY');
    expect(c.pageTitle(1), isNot('PARTY'));
    // the built save's party is empty: putting one there is refused
    c.turnPage(1);
    c.select(0);
    await c.confirm();
    c.turnPage(-1);
    c.select(0);
    await c.confirm();
    expect(c.notice, PokevilleController.partyFull);
    expect(c.holding, isTrue);
  });

  group('real saves', () {
    final root = Platform.environment['POKE_SAMPLES'];
    final skip = root == null || !Directory(root).existsSync()
        ? 'POKE_SAMPLES not set'
        : null;
    test(
      "every game's party: shown, renamed and named back (temp copies)",
      skip: skip,
      () async {
        final real = Directory.systemTemp.createTempSync('pokeville_real');
        addTearDown(() => real.deleteSync(recursive: true));
        final ra = p.join(real.path, 'saves');
        copyTree(p.join(root!, 'saves', 'retroarch'), ra);
        final box = p.join(real.path, 'pokeville');
        copyTree(p.join(root, 'pokeville'), box);
        final c = PokevilleController(
          PokevilleFolder(box, runner: runHere),
          games: PokeGames([ra]),
          guard: SaveGuard.none(),
          animate: false,
        );
        await c.open();
        expect(c.gameSaves, hasLength(8));
        for (var i = 0; i < c.gameSaves.length; i++) {
          final g = c.gameSaves[i];
          final before = File(g.path).readAsBytesSync();
          final save = ps.PokeSave.open(before, fileName: g.fileName)!;
          await c.showSource(i);
          c.goToPage(0);
          expect(c.onParty, isTrue);
          final party = save.party;
          expect(party, isNotEmpty);
          for (var s = 0; s < 6; s++) {
            expect(
              c.pageMon(0, s)?.name,
              s < party.length ? ps.speciesName(party[s].species) : null,
            );
          }
          // picking one up is refused (the party stays, as on the PC)
          c.select(0);
          await c.confirm();
          expect(c.holding, isFalse);
          expect(c.notice, PokevilleController.partyStays);
          // rename the first, then name it back
          final first = party.first;
          c.check();
          await c.confirm();
          await c.confirm();
          await c.typedName('Q');
          expect(c.notice, 'Q: nickname saved', reason: g.game);
          final mid = ps.PokeSave.open(
            File(g.path).readAsBytesSync(),
            fileName: g.fileName,
          )!;
          expect(mid.check(), '');
          expect(mid.party.first.nickname, 'Q');
          expect(mid.party.length, party.length);
          await c.confirm();
          await c.confirm();
          await c.typedName(first.isNicknamed ? first.nickname : '');
          final after = ps.PokeSave.open(
            File(g.path).readAsBytesSync(),
            fileName: g.fileName,
          )!;
          expect(after.party.first.summary, first.summary, reason: g.game);
          expect(after.check(), '');
          c.cancel();
        }
        // a real Pokéville file renamed and back: the same bytes
        await c.showSource(-1);
        c.goToPage(0);
        c.select(0);
        final file = '${PokeBoxStore.slot(c.data, 0, 0)['file']}';
        final before = File(PokeBoxStore.absolute(box, file)).readAsBytesSync();
        final m = c.hovered!;
        c.check();
        await c.confirm();
        await c.confirm();
        await c.typedName('Q');
        expect(c.shown!.nickname, 'Q');
        await c.confirm();
        await c.confirm();
        await c.typedName(m.nickname);
        expect(
          File(PokeBoxStore.absolute(box, file)).readAsBytesSync(),
          before,
        );
      },
    );
  });
}
