import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:save_kit/save_kit.dart';
import 'package:test/test.dart';

/// A made-up .mcs: its directory frame, then [blocks] blocks of [fill].
Uint8List mcs(String name, int blocks, int fill) {
  final b = Uint8List(128 + blocks * 8192)
    ..fillRange(128, 128 + blocks * 8192, fill);
  b[0] = 0x51;
  Bytes.put32(b, 4, blocks * 8192);
  Bytes.put16(b, 8, 0xFFFF);
  for (var i = 0; i < name.length; i++) {
    b[10 + i] = name.codeUnitAt(i);
  }
  return b;
}

void main() {
  test('built PS1 cards: import, delete, undelete, export', () {
    final blank = Ps1Writer.blank();
    expect(Ps1Writer.check(blank), '');
    expect(Ps1Writer.freeBlocks(blank), 15);
    expect(Ps1Card.parse(blank, 'n', 'n', 0).free, 15);
    final a = Ps1Writer.importSave(blank, mcs('BASLUS-00001A', 3, 0x11));
    expect(a.ok, isTrue);
    expect(Ps1Writer.check(a.data), '');
    expect(Ps1Writer.saves(a.data), [1]);
    expect(Ps1Writer.freeBlocks(a.data), 12);
    final parsed = Ps1Card.parse(a.data, 'n', 'n', 0);
    expect(parsed.saves.single.id, 'BASLUS-00001A');
    expect(parsed.saves.single.blocks, 3);
    expect(parsed.saves.single.serial, 'SLUS-00001');
    expect(parsed.saves.single.region, 'America');
    expect(
      Ps1Writer.importSave(a.data, mcs('BASLUS-00001A', 1, 2)).ok,
      isFalse,
      reason: 'same name is refused, not replaced',
    );
    expect(
      Ps1Writer.importSave(a.data, mcs('BASLUS-00002B', 13, 2)).ok,
      isFalse,
      reason: 'too big',
    );
    expect(
      Ps1Writer.importSave(a.data, Uint8List.fromList([0x51, 1, 2])).ok,
      isFalse,
    );
    final gone = Ps1Writer.delete(a.data, 1);
    expect(gone.ok, isTrue);
    expect(Ps1Writer.check(gone.data), '');
    expect(Ps1Writer.freeBlocks(gone.data), 15);
    expect(Ps1Writer.deleted(gone.data), [1]);
    expect(
      Ps1Writer.undelete(gone.data, 1).data,
      a.data,
      reason: 'byte for byte',
    );
    expect(Ps1Writer.delete(gone.data, 1).ok, isFalse);
    expect(
      Ps1Writer.delete(a.data, 2).ok,
      isFalse,
      reason: "only a save's start deletes",
    );
    final beside = Ps1Writer.importSave(
      gone.data,
      mcs('BASLUS-00002B', 2, 0x22),
    );
    expect(Ps1Writer.saves(beside.data), [
      4,
    ], reason: 'new saves avoid deleted ones');
    expect(Ps1Writer.deleted(beside.data), [1]);
    final over = Ps1Writer.importSave(
      gone.data,
      mcs('BASLUS-00003C', 13, 0x33),
    );
    expect(over.ok, isTrue);
    expect(Ps1Writer.check(over.data), '');
    expect(
      Ps1Writer.deleted(over.data),
      isEmpty,
      reason: "a written-over save can't be half undeleted",
    );
    final torn = Uint8List.fromList(a.data);
    torn[2 * 128 + 4] ^= 1;
    expect(Ps1Writer.check(torn), isNot(''));
  });

  final samples = Platform.environment['SAVE_SAMPLES'];
  test('real PS1 cards', () {
    final files = Directory(samples!)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) {
          final e = p.extension(f.path).toLowerCase();
          return (e == '.mcd' || e == '.mcr' || e == '.srm' || e == '.mc') &&
              f.lengthSync() == Ps1Card.size;
        })
        .toList();
    var cards = 0, saves = 0, titled = 0;
    for (final f in files) {
      final d = f.readAsBytesSync();
      if (!Ps1Card.isCard(d)) continue;
      cards++;
      final where = p.basename(f.path);
      expect(Ps1Writer.check(d), '', reason: where);
      final parsed = Ps1Card.parse(d, where, f.path, 0);
      expect(parsed.error, '');
      expect(Ps1Writer.saves(d).length, parsed.saves.length, reason: where);
      for (final s in parsed.saves) {
        if (s.titleLines.isNotEmpty) titled++;
      }
      for (final slot in Ps1Writer.saves(d)) {
        saves++;
        final out = Ps1Writer.exportSave(d, slot);
        final gone = Ps1Writer.delete(d, slot);
        expect(out.ok && gone.ok, isTrue, reason: '$where $slot');
        expect(Ps1Writer.check(gone.data), '');
        expect(
          Ps1Writer.undelete(gone.data, slot).data,
          d,
          reason: '$where $slot',
        );
        final copy = Ps1Writer.importSave(Ps1Writer.blank(), out.data);
        expect(copy.ok, isTrue, reason: '$where $slot');
        expect(Ps1Writer.check(copy.data), '');
        final back = Ps1Writer.exportSave(copy.data, 1).data;
        expect(back.sublist(128), out.data.sublist(128));
        expect(back.sublist(10, 31), out.data.sublist(10, 31));
      }
    }
    expect(saves, greaterThan(0));
    // ignore: avoid_print
    print('PS1: $cards real cards, $saves saves round-tripped, $titled titled');
  }, skip: samples == null ? 'set SAVE_SAMPLES to the sample saves' : false);
}
