import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:save_kit/save_kit.dart';
import 'package:test/test.dart';

/// A made-up .bup: [name], [length] bytes of data.
Uint8List bup(String name, int length) {
  final b = Uint8List(64 + length)..setAll(0, 'Vmem'.codeUnits);
  b.setAll(0x10, name.codeUnits);
  Bytes.putBe32(b, 0x28, 23142240);
  Bytes.putBe32(b, 0x2C, length);
  for (var i = 0; i < length; i++) {
    b[64 + i] = (i * 7 + 1) & 0xFF;
  }
  return b;
}

List<File> sampleFiles(String root, List<String> exts) => [
  for (final f in Directory(root).listSync(recursive: true))
    if (f is File &&
        !f.path.contains('${p.separator}.git${p.separator}') &&
        exts.contains(p.extension(f.path).toLowerCase()))
      f,
]..sort((a, b) => a.path.compareTo(b.path));

void main() {
  for (final size in [SaturnWriter.internal, SaturnWriter.cart]) {
    final label = 'Saturn ${size ~/ 1024} KB';
    test('$label: import, read back, refuse, delete', () {
      final blank = SaturnWriter.blank(size);
      expect(SaturnWriter.check(blank), '');
      expect(SaturnWriter.saves(blank), isEmpty);
      final total = SaturnWriter.freeList(blank).length;
      expect(total, size ~/ SaturnWriter.blockSize(size) - 2);
      var card = blank;
      const lengths = [0, 1, 26, 27, 28, 29, 85, 86, 87, 88, 1000, 9000];
      for (var i = 0; i < lengths.length; i++) {
        final one = bup('SAVE_$i', lengths[i]);
        final put = SaturnWriter.importSave(card, one);
        expect(put.ok, isTrue, reason: '${lengths[i]} bytes: ${put.error}');
        card = put.data;
        final first = SaturnWriter.saveNamed(card, one);
        expect(first, greaterThanOrEqualTo(2));
        expect(
          SaturnWriter.save(card, first)!.data,
          one.sublist(64),
          reason: '${lengths[i]} bytes come back',
        );
        final out = SaturnWriter.exportSave(card, first).data;
        expect(out.sublist(0, 0x30), one.sublist(0, 0x30));
        expect(out.sublist(64), one.sublist(64));
      }
      expect(SaturnWriter.check(card), '');
      expect(SaturnWriter.saves(card).length, lengths.length);
      expect(SaturnWriter.importSave(card, bup('SAVE_1', 4)).ok, isFalse);
      expect(SaturnWriter.importSave(card, bup('HUGE', size)).ok, isFalse);
      expect(SaturnWriter.importSave(card, bup('', 4)).ok, isFalse);
      final notBup = bup('X', 4)..[0] = 0;
      expect(SaturnWriter.importSave(card, notBup).ok, isFalse);
      final wrongLength = bup('X', 4);
      Bytes.putBe32(wrongLength, 0x2C, 5);
      expect(SaturnWriter.importSave(card, wrongLength).ok, isFalse);
      for (final b in SaturnWriter.saves(card)) {
        card = SaturnWriter.delete(card, b).data;
      }
      expect(SaturnWriter.freeList(card).length, total);
      expect(SaturnWriter.delete(card, 2).ok, isFalse);
    });
  }

  test('a long save: its list runs on into the blocks it names', () {
    // 9000 bytes in 64-byte blocks needs ~150 blocks: a list of 300 bytes,
    // far more than the first block holds.
    final card = SaturnWriter.importSave(
      SaturnWriter.blank(),
      bup('LONG', 9000),
    ).data;
    final s = SaturnWriter.save(card, 2)!;
    expect(s.blocks.length, greaterThan(30));
    expect(s.blocks.toSet().length, s.blocks.length);
    expect(s.data, bup('LONG', 9000).sublist(64));
    final broken = Uint8List.fromList(card);
    Bytes.putBe16(broken, 2 * 64 + 0x22, 1); // a block below the data
    expect(SaturnWriter.save(broken, 2), isNull);
    expect(SaturnWriter.check(broken), contains('broken'));
    final shared = Uint8List.fromList(card);
    shared[s.blocks[5] * 64] = 1; // another save's tag in its block
    expect(SaturnWriter.check(shared), contains('two saves'));
  });

  test('reader: name, comment, language, 1980 minutes', () {
    final file = bup('NIGHTS_01', 100);
    file.setAll(0x1C, [0x82, 0x60, 0x82, 0x50]); // full-width "A1"
    file[0x27] = 1;
    final d = SaturnWriter.importSave(SaturnWriter.blank(), file).data;
    final card = SaturnCard.parse(d, MemoryCard()..modified = 7);
    expect(card.error, '');
    expect(card.total, 510);
    final s = card.saves.single;
    expect(s.id, 'NIGHTS_01');
    expect(s.titleLines, ['A1']);
    expect(s.region, 'English');
    expect(s.slot, 2);
    expect(s.blocks, 3);
    expect(s.kb, 1);
    expect(card.free, 507);
    final t = DateTime.utc(1980).add(const Duration(minutes: 23142240));
    expect(
      s.created,
      DateTime(
            t.year,
            t.month,
            t.day,
            t.hour,
            t.minute,
          ).millisecondsSinceEpoch ~/
          1000,
    );
    expect(s.modified, s.created);
    expect(SaturnCard.time(0), 0);
    final undated = Uint8List.fromList(d);
    Bytes.putBe32(undated, 2 * 64 + 0x1A, 0);
    expect(
      SaturnCard.parse(
        undated,
        MemoryCard()..modified = 7,
      ).saves.single.modified,
      7,
    );
    expect(SaturnCard.parse(Uint8List(100), MemoryCard()).error, isNotEmpty);
  });

  test('padded and gzipped files keep their shape', () {
    final doubled = Uint8List(SaturnWriter.internal * 2)
      ..fillRange(0, SaturnWriter.internal * 2, 0xFF);
    final small = SaturnWriter.blank();
    final wide = SaturnWriter.packed(doubled, small);
    expect(SaturnWriter.plain(wide), small);
    expect(wide[0], 0xFF);
    expect(SaturnWriter.packed(Uint8List(5), small), isEmpty);
    expect(SaturnWriter.plain(Uint8List(SaturnWriter.internal * 2)), isEmpty);
    final cart = SaturnWriter.blank(SaturnWriter.cart);
    final zipped = SaturnWriter.gzip(cart);
    expect(SaturnWriter.isGzip(zipped), isTrue);
    expect(SaturnWriter.gunzip(zipped), cart);
    expect(SaturnWriter.gunzip(cart), isEmpty);
  });

  final samples = Platform.environment['SAVE_SAMPLES'] ?? '';
  final noSamples = samples.isEmpty ? 'SAVE_SAMPLES not set' : false;

  test('real Saturn memory: read, check, empty and rebuild', () {
    var cards = 0, saves = 0;
    for (final f in sampleFiles(samples, ['.bkr', '.bcr', '.srm', '.sav'])) {
      final file = f.readAsBytesSync();
      final before = Uint8List.fromList(file);
      var d = SaturnWriter.plain(file);
      if (d.isEmpty) d = SaturnWriter.gunzip(file);
      if (d.isEmpty) continue;
      final name = p.basename(f.path);
      cards++;
      expect(SaturnWriter.check(d), '', reason: name);
      final read = SaturnCard.parse(d, MemoryCard());
      expect(read.error, '', reason: name);
      expect(read.saves.length, SaturnWriter.saves(d).length, reason: name);
      if (!SaturnWriter.isGzip(file)) {
        expect(
          SaturnWriter.packed(file, d),
          file,
          reason: '$name keeps its shape',
        );
      }
      final kept = <Uint8List>[];
      var card = d;
      for (final b in SaturnWriter.saves(d)) {
        kept.add(SaturnWriter.exportSave(d, b).data);
        card = SaturnWriter.delete(card, b).data;
      }
      expect(SaturnWriter.saves(card), isEmpty, reason: name);
      for (final one in kept) {
        final put = SaturnWriter.importSave(card, one);
        expect(put.ok, isTrue, reason: '$name: ${put.error}');
        card = put.data;
        saves++;
      }
      expect(SaturnWriter.check(card), '', reason: name);
      final again = SaturnWriter.saves(card);
      expect(again.length, kept.length, reason: '$name rebuilt');
      for (var i = 0; i < kept.length; i++) {
        expect(
          SaturnWriter.exportSave(card, again[i]).data,
          kept[i],
          reason: name,
        );
      }
      expect(file, before, reason: 'never changed in place');
    }
    expect(cards, greaterThan(0));
    // ignore: avoid_print
    print('Saturn: $cards real cards, $saves saves copied back');
  }, skip: noSamples);

  test('real .bup saves go onto a card byte for byte', () {
    var internal = 0, cart = 0;
    for (final f in sampleFiles(samples, ['.bup'])) {
      final b = f.readAsBytesSync();
      final name = p.basename(f.path);
      var put = SaturnWriter.importSave(SaturnWriter.blank(), b);
      if (put.ok) {
        internal++;
      } else {
        // Too big for internal memory: the cartridge.
        expect(put.error, startsWith('Not enough room'), reason: name);
        put = SaturnWriter.importSave(SaturnWriter.blank(SaturnWriter.cart), b);
        cart++;
      }
      expect(put.ok, isTrue, reason: '$name: ${put.error}');
      expect(SaturnWriter.check(put.data), '', reason: name);
      expect(SaturnWriter.save(put.data, 2)!.data, b.sublist(64), reason: name);
      final out = SaturnWriter.exportSave(put.data, 2).data;
      // What the card keeps: name (11), comment (10), language, minutes,
      // length. Byte 0x1B and 0x26 are the .bup's own padding.
      for (final (at, n) in const [(0x10, 11), (0x1C, 10), (0x27, 9)]) {
        expect(out.sublist(at, at + n), b.sublist(at, at + n), reason: name);
      }
      expect(out.sublist(64), b.sublist(64), reason: name);
      final s = SaturnCard.parse(put.data, MemoryCard()).saves.single;
      expect(s.id, isNotEmpty, reason: name);
    }
    expect(internal + cart, greaterThan(0));
    // ignore: avoid_print
    print(
      'Saturn: ${internal + cart} real .bup saves ($cart only fit the cartridge)',
    );
  }, skip: noSamples);
}
