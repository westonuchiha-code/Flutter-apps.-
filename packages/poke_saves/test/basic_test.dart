import 'dart:typed_data';

import 'package:poke_saves/poke_saves.dart';
import 'package:poke_saves/testing.dart';
import 'package:poke_saves/src/data/tables.g.dart';
import 'package:poke_saves/src/mon.dart';
import 'package:poke_saves/src/text.dart';
import 'package:test/test.dart';

void main() {
  test('generated tables have every entry', () {
    expect(speciesNames.length, 387);
    expect(moveNames.length, 355);
    expect(abilityNames.length, 78);
    expect(itemNamesGen2.length, 255);
    expect(itemNamesGen3.length, 377);
    expect(itemNamesGen2[0xAD], 'Berry');
    expect(itemNamesGen3[157], 'Grepa Berry');
    expect(speciesName(122), 'Mr. Mime');
    expect(gen1InternalIndex[1], 0x99);
    expect(gen3InternalIndex[252], 277);
  });

  test('Game Boy and GBA text', () {
    expect(decodeGb(gbName('Weston'), gen2: false), 'Weston');
    expect(decodeGb([0x83, 0xE8, 0x88, 0xE8, 0x50], gen2: true), 'D․I․');
    expect(decodeGba([0xC7, 0xD5, 0xEC, 0xFF]), 'Max');
    expect(decodeGba([0xB5, 0xB6, 0xA1, 0xFF]), '♂♀0');
  });

  test('Gen 3 encryption round trips for every PID order', () {
    for (var pid = 0; pid < 24; pid++) {
      final d = Uint8List(80);
      for (var i = 0; i < 80; i++) {
        d[i] = (i * 7 + pid) & 0xFF;
      }
      ByteData.sublistView(d).setUint32(0, pid + 24 * 1000, Endian.little);
      final copy = Uint8List.fromList(d);
      gen3Encrypt(d);
      gen3Decrypt(d);
      expect(d, copy);
    }
  });

  test('a .pk1 file reads and writes back byte for byte', () {
    final f = bulbasaurPk1();
    final m = Mon.fromFile(f, ext: 'pk1')!;
    expect(m.species, 1);
    expect(m.level, 5);
    expect(m.isShiny, isTrue);
    expect(m.summary['nickname'], '');
    expect(m.summary['moves'], ['Tackle', 'Growl']);
    expect(m.bytes, f);
    expect(Mon.fromFile(Uint8List(69), ext: 'pk1'), isNull);
  });

  test('Gen 1 save: put, take, packed boxes, uninitialised boxes', () {
    final save = PokeSave.open(gen1Save())!;
    expect(save.game, PokeGame.redBlue);
    expect(save.trainer, 'ASH');
    var r = save.put(0, 7, bulbasaurPk1(), ext: 'pk1');
    expect(r.ok, isTrue, reason: r.error);
    var s = PokeSave.open(r.save!)!;
    expect(s.check(), '');
    expect(s.boxMon(0, 0)!.species, 1); // no gaps: it went to the front
    expect(s.boxMon(0, 7), isNull);
    // Another box before the game set its boxes up: the boxes get marked as
    // set up so the game won't wipe them on the first box change.
    r = s.put(4, 0, bulbasaurPk1(), ext: 'pk1');
    expect(r.ok, isTrue, reason: r.error);
    s = PokeSave.open(r.save!)!;
    expect(r.save![0x284C] & 0x80, 0x80);
    expect(s.boxMon(4, 0)!.species, 1);
    final t = s.take(0, 0);
    expect(t.ok, isTrue);
    expect(t.mon!.species, 1);
    expect(PokeSave.open(t.save!)!.boxes[0].count, 0);
    expect(s.take(0, 5).error, 'that slot is empty');
  });

  test(
    'Gen 1: the last one out of the current box before boxes are set up',
    () {
      final one = PokeSave.open(
        gen1Save(),
      )!.put(0, 0, bulbasaurPk1(), ext: 'pk1');
      expect(one.ok, isTrue, reason: one.error);
      final t = PokeSave.open(one.save!)!.take(0, 0);
      expect(t.ok, isTrue, reason: t.error);
      final s = PokeSave.open(t.save!)!;
      expect(s.boxes[0].count, 0);
      expect(s.check(), '');
    },
  );

  test('Gen 1 <-> Gen 2 through the Time Capsule', () {
    final crystal = PokeSave.open(crystalSave())!;
    expect(crystal.game, PokeGame.crystal);
    final r = crystal.put(0, 0, bulbasaurPk1(), ext: 'pk1');
    expect(r.ok, isTrue, reason: r.error);
    expect(r.reason, 'converted from pk1 to pk2');
    final m = PokeSave.open(r.save!)!.boxMon(0, 0)!;
    expect(m.ext, 'pk2');
    expect(m.level, 5);
    expect(
      m.heldItem,
      0x53,
    ); // catch rate 45 is no Gen 2 held item: the Time Capsule gives a Bitter Berry
    final gen1 = PokeSave.open(gen1Save())!;
    final back = gen1.put(0, 0, chikoritaPk2(), ext: 'pk2');
    expect(back.ok, isFalse);
    expect(back.error, contains("Chikorita doesn't exist"));
  });

  test('Gen 2 save keeps both checksums right', () {
    final crystal = PokeSave.open(crystalSave())!;
    final r = crystal.put(3, 0, chikoritaPk2(), ext: 'pk2');
    expect(r.ok, isTrue, reason: r.error);
    final s = PokeSave.open(r.save!)!;
    expect(s.check(), '');
    expect(s.boxMon(3, 0)!.summary['item'], 'Berry');
    expect(s.boxMon(3, 0)!.summary['nickname'], 'Leafy');
    expect(s.boxMon(3, 0)!.bytes.sublist(0, 35), chikoritaPk2().sublist(0, 35));
  });

  test('Gen 3 save: detection, put, take, checksums', () {
    final frlg = PokeSave.open(gen3Save(code: 1))!;
    expect(frlg.game, PokeGame.fireRedLeafGreen);
    expect(frlg.trainer, 'Wlaf');
    expect(frlg.check(), '');
    final file = treeckoPk3();
    final r = frlg.put(13, 29, file, ext: 'pk3');
    expect(r.ok, isTrue, reason: r.error);
    final s = PokeSave.open(r.save!)!;
    expect(s.check(), '');
    final m = s.boxMon(13, 29)!;
    expect(m.bytes, file);
    expect(m.summary['name'], 'Treecko');
    expect(m.summary['nickname'], 'Tak');
    expect(m.summary['item'], 'Oran Berry');
    expect(m.summary['origin'], 'Ruby');
    expect(m.summary['ball'], 'Poké Ball');
    final t = s.take(13, 29);
    expect(t.mon!.bytes, file);
    expect(PokeSave.open(t.save!)!.boxMon(13, 29), isNull);
    expect(PokeSave.open(gen3Save(code: 0))!.game, PokeGame.rubySapphire);
  });

  test('items a Pokémon can hold', () {
    expect(heldItemChoices(1), isEmpty);
    final g2 = heldItemChoices(2);
    expect(g2.first.name, 'None');
    expect(g2.map((e) => e.name), contains('Leftovers'));
    expect(g2.map((e) => e.name), isNot(contains('Bicycle')));
    final g3 = heldItemChoices(3);
    expect(g3.map((e) => e.name), contains('Choice Band'));
    expect(g3.map((e) => e.name), isNot(contains('Safari Ball')));
  });

  test('not a Pokémon save', () {
    expect(PokeSave.open(Uint8List(0x8000)), isNull);
    expect(PokeSave.open(Uint8List(1234)), isNull);
  });
}
