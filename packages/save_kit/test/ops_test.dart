// Every verb on every console (ported from the PC's CardOpsTests.gd),
// through real files in a test folder: cards found by the menu's own
// reader, changed by CardOps, read back from disk.
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:save_kit/save_kit.dart';
import 'package:test/test.dart';

import 'dreamcast_test.dart' show dci;
import 'gamecube_test.dart' show gci;
import 'ps1_test.dart' show mcs;
import 'ps2_test.dart' show psu;
import 'saturn_test.dart' show bup;

/// The emulators running in these tests: none of them.
List<String> nothingRunning() => ['bash'];

CardOps opsIn(
  String dir,
  CardSafety safety, {
  String favoritesFile = '',
  List<String>? Function()? running = nothingRunning,
}) => CardOps(
  safety: safety,
  backupRoot: p.join(dir, 'backups'),
  exportDir: p.join(dir, 'exports'),
  favoritesFile: favoritesFile,
  running: running,
);

void put(String path, List<int> bytes) {
  Directory(p.dirname(path)).createSync(recursive: true);
  File(path).writeAsBytesSync(bytes, flush: true);
}

Uint8List bytesOf(String path) => File(path).readAsBytesSync();

/// The [at]th card in a file, as the menu reads it (null = none).
MemoryCard? cardAt(String path, [int at = 0]) {
  final found = MemoryCards.readFile(path);
  return at < found.length ? found[at] : null;
}

/// (file name, blank card, a save file) per console.
Map<String, (String, Uint8List, Uint8List)> fixtures() {
  final note = Uint8List(32 + 2 * 256);
  for (var i = 0; i < 6; i++) {
    note[i] = 0x41 + i;
  }
  Bytes.putBe16(note, 6, PakWriter.noStart);
  note[8] = 2;
  note[16] = 0x1A;
  final neo = Uint8List(4 + 64);
  neo[0] = 1;
  neo[2] = 0x55;
  return {
    'PS1': ('card.mcd', Ps1Writer.blank(), mcs('BASLUS-00001A', 2, 7)),
    'PS2': ('card.ps2', Ps2Writer.blank(), psu('BASLUS-00002B', [964, 3000])),
    'DC': ('card.vmu', VmuWriter.blank(), dci('SAVE_ONE', 3, VmuWriter.data)),
    'GC': ('card.raw', GcWriter.blank(4), gci('GTST', 2)),
    'N64': ('card.mpk', PakWriter.blank(), note),
    'SATURN': ('card.bkr', SaturnWriter.blank(), bup('SAVE_ONE', 300)),
    'NEO GEO': ('card.mcr', NeoWriter.blank(), neo),
  };
}

/// The directory part of a save file holds where it sat, which may move.
bool sameSave(String system, Uint8List a, Uint8List b) {
  final skip = CardOps.entryBytes[system]!;
  return a.isNotEmpty &&
      a.length == b.length &&
      Bytes.same(a.sublist(skip), b.sublist(skip));
}

String folderOf(String system) => system.toLowerCase().replaceAll(' ', '_');

void main() {
  late Directory temp;
  late String dir;
  late CardSafety safety;
  late CardOps ops;
  final all = fixtures();

  setUpAll(() {
    temp = Directory.systemTemp.createTempSync('card_ops_test');
    dir = p.join(temp.path, 'ops');
    Directory(dir).createSync(recursive: true);
    safety = CardSafety(isApp: false, testRoots: [temp.path]);
    ops = opsIn(dir, safety);
  });
  tearDownAll(() => temp.deleteSync(recursive: true));

  for (final MapEntry(key: system, value: fixture) in all.entries) {
    test('$system: every verb', () {
      final (name, blank, save) = fixture;
      final d = p.join(dir, folderOf(system));
      final aPath = p.join(d, 'a_$name'), bPath = p.join(d, 'b_$name');
      put(aPath, blank);
      put(bPath, blank);
      final savePath = p.join(d, 'save.${CardOps.saveExt[system]}');
      put(savePath, save);
      var a = cardAt(aPath)!;
      final b = cardAt(bPath)!;
      expect(a.system, system, reason: 'the cards are found');

      var r = ops.importFile(a, savePath);
      expect(r.ok, isTrue, reason: 'import (${r.text})');
      a = cardAt(aPath)!;
      expect(a.saves, hasLength(1), reason: 'the imported save shows');
      final id = a.saves[0].id;
      expect(
        CardOps.idIn(system, save),
        id,
        reason: 'a save file and its save share an id',
      );
      r = ops.importFile(a, savePath);
      expect(r.ok, isFalse);
      expect(r.conflicts, [id], reason: 'the same save asks before replacing');
      expect(ops.importFile(a, savePath, replace: true).ok, isTrue);
      expect(cardAt(aPath)!.saves, hasLength(1), reason: 'replace leaves one');

      final ids = [id];
      final kept = ops.exportBytes(ops.openCard(a), id).data;
      r = ops.copySaves(a, ids, b);
      expect(r.ok, isTrue, reason: 'copy (${r.text})');
      expect(cardAt(bPath)!.saves, hasLength(1));
      expect(
        ops.copySaves(a, ids, b).conflicts,
        isNotEmpty,
        reason: 'copy asks before replacing',
      );
      expect(ops.backUpSaves(a, ids).ok, isTrue);
      expect(
        ops.saveHistory(a, id).length,
        greaterThanOrEqualTo(2),
        reason: 'save history',
      );
      expect(ops.exportSaves(a, ids).ok, isTrue, reason: 'export');
      expect(ops.checkCard(a).ok, isTrue, reason: 'check');

      expect(ops.deleteSaves(a, ids).ok, isTrue, reason: 'delete');
      expect(cardAt(aPath)!.saves, isEmpty);
      final lost = ops.lostSaves(a);
      expect(lost, hasLength(1), reason: 'a deleted save is offered back');
      expect(lost[0].id, id);
      r = ops.undelete(a, lost[0]);
      expect(r.ok, isTrue, reason: 'undelete (${r.text})');
      final back = ops.exportBytes(ops.openCard(a), id);
      expect(sameSave(system, back.data, kept), isTrue, reason: 'undelete');

      expect(ops.deleteSaves(b, ids).ok, isTrue, reason: 'delete the copy');
      r = ops.copySaves(a, ids, b, move: true);
      expect(r.ok, isTrue, reason: 'move (${r.text})');
      expect(cardAt(aPath)!.saves, isEmpty);
      expect(cardAt(bPath)!.saves, hasLength(1));

      expect(ops.backUpCards([b]).ok, isTrue, reason: 'back up card');
      final full = bytesOf(bPath);
      final wanted = ops.cardHistory(b)[0];
      r = ops.formatCard(b);
      expect(r.ok, isTrue, reason: 'format (${r.text})');
      expect(cardAt(bPath)!.saves, isEmpty);
      r = ops.restoreCard(b, wanted);
      expect(r.ok, isTrue, reason: 'restore card (${r.text})');
      expect(bytesOf(bPath), full, reason: 'byte for byte');
      expect(ops.duplicateCard(b).ok, isTrue, reason: 'duplicate');
      r = ops.newCard(b);
      expect(r.ok, isTrue, reason: 'new card (${r.text})');
      var total = 0, empty = 0;
      for (final c in MemoryCards.readCards([d])) {
        // the test's own .gci file rightly reads as a folder of saves
        if (c.isFolder) continue;
        total++;
        if (c.error.isEmpty && c.saves.isEmpty) empty++;
      }
      expect(
        (total, empty),
        (4, 2),
        reason: 'the duplicate and new card read as cards',
      );
    });
  }

  test('a file shared by four paks', () {
    final file = Uint8List(CardImage.n64Combined)
      ..fillRange(0, CardImage.n64Combined, 0x5A); // the game's own EEPROM...
    for (var i = 0; i < 4; i++) {
      file.setAll(CardImage.n64PaksAt + i * PakWriter.size, PakWriter.blank());
    }
    final path = p.join(dir, 'shared', 'Game.srm');
    put(path, file);
    final notePath = p.join(dir, 'n64', 'save.note');
    var r = ops.importFile(cardAt(path, 1)!, notePath);
    expect(r.ok, isTrue, reason: 'import into pak 2 (${r.text})');
    final now = bytesOf(path);
    final cut = CardImage.n64PaksAt + PakWriter.size;
    expect(now.sublist(0, cut), file.sublist(0, cut));
    expect(
      now.sublist(cut + PakWriter.size),
      file.sublist(cut + PakWriter.size),
      reason: 'only that pak changed',
    );
    final two = cardAt(path, 1)!;
    expect(two.saves, isNotEmpty);
    r = ops.copySaves(two, [two.saves[0].id], cardAt(path, 2)!, move: true);
    expect(r.ok, isTrue, reason: 'move between its own paks (${r.text})');
    expect(cardAt(path, 1)!.saves, isEmpty);
    expect(cardAt(path, 2)!.saves, hasLength(1));
  });

  test('a folder of .gci', () {
    final d = p.join(dir, 'dolphin', 'USA', 'Card A');
    final gciFile = bytesOf(p.join(dir, 'gc', 'save.gci'));
    put(p.join(d, 'first.gci'), gciFile);
    final cards = MemoryCards.readCards([d]);
    expect(cards, hasLength(1));
    expect(cards[0].isFolder, isTrue, reason: 'a .gci folder is found');
    expect(cards[0].saves, isNotEmpty);
    final ids = [cards[0].saves[0].id];
    expect(ops.deleteSaves(cards[0], ids).ok, isTrue);
    expect(File(p.join(d, 'first.gci')).existsSync(), isFalse);
    final lost = ops.lostSaves(cards[0]);
    expect(lost, hasLength(1));
    expect(ops.undelete(cards[0], lost[0]).ok, isTrue, reason: 'undelete');
    expect(Directory(d).listSync(), hasLength(1), reason: 'one file again');
    expect(ops.lostSaves(cards[0]), isEmpty, reason: "it's back, not lost");
    final again = ops.restoreSave(cards[0], lost[0].backup!);
    expect(again.ok, isFalse, reason: 'restoring over it asks first');
    expect(again.conflicts, isNotEmpty);
    expect(
      ops.restoreSave(cards[0], lost[0].backup!, replace: true).ok,
      isTrue,
    );
    expect(Directory(d).listSync(), hasLength(1), reason: 'still one file');

    final twins = p.join(dir, 'dolphin', 'EUR', 'Card A');
    final first = gciFile;
    final second = Uint8List.fromList(first);
    second[second.length - 1] ^= 0xFF;
    put(p.join(twins, 'one.gci'), first);
    put(p.join(twins, 'two.gci'), second);
    final folder = MemoryCards.readCards([twins])[0];
    expect(
      folder.saves[0].id,
      isNot(folder.saves[1].id),
      reason: 'two same-named .gci stay two saves',
    );
    final both = [folder.saves[0].id, folder.saves[1].id];
    expect(ops.deleteSaves(folder, both).ok, isTrue);
    expect(Directory(twins).listSync(), isEmpty, reason: 'both delete');
    for (final e in ops.lostSaves(folder)) {
      ops.undelete(folder, e);
    }
    expect(bytesOf(p.join(twins, 'one.gci')), first);
    expect(
      bytesOf(p.join(twins, 'two.gci')),
      second,
      reason: 'each comes back as itself',
    );
    expect(
      CardOps.namedFile('G x [../../evil.gci]'),
      '',
      reason: "a file name out of a backup can't leave the folder",
    );
    expect(CardOps.namedFile('G x [two.gci]'), 'two.gci');
  });

  test('a gzipped Saturn cart stays gzipped', () {
    final path = p.join(dir, 'gzip', 'Game.bcr');
    put(
      path,
      const GZipEncoder().encode(SaturnWriter.blank(SaturnWriter.cart)),
    );
    final r = ops.importFile(cardAt(path)!, p.join(dir, 'saturn', 'save.bup'));
    final now = cardAt(path);
    expect(r.ok, isTrue, reason: r.text);
    expect(now, isNotNull);
    expect(now!.gzip, isTrue, reason: 'still gzip');
    expect(now.saves, hasLength(1));
  });

  // A starred save survives every way of losing it; backing up and moving
  // still work.
  for (final MapEntry(key: system, value: fixture) in all.entries) {
    test('$system: favorites', () {
      final (name, blank, save) = fixture;
      final d = p.join(dir, 'stars', folderOf(system));
      final aPath = p.join(d, 'a_$name'), bPath = p.join(d, 'b_$name');
      put(aPath, blank);
      put(bPath, blank);
      final savePath = p.join(d, 'save.${CardOps.saveExt[system]}');
      put(savePath, save);
      final empty = cardAt(aPath)!;
      ops.backUpCards([empty]);
      final emptied = ops.cardHistory(empty)[0];
      ops.importFile(empty, savePath);
      final a = cardAt(aPath)!;
      expect(a.saves, isNotEmpty, reason: 'favorite fixture');
      final ids = [a.saves[0].id];
      expect(ops.favorites.setFor([a.saves[0]], true), '', reason: 'star it');
      final was = bytesOf(aPath);
      expect(
        ops.deleteSaves(a, ids).ok,
        isFalse,
        reason: "a favorite can't be deleted",
      );
      expect(ops.formatCard(a).ok, isFalse, reason: 'or formatted away');
      final over = ops.importFile(a, savePath, replace: true);
      expect(over.ok, isFalse, reason: 'or replaced');
      expect(over.conflicts, isEmpty);
      expect(
        ops.restoreCard(a, emptied).ok,
        isFalse,
        reason: 'or lost to an older card',
      );
      expect(bytesOf(aPath), was, reason: 'and the card is untouched');
      expect(ops.backUpSaves(a, ids).ok, isTrue, reason: 'can be backed up');
      final moved = ops.copySaves(a, ids, cardAt(bPath)!, move: true);
      final b = cardAt(bPath)!;
      expect(moved.ok, isTrue, reason: 'and moved (${moved.text})');
      expect(b.saves, hasLength(1));
      expect(cardAt(aPath)!.saves, isEmpty);
      final there = [b.saves[0].id];
      expect(
        ops.deleteSaves(b, there).ok,
        isFalse,
        reason: 'the star moved with it',
      );
      ops.favorites.setFor([b.saves[0]], false);
      expect(
        ops.deleteSaves(b, there).ok,
        isTrue,
        reason: 'no star, deletes again',
      );
    });
  }

  test('refusals', () {
    final broken = p.join(dir, 'broken_stars.json');
    put(broken, '{not json'.codeUnits);
    final careful = opsIn(dir, safety, favoritesFile: broken);
    final ps1 = cardAt(p.join(dir, 'ps1', 'a_card.mcd'))!;
    expect(
      !careful.formatCard(ps1).ok || ps1.saves.isEmpty,
      isTrue,
      reason: 'an unreadable list protects everything',
    );
    final dPath = p.join(dir, 'ps1', 'd.mcd');
    put(dPath, Ps1Writer.blank());
    ops.importFile(cardAt(dPath)!, p.join(dir, 'ps1', 'save.mcs'));
    final dCard = cardAt(dPath)!;
    expect(dCard.saves, isNotEmpty);
    final stopped = careful.deleteSaves(dCard, [dCard.saves[0].id]);
    expect(stopped.ok, isFalse);
    expect(stopped.text, CardFavorites.unreadable, reason: 'and says why');

    final aPath = p.join(dir, 'ps1', 'a_card.mcd');
    final a = cardAt(aPath)!;
    final before = bytesOf(aPath);
    final save = p.join(dir, 'ps1', 'save.mcs');
    expect(
      ops.importFile(a, p.join(dir, 'ps2', 'save.psu')).ok,
      isFalse,
      reason: "another console's save file is refused",
    );
    final busy = opsIn(dir, safety, running: () => ['duckstation-qt.exe']);
    final r = busy.importFile(a, save);
    expect(r.ok, isFalse);
    expect(
      r.text,
      contains('DuckStation'),
      reason: 'a running emulator stops every verb',
    );
    final blind = opsIn(dir, safety, running: () => null);
    expect(
      blind.importFile(a, save).text,
      CardOwners.cantTell,
      reason: "can't tell = no write",
    );
    final outsidePath = p.join(temp.parent.path, '_not_a_test_card.mcd');
    final outside = MemoryCard()
      ..system = 'PS1'
      ..path = outsidePath;
    expect(
      ops.formatCard(outside).ok,
      isFalse,
      reason: 'nothing outside the test folders',
    );
    expect(File(outsidePath).existsSync(), isFalse);
    expect(bytesOf(aPath), before, reason: 'refusals change nothing');
    for (final evil in ['../../x', 'CON', r'a/b\c:d*?', '', 'nul', 'x.']) {
      final name = CardOps.fileSafe(evil);
      final plain = !RegExp(r'[/\\:.]').hasMatch(name);
      expect(
        name.isNotEmpty &&
            plain &&
            !['CON', 'NUL'].contains(name.toUpperCase()),
        isTrue,
        reason: "safe file name for '$evil' ($name)",
      );
    }
  });
}
