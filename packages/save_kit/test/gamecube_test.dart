import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:save_kit/save_kit.dart';
import 'package:test/test.dart';

/// A made-up save: [game] + maker "01", file name "S", every body byte
/// = [blocks].
Uint8List gci(String game, int blocks, {String name = 'S'}) {
  final b = Uint8List(64 + blocks * 8192)
    ..fillRange(64, 64 + blocks * 8192, blocks);
  b.setAll(0, '${game}01'.codeUnits.take(6));
  b.setAll(8, name.codeUnits);
  Bytes.putBe16(b, 0x38, blocks);
  return b;
}

List<int> slice(List<int> b, int from, [int? to]) => b.sublist(from, to);

/// Every card image and .gci under [root], skipping git folders.
List<File> samples(String root, Set<String> exts) {
  final out = <File>[];
  for (final e in Directory(root).listSync(recursive: true)) {
    if (e is! File) continue;
    if (p.split(e.path).contains('.git')) continue;
    if (exts.contains(p.extension(e.path).toLowerCase())) out.add(e);
  }
  out.sort((a, b) => a.path.compareTo(b.path));
  return out;
}

void main() {
  group('GameCube writer, built cards', () {
    final blank = GcWriter.blank(4);
    final one = gci('GTST', 3);
    final a = GcWriter.importSave(blank, one);

    test('a new 59-block card is valid', () {
      expect(GcWriter.check(blank), '');
      expect(GcWriter.freeBlocks(blank), 59);
      expect(GcWriter.saves(blank), isEmpty);
    });

    test('blank refuses a size no card has', () {
      expect(GcWriter.blank(3), isEmpty);
      expect(GcWriter.isCard(Uint8List(5 * GcWriter.mbit)), isFalse);
    });

    test('import', () {
      expect(a.ok, isTrue, reason: a.error);
      expect(GcWriter.check(a.data), '');
    });

    test('three blocks used', () {
      expect(GcWriter.chain(a.data, 0), [5, 6, 7]);
      expect(GcWriter.freeBlocks(a.data), 56);
    });

    test('written into the other copy', () {
      expect(GcWriter.directory(a.data), 2);
      expect(GcWriter.blockTable(a.data), 4);
    });

    test('export gives back the save', () {
      final back = GcWriter.exportSave(a.data, 0).data;
      expect(slice(back, 64), slice(one, 64));
      expect(slice(back, 0, 0x36), slice(one, 0, 0x36));
    });

    test('same name refused', () {
      expect(GcWriter.importSave(a.data, one).ok, isFalse);
    });

    test('too big refused', () {
      expect(GcWriter.importSave(a.data, gci('GBIG', 57)).ok, isFalse);
    });

    test('junk refused', () {
      expect(GcWriter.importSave(a.data, slice(one, 0, 900)).ok, isFalse);
      final wrong = Uint8List.fromList(one);
      Bytes.putBe16(wrong, 0x38, 2);
      expect(GcWriter.importSave(a.data, wrong).ok, isFalse);
    });

    test('a save locked to its card goes back only on its own card', () {
      final tied = gci('GFZE', 1);
      expect(GcWriter.importSave(a.data, tied).ok, isFalse);
      expect(
        GcWriter.importSave(a.data, tied, GcWriter.serial(a.data)).ok,
        isTrue,
      );
    });

    test('delete frees it', () {
      final gone = GcWriter.delete(a.data, 0);
      expect(gone.ok, isTrue);
      expect(GcWriter.check(gone.data), '');
      expect(GcWriter.freeBlocks(gone.data), 59);
      expect(GcWriter.saves(gone.data), isEmpty);
      expect(GcWriter.delete(gone.data, 0).ok, isFalse);
      // Deleting writes the copy that wasn't current again.
      expect(GcWriter.directory(gone.data), 1);
      expect(GcWriter.blockTable(gone.data), 3);
    });

    test('a damaged copy falls back to the older one', () {
      final hurt = Uint8List.fromList(a.data);
      hurt[2 * 8192 + 100] ^= 1;
      expect(GcWriter.directory(hurt), 1);
      expect(GcWriter.saves(hurt), isEmpty);
    });

    test('both copies damaged: nothing is read or written', () {
      final hurt = Uint8List.fromList(a.data);
      hurt[1 * 8192 + 100] ^= 1;
      hurt[2 * 8192 + 100] ^= 1;
      expect(GcWriter.directory(hurt), 0);
      expect(GcWriter.check(hurt), isNot(''));
      expect(GcWriter.importSave(hurt, gci('GNEW', 1)).ok, isFalse);
      expect(GcCard.parse(hurt).error, isNotEmpty);
    });

    test('a broken header sum is not a card', () {
      final hurt = Uint8List.fromList(blank);
      hurt[0x30] ^= 1;
      expect(GcWriter.isCard(hurt), isFalse);
      expect(GcWriter.check(hurt), isNot(''));
    });

    test('two saves sharing a block are caught', () {
      final two = GcWriter.importSave(a.data, gci('GTWO', 1)).data;
      final table = GcWriter.directory(two);
      final hurt = Uint8List.fromList(two);
      Bytes.putBe16(hurt, table * 8192 + 64 + 0x36, 7); // into the first save
      // Reseal so only the sharing is wrong.
      final sums = GcWriter.sum(hurt, table * 8192, GcWriter.dirSumAt);
      Bytes.putBe16(hurt, table * 8192 + GcWriter.dirSumAt, sums.$1);
      Bytes.putBe16(hurt, table * 8192 + GcWriter.dirSumAt + 2, sums.$2);
      expect(GcWriter.check(hurt), isNot(''));
    });

    test('allocation carries on after the last block handed out', () {
      final two = GcWriter.importSave(a.data, gci('GTWO', 2)).data;
      final gone = GcWriter.delete(two, 0).data;
      final three = GcWriter.importSave(gone, gci('GTRI', 2)).data;
      expect(GcWriter.chain(three, 0), [10, 11]);
      expect(GcWriter.check(three), '');
    });

    test('fills up at 127 saves', () {
      var card = GcWriter.blank(16);
      for (var i = 0; i < 127; i++) {
        final put = GcWriter.importSave(
          card,
          gci('G${i.toString().padLeft(3, '0')}', 1),
        );
        expect(put.ok, isTrue, reason: put.error);
        card = put.data;
      }
      expect(GcWriter.importSave(card, gci('GMOR', 1)).error, contains('127'));
      expect(GcWriter.check(card), '');
    });

    test('counters', () {
      // Each change bumps the counter of the copy it writes.
      var card = blank;
      for (var i = 0; i < 5; i++) {
        card = GcWriter.importSave(card, gci('GC$i', 1)).data;
      }
      final dir = GcWriter.directory(card);
      expect(GcWriter.signed16(card, dir * 8192 + GcWriter.dirCountAt), 5);
      final bat = GcWriter.blockTable(card);
      expect(GcWriter.signed16(card, bat * 8192 + GcWriter.batCountAt), 5);
    });

    test('the new card header', () {
      final c = GcWriter.blank(16, true, GcWriter.epoch + 10, math.Random(1));
      expect(Bytes.be16(c, 0x22), 16);
      expect(Bytes.be16(c, 0x24), 1);
      expect(
        Bytes.be32(c, 0x0C) << 32 | Bytes.be32(c, 0x10),
        10 * GcWriter.ticks,
      );
      expect(GcWriter.isCard(c), isTrue);
    });
  });

  group('GameCube reader, built cards', () {
    test('a card and its saves', () {
      final save = gci('GTSE', 2, name: 'progress.dat');
      save[0x07] = 0; // no banner
      save[0x34] = GcCard.noCopy;
      Bytes.putBe32(save, 0x28, 86400 * 365);
      // A comment at 0, an RGB5A3 icon at 64.
      save.setAll(64, 'Test Game'.codeUnits);
      save.fillRange(64 + 9, 64 + 32, 0);
      save.setAll(64 + 32, 'Day 3'.codeUnits);
      save.fillRange(64 + 37, 64 + 64, 0);
      Bytes.putBe32(save, 0x3C, 0);
      Bytes.putBe32(save, 0x2C, 64);
      Bytes.putBe16(save, 0x30, 2); // icon 0: RGB5A3
      Bytes.putBe16(save, 0x32, 1); // one frame
      for (var i = 0; i < 1024; i++) {
        Bytes.putBe16(save, 64 + 64 + i * 2, 0xFC00); // opaque red
      }
      final card = GcWriter.importSave(GcWriter.blank(4), save).data;
      final m = GcCard.parse(card, MemoryCard()..modified = 99);
      expect(m.error, '');
      expect(m.system, 'GC');
      expect(m.total, 59);
      expect(m.free, 57);
      expect(m.saves, hasLength(1));
      final s = m.saves.single;
      expect(s.id, 'GTSE01 progress.dat');
      expect(s.serial, 'GTSE01');
      expect(s.region, 'America');
      expect(s.copyProtected, isTrue);
      expect(s.blocks, 2);
      expect(s.kb, 16);
      expect(s.slot, 0);
      expect(s.titleLines, ['Test Game', 'Day 3']);
      final t = DateTime.fromMillisecondsSinceEpoch(
        (GcCard.epoch + 86400 * 365) * 1000,
        isUtc: true,
      );
      expect(
        s.created,
        DateTime(t.year, t.month, t.day).millisecondsSinceEpoch ~/ 1000,
      );
      expect(s.modified, s.created);
      expect(s.frames, hasLength(1));
      expect(s.frames.single.w, 32);
      expect(s.frames.single.at(0, 0), 0xFFFF0000);
    });

    test('no icon: our own stand-in, and the card date', () {
      final save = gci('GTSP', 1);
      Bytes.putBe32(save, 0x2C, 0xFFFFFFFF);
      final s = GcCard.saveFrom(save, MemoryCard()..modified = 1234);
      expect(s.frames, hasLength(1));
      expect(s.frames.single.w, CardPictures.tile);
      expect(s.created, 0);
      expect(s.modified, 1234);
      expect(s.region, 'Europe');
    });

    test('a shared palette after all the CI8 frames', () {
      final save = gci('GPAL', 1);
      Bytes.putBe32(save, 0x2C, 0);
      Bytes.putBe16(save, 0x30, 1 | 1 << 2); // two CI8 frames, shared palette
      Bytes.putBe16(save, 0x32, 1 | 1 << 2);
      save.fillRange(64, 64 + 2048, 3); // palette entry 3
      Bytes.putBe16(save, 64 + 2048 + 3 * 2, 0x801F); // opaque blue
      final s = GcCard.saveFrom(save);
      expect(s.frames, hasLength(2));
      expect(s.frames[1].at(31, 31), 0xFF0000FF);
    });

    test('a short or junk .gci never throws', () {
      expect(GcCard.saveFrom(Uint8List(10)).frames, hasLength(1));
      expect(GcCard.saveFrom(Uint8List(0)).id, ' ');
      expect(GcCard.parse(Uint8List(100)).error, isNotEmpty);
    });

    test('a folder of .gci, with repeated names', () {
      final dir = Directory.systemTemp.createTempSync('gc_folder');
      addTearDown(() => dir.deleteSync(recursive: true));
      File(p.join(dir.path, 'a.gci')).writeAsBytesSync(gci('GAAE', 2));
      File(p.join(dir.path, 'b.GCI')).writeAsBytesSync(gci('GAAE', 1));
      File(p.join(dir.path, 'c.gci')).writeAsBytesSync(gci('GCCE', 3));
      File(p.join(dir.path, 'tiny.gci')).writeAsBytesSync([1, 2, 3]);
      File(p.join(dir.path, 'notes.txt')).writeAsStringSync('hi');
      final m = GcCard.parseFolder(dir.path);
      expect(m.isFolder, isTrue);
      expect(m.total, GcCard.folderBlocks);
      expect(m.free, GcCard.folderBlocks - 6);
      expect(m.saves.map((s) => s.id), [
        'GAAE01 S [a.gci]',
        'GAAE01 S [b.GCI]',
        'GCCE01 S',
      ]);
      expect(m.saves.map((s) => s.file), ['a.gci', 'b.GCI', 'c.gci']);
    });

    test('a missing folder reads as empty', () {
      final m = GcCard.parseFolder(
        p.join(Directory.systemTemp.path, 'no_such_gc_dir_x'),
      );
      expect(m.saves, isEmpty);
      expect(m.free, GcCard.folderBlocks);
    });
  });

  final root = Platform.environment['SAVE_SAMPLES'] ?? '';
  final skip = root.isEmpty || !Directory(root).existsSync()
      ? 'set SAVE_SAMPLES to the real samples folder'
      : null;

  group('GameCube, real cards', () {
    test('every card reads, checks and round-trips', () {
      final cards = samples(root, {'.raw', '.gcp', '.mci'});
      expect(cards, isNotEmpty);
      var copies = 0, matched = 0, icons = 0;
      for (final f in cards) {
        final name = p.relative(f.path, from: root);
        final d = f.readAsBytesSync();
        final before = Uint8List.fromList(d);
        expect(GcWriter.check(d), '', reason: name);
        final m = GcCard.parse(d, MemoryCard()..name = name);
        expect(m.error, '', reason: name);
        expect(m.saves.length, GcWriter.saves(d).length, reason: name);
        expect(m.free, GcWriter.freeBlocks(d), reason: name);
        for (final s in m.saves) {
          expect(s.frames, isNotEmpty, reason: '$name ${s.id}');
          if (s.frames.first.w == 32) icons++;
        }
        var empty = d;
        final kept = <Uint8List>[];
        for (final slot in GcWriter.saves(d)) {
          final out = GcWriter.exportSave(d, slot);
          expect(out.ok, isTrue, reason: '$name slot $slot');
          kept.add(out.data);
          final gone = GcWriter.delete(empty, slot);
          expect(gone.ok, isTrue, reason: '$name slot $slot');
          expect(GcWriter.check(gone.data), '', reason: '$name slot $slot');
          empty = gone.data;
        }
        expect(GcWriter.saves(empty), isEmpty, reason: name);
        expect(GcWriter.freeBlocks(empty), d.length ~/ 8192 - 5, reason: name);
        final fresh = GcWriter.blank(d.length ~/ GcWriter.mbit);
        if (Bytes.same(slice(fresh, 0x26, 0x1FC), slice(d, 0x26, 0x1FC)) &&
            Bytes.same(slice(fresh, 0x200, 0x2000), slice(d, 0x200, 0x2000))) {
          matched++;
        }
        for (final target in [empty, fresh]) {
          var card = target;
          for (final save in kept) {
            final put = GcWriter.importSave(card, save, GcWriter.serial(card));
            expect(put.ok, isTrue, reason: '$name copies back (${put.error})');
            if (!put.ok) continue;
            card = put.data;
            copies++;
          }
          expect(GcWriter.check(card), '', reason: '$name rebuilt');
          final slots = GcWriter.saves(card);
          expect(slots.length, kept.length, reason: name);
          for (var i = 0; i < math.min(slots.length, kept.length); i++) {
            final back = GcWriter.exportSave(card, slots[i]).data;
            expect(
              slice(back, 64),
              slice(kept[i], 64),
              reason: '$name byte for byte',
            );
            expect(slice(back, 0, 0x36), slice(kept[i], 0, 0x36), reason: name);
          }
        }
        expect(Bytes.same(d, before), isTrue, reason: '$name left untouched');
      }
      expect(
        matched,
        greaterThan(0),
        reason: "a new card's header fill matches a real one",
      );
      expect(icons, greaterThan(0));
      printOnFailure('${cards.length} cards, $copies copies');
      print(
        '  GameCube: ${cards.length} real cards, $copies save copies, '
        '$matched with a header like ours, $icons icons',
      );
    });

    test('every .gci goes on a card and comes back byte for byte', () {
      final files = samples(root, {'.gci'});
      expect(files, isNotEmpty);
      for (final f in files) {
        final b = f.readAsBytesSync();
        final put = GcWriter.importSave(GcWriter.blank(), b);
        expect(put.ok, isTrue, reason: '${f.path} (${put.error})');
        expect(slice(GcWriter.exportSave(put.data, 0).data, 64), slice(b, 64));
        final s = GcCard.saveFrom(b);
        expect(s.frames, isNotEmpty);
        expect(s.blocks, (b.length - 64) ~/ 8192);
      }
      print('  GameCube: ${files.length} real .gci');
    });

    test('a folder of real .gci reads as one card', () {
      final dirs = {
        for (final f in samples(root, {'.gci'})) p.dirname(f.path),
      };
      for (final dir in dirs) {
        final m = GcCard.parseFolder(dir);
        expect(m.saves, isNotEmpty, reason: dir);
        expect(m.saves.map((s) => s.id).toSet(), hasLength(m.saves.length));
      }
    });
  }, skip: skip);
}
