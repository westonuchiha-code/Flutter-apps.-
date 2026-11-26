import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:save_kit/save_kit.dart';
import 'package:test/test.dart';

Uint8List hex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
]);

/// Geolith's formatted card, as its source publishes it: size, both
/// checksums, the magic, the region, the two tables.
Uint8List geolithCard() {
  final d = Uint8List(2048)
    ..setAll(
      0,
      hex(
        '00000000000000000000100000'
        '0a0aff',
      ),
    )
    ..setAll(0x20, hex('4e4045444f482d4c475045544f58805c'))
    ..setAll(0xC0, hex('0202020202'))
    ..setAll(0x100, hex('0202020202'));
  for (var slot = 0; slot < 32; slot++) {
    d[0x40 + slot * 4] = 0xFF;
  }
  return d;
}

/// Save 3 of game NGH-055 ("METAL SLUG"), [blocks] blocks.
Uint8List neoSave([int blocks = 3, int number = 2]) {
  final one = Uint8List(4 + blocks * 64);
  one[0] = number;
  one[2] = 0x55;
  one.setAll(4, 'METAL SLUG'.codeUnits);
  return one;
}

void main() {
  test("Geolith's formatted card reads as empty and valid", () {
    final d = geolithCard();
    expect(NeoWriter.check(d), '');
    expect(NeoWriter.saves(d), isEmpty);
    expect(NeoWriter.freeList(d).length, 27);
    final blank = NeoWriter.blank();
    expect(blank[0x0D], d[0x0D]);
    expect(blank[0x0E], d[0x0E]);
    expect(blank.sublist(0xC0, 0x140), d.sublist(0xC0, 0x140));
    expect(blank.sublist(0, 0x0F), d.sublist(0, 0x0F));
    expect(blank.sublist(0x20, 0x30), d.sublist(0x20, 0x30));
    expect(blank[0x30], 1);
    expect(blank[5 * 64], 0x02); // an erased block: twice its address
    expect(blank[5 * 64 + 1], 0x80);
    final card = NeoCard.parse(d, MemoryCard());
    expect(card.error, '');
    expect(card.total, 27);
    expect(card.free, 27);
    expect(NeoWriter.blank(1, 3000), isEmpty);
  });

  test('an 8 KB CD card', () {
    final d = NeoWriter.blank(1, NeoWriter.cdSize);
    expect(NeoWriter.check(d), '');
    expect(NeoWriter.freeList(d).length, 115);
    expect(NeoWriter.fat1(d), 0x240);
    expect(NeoWriter.fat2(d), 0x2C0);
    expect(NeoWriter.firstData(d), 13);
    final put = NeoWriter.importSave(d, neoSave(100));
    expect(put.ok, isTrue, reason: put.error);
    expect(NeoWriter.check(put.data), '');
    expect(NeoWriter.chain(put.data, 0).first, 13);
    final wrongSize = Uint8List.fromList(d);
    wrongSize[NeoWriter.sizeAt] = 0x10; // says 2 KB
    expect(NeoWriter.isCard(wrongSize), isFalse);
  });

  test('import, export, title, refusals, delete, mirror', () {
    final blank = NeoWriter.blank();
    final one = neoSave();
    final a = NeoWriter.importSave(blank, one);
    expect(a.ok, isTrue, reason: a.error);
    expect(NeoWriter.check(a.data), '');
    expect(NeoWriter.saves(a.data), [0]);
    expect(NeoWriter.chain(a.data, 0), [5, 6, 7]);
    expect(NeoWriter.exportSave(a.data, 0).data, one);
    expect(NeoWriter.title(a.data, 0), 'METAL SLUG');
    expect(NeoWriter.saveNamed(a.data, one), 0);
    expect(NeoWriter.importSave(a.data, one).ok, isFalse);
    expect(
      NeoWriter.importSave(a.data, Uint8List(4 + 25 * 64)..[0] = 1).ok,
      isFalse,
    );
    expect(NeoWriter.importSave(a.data, neoSave(1, 16)).ok, isFalse);
    expect(NeoWriter.importSave(a.data, Uint8List(4 + 30)).ok, isFalse);
    expect(NeoWriter.importSave(Uint8List(2048), one).ok, isFalse);

    final gone = NeoWriter.delete(a.data, 0);
    expect(gone.ok, isTrue);
    expect(NeoWriter.check(gone.data), '');
    expect(NeoWriter.freeList(gone.data).length, 27);
    expect(NeoWriter.delete(gone.data, 0).ok, isFalse);

    final hurt = Uint8List.fromList(a.data);
    hurt[0xC0 + 6] ^= 4;
    expect(NeoWriter.fatAt(hurt), NeoWriter.fat2(hurt));
    expect(NeoWriter.check(hurt), '');
    final mended = NeoWriter.delete(hurt, 0).data;
    expect(NeoWriter.fatAt(mended), NeoWriter.fat1(mended));
    expect(NeoWriter.freeList(mended).length, 27);
    final both = Uint8List.fromList(hurt)..[0x100 + 6] ^= 4;
    expect(NeoWriter.fatAt(both), 0);
    expect(NeoWriter.check(both), contains('both copies'));
    expect(NeoCard.parse(both, MemoryCard()).error, isNotEmpty);

    final looped = Uint8List.fromList(a.data)..[0xC0 + 7] = 5;
    // A table that loops back is no save.
    final sum =
        [
          for (var i = 0; i < 32; i++) looped[0xC0 + i],
        ].reduce((x, y) => x + y) &
        0xFF;
    looped[0x0D] = sum;
    expect(NeoWriter.chain(looped, 0), isEmpty);
    expect(NeoWriter.check(looped), 'save 0 is broken');

    var full = blank;
    for (var i = 0; i < 9; i++) {
      final put = NeoWriter.importSave(full, neoSave(3, i));
      expect(put.ok, isTrue, reason: put.error);
      full = put.data;
    }
    expect(NeoWriter.freeList(full), isEmpty);
    expect(
      NeoWriter.importSave(full, neoSave(1, 15)).error,
      startsWith('Not enough room'),
    );
  });

  test('reader', () {
    final d = NeoWriter.importSave(NeoWriter.blank(), neoSave()).data;
    final card = NeoCard.parse(d, MemoryCard()..modified = 3);
    expect(card.error, '');
    expect(card.free, 24);
    final s = card.saves.single;
    expect(s.serial, 'NGH-055');
    expect(s.id, 'NGH-055 #3');
    expect(s.titleLines, ['METAL SLUG']);
    expect(s.blocks, 3);
    expect(s.kb, 1);
    expect(s.held, [5, 6, 7]);
    expect(s.modified, 3);
    expect(s.frames, hasLength(1));
  });

  test('odd-byte and MiSTer files keep their shape', () {
    final card = NeoWriter.importSave(NeoWriter.blank(), neoSave()).data;
    for (final length in [4096, 0x20000]) {
      final wide = Uint8List(length)..fillRange(0, length, 0xFF);
      final file = NeoWriter.packed(wide, card);
      expect(NeoWriter.plain(file), card, reason: '$length');
      expect(file[0], 0xFF);
      expect(NeoWriter.packed(file, NeoWriter.plain(file)), file);
    }
    expect(
      NeoWriter.packed(Uint8List(4096), NeoWriter.blank(1, 8192)),
      isEmpty,
    );
    for (final c in [card, NeoWriter.blank(1, NeoWriter.cdSize)]) {
      final mister = Uint8List(NeoWriter.mister)
        ..fillRange(0, NeoWriter.mister, 0xA5);
      final file = NeoWriter.packed(mister, c);
      expect(file.length, NeoWriter.mister);
      expect(file[0], 0xA5);
      expect(file[NeoWriter.misterAt + 0x21], 0x4E); // swapped words
      expect(NeoWriter.plain(file), c, reason: '${c.length}');
      expect(NeoWriter.packed(file, NeoWriter.plain(file)), file);
    }
    expect(NeoWriter.plain(Uint8List(NeoWriter.mister)), isEmpty);
    expect(NeoWriter.plain(Uint8List(5000)), isEmpty);
  });

  final samples = Platform.environment['SAVE_SAMPLES'] ?? '';
  test('real Neo Geo cards (none are known; any found are checked)', () {
    var cards = 0, saves = 0;
    for (final f in Directory(samples).listSync(recursive: true)) {
      if (f is! File) continue;
      final ext = p.extension(f.path).toLowerCase();
      if (!const ['.mcr', '.bin', '.srm', '.mem', '.sav'].contains(ext)) {
        continue;
      }
      final len = f.lengthSync();
      if (!NeoWriter.goodSize(len) &&
          len != NeoWriter.mister &&
          len != 0x20000) {
        continue;
      }
      final file = f.readAsBytesSync();
      final d = NeoWriter.plain(file);
      if (d.isEmpty) continue;
      final name = p.basename(f.path);
      cards++;
      expect(NeoWriter.check(d), '', reason: name);
      expect(NeoCard.parse(d, MemoryCard()).error, '', reason: name);
      expect(NeoWriter.packed(file, d), file, reason: name);
      final kept = <Uint8List>[];
      var card = d;
      for (final slot in NeoWriter.saves(d)) {
        kept.add(NeoWriter.exportSave(d, slot).data);
        card = NeoWriter.delete(card, slot).data;
      }
      for (final one in kept) {
        final put = NeoWriter.importSave(card, one);
        expect(put.ok, isTrue, reason: '$name: ${put.error}');
        card = put.data;
        saves++;
      }
      expect(card.sublist(0, 0x10), d.sublist(0, 0x10), reason: name);
      final slots = NeoWriter.saves(card);
      expect(slots.length, kept.length, reason: name);
      for (var i = 0; i < kept.length; i++) {
        expect(
          NeoWriter.exportSave(card, slots[i]).data,
          kept[i],
          reason: name,
        );
      }
    }
    // ignore: avoid_print
    print('Neo Geo: $cards real cards, $saves saves');
  }, skip: samples.isEmpty ? 'SAVE_SAMPLES not set' : false);
}
