import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:save_kit/save_kit.dart';
import 'package:test/test.dart';

/// A made-up .dci: every body byte = [blocks].
Uint8List dci(String name, int blocks, int type) {
  final b = Uint8List(32 + blocks * 512)
    ..fillRange(32, 32 + blocks * 512, blocks);
  b[0] = type;
  b.setAll(4, name.padRight(12).codeUnits);
  Bytes.put16(b, 0x18, blocks);
  return b;
}

List<int> slice(List<int> b, int from, [int? to]) => b.sublist(from, to);

List<File> samples(String root, bool Function(String ext) want) {
  final out = <File>[];
  for (final e in Directory(root).listSync(recursive: true)) {
    if (e is! File) continue;
    if (p.split(e.path).contains('.git')) continue;
    if (want(p.extension(e.path).toLowerCase())) out.add(e);
  }
  out.sort((a, b) => a.path.compareTo(b.path));
  return out;
}

void main() {
  group('VMU writer, built cards', () {
    final blank = VmuWriter.blank();
    final one = dci('SAVE_ONE', 3, VmuWriter.data);
    final a = VmuWriter.importSave(blank, one);

    test('a new VMU is valid and empty', () {
      expect(VmuWriter.check(blank), '');
      expect(VmuWriter.freeBlocks(blank), 200);
      expect(VmuWriter.saves(blank), isEmpty);
    });

    test('import', () {
      expect(a.ok, isTrue, reason: a.error);
      expect(VmuWriter.check(a.data), '');
    });

    test('data fills from the top down', () {
      expect(VmuWriter.chain(a.data, 0), [199, 198, 197]);
      expect(VmuWriter.freeBlocks(a.data), 197);
    });

    test('export gives back the same save', () {
      final back = VmuWriter.exportSave(a.data, 0).data;
      expect(slice(back, 4), slice(one, 4));
    });

    test('same name refused', () {
      expect(VmuWriter.importSave(a.data, one).ok, isFalse);
    });

    test('too big refused', () {
      expect(
        VmuWriter.importSave(a.data, dci('BIG', 198, VmuWriter.data)).ok,
        isFalse,
      );
    });

    test('junk refused', () {
      expect(VmuWriter.importSave(a.data, slice(one, 0, 100)).ok, isFalse);
      final wrong = Uint8List.fromList(dci('WRONG', 2, VmuWriter.data));
      Bytes.put16(wrong, 0x18, 3);
      expect(VmuWriter.importSave(a.data, wrong).ok, isFalse);
      final kind = dci('KIND', 1, 0x12);
      expect(VmuWriter.importSave(a.data, kind).ok, isFalse);
    });

    test('a game starts at block 0, and there is room for one', () {
      final game = VmuWriter.importSave(a.data, dci('GAME', 4, VmuWriter.game));
      expect(game.ok, isTrue, reason: game.error);
      expect(VmuWriter.chain(game.data, 1), [0, 1, 2, 3]);
      expect(
        VmuWriter.importSave(game.data, dci('GAME2', 2, VmuWriter.game)).ok,
        isFalse,
      );
    });

    test('delete frees it, and it is gone', () {
      final gone = VmuWriter.delete(a.data, 0);
      expect(gone.ok, isTrue);
      expect(VmuWriter.check(gone.data), '');
      expect(VmuWriter.freeBlocks(gone.data), 200);
      expect(VmuWriter.saves(gone.data), isEmpty);
      expect(VmuWriter.delete(gone.data, 0).ok, isFalse);
    });

    test('a broken chain or shared block is caught', () {
      final two = VmuWriter.importSave(
        a.data,
        dci('TWO', 1, VmuWriter.data),
      ).data;
      final shared = Uint8List.fromList(two);
      Bytes.put16(shared, VmuWriter.entryAt(1) + 2, 197);
      expect(VmuWriter.check(shared), contains('share'));
      final cut = Uint8List.fromList(a.data);
      Bytes.put16(cut, VmuWriter.fat * 512 + 198 * 2, VmuWriter.free);
      expect(VmuWriter.chain(cut, 0), isEmpty);
      expect(VmuWriter.check(cut), contains('broken'));
      final loop = Uint8List.fromList(a.data);
      Bytes.put16(loop, VmuWriter.fat * 512 + 197 * 2, 199);
      expect(VmuWriter.chain(loop, 0), isEmpty);
    });

    test('an unusual layout and an unformatted card are caught', () {
      final odd = Uint8List.fromList(blank);
      odd[255 * 512 + 0x50] = 100;
      expect(VmuWriter.check(odd), 'an unusual layout');
      expect(VmuWriter.isCard(Uint8List(VmuWriter.size)), isFalse);
      expect(VmuWriter.isCard(Uint8List(100)), isFalse);
      expect(VmuWriter.importSave(Uint8List(100), one).ok, isFalse);
    });

    test('the directory has 208 slots, then it is full', () {
      var card = blank;
      for (var i = 0; i < VmuWriter.slots; i++) {
        final put = VmuWriter.importSave(
          card,
          dci('N$i', 0 + 1, VmuWriter.data),
        );
        if (i < 200) {
          expect(put.ok, isTrue, reason: put.error);
          card = put.data;
        } else {
          expect(put.ok, isFalse); // out of blocks first
        }
      }
      expect(VmuWriter.freeBlocks(card), 0);
      expect(VmuWriter.check(card), '');
    });

    test('directory slots sit in blocks 253 down to 241', () {
      expect(VmuWriter.entryAt(0), 253 * 512);
      expect(VmuWriter.entryAt(15), 253 * 512 + 15 * 32);
      expect(VmuWriter.entryAt(16), 252 * 512);
      expect(VmuWriter.entryAt(207), 241 * 512 + 15 * 32);
    });

    test('the new card is dated with BCD, Monday = 0', () {
      // 2024-01-01 12:34:56 UTC was a Monday.
      final when =
          DateTime.utc(2024, 1, 1, 12, 34, 56).millisecondsSinceEpoch ~/ 1000;
      final c = VmuWriter.blank(when);
      expect(slice(c, 255 * 512 + 0x30, 255 * 512 + 0x38), [
        0x20,
        0x24,
        0x01,
        0x01,
        0x12,
        0x34,
        0x56,
        0,
      ]);
    });

    test('turned turns every four bytes and keeps a short tail', () {
      expect(VmuWriter.turned([1, 2, 3, 4, 5, 6, 7, 8, 9]), [
        4,
        3,
        2,
        1,
        8,
        7,
        6,
        5,
        9,
      ]);
    });
  });

  group('VMU reader, built cards', () {
    Uint8List titled() {
      final b = dci('MYSAVE', 2, VmuWriter.data);
      b[1] = 0xFF; // copy-protected
      b.setAll(0x10, [0x20, 0x01, 0x12, 0x25, 0x23, 0x59, 0x07, 1]);
      Bytes.put16(b, 0x1A, 0); // header in the first block
      // The body is stored turned round, so build it plain and turn it.
      final body = Uint8List(1024);
      body.setAll(0, 'Short'.codeUnits);
      body.setAll(0x10, 'A longer description'.codeUnits);
      Bytes.put16(body, 0x40, 1); // one icon
      Bytes.put16(body, 0x60 + 5 * 2, 0xF0F0); // colour 5: opaque green
      body.fillRange(0x80, 0x80 + 512, 0x55);
      b.setAll(32, VmuWriter.turned(body));
      return b;
    }

    test('a save: names, date, lock, icon', () {
      final card = VmuWriter.importSave(VmuWriter.blank(), titled()).data;
      final m = VmuCard.parse(card, MemoryCard()..modified = 7);
      expect(m.error, '');
      expect(m.system, 'DC');
      expect(m.total, 200);
      expect(m.free, 198);
      final s = m.saves.single;
      expect(s.id, 'MYSAVE');
      expect(s.slot, 0);
      expect(s.copyProtected, isTrue);
      expect(s.blocks, 2);
      expect(s.kb, 1);
      expect(s.held, [199, 198]);
      expect(s.titleLines, ['A longer description', 'Short']);
      expect(
        s.created,
        DateTime(2001, 12, 25, 23, 59, 7).millisecondsSinceEpoch ~/ 1000,
      );
      expect(s.modified, s.created);
      expect(s.frames, hasLength(1));
      expect(s.frames.single.w, 32);
      expect(s.frames.single.at(3, 3), 0xFF00FF00);
    });

    test('a bad BCD date reads as none; the card date stands in', () {
      final b = titled();
      b[0x12] = 0x1A;
      final card = VmuWriter.importSave(VmuWriter.blank(), b).data;
      final s = VmuCard.parse(card, MemoryCard()..modified = 7).saves.single;
      expect(s.created, 0);
      expect(s.modified, 7);
    });

    test("the VMU's own picture", () {
      final card = VmuWriter.importSave(
        VmuWriter.blank(),
        dci(VmuCard.iconData, 1, VmuWriter.data),
      ).data;
      final s = VmuCard.parse(card).saves.single;
      expect(s.titleLines, ["The VMU's own picture"]);
      expect(s.frames.single.w, CardPictures.tile);
    });

    test('a broken save still lists, with a stand-in', () {
      final card = Uint8List.fromList(
        VmuWriter.importSave(VmuWriter.blank(), titled()).data,
      );
      Bytes.put16(card, VmuWriter.fat * 512 + 198 * 2, VmuWriter.free);
      final s = VmuCard.parse(card).saves.single;
      expect(s.held, isEmpty);
      expect(s.blocks, 2);
      expect(s.frames.single.w, CardPictures.tile);
    });

    test('not a VMU', () {
      expect(VmuCard.parse(Uint8List(10)).error, isNotEmpty);
    });

    test('a VMI + VMS pair', () {
      final vms = Uint8List(1024)..fillRange(0, 1024, 9);
      final vmi = Uint8List(108);
      Bytes.put16(vmi, 0x44, 2003);
      vmi.setAll(0x46, [4, 5, 6, 7, 8, 9]);
      vmi.setAll(0x58, 'PAIRED_SAVE1'.codeUnits);
      Bytes.put16(vmi, 0x64, VmuWriter.vmiProtect);
      Bytes.put32(vmi, 0x68, vms.length);
      final pair = VmuWriter.fromVmi(vmi, vms);
      expect(pair.ok, isTrue, reason: pair.error);
      expect(pair.data[0], VmuWriter.data);
      expect(pair.data[1], 0xFF);
      expect(slice(pair.data, 0x10, 0x18), [
        0x20,
        0x03,
        0x04,
        0x05,
        0x06,
        0x07,
        0x08,
        2,
      ]);
      final put = VmuWriter.importSave(VmuWriter.blank(), pair.data);
      expect(put.ok, isTrue);
      expect(VmuWriter.check(put.data), '');
      expect(
        VmuWriter.turned(slice(VmuWriter.exportSave(put.data, 0).data, 32)),
        vms,
      );
      final s = VmuCard.parse(put.data).saves.single;
      expect(s.id, 'PAIRED_SAVE1');
      expect(
        s.created,
        DateTime(2003, 4, 5, 6, 7, 8).millisecondsSinceEpoch ~/ 1000,
      );

      Bytes.put16(vmi, 0x64, VmuWriter.vmiGame);
      final game = VmuWriter.fromVmi(vmi, vms).data;
      expect(game[0], VmuWriter.game);
      expect(Bytes.u16(game, 0x1A), 1);

      Bytes.put32(vmi, 0x68, 512);
      expect(VmuWriter.fromVmi(vmi, vms).ok, isFalse);
      expect(VmuWriter.fromVmi(slice(vmi, 0, 100), vms).ok, isFalse);
      expect(VmuWriter.fromVmi(vmi, Uint8List(0)).ok, isFalse);
      expect(VmuWriter.fromVmi(vmi, Uint8List(700)).ok, isFalse);
    });
  });

  final root = Platform.environment['SAVE_SAMPLES'] ?? '';
  final skip = root.isEmpty || !Directory(root).existsSync()
      ? 'set SAVE_SAMPLES to the real samples folder'
      : null;

  group('Dreamcast, real cards', () {
    test('every card reads, checks and round-trips', () {
      final cards = [
        for (final f in samples(root, (e) => e == '.vmu' || e == '.bin'))
          if (f.lengthSync() == VmuWriter.size) f,
      ];
      expect(cards, isNotEmpty);
      var copies = 0, saves = 0, icons = 0;
      for (final f in cards) {
        final name = p.relative(f.path, from: root);
        final d = f.readAsBytesSync();
        final before = Uint8List.fromList(d);
        expect(VmuWriter.check(d), '', reason: name);
        final m = VmuCard.parse(d);
        expect(m.error, '', reason: name);
        expect(m.saves.length, VmuWriter.saves(d).length, reason: name);
        for (final s in m.saves) {
          saves++;
          expect(s.frames, isNotEmpty, reason: '$name ${s.id}');
          expect(s.held, isNotEmpty, reason: '$name ${s.id}');
          if (s.frames.first.w == 32) icons++;
        }
        final kept = <Uint8List>[];
        var empty = d;
        for (final slot in VmuWriter.saves(d)) {
          final out = VmuWriter.exportSave(d, slot);
          expect(out.ok, isTrue, reason: '$name slot $slot');
          kept.add(out.data);
          final gone = VmuWriter.delete(empty, slot);
          expect(gone.ok, isTrue, reason: '$name: save $slot deletes');
          expect(
            VmuWriter.check(gone.data),
            '',
            reason: '$name: save $slot deletes',
          );
          empty = gone.data;
        }
        expect(VmuWriter.freeBlocks(empty), 200, reason: '$name empties fully');
        for (final target in [empty, VmuWriter.blank()]) {
          var card = target;
          for (final save in kept) {
            final put = VmuWriter.importSave(card, save);
            expect(put.ok, isTrue, reason: '$name: copies back (${put.error})');
            if (!put.ok) continue;
            card = put.data;
            copies++;
          }
          expect(VmuWriter.check(card), '', reason: '$name rebuilt');
          final slots = VmuWriter.saves(card);
          expect(slots.length, kept.length, reason: '$name rebuilt');
          for (var i = 0; i < math.min(slots.length, kept.length); i++) {
            expect(
              slice(VmuWriter.exportSave(card, slots[i]).data, 4),
              slice(kept[i], 4),
              reason: '$name: byte for byte',
            );
          }
        }
        expect(Bytes.same(d, before), isTrue, reason: '$name left untouched');
      }
      expect(icons, greaterThan(0));
      print(
        '  Dreamcast: ${cards.length} real cards, $saves saves, '
        '$copies save copies, $icons icons',
      );
    });

    test('every VMI + VMS pair goes on a card byte for byte', () {
      final vmis = samples(root, (e) => e == '.vmi');
      var pairs = 0;
      for (final f in vmis) {
        final base = p.withoutExtension(f.path);
        final vms = [
          for (final ext in ['.VMS', '.vms', '.Vms'])
            if (File(base + ext).existsSync()) File(base + ext),
        ];
        if (vms.isEmpty) continue;
        final vmsBytes = vms.first.readAsBytesSync();
        final save = VmuWriter.fromVmi(f.readAsBytesSync(), vmsBytes);
        expect(save.ok, isTrue, reason: '${f.path} (${save.error})');
        if (!save.ok) continue;
        pairs++;
        final put = VmuWriter.importSave(VmuWriter.blank(), save.data);
        expect(put.ok, isTrue, reason: '${f.path} (${put.error})');
        expect(VmuWriter.check(put.data), '', reason: f.path);
        expect(
          VmuWriter.turned(slice(VmuWriter.exportSave(put.data, 0).data, 32)),
          vmsBytes,
          reason: f.path,
        );
        final s = VmuCard.parse(put.data).saves.single;
        expect(s.frames, isNotEmpty);
      }
      expect(pairs, greaterThan(0));
      print('  Dreamcast: $pairs real VMI + VMS pairs');
    });
  }, skip: skip);
}
