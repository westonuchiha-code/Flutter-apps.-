// Nicknames and held items, as the PC's helper changes them with PKHeX
// (pkhelper's nick / item / nickfile / itemfile). Built Pokémon here; the
// owner's real ones in real_saves_test.dart.
import 'dart:typed_data';

import 'package:poke_saves/poke_saves.dart';
import 'package:poke_saves/testing.dart';
import 'package:test/test.dart';

Mon mon(Uint8List file, String ext) => Mon.fromFile(file, ext: ext)!;

void main() {
  group('Game Boy nicknames', () {
    test('rename, then clear back to the species name: the same bytes', () {
      final b = mon(bulbasaurPk1(), 'pk1');
      expect(b.isNicknamed, isFalse);
      final r = b.withNickname('Bulby');
      expect(r.ok, isTrue, reason: r.error);
      expect(r.mon!.nickname, 'Bulby');
      expect(r.mon!.isNicknamed, isTrue);
      expect(r.mon!.summary['nickname'], 'Bulby');
      // 0x50-filled buffer: letters, then 0x50s (PKHeX's Clear50)
      expect(r.mon!.nick, [
        0x81, 0xB4, 0xAB, 0xA1, 0xB8, 0x50, 0x50, 0x50, 0x50, 0x50, 0x50, //
      ]);
      final back = r.mon!.withNickname('');
      expect(back.ok, isTrue);
      expect(back.mon!.isNicknamed, isFalse);
      expect(back.mon!.bytes, bulbasaurPk1());
    });

    test('a nicknamed one renamed and named back: the same bytes', () {
      final c = mon(chikoritaPk2(), 'pk2'); // "Leafy"
      expect(c.nickname, 'Leafy');
      final r = c.withNickname('X')..mon!.withNickname('Leafy');
      expect(r.mon!.withNickname('Leafy').mon!.bytes, chikoritaPk2());
    });

    test('ten letters fit; eleven are refused', () {
      final b = mon(bulbasaurPk1(), 'pk1');
      final ten = b.withNickname('ABCDEFGHIJ');
      expect(ten.ok, isTrue);
      expect(ten.mon!.nick[10], 0x50);
      expect(b.withNickname('ABCDEFGHIJK').error, contains('10 letters'));
    });

    test('letters a Game Boy game can\'t write are refused', () {
      final b = mon(bulbasaurPk1(), 'pk1');
      for (final bad in ['Zoë', 'naïve', 'a~b', 'A_B', 'Ω']) {
        expect(
          b.withNickname(bad).error,
          "this game can't write some of those letters",
          reason: bad,
        );
      }
      // Gen 2 has no plain apostrophe (only ’); Gen 1 has both
      final c = mon(chikoritaPk2(), 'pk2');
      expect(c.withNickname("Ch'ko").ok, isFalse);
      expect(c.withNickname('Ch’ko').ok, isTrue);
      expect(b.withNickname("Ch'ko").ok, isTrue);
      expect(nicknameCanWrite(2, "'"), isFalse);
      expect(nicknameCanWrite(1, "'"), isTrue);
      expect(nicknameCanWrite(1, '+'), isFalse);
      expect(nicknameCanWrite(2, '+'), isTrue);
      expect(nicknameCanWrite(1, '♀'), isTrue);
      expect(nicknameCanWrite(1, '*'), isFalse);
    });

    test('a zero-filled buffer stays zero-filled (as PKHeX keeps it)', () {
      final file = bulbasaurPk1();
      // Bulbasaur's nickname buffer, cleared with zeros
      file.fillRange(58, 69, 0);
      file.setAll(58, [0x81, 0x50]);
      final r = mon(file, 'pk1').withNickname('Bo');
      expect(r.mon!.nick, [0x81, 0xAE, 0x50, 0, 0, 0, 0, 0, 0, 0, 0]);
    });

    test('Eggs are refused', () {
      final egg = Uint8List.fromList(chikoritaPk2())..[1] = 0xFD;
      final m = mon(egg, 'pk2');
      expect(m.isEgg, isTrue);
      expect(m.withNickname('Hi').error, "Eggs can't be renamed");
      expect(m.withItem(0).error, "Eggs can't hold items");
    });
  });

  group('GBA nicknames', () {
    test('rename and back: the same bytes, checksum refreshed', () {
      final t = mon(treeckoPk3(), 'pk3');
      final was = t.nickname;
      final r = t.withNickname('Gecko♂');
      expect(r.ok, isTrue, reason: r.error);
      expect(r.mon!.nickname, 'Gecko♂');
      final file = r.mon!.bytes;
      expect(Mon.fromFile(file, ext: 'pk3')!.nickname, 'Gecko♂');
      // the checksum PKHeX checks
      final sum = [
        for (var i = 0x20; i < 80; i += 2) file[i] | file[i + 1] << 8,
      ].fold(0, (a, b) => a + b);
      expect(file[0x1C] | file[0x1D] << 8, sum & 0xFFFF);
      // PKHeX writes a GBA name over the old one (no clearing): named back,
      // the longer name's leftovers stay after the 0xFF, as with PKHeX
      final back = r.mon!.withNickname(was).mon!;
      expect(back.nickname, was);
      expect(back.data.sublist(8, 18), [
        0xCE, 0xD5, 0xDF, 0xFF, 0xE3, 0xB5, 0xFF, 0xFF, 0xFF, 0xFF, //
      ]);
      expect(back.withNickname('Gecko♂').mon!.bytes, file);
    });

    test('a one-letter name and back, then clearing it', () {
      final t = mon(treeckoPk3(), 'pk3'); // "Tak"
      final a = t.withNickname('A').mon!;
      expect(a.nickname, 'A');
      expect(a.withNickname('Tak').mon!.bytes, t.bytes);
      final plain = a.withNickname('').mon!;
      expect(plain.nickname, 'TREECKO');
      expect(plain.isNicknamed, isFalse);
      expect(plain.summary['nickname'], '');
    });

    test('quotes and the apostrophe map as PKHeX maps them', () {
      final t = mon(treeckoPk3(), 'pk3');
      expect(t.withNickname('“Hi”').mon!.nickname, '“Hi”');
      // ’ is written as the game's apostrophe and reads back as '
      expect(t.withNickname('It’s').ok, isFalse);
      expect(t.withNickname("It's").ok, isTrue);
      expect(t.withNickname('×').ok, isFalse);
      expect(nicknameCanWrite(3, '×'), isFalse);
      expect(nicknameCanWrite(3, "'"), isTrue);
    });
  });

  group('held items', () {
    test('Gen 2: give, take back; refused items', () {
      final c = mon(chikoritaPk2(), 'pk2');
      final had = c.heldItem;
      final r = c.withItem(0x92); // Leftovers
      expect(r.ok, isTrue);
      expect(r.mon!.itemName, 'Leftovers');
      expect(r.mon!.withItem(had).mon!.bytes, chikoritaPk2());
      expect(r.mon!.withItem(0).mon!.itemName, '');
      expect(c.withItem(7).error, contains("doesn't let")); // Bicycle
      expect(c.withItem(256).ok, isFalse);
    });

    test('Gen 3: give, take back; Safari Ball and Berry Juice refused', () {
      final t = mon(treeckoPk3(), 'pk3');
      final r = t.withItem(200); // Leftovers
      expect(r.mon!.itemName, 'Leftovers');
      expect(r.mon!.withItem(t.heldItem).mon!.bytes, t.bytes);
      expect(r.mon!.withItem(0).mon!.heldItem, 0);
      expect(t.withItem(5).ok, isFalse);
      expect(t.withItem(44).ok, isFalse);
      expect(t.withItem(377).ok, isFalse);
      expect(t.withItem(259).ok, isFalse); // a key item
    });

    test("Gen 1 Pokémon can't hold items", () {
      final b = mon(bulbasaurPk1(), 'pk1');
      expect(b.withItem(0).error, "Gen 1 Pokémon can't hold items");
    });

    test('the lists match what may be held', () {
      for (final g in [2, 3]) {
        for (final it in heldItemChoices(g)) {
          expect(heldItemAllowed(g, it.id), isTrue, reason: it.name);
        }
      }
      // as the PC's list for Crystal (193 rows, None first)
      expect(heldItemChoices(2).length, 193);
    });
  });

  group('in a save', () {
    test('Gen 1 box and party: rename, item refused, checksums right', () {
      final s0 = PokeSave.open(gen1Save())!;
      final put = s0.put(0, 0, bulbasaurPk1(), ext: 'pk1');
      final s = PokeSave.open(put.save!)!;
      final r = s.setNickname(0, 0, 'Seedy');
      expect(r.ok, isTrue, reason: r.error);
      final s2 = PokeSave.open(r.save!)!;
      expect(s2.check(), '');
      expect(s2.boxMon(0, 0)!.nickname, 'Seedy');
      expect(s2.setItem(0, 0, 0).error, "Gen 1 Pokémon can't hold items");
      final back = s2.setNickname(0, 0, '');
      expect(back.save, put.save);
      expect(s.setNickname(0, 5, 'X').error, 'no Pokémon in that box slot');
      expect(s.setNickname(PokeSave.partyBox, 0, 'X').ok, isFalse);
    });

    test('Gen 2: item and nickname, both checksums', () {
      final s0 = PokeSave.open(crystalSave())!;
      final put = s0.put(1, 0, chikoritaPk2(), ext: 'pk2');
      final s = PokeSave.open(put.save!)!;
      final r = s.setItem(1, 0, 0x92);
      expect(r.ok, isTrue, reason: r.error);
      final s2 = PokeSave.open(r.save!)!;
      expect(s2.check(), '');
      expect(s2.boxMon(1, 0)!.itemName, 'Leftovers');
      final n = s2.setNickname(1, 0, 'Ch’ko');
      final s3 = PokeSave.open(n.save!)!;
      expect(s3.boxMon(1, 0)!.nickname, 'Ch’ko');
      expect(s3.check(), '');
      final undo = PokeSave.open(s3.setNickname(1, 0, 'Leafy').save!)!;
      expect(undo.setItem(1, 0, 173).save, put.save);
    });

    test('Gen 3: rename and item in a box, sectors right', () {
      final s0 = PokeSave.open(gen3Save(code: 1))!;
      final put = s0.put(2, 4, treeckoPk3(), ext: 'pk3');
      final s = PokeSave.open(put.save!)!;
      final r = s.setNickname(2, 4, 'Mo');
      expect(r.ok, isTrue, reason: r.error);
      final s2 = PokeSave.open(r.save!)!;
      expect(s2.check(), '');
      expect(s2.boxMon(2, 4)!.nickname, 'Mo');
      final i = PokeSave.open(s2.setItem(2, 4, 200).save!)!;
      expect(i.boxMon(2, 4)!.itemName, 'Leftovers');
      expect(i.check(), '');
      final undo = PokeSave.open(i.setItem(2, 4, 139).save!)!;
      expect(undo.setNickname(2, 4, 'Tak').save, put.save);
    });

    test('Gen 2 party: rename and item, the party stays the same size', () {
      final save = withPartyMon(crystalSave(), chikoritaPk2(), ext: 'pk2');
      final s = PokeSave.open(save)!;
      expect(s.party, hasLength(1));
      final r = s.setNickname(PokeSave.partyBox, 0, 'Chiko');
      expect(r.ok, isTrue, reason: r.error);
      final s2 = PokeSave.open(r.save!)!;
      expect(s2.check(), '');
      expect(s2.party.single.nickname, 'Chiko');
      final i = PokeSave.open(s2.setItem(PokeSave.partyBox, 0, 0x92).save!)!;
      expect(i.party.single.itemName, 'Leftovers');
      expect(i.setNickname(PokeSave.partyBox, 1, 'X').ok, isFalse);
      final undo = PokeSave.open(i.setItem(PokeSave.partyBox, 0, 173).save!)!;
      expect(undo.setNickname(PokeSave.partyBox, 0, 'Leafy').save, s.rewrite());
    });
  });
}
