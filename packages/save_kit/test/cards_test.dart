import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:save_kit/src/card_image.dart';
import 'package:save_kit/src/cards.dart';
import 'package:save_kit/src/formats/n64.dart';
import 'package:save_kit/src/formats/ps1.dart';
import 'package:save_kit/src/formats/saturn.dart';
import 'package:save_kit/src/model.dart';
import 'package:test/test.dart';

void main() {
  test('card names', () {
    expect(MemoryCards.cardName('Mcd001'), 'PS2 Card 1');
    expect(MemoryCards.cardName('shared_card_2'), 'PS1 Card 2');
    expect(MemoryCards.cardName('vmu_save_a1'), 'VMU A1');
    expect(MemoryCards.cardName('MemoryCardA.USA'), 'GC Card A (USA)');
    expect(MemoryCards.cardName('Jersey Devil (USA)_1'), 'Jersey Devil');
  });

  test('match keys ignore punctuation, order and articles', () {
    expect(
      MemoryCards.matchKey('Saru Get You - Million Monkeys'),
      MemoryCards.matchKey('Saru! Get You! Million Monkeys'),
    );
    expect(
      MemoryCards.matchKey('The Legend of Dragoon'),
      MemoryCards.matchKey('Legend of Dragoon, The'),
    );
  });

  test('GameIndex names prefer English', () {
    const yaml =
        'SLUS-20001:\n  name: "Japanese"\n  name-en: "English"\n  region: "NTSC-U"\nSLUS-20002:\n  name: Other\n';
    expect(MemoryCards.indexName(yaml, 'SLUS-20001'), 'English');
    expect(MemoryCards.indexName(yaml, 'SLUS-20002'), 'Other');
    expect(MemoryCards.indexName(yaml, 'SLUS-20003'), '');
  });

  test('a scan finds cards in folders, names saves and matches games', () {
    final dir = Directory.systemTemp.createTempSync('cards');
    addTearDown(() => dir.deleteSync(recursive: true));
    final ps1 = Ps1Writer.importSave(
      Ps1Writer.blank(),
      _mcs('BASLUS-00001A', 1),
    ).data;
    File(p.join(dir.path, 'Crash (USA)_1.mcd')).writeAsBytesSync(ps1);
    final deeper = Directory(p.join(dir.path, 'a', 'b'))
      ..createSync(recursive: true);
    File(p.join(deeper.path, 'shared_card_1.mcd')).writeAsBytesSync(ps1);
    File(p.join(dir.path, 'notes.bin')).writeAsBytesSync(List.filled(1000, 1));
    final all = MemoryCards.readAll(
      [dir.path],
      games: [(id: 'g1', title: 'Crash', system: 'PS1', serial: '')],
      played: {'g1': (seconds: 60, sessions: 2, last: 5)},
    );
    expect(
      all.cards.map((c) => c.name),
      unorderedEquals(['Crash', 'PS1 Card 1']),
    );
    expect(all.saves.length, 2);
    final own = all.saves.firstWhere((s) => s.card!.name == 'Crash');
    expect(own.gameId, 'g1');
    expect(own.sessions, 2);
    final shared = all.saves.firstWhere((s) => s.card!.name == 'PS1 Card 1');
    expect(
      shared.gameId,
      '',
      reason: 'a shared card is not named for one game',
    );
  });

  test('N64 .srm with four paks, and gzipped Saturn, go back in place', () {
    final pak = PakWriter.blank();
    final srm = Uint8List(CardImage.n64Combined);
    for (var i = 0; i < 4; i++) {
      srm.setRange(
        CardImage.n64PaksAt + i * pak.length,
        CardImage.n64PaksAt + (i + 1) * pak.length,
        pak,
      );
    }
    final parts = CardImage.find(srm, 'srm');
    expect(parts.where((x) => x.system == 'N64').length, 4);
    final card = MemoryCard()
      ..system = 'N64'
      ..offset = parts[2].offset
      ..span = parts[2].span;
    final changed = Uint8List.fromList(pak)..[pak.length - 1] ^= 1;
    final back = CardImage.put(srm, card, changed);
    expect(back.length, srm.length);
    expect(CardImage.take(back, card), changed);
    expect(back.sublist(0, card.offset), srm.sublist(0, card.offset));

    final sat = SaturnWriter.gzip(SaturnWriter.blank());
    final sp = CardImage.find(sat, 'bkr');
    expect(sp.single.gzip, isTrue);
    final sc = MemoryCard()
      ..system = 'SATURN'
      ..span = sat.length
      ..gzip = true;
    expect(CardImage.take(sat, sc), SaturnWriter.blank());
  });

  final samples = Platform.environment['SAVE_SAMPLES'] ?? '';
  test(
    'every real sample folder scans',
    skip: samples.isEmpty ? 'SAVE_SAMPLES not set' : false,
    () {
      final before = <String, int>{};
      for (final f in Directory(
        samples,
      ).listSync(recursive: true).whereType<File>()) {
        before[f.path] = f.lengthSync();
      }
      final all = MemoryCards.readAll([samples]);
      final by = <String, int>{};
      final saves = <String, int>{};
      for (final c in all.cards) {
        by[c.system] = (by[c.system] ?? 0) + 1;
        saves[c.system] = (saves[c.system] ?? 0) + c.saves.length;
        expect(
          c.error,
          anyOf('', 'not formatted'),
          reason: '${c.path}: ${c.error}',
        );
      }
      // ignore: avoid_print
      print('cards $by, saves $saves');
      for (final s in ['PS1', 'PS2', 'DC', 'GC', 'N64', 'SATURN']) {
        expect(by[s] ?? 0, greaterThan(0), reason: 'no $s cards found');
      }
      for (final s in all.saves) {
        expect(s.titleLines.isNotEmpty || s.id.isNotEmpty, isTrue);
      }
      for (final e in before.entries) {
        expect(File(e.key).lengthSync(), e.value);
      }
    },
  );
}

Uint8List _mcs(String name, int blocks) {
  final b = Uint8List(128 + blocks * 8192)
    ..fillRange(128, 128 + blocks * 8192, 0x11);
  b[0] = 0x51;
  b.buffer.asByteData().setUint32(4, blocks * 8192, Endian.little);
  b.buffer.asByteData().setUint16(8, 0xFFFF, Endian.little);
  b.setRange(10, 10 + name.length, name.codeUnits);
  return b;
}
