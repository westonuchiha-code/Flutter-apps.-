// Delete card (ported from the PC's CardDeleteTests.gd): the file goes only
// after a backup that reads back, never with a favorite on it or while a
// console has it, and Bring back a deleted card puts it back byte for byte.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:save_kit/save_kit.dart';
import 'package:test/test.dart';

import 'ops_test.dart' show bytesOf, cardAt, opsIn, put;
import 'ps1_test.dart' show mcs;
import 'slots_test.dart' show formats;

void main() {
  late Directory temp;
  late String dir;
  late CardSafety safety;
  late CardOps ops;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('card_delete_test');
    dir = p.join(temp.path, 'delete');
    Directory(dir).createSync(recursive: true);
    safety = CardSafety(isApp: false, testRoots: [temp.path]);
    ops = opsIn(dir, safety, favoritesFile: p.join(dir, 'stars.json'));
    ops.slots = CardSlots(
      store: ops.store,
      recordFile: p.join(dir, 'slots.json'),
      formats: formats,
      raRoot: p.join(dir, 'RetroArch'),
    );
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test('an empty card is deleted and brought back byte for byte', () {
    final empty = p.join(dir, 'Empty.mcd');
    final bytes = Ps1Writer.blank();
    put(empty, bytes);
    var r = ops.deleteCard(cardAt(empty)!);
    expect(r.ok, isTrue, reason: r.text);
    expect(File(empty).existsSync(), isFalse);
    final gone = ops.deletedCards();
    expect(gone, hasLength(1), reason: 'listed to bring back');
    expect(gone[0].path, empty);
    r = ops.bringBack(gone[0]);
    expect(r.ok, isTrue, reason: r.text);
    expect(bytesOf(empty), bytes, reason: 'byte for byte');
    expect(ops.deletedCards(), isEmpty, reason: "isn't listed any more");
    expect(
      ops.bringBack(gone[0]).ok,
      isFalse,
      reason: "bringing back over a card that's there is refused",
    );
  });

  test('a card with a favorite on it stays', () {
    final full = p.join(dir, 'Full.mcd');
    final withSave = Ps1Writer.importSave(
      Ps1Writer.blank(),
      mcs('BASLUS-00001A', 1, 3),
    ).data;
    put(full, withSave);
    final card = cardAt(full)!;
    expect(card.saves, isNotEmpty);
    expect(ops.favorites.setFor(card.saves, true), '');
    final r = ops.deleteCard(card);
    expect(r.ok, isFalse);
    expect(r.text, contains('has a favorite on it'));
    expect(bytesOf(full), withSave);
    ops.favorites.setFor(card.saves, false);
    expect(
      ops.deleteCard(cardAt(full)!).ok,
      isTrue,
      reason: 'without the star it can go',
    );
    expect(File(full).existsSync(), isFalse);
  });

  test('an unreadable favorites list keeps every card', () {
    final path = p.join(dir, 'Any.mcd');
    put(path, Ps1Writer.blank());
    put(p.join(dir, 'stars.json'), '{broken'.codeUnits);
    final r = ops.deleteCard(cardAt(path)!);
    expect(r.text, CardFavorites.unreadable);
    expect(File(path).existsSync(), isTrue);
  });

  test('a card in a console slot stays', () {
    final a1 = p.join(dir, 'RetroArch', 'system', 'dc', 'vmu_save_A1.bin');
    put(a1, VmuWriter.blank());
    final card = MemoryCards.readFile(a1).first;
    final r = ops.deleteCard(card);
    expect(r.ok, isFalse);
    expect(r.text, contains('in the console'));
    expect(File(a1).existsSync(), isTrue);
  });

  test("a tool can't delete a real card", () {
    final real = opsIn(dir, safety, favoritesFile: p.join(dir, 'stars.json'));
    // a card that is there, just not in a test folder
    final elsewhere = Directory.systemTemp.createTempSync('not_a_test_root');
    addTearDown(() => elsewhere.deleteSync(recursive: true));
    final outsidePath = p.join(elsewhere.path, 'whatever.mcd');
    put(outsidePath, Ps1Writer.blank());
    final r = real.deleteCard(cardAt(outsidePath)!);
    expect(r.ok, isFalse);
    expect(r.text, CardSafety.refused);
    expect(File(outsidePath).existsSync(), isTrue);
  });
}
