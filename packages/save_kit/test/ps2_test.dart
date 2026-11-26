// PS2 cards: the reader and writer on cards built here (ported from the
// PC's MemoryCardTests.gd and Ps2WriteTests.gd), and every real card under
// $SAVE_SAMPLES (only ever read: every change happens on copies in memory).
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:save_kit/src/bytes.dart';
import 'package:save_kit/src/formats/ps2.dart';
import 'package:save_kit/src/formats/ps2_icon.dart';
import 'package:save_kit/src/model.dart';
import 'package:test/test.dart';

void _put(Uint8List b, int at, String s) => b.setAll(at, s.codeUnits);

void _putS16(Uint8List b, int at, int v) =>
    ByteData.sublistView(b).setInt16(at, v, Endian.little);

void _putF32(Uint8List b, int at, double v) =>
    ByteData.sublistView(b).setFloat32(at, v, Endian.little);

Uint8List _cat(List<Uint8List> parts) {
  final out = BytesBuilder();
  parts.forEach(out.add);
  return out.takeBytes();
}

/// Two shapes, one triangle, two tracks, a packed texture that is all red.
Uint8List iconFile() {
  final b = Uint8List(20 + 3 * 32);
  Bytes.put32(b, 0, 0x10000);
  Bytes.put32(b, 4, 2);
  Bytes.put32(b, 8, 14);
  Bytes.put32(b, 16, 3);
  for (var i = 0; i < 3; i++) {
    final at = 20 + i * 32;
    _putS16(b, at, i * 4096);
    _putS16(b, at + 2, -i * i * 4096);
    _putS16(b, at + 8, i * 8192);
    _putS16(b, at + 10, -i * 4096);
    _putS16(b, at + 20, -4096);
    _putS16(b, at + 24, 2048);
    for (var k = 0; k < 3; k++) {
      b[at + 28 + k] = 128;
    }
  }
  final anim = Uint8List(20 + 2 * 24 + 4 + 4);
  Bytes.put32(anim, 0, 1);
  Bytes.put32(anim, 4, 60);
  _putF32(anim, 8, 1);
  Bytes.put32(anim, 16, 2);
  const tracks = [
    [0, 1.0, 0.0],
    [1, 0.0, 1.0],
  ];
  for (var i = 0; i < 2; i++) {
    final at = 20 + i * 24;
    Bytes.put32(anim, at, tracks[i][0] as int);
    Bytes.put32(anim, at + 4, 2);
    _putF32(anim, at + 8, 0);
    _putF32(anim, at + 12, tracks[i][1] as double);
    _putF32(anim, at + 16, 60);
    _putF32(anim, at + 20, tracks[i][2] as double);
  }
  Bytes.put32(anim, 68, 4);
  Bytes.put16(anim, 72, 16384);
  Bytes.put16(anim, 74, 31);
  return _cat([b, anim]);
}

Uint8List iconSys() {
  final b = Uint8List(964);
  _put(b, 0, 'PS2D');
  Bytes.put16(b, 6, 6);
  Bytes.put32(b, 0xC, 96);
  Bytes.put32(b, 0x10, 128);
  _putF32(b, 0x58, 1);
  _putF32(b, 0x80, 0.5);
  _putF32(b, 0xB0, 0.25);
  _put(b, 0xC0, 'HELLO WORLD');
  for (final at in Ps2Card.iconNameAt) {
    _put(b, at, 'a.ico');
  }
  return b;
}

Uint8List _entry(int mode, int size, int first, String name, int day) {
  final e = Uint8List(512);
  Bytes.put16(e, 0, mode);
  Bytes.put32(e, 4, size);
  Bytes.put32(e, 0x10, first);
  for (final at in const [8, 0x18]) {
    e[at + 4] = day;
    e[at + 5] = 11;
    Bytes.put16(e, at + 6, 2026);
  }
  _put(e, 0x40, name);
  return e;
}

/// A 64-cluster card with one protected save and one deleted entry.
/// [ecc] = bytes after each page.
Uint8List ps2Card(int ecc) {
  final plain = Uint8List(64 * 1024);
  _put(plain, 0, Ps2Card.magic);
  Bytes.put16(plain, 0x28, 512);
  Bytes.put16(plain, 0x2A, 2);
  Bytes.put32(plain, 0x30, 64);
  Bytes.put32(plain, 0x34, 8);
  Bytes.put32(plain, 0x38, 40);
  Bytes.put32(plain, 0x50, 1);
  Bytes.put32(plain, 1024, 2); // indirect FAT -> cluster 2
  const chains = {0: 1, 1: -1, 2: 3, 3: -1, 4: -1, 5: -1};
  chains.forEach((c, to) {
    Bytes.put32(plain, 2048 + c * 4, to < 0 ? 0xFFFFFFFF : 0x80000000 | to);
  });
  final ico = iconFile();
  final root = _cat([
    _entry(0x8427, 4, 0, '.', 1),
    _entry(0x8426, 0, 0, '..', 1),
    _entry(0x842F, 4, 2, 'BASLUS-21120-00', 5),
    _entry(0x0427, 2, 9, 'BASLUS-99999GONE', 2),
  ]);
  final folder = _cat([
    _entry(0x8427, 0, 0, '.', 1),
    _entry(0x8427, 0, 0, '..', 1),
    _entry(0x8497, 964, 4, 'icon.sys', 5),
    _entry(0x8497, ico.length, 5, 'a.ico', 7),
  ]);
  plain.setAll(8 * 1024, root);
  plain.setAll(10 * 1024, folder);
  plain.setAll(12 * 1024, iconSys());
  plain.setAll(13 * 1024, ico);
  if (ecc == 0) return plain;
  final out = BytesBuilder();
  for (var pg = 0; pg < 128; pg++) {
    out.add(plain.sublist(pg * 512, pg * 512 + 512));
    out.add(Uint8List(ecc));
  }
  return out.takeBytes();
}

const _when = 1795355442;

/// A .psu holding files of [sizes], each filled with a counting pattern.
Uint8List psu(String saveName, List<int> sizes) {
  final b = BytesBuilder()
    ..add(Ps2Writer.newEntry(0x8427, sizes.length + 2, saveName, _when))
    ..add(Ps2Writer.newEntry(0x8427, 0, '.', _when))
    ..add(Ps2Writer.newEntry(0x8427, 0, '..', _when));
  for (var i = 0; i < sizes.length; i++) {
    final size = sizes[i];
    b.add(Ps2Writer.newEntry(0x8497, size, 'file$i', _when));
    final data = Uint8List((size / 1024).ceil() * 1024);
    for (var k = 0; k < size; k++) {
      data[k] = (k + i) & 0xFF;
    }
    b.add(data);
  }
  return b.takeBytes();
}

/// The files inside a .psu: name -> bytes.
Map<String, Uint8List> psuFiles(Uint8List d) {
  final out = <String, Uint8List>{};
  final count = Bytes.u32(d, 4);
  var at = 512 * 3;
  for (var i = 0; i < count - 2; i++) {
    final size = Bytes.u32(d, at + 4);
    out[Bytes.ascii(d, at + 0x40, 32)] = d.sublist(at + 512, at + 512 + size);
    at += 512 + (size / 1024).ceil() * 1024;
  }
  return out;
}

bool _near(double a, double b) => (a - b).abs() < 1e-5;

void main() {
  test('PS2 time is Japan time', () {
    final t = Uint8List.fromList([0, 42, 50, 22, 22, 11, 0, 0]);
    Bytes.put16(t, 6, 2026);
    expect(
      DateTime.fromMillisecondsSinceEpoch(
        Bytes.stamp(t, 0) * 1000,
        isUtc: true,
      ).toIso8601String(),
      '2026-11-22T13:50:42.000Z',
    );
    final e = Ps2Writer.newEntry(0x8427, 0, 'x', Bytes.stamp(t, 0));
    expect(e.sublist(9, 16), t.sublist(1, 8), reason: 'and written back so');
  });

  for (final ecc in [0, 16]) {
    group('PS2 card (ecc $ecc)', () {
      final c = Ps2Card.parse(ps2Card(ecc), 'PS2 Card 1', 'x.ps2', 1);
      test('one save, the deleted one left out', () {
        expect(c.error, '');
        expect(c.saves.length, 1);
      });
      test('free space from the FAT', () {
        expect(c.total, 40);
        expect(c.free, 34);
      });
      test('facts, dates, title, files, background, lights', () {
        final s = c.saves[0];
        expect(s.system, 'PS2');
        expect(s.serial, 'SLUS-21120');
        expect(s.region, 'America');
        expect(s.copyProtected, isTrue);
        expect(s.kb, 4);
        expect(s.modified - s.created, 2 * 86400);
        expect(s.titleLines, ['HELLO', 'WORLD']);
        expect(s.files.length, 2);
        expect(_near(s.backAlpha, 0.75), isTrue);
        expect(_near(s.ambient.r, 0.25), isTrue);
        final d = s.lightDirs[0];
        expect([d.x, d.y, d.z], [0, 0, -1], reason: 'flipped like models');
        expect(s.lightDirs[1].z, 1, reason: 'no direction = toward you');
        expect(s.lightColors[0].r, 0.5);
        expect(s.backColors[0].r, 128 / 255);
      });
      test('icon', () {
        final s = c.saves[0];
        final ico = s.icons[0];
        expect(ico, isNotNull);
        expect(identical(ico, s.icons[1]) && identical(ico, s.icons[2]), true);
        expect(ico!.shapes.length, 2);
        expect(ico.vertexCount, 3);
        expect(ico.tracks.length, 2);
        expect(ico.texture, isNotNull);
        expect(ico.texture!.at(127, 127), 0xFFFF0000, reason: 'packed red');
        expect(ico.texture!.at(0, 0), 0xFFFF0000);
        expect(ico.colorScale, 255 / 128);
        final w = ico.weights(0.25);
        expect(_near(w[0], 0.75) && _near(w[1], 0.25), isTrue, reason: '$w');
        var widest = 0.0;
        for (final pt in [...ico.shapes[0], ...ico.shapes[1]]) {
          widest = math.max(widest, pt.y.abs());
        }
        expect(widest, lessThanOrEqualTo(Ps2IconFile.fit + 0.001));
        expect(_near(ico.normals[0].z, 1), isTrue, reason: 'z flipped');
        expect(ico.uvs[1], (0.5, 0.0));
        expect(ico.colors[0].r, 128 / 255);
      });
    });
  }

  group('damage never crashes, hangs or reads outside', () {
    final whole = ps2Card(0);
    test('cut-short card refused', () {
      expect(
        Ps2Card.parse(whole.sublist(0, 4096), 'x', 'x', 0).error,
        isNot(''),
      );
    });
    test('not a card', () {
      expect(Ps2Card.isCard(Uint8List(0x200)), isFalse);
      expect(Ps2Card.parse(Uint8List(10), 'x', 'x', 0).error, isNot(''));
    });
    test('FAT loop ends', () {
      final looped = Uint8List.fromList(whole);
      Bytes.put32(looped, 2048, 0x80000000); // the root chain points at itself
      expect(Ps2Card.parse(looped, 'x', 'x', 0).saves, isEmpty);
    });
    test('FAT outside the card is survived', () {
      final wild = Uint8List.fromList(whole);
      Bytes.put32(wild, 0x50, 0xFFFFFF);
      Ps2Card.parse(wild, 'x', 'x', 0);
    });
    test('absurd size refused', () {
      final huge = Uint8List.fromList(whole);
      Bytes.put32(huge, 0x30, 0x7FFFFFFF);
      expect(Ps2Card.parse(huge, 'x', 'x', 0).error, isNot(''));
    });
    test('icons cut short or scrambled', () {
      final ico = iconFile();
      for (final cut in [0, 4, 19, 20, 100, 116, 130, ico.length - 1]) {
        final part = Ps2IconFile.parse(ico.sublist(0, cut));
        expect(part == null || part.vertexCount == 3, isTrue, reason: '$cut');
      }
      final many = Uint8List.fromList(ico);
      Bytes.put32(many, 16, 0xFFFFFFF);
      expect(Ps2IconFile.parse(many), isNull, reason: 'absurd vertex count');
      final rng = math.Random(20261122);
      for (var i = 0; i < 300; i++) {
        final junk = Uint8List.fromList(ico);
        for (var k = 0; k < 12; k++) {
          junk[rng.nextInt(junk.length)] = rng.nextInt(256);
        }
        final pi = Ps2IconFile.parse(junk);
        if (pi != null) {
          final w = pi.weights(0.3);
          expect(w.length, pi.shapes.length);
          expect(w.every((v) => v.isFinite), isTrue);
        }
      }
    });
    test('a plain (unpacked) texture', () {
      final b = Uint8List(128 * 128 * 2);
      Bytes.put16(b, 0, 31 << 5);
      final t = Ps2IconFile.readTexture(b, 0, false);
      expect(t.at(0, 0), 0xFF00FF00);
      expect(t.at(1, 0), 0xFF000000);
      final short = Ps2IconFile.readTexture(Uint8List(3), 0, true);
      expect(short.at(5, 5), 0xFF000000);
    });
  });

  test('a PCSX2 folder card', () {
    final dir = Directory.systemTemp.createTempSync('ps2_folder_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File(p.join(dir.path, Ps2Card.folderMark)).writeAsBytesSync([0]);
    final save = Directory(p.join(dir.path, 'BASLUS-21120-00'))..createSync();
    File(p.join(save.path, 'icon.sys')).writeAsBytesSync(iconSys());
    File(p.join(save.path, 'a.ico')).writeAsBytesSync(iconFile());
    File(p.join(save.path, 'data')).writeAsBytesSync(Uint8List(3000));
    File(p.join(save.path, '_pcsx2_meta')).writeAsBytesSync([1]);
    Directory(p.join(dir.path, 'not-a-save')).createSync();
    final c = Ps2Card.parseFolder(dir.path, 'PS2 Card 1');
    expect(c.error, '');
    expect(c.modified, greaterThan(0));
    expect(c.saves.length, 1);
    final s = c.saves[0];
    expect(s.files.map((f) => f.name).toSet(), {'icon.sys', 'a.ico', 'data'});
    expect(s.kb, 1 + 1 + 3 + 3, reason: 'each file rounded up, plus entries');
    expect(c.total, 8000);
    expect(c.free, 8000 - s.kb);
    expect(s.titleLines, ['HELLO', 'WORLD']);
    expect(s.icons[0], isNotNull);
  });

  for (final withEcc in [true, false]) {
    group(withEcc ? 'writer, ecc card' : 'writer, plain card', () {
      final blank = Ps2Writer.blank(withEcc);
      final one = psu('BASLUS-00001A', [0, 1, 1024, 70000]);
      test('a new card is valid and the reader agrees', () {
        expect(blank.length, 8192 * 2 * (withEcc ? 528 : 512));
        expect(Ps2Writer.check(blank), '');
        expect(Ps2Writer.freeClusters(blank), 7999);
        final seen = Ps2Card.parse(blank, 'n', 'n', 0);
        expect(seen.error, '');
        expect(seen.saves, isEmpty);
        expect(seen.free, 7999);
        expect(seen.total, 8000);
      });
      test('ECC matches the PS2 algorithm on every page written', () {
        if (!withEcc) return;
        for (final pg in [0, 16, 17, 82]) {
          final at = pg * 528;
          for (var k = 0; k < 4; k++) {
            expect(
              blank.sublist(at + 512 + k * 3, at + 515 + k * 3),
              Ps2Writer.ecc(blank, at + k * 128),
            );
          }
        }
        // An all-0xFF page's ECC is all zero bits flipped: 77 7F 7F.
        expect(Ps2Writer.ecc(Uint8List(128), 0), [0x77, 0x7F, 0x7F]);
      });
      final a = Ps2Writer.importSave(blank, one);
      test('import, export, refusals, delete', () {
        expect(a.error, '');
        expect(Ps2Writer.check(a.data), '');
        expect(Ps2Writer.saveNames(a.data), ['BASLUS-00001A']);
        expect(Ps2Writer.exportSave(a.data, 'BASLUS-00001A').data, one);
        expect(Ps2Writer.importSave(a.data, one).ok, isFalse, reason: 'name');
        expect(
          Ps2Writer.importSave(a.data, psu('BASLUS-00002B', [8000 * 1024])).ok,
          isFalse,
          reason: 'too big',
        );
        expect(
          Ps2Writer.importSave(a.data, one.sublist(0, 1800)).ok,
          isFalse,
          reason: 'cut short',
        );
        expect(Ps2Writer.importSave(a.data, Uint8List(2000)).ok, isFalse);
        final gone = Ps2Writer.delete(a.data, 'BASLUS-00001A');
        expect(gone.error, '');
        expect(Ps2Writer.check(gone.data), '');
        expect(Ps2Writer.saveNames(gone.data), isEmpty);
        // The main folder keeps the cluster it grew by.
        expect(Ps2Writer.freeClusters(gone.data), 7998);
        expect(Ps2Writer.delete(gone.data, 'BASLUS-00001A').ok, isFalse);
        expect(Ps2Writer.exportSave(gone.data, 'nope').ok, isFalse);
      });
      test('the reader sees the import', () {
        final c = Ps2Card.parse(a.data, 'n', 'n', 0);
        expect(c.saves.length, 1);
        final s = c.saves[0];
        expect(s.id, 'BASLUS-00001A');
        expect(s.files.map((f) => f.size), [0, 1, 1024, 70000]);
        expect(s.created, _when);
        expect(s.modified, _when);
        expect(s.kb, 3 + 0 + 1 + 1 + 69);
        expect(c.free, 7999 - 1 - 3 - 71);
      });
      test('the input is never changed', () {
        expect(Ps2Writer.check(blank), '');
        expect(Ps2Writer.saveNames(blank), isEmpty);
      });
      test('saves fit as the main folder grows', () {
        var many = blank;
        for (var i = 0; i < 4; i++) {
          final next = Ps2Writer.importSave(
            many,
            psu('BASLUS-1000$i', [10 + i]),
          );
          expect(next.error, '', reason: 'save $i');
          many = next.data;
        }
        expect(Ps2Writer.check(many), '');
        expect(Ps2Card.parse(many, 'n', 'n', 0).saves.length, 4);
        // A deleted slot in the main folder is used again.
        final less = Ps2Writer.delete(many, 'BASLUS-10001').data;
        final again = Ps2Writer.importSave(less, psu('BASLUS-20000', [5]));
        expect(Ps2Writer.check(again.data), '');
        expect(Ps2Writer.saveNames(again.data), [
          'BASLUS-10000',
          'BASLUS-20000',
          'BASLUS-10002',
          'BASLUS-10003',
        ]);
      });
      test('damage is caught, not written over', () {
        final broken = Uint8List.fromList(a.data);
        // Make the save's first file chain loop back on itself.
        final s = Ps2Writer.saveNames(a.data);
        expect(s, isNotEmpty);
        final stride = withEcc ? 528 : 512;
        // FAT table 0 is in cluster 9 (pages 18, 19).
        final c = Ps2Card.parse(a.data, 'n', 'n', 0);
        expect(c.saves, isNotEmpty);
        for (var k = 0; k < 256; k++) {
          final at = (18 + k * 4 ~/ 512) * stride + k * 4 % 512;
          if (Bytes.u32(broken, at) == 0xFFFFFFFF && k > 1) {
            Bytes.put32(broken, at, 0x80000000 | k);
          }
        }
        expect(Ps2Writer.check(broken), isNot(''));
        expect(Ps2Writer.delete(broken, 'BASLUS-00001A').ok, isFalse);
        final wrong = Uint8List.fromList(blank.sublist(0, blank.length - 512));
        expect(Ps2Writer.check(wrong), isNot(''));
        expect(Ps2Writer.importSave(wrong, one).ok, isFalse);
      });
    });
  }

  _samples();
}

void _samples() {
  final root = Platform.environment['SAVE_SAMPLES'] ?? '';
  final skip = root.isEmpty || !Directory(root).existsSync()
      ? 'SAVE_SAMPLES is not set'
      : null;
  final cards = <File>[];
  if (skip == null) {
    for (final f in Directory(root).listSync(recursive: true)) {
      final ext = p.extension(f.path).toLowerCase();
      if (f is File && (ext == '.mc2' || ext == '.ps2')) cards.add(f);
    }
    cards.sort((a, b) => a.path.compareTo(b.path));
  }
  group('real PS2 cards', skip: skip, () {
    var saves = 0, titled = 0, icons = 0, headers = 0, copied = 0, refused = 0;
    test('there are some', () => expect(cards, isNotEmpty));
    for (final f in cards) {
      final label = p.relative(f.path, from: root);
      test(label, () {
        final d = Uint8List.fromList(f.readAsBytesSync());
        final before = Uint8List.fromList(d);
        expect(Ps2Card.isCard(d), isTrue);
        final card = Ps2Card.parse(d, label, f.path, 0);
        expect(card.error, '');
        expect(Ps2Writer.check(d), '');
        final names = Ps2Writer.saveNames(d);
        expect(names, [for (final s in card.saves) s.id]);
        for (final s in card.saves) {
          saves++;
          if (s.titleLines.isNotEmpty) titled++;
          if (s.icons.every((i) => i != null)) icons++;
        }

        final ecc = d.length != Ps2Writer.total * 2 * Ps2Writer.page;
        var fresh = Ps2Writer.blank(ecc);
        final stride = ecc ? 528 : 512;
        final indirect = 8 * 2 * stride;
        if (Bytes.same(fresh.sublist(0, 0x50), d.sublist(0, 0x50)) &&
            Bytes.same(fresh.sublist(0x150, 0x170), d.sublist(0x150, 0x170)) &&
            Bytes.same(
              fresh.sublist(indirect, indirect + 2 * stride),
              d.sublist(indirect, indirect + 2 * stride),
            )) {
          headers++;
        }

        // A save with entries that look like folders inside it (one card
        // has a directory listing erased 0xFF entries) is refused whole,
        // as the PC does: it stays where it is.
        const inside = 'has folders inside it';
        final kept = <String, Uint8List>{};
        final stays = <String>[];
        var emptied = d;
        for (final name in names) {
          final out = Ps2Writer.exportSave(d, name);
          final gone = Ps2Writer.delete(emptied, name);
          if (out.error.contains(inside)) {
            expect(gone.error, contains(inside), reason: '$name stays');
            stays.add(name);
            refused++;
            continue;
          }
          expect(out.error, '', reason: '$name exports');
          kept[name] = out.data;
          final s = card.saves.firstWhere((s) => s.id == name);
          final files = psuFiles(out.data);
          expect(files.keys.toSet(), {for (final f in s.files) f.name});
          expect(gone.error, '', reason: '$name deletes');
          expect(Ps2Writer.check(gone.data), '');
          emptied = gone.data;
        }
        expect(Ps2Writer.saveNames(emptied), stays);
        expect(Ps2Card.parse(emptied, 'e', 'e', 0).saves.length, stays.length);
        var rebuilt = emptied;
        for (final name in kept.keys) {
          var put = Ps2Writer.importSave(rebuilt, kept[name]!);
          expect(put.error, '', reason: '$name copies back');
          rebuilt = put.data;
          put = Ps2Writer.importSave(fresh, kept[name]!);
          expect(put.error, '', reason: '$name copies to a new card');
          fresh = put.data;
        }
        for (final copy in [rebuilt, fresh]) {
          expect(Ps2Writer.check(copy), '');
          for (final name in kept.keys) {
            expect(
              Bytes.same(Ps2Writer.exportSave(copy, name).data, kept[name]!),
              isTrue,
              reason: '$name is unchanged byte for byte',
            );
          }
          final again = Ps2Card.parse(copy, 'c', 'c', 0);
          String titles(MemoryCard c) => [
            for (final s in c.saves)
              if (kept.containsKey(s.id)) '${s.id}: ${s.titleLines.join('/')}',
          ].join(', ');
          expect(titles(again), titles(card));
        }
        expect(
          Ps2Writer.freeClusters(rebuilt),
          Ps2Writer.freeClusters(d),
          reason: 'no space leaked',
        );
        expect(Bytes.same(d, before), isTrue, reason: 'the card is untouched');
        copied += kept.length;
      });
    }
    test('a PCSX2 folder card made from the real saves', () {
      final dir = Directory.systemTemp.createTempSync('ps2_real_folder_');
      addTearDown(() => dir.deleteSync(recursive: true));
      File(p.join(dir.path, Ps2Card.folderMark)).writeAsBytesSync([0]);
      final want = <String, String>{};
      for (final f in cards.take(20)) {
        final d = Uint8List.fromList(f.readAsBytesSync());
        final card = Ps2Card.parse(d, 'x', 'x', 0);
        for (final s in card.saves) {
          if (want.containsKey(s.id)) continue;
          final sub = Directory(p.join(dir.path, s.id))..createSync();
          psuFiles(Ps2Writer.exportSave(d, s.id).data).forEach((n, b) {
            File(p.join(sub.path, n)).writeAsBytesSync(b);
          });
          if (File(p.join(sub.path, 'icon.sys')).existsSync()) {
            want[s.id] = s.titleLines.join('/');
          }
        }
      }
      final folder = Ps2Card.parseFolder(dir.path, 'PS2 Card 1');
      expect({
        for (final s in folder.saves) s.id: s.titleLines.join('/'),
      }, want);
    });
    tearDownAll(() {
      // ignore: avoid_print
      print(
        'PS2 samples: ${cards.length} cards, $saves saves ($titled titled, '
        '$icons with all three icons), $copied exported, deleted and '
        'imported byte for byte, $refused refused as damaged; $headers '
        'headers match a new card',
      );
    });
  });
}
