/// Saves and Pokémon files built from scratch, for tests (here and in the
/// apps that use this package): a blank Gen 1 (Red/Blue) save, a blank
/// Crystal save, a blank Gen 3 save of any game code, and a Bulbasaur
/// (.pk1), a Chikorita (.pk2) and a Treecko (.pk3).
library;

import 'dart:typed_data';

import 'src/gb_save.dart';
import 'src/gba_save.dart';
import 'src/mon.dart';
import 'src/text.dart';

/// [s] in Game Boy text (11 bytes).
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

/// A Game Boy [save] with the PKHeX file [pk] added to the end of its party
/// (tests and screenshots: the built saves start with an empty party).
Uint8List withPartyMon(Uint8List save, Uint8List pk, {String? ext}) {
  final gb = GbSave.detect(save);
  final m = Mon.fromFile(pk, ext: ext);
  if (gb == null || m == null) {
    throw ArgumentError('a Game Boy save and a .pk1 / .pk2 file');
  }
  final n = gb.party.where((s) => s.present).length;
  if (n >= 6) {
    throw StateError('the party is full');
  }
  gb.setSlot(gb.party[n], m, box: false);
  return gb.write();
}
