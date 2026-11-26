import 'dart:typed_data';

import 'package:poke_saves/poke_saves.dart';
import 'package:poke_saves/src/data/tables.g.dart';
import 'package:poke_saves/src/gba_save.dart';
import 'package:poke_saves/src/mon.dart';
import 'package:poke_saves/src/text.dart';
import 'package:test/test.dart';

Uint8List gbName(String s, {bool gen2 = false}) => encodeGb(s, 11, gen2: gen2)!;

/// A Bulbasaur as a .pk1 file (69 bytes).
Uint8List bulbasaurPk1() {
  final body = Uint8List(44);
  body[0] = 0x99; // internal species number of Bulbasaur
  body[1] = 0;
  body[2] = 20; // HP
  body[5] = 0x16;
  body[6] = 0x03; // Grass / Poison
  body[7] = 45; // catch rate
  body[8] = 33; // Tackle
  body[9] = 45; // Growl
  body[0xC] = 0x12;
  body[0xD] = 0x34; // trainer ID
  body[0x10] = 135; // 135 EXP = level 5 (medium slow)
  body[0x1B] = 0xAA;
  body[0x1C] = 0xAA; // DVs (shiny pattern)
  body[0x1D] = 35;
  body[0x1E] = 40;
  body[0x21] = 5;
  return Uint8List.fromList([
    1,
    0x99,
    0xFF,
    ...body,
    ...gbName('WESTON'),
    ...gbName('BULBASAUR'),
  ]);
}

/// A Chikorita as a .pk2 file (73 bytes) holding a Berry.
Uint8List chikoritaPk2() {
  final body = Uint8List(48);
  body[0] = 152;
  body[1] = 0xAD; // Berry
  body[2] = 33;
  body[3] = 45;
  body[6] = 0x12;
  body[7] = 0x34;
  body[0xA] = 135; // level 5 (medium slow)
  body[0x15] = 0x12;
  body[0x16] = 0x34;
  body[0x17] = 35;
  body[0x18] = 40;
  body[0x1B] = 70;
  body[0x1F] = 5;
  return Uint8List.fromList([
    1,
    152,
    0xFF,
    ...body,
    ...gbName('WESTON', gen2: true),
    ...gbName('Leafy', gen2: true),
  ]);
}

Uint8List gen1Save() {
  final d = Uint8List(0x8000);
  d[0x2F2D] = 0xFF; // party: none
  d[0x30C0 + 1] = 0xFF; // current box: none
  d.setRange(0x2598, 0x2598 + 11, gbName('ASH'));
  return d;
}

Uint8List crystalSave() {
  final d = Uint8List(0x8000);
  d[0x2865 + 1] = 0xFF;
  d[0x2D10 + 1] = 0xFF;
  d.setRange(0x200B, 0x200B + 11, gbName('Kris', gen2: true));
  return d;
}

Uint8List gen3Save({required int code}) {
  final d = Uint8List(0x20000);
  for (var slot = 0; slot < 2; slot++) {
    for (var id = 0; id < 14; id++) {
      final at = slot * 14 * 0x1000 + id * 0x1000;
      d[at + 0xFF4] = id;
      d.setRange(at + 0xFF8, at + 0xFFC, [0x25, 0x20, 0x01, 0x08]);
      d[at + 0xFFC] = slot + 1; // save counter: slot 1 is newer
      if (id == 0) {
        d.setRange(at, at + 8, [
          0xD1,
          0xE0,
          0xD5,
          0xDA,
          0xFF,
          0xFF,
          0xFF,
          0xFF,
        ]); // "Wlaf"
        d[at + 0xAC] = code;
      }
      final c = GbaSave.sectorSum(d, at);
      d[at + 0xFF6] = c & 0xFF;
      d[at + 0xFF7] = c >> 8;
    }
  }
  return d;
}

/// A Treecko (.pk3, 80 decrypted bytes).
Uint8List treeckoPk3() {
  final d = Uint8List(100);
  final bd = ByteData.sublistView(d);
  bd.setUint32(0, 0x9ABCDEF1, Endian.little);
  bd.setUint32(4, 0x00010002, Endian.little);
  d.setRange(8, 18, [
    0xCE,
    0xD5,
    0xDF,
    0xFF,
    0xFF,
    0xFF,
    0xFF,
    0xFF,
    0xFF,
    0xFF,
  ]); // "Tak"
  d[0x12] = 2; // English
  d[0x13] = 2;
  d.setRange(0x14, 0x1B, [0xC7, 0xD5, 0xEC, 0xFF, 0xFF, 0xFF, 0xFF]); // "Max"
  bd.setUint16(0x20, 277, Endian.little); // internal number of Treecko
  bd.setUint16(0x22, 139, Endian.little); // Oran Berry
  bd.setUint32(0x24, 135, Endian.little);
  bd.setUint16(0x2C, 1, Endian.little); // Pound
  bd.setUint16(
    0x46,
    (4 << 11) | (2 << 7) | 5,
    Endian.little,
  ); // Poké Ball, Ruby, met at 5
  final m = Mon.gba(d);
  return m.bytes;
}

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
