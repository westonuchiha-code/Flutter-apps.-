import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:save_kit/save_kit.dart';
import 'package:test/test.dart';

/// A made-up .note: game "ABCD", publisher "EF", name "A", 3 pages of 9.
Uint8List noteFile([int pages = 3, int game = 0x41]) {
  final note = Uint8List(32 + pages * 256)..fillRange(32, 32 + pages * 256, 9);
  for (var i = 0; i < 6; i++) {
    note[i] = game + i;
  }
  Bytes.putBe16(note, 6, PakWriter.noStart);
  note[8] = 2;
  note[16] = 0x1A;
  return note;
}

/// Every pak in the samples folder: (file name, its bytes).
List<(String, Uint8List)> samplePaks(String root) {
  final out = <(String, Uint8List)>[];
  for (final f in Directory(root).listSync(recursive: true)) {
    if (f is! File) continue;
    final ext = p.extension(f.path).toLowerCase();
    if (!const ['.mpk', '.cpk', '.pak', '.srm'].contains(ext)) continue;
    final len = f.lengthSync();
    if (len != PakWriter.combined &&
        (len % PakWriter.size != 0 || len > 4 * PakWriter.size)) {
      continue;
    }
    final file = f.readAsBytesSync();
    for (final at in PakWriter.paksIn(file)) {
      out.add((
        '${p.basename(f.path)}#$at',
        Uint8List.fromList(file.sublist(at, at + PakWriter.size)),
      ));
    }
  }
  return out;
}

void main() {
  test('a new pak is valid and empty', () {
    final blank = PakWriter.blank(math.Random(7));
    expect(PakWriter.check(blank), '');
    expect(PakWriter.freeList(blank).length, 123);
    expect(PakWriter.saves(blank), isEmpty);
    expect(PakWriter.idFine(blank), isTrue);
    expect(PakWriter.indexPage(blank), 1);
    final card = PakCard.parse(blank, MemoryCard()..modified = 5);
    expect(card.error, '');
    expect(card.total, 123);
    expect(card.free, 123);
    expect(
      PakWriter.blank(math.Random(8)).sublist(0x20, 0x38),
      isNot(blank.sublist(0x20, 0x38)),
    );
  });

  test('pak import, export, same name, backup index, delete', () {
    final blank = PakWriter.blank();
    final note = noteFile();
    final a = PakWriter.importSave(blank, note);
    expect(a.ok, isTrue, reason: a.error);
    expect(PakWriter.check(a.data), '');
    expect(PakWriter.saves(a.data), [0]);
    expect(PakWriter.chain(a.data, 0), [5, 6, 7]);
    expect(PakWriter.freeList(a.data).length, 120);
    expect(PakWriter.exportSave(a.data, 0).data, note);
    expect(PakWriter.noteNamed(a.data, note), 0);
    expect(PakWriter.importSave(a.data, note).ok, isFalse);

    final hurt = Uint8List.fromList(a.data);
    hurt[256 + 40] ^= 1;
    expect(PakWriter.indexPage(hurt), 2);
    expect(PakWriter.check(hurt), '');
    final gone = PakWriter.delete(hurt, 0);
    expect(gone.ok, isTrue);
    expect(PakWriter.freeList(gone.data).length, 123);
    expect(PakWriter.indexPage(gone.data), 1);
    expect(PakWriter.check(gone.data), '');
    expect(PakWriter.delete(gone.data, 0).ok, isFalse);
    expect(PakWriter.exportSave(gone.data, 0).ok, isFalse);
  });

  test('pak refusals', () {
    var card = PakWriter.blank();
    expect(PakWriter.importSave(card, Uint8List(32 + 256)).ok, isFalse);
    expect(PakWriter.importSave(card, Uint8List(32 + 100)).ok, isFalse);
    expect(PakWriter.importSave(card, noteFile(124)).ok, isFalse);
    expect(PakWriter.importSave(Uint8List(100), noteFile()).ok, isFalse);
    final bothBad = Uint8List.fromList(card);
    bothBad[256 + 40] ^= 1;
    bothBad[512 + 40] ^= 1;
    expect(PakWriter.indexPage(bothBad), 0);
    expect(PakWriter.check(bothBad), 'both copies of its index are damaged');
    expect(PakCard.parse(bothBad, MemoryCard()).error, isNotEmpty);
    final noId = Uint8List.fromList(card);
    for (final at in PakWriter.idAt) {
      noId[at + 0x1C] ^= 1;
    }
    expect(PakWriter.check(noId), 'its ID is damaged');

    for (var i = 0; i < 16; i++) {
      final put = PakWriter.importSave(card, noteFile(1, 0x10 + i * 6));
      expect(put.ok, isTrue, reason: put.error);
      card = put.data;
    }
    expect(PakWriter.check(card), '');
    expect(PakWriter.importSave(card, noteFile(1, 0xB0)).error, contains('16'));
    final big = PakWriter.blank();
    final huge = PakWriter.importSave(big, noteFile(123));
    expect(huge.ok, isTrue);
    expect(PakWriter.freeList(huge.data), isEmpty);
    expect(PakWriter.importSave(huge.data, noteFile(1, 0x60)).ok, isFalse);
  });

  test('pak reader: names, regions, kana', () {
    final note = noteFile();
    // "MARIO.A" with a space and a kana: M A R I O, ext "A".
    note.setAll(0x10, [0x26, 0x1A, 0x2B, 0x22, 0x28, 0x0F, 0x42 + 19, 0]);
    note[0x0C] = 0x1A;
    final card = PakCard.parse(
      PakWriter.importSave(PakWriter.blank(), note).data,
      MemoryCard()..modified = 99,
    );
    final s = card.saves.single;
    expect(s.titleLines.single, 'MARIO カ.A');
    expect(s.id, 'ABCDEF MARIO カ.A');
    expect(s.serial, 'ABCD');
    expect(s.region, 'Germany');
    expect(s.blocks, 3);
    expect(s.kb, 1);
    expect(s.held, [5, 6, 7]);
    expect(s.modified, 99);
    expect(s.frames, hasLength(1));
    expect(card.free, 120);
    expect(
      PakCard.n64Text([0x10, 0x19, 0x3C, 0x34, 0x41, 0x42, 0xFF], 0, 7),
      '09.!@。_',
    );
    expect(PakCard.n64Text([0x0F, 0x1A, 0x0F], 0, 3), 'A');
  });

  test('four paks in one mupen64plus .srm', () {
    final combined = Uint8List(PakWriter.combined);
    for (var i = 0; i < 4; i++) {
      combined.setAll(PakWriter.paksAt + i * PakWriter.size, PakWriter.blank());
    }
    expect(PakWriter.paksIn(combined), [
      for (var i = 0; i < 4; i++) PakWriter.paksAt + i * PakWriter.size,
    ]);
    expect(PakWriter.paksIn(Uint8List(PakWriter.size)), isEmpty);
    final two = Uint8List(2 * PakWriter.size)
      ..setAll(PakWriter.size, PakWriter.blank());
    expect(PakWriter.paksIn(two), [PakWriter.size]);
  });

  final samples = Platform.environment['SAVE_SAMPLES'] ?? '';
  test('real paks: read, check, empty, copy note for note', () {
    final paks = samplePaks(samples);
    expect(paks, isNotEmpty);
    var notes = 0;
    for (final (name, d) in paks) {
      final before = Uint8List.fromList(d);
      expect(PakWriter.check(d), '', reason: name);
      final card = PakCard.parse(d, MemoryCard());
      expect(card.error, '', reason: name);
      expect(card.saves.length, PakWriter.saves(d).length, reason: name);
      for (final s in card.saves) {
        expect(s.blocks, greaterThan(0), reason: '$name ${s.id}');
      }
      final kept = <Uint8List>[];
      var empty = d;
      for (final n in PakWriter.saves(d)) {
        kept.add(PakWriter.exportSave(d, n).data);
        empty = PakWriter.delete(empty, n).data;
      }
      expect(PakWriter.freeList(empty).length, 123, reason: '$name empties');
      expect(PakWriter.check(empty), '', reason: name);
      var fresh = PakWriter.blank();
      for (final note in kept) {
        final put = PakWriter.importSave(fresh, note);
        expect(put.ok, isTrue, reason: '$name: ${put.error}');
        fresh = put.data;
        notes++;
      }
      expect(PakWriter.check(fresh), '', reason: name);
      for (var i = 0; i < kept.length; i++) {
        expect(PakWriter.exportSave(fresh, i).data, kept[i], reason: name);
      }
      // Back onto the emptied pak too.
      var back = empty;
      for (final note in kept) {
        back = PakWriter.importSave(back, note).data;
      }
      expect(PakWriter.check(back), '', reason: name);
      expect(PakWriter.saves(back).length, kept.length, reason: name);
      expect(d, before, reason: 'never changed in place');
    }
    // ignore: avoid_print
    print('N64: ${paks.length} real paks, $notes notes');
  }, skip: samples.isEmpty ? 'SAVE_SAMPLES not set' : false);
}
