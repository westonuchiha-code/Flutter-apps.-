// The phone's copies of the PC's PS2 cards and PS3 saves (Cross-Save brings
// them down; no emulator here uses them): read, export, back up and copy
// from, never changed.
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:save_kit/save_kit.dart';
import 'package:test/test.dart';

import 'ops_test.dart' show bytesOf, cardAt, opsIn, put;
import 'ps2_test.dart' show psu;
import 'ps3_ops_test.dart' show makeSave, saveId;

/// Every file under [dir]: path -> bytes, to see nothing changed.
Map<String, List<int>> filesIn(String dir) => {
  for (final e in Directory(dir).listSync(recursive: true))
    if (e is File) e.path: e.readAsBytesSync(),
};

void main() {
  late Directory temp;
  late String copies, mine;
  late CardSafety safety;
  late CardOps ops;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('read_only_test');
    final saves = p.join(temp.path, 'XMB Frontend', 'Saves');
    copies = p.join(saves, 'PCSX2');
    mine = p.join(temp.path, 'mine');
    safety = CardSafety(
      isApp: false,
      testRoots: [temp.path],
      readOnly: [copies, p.join(saves, 'RPCS3')],
    );
    ops = opsIn(p.join(temp.path, 'app'), safety);
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test('the gate: under a read-only folder, whatever the spelling', () {
    expect(
      safety.refusal(p.join(copies, 'memcards', 'Mcd001.ps2')),
      CardSafety.readOnlyNotice,
    );
    expect(safety.refusal(copies.toUpperCase()), CardSafety.readOnlyNotice);
    expect(
      safety.refusal(p.join(copies, 'memcards', '..', 'x.ps2')),
      CardSafety.readOnlyNotice,
    );
    expect(safety.refusal(p.join(mine, 'Mcd001.ps2')), '');
    expect(safety.refusal('${copies}2/x.ps2'), '', reason: 'a sibling');
    expect(safety.isReadOnly(''), isFalse);
  });

  test('a PC copy of a PS2 card: look, export, back up, copy from', () {
    final path = p.join(copies, 'memcards', 'Mcd001.ps2');
    put(path, Ps2Writer.blank());
    final mineCard = p.join(mine, 'card.ps2');
    put(mineCard, Ps2Writer.blank());
    // a save on the copy (put there as the PC would have)
    final savePath = p.join(mine, 'save.psu');
    put(savePath, psu('BASLUS-00002B', [964, 3000]));
    final open = CardSafety(isApp: false, testRoots: [temp.path]);
    expect(
      opsIn(
        p.join(temp.path, 'pc'),
        open,
      ).importFile(cardAt(path)!, savePath).ok,
      isTrue,
    );
    final card = cardAt(path)!;
    final ids = [card.saves.single.id];
    final before = filesIn(copies);

    expect(ops.exportSaves(card, ids).ok, isTrue, reason: 'export');
    expect(ops.backUpSaves(card, ids).ok, isTrue, reason: 'back up saves');
    expect(ops.backUpCards([card]).ok, isTrue, reason: 'back up the card');
    expect(ops.checkCard(card).ok, isTrue);
    final copied = ops.copySaves(card, ids, cardAt(mineCard)!);
    expect(copied.ok, isTrue, reason: 'copy from it (${copied.text})');
    expect(cardAt(mineCard)!.saves, hasLength(1));

    final refused = <String, OpResult>{
      'delete saves': ops.deleteSaves(card, ids),
      'import': ops.importFile(card, savePath, replace: true),
      'copy onto': ops.copySaves(cardAt(mineCard)!, ids, card, replace: true),
      'move away': ops.copySaves(
        card,
        ids,
        cardAt(mineCard)!,
        replace: true,
        move: true,
      ),
      'restore save': ops.restoreSave(card, ops.saveHistory(card, ids[0])[0]),
      'format': ops.formatCard(card),
      'restore card': ops.restoreCard(card, ops.cardHistory(card)[0]),
      'delete card': ops.deleteCard(card),
      'duplicate': ops.duplicateCard(card),
      'new card': ops.newCard(card),
    };
    for (final e in refused.entries) {
      expect(e.value.ok, isFalse, reason: e.key);
      expect(e.value.text, CardSafety.readOnlyNotice, reason: e.key);
    }
    expect(filesIn(copies).keys, before.keys, reason: 'no file made or gone');
    for (final e in before.entries) {
      expect(filesIn(copies)[e.key], e.value, reason: e.key);
    }
    // the store itself refuses too (every write path)
    final store = ops.store;
    expect(
      store.create(
        p.join(copies, 'memcards', 'New.ps2'),
        Ps2Writer.blank(),
        (_) => '',
      ),
      CardSafety.readOnlyNotice,
    );
    expect(
      store.writeFile(p.join(copies, 'x'), Uint8List(1), 'x'),
      CardSafety.readOnlyNotice,
    );
    expect(store.remove(path, bytesOf(path), 'x'), CardSafety.readOnlyNotice);
    expect(store.makeFolder(p.join(copies, 'new')), CardSafety.readOnlyNotice);
  });

  test("the PC's PS2 cards and PS3 saves are found, and kept as they are", () {
    final savedata = p.join(
      temp.path,
      'XMB Frontend',
      'Saves',
      'RPCS3',
      'savedata',
    );
    makeSave(p.join(savedata, saveId), 3000);
    put(p.join(copies, 'memcards', 'Mcd001.ps2'), Ps2Writer.blank());
    // the Android list reads XMB Frontend/Saves as a whole
    final found = MemoryCards.readCards([
      p.join(temp.path, 'XMB Frontend', 'Saves'),
    ]);
    final ps3 = found.singleWhere((c) => c.system == 'PS3');
    expect(
      found.singleWhere((c) => c.system == 'PS2').path,
      p.join(copies, 'memcards', 'Mcd001.ps2'),
    );
    expect(ps3.path, savedata);
    expect(ps3.saves.single.id, saveId);
    final before = filesIn(savedata);
    expect(ops.exportSaves(ps3, [saveId]).ok, isTrue);
    expect(ops.backUpSaves(ps3, [saveId]).ok, isTrue);
    final del = ops.deleteSaves(ps3, [saveId]);
    expect(del.text, CardSafety.readOnlyNotice);
    expect(ops.newCard(ps3).ok, isFalse);
    expect(filesIn(savedata).keys, before.keys);
    for (final e in before.entries) {
      expect(filesIn(savedata)[e.key], e.value);
    }
  });
}
