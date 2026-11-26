/// One Pokémon in PKHeX's stored-file formats: .pk1 (Gen 1), .pk2 (Gen 2),
/// .pk3 (Gen 3), with the summary the PC's helper builds for Pokéville.
library;

import 'dart:typed_data';

import 'dex.dart';
import 'text.dart';

const int pk1Body = 44, pk1Box = 33, pk1File = 69;
const int pk2Body = 48, pk2Box = 32, pk2File = 73;
const int pk3Party = 100, pk3Stored = 80;
const int gbNameLength = 11;

/// A Pokémon. GB formats keep the party struct ([data], 44 / 48 bytes) and the
/// trainer / nickname buffers separately, as PKHeX does; Gen 3 keeps the
/// decrypted 100-byte party struct.
class Mon {
  Mon._(this.format, this.data, this.ot, this.nick, this.isEgg2);

  /// 1, 2 or 3.
  final int format;
  final Uint8List data;
  final Uint8List ot;
  final Uint8List nick;
  bool isEgg2;

  factory Mon.gb(
    int format,
    List<int> body,
    List<int> ot,
    List<int> nick, {
    bool egg = false,
  }) {
    final size = format == 1 ? pk1Body : pk2Body;
    final d = Uint8List(size)..setRange(0, body.length.clamp(0, size), body);
    return Mon._(
      format,
      d,
      Uint8List.fromList(ot),
      Uint8List.fromList(nick),
      format == 2 && egg,
    );
  }

  /// A blank GB Pokémon as PKHeX makes one: zeros, names full of 0x50.
  factory Mon.blankGb(int format) => Mon._(
    format,
    Uint8List(format == 1 ? pk1Body : pk2Body),
    Uint8List(gbNameLength)..fillRange(0, gbNameLength, gbTerminator),
    Uint8List(gbNameLength)..fillRange(0, gbNameLength, gbTerminator),
    false,
  );

  /// Gen 3 from decrypted data (80 or 100 bytes).
  factory Mon.gba(List<int> decrypted) {
    final d = Uint8List(pk3Party)
      ..setRange(0, decrypted.length.clamp(0, pk3Party), decrypted);
    return Mon._(3, d, Uint8List(0), Uint8List(0), false);
  }

  /// Reads a PKHeX file. [ext] is "pk1", "pk2" or "pk3" (with or without the
  /// dot); without it the size decides. Null if it isn't one, or is empty.
  static Mon? fromFile(List<int> bytes, {String? ext}) {
    var e = (ext ?? '').toLowerCase();
    if (e.startsWith('.')) {
      e = e.substring(1);
    }
    if (e.isEmpty) {
      e = switch (bytes.length) {
        pk1File => 'pk1',
        pk2File => 'pk2',
        pk3Stored || pk3Party => 'pk3',
        _ => '',
      };
    }
    Mon? m;
    if (e == 'pk1' && bytes.length == pk1File) {
      m = Mon.gb(
        1,
        bytes.sublist(3, 47),
        bytes.sublist(47, 58),
        bytes.sublist(58, 69),
      );
    } else if (e == 'pk2' && bytes.length == pk2File) {
      m = Mon.gb(
        2,
        bytes.sublist(3, 51),
        bytes.sublist(51, 62),
        bytes.sublist(62, 73),
        egg: bytes[1] == 0xFD,
      );
    } else if (e == 'pk3' &&
        (bytes.length == pk3Stored || bytes.length == pk3Party)) {
      final d = Uint8List.fromList(bytes);
      if (!pk3ChecksumOk(d)) {
        gen3Decrypt(d);
      }
      m = Mon.gba(d);
    }
    if (m == null || m.species == 0) {
      return null;
    }
    return m;
  }

  Mon clone() => Mon._(
    format,
    Uint8List.fromList(data),
    Uint8List.fromList(ot),
    Uint8List.fromList(nick),
    isEgg2,
  );

  String get ext => 'pk$format';
  int get generationFormat => format;

  // ------------------------------------------------------------ fields

  ByteData get _bd => ByteData.sublistView(data);

  int get speciesInternal => switch (format) {
    1 => data[0],
    2 => data[0],
    _ => _bd.getUint16(0x20, Endian.little),
  };

  int get species => switch (format) {
    1 => gen1ToNational(data[0]),
    2 => data[0],
    _ => gen3ToNational(_bd.getUint16(0x20, Endian.little)),
  };

  int get exp => switch (format) {
    1 => (data[0xE] << 16) | (data[0xF] << 8) | data[0x10],
    2 => (data[0x8] << 16) | (data[0x9] << 8) | data[0xA],
    _ => _bd.getUint32(0x24, Endian.little),
  };

  int get level => levelFor(species, exp);

  int get dv16 => format == 1
      ? (data[0x1B] << 8) | data[0x1C]
      : (data[0x15] << 8) | data[0x16];

  int get pid => format == 3 ? _bd.getUint32(0, Endian.little) : 0;
  int get tid => switch (format) {
    1 => (data[0xC] << 8) | data[0xD],
    2 => (data[6] << 8) | data[7],
    _ => _bd.getUint16(4, Endian.little),
  };
  int get sid => format == 3 ? _bd.getUint16(6, Endian.little) : 0;
  int get iv32 => _bd.getUint32(0x48, Endian.little);

  bool get isEgg => switch (format) {
    1 => false,
    2 => isEgg2,
    _ => (iv32 >> 30) & 1 == 1,
  };

  int get heldItem => switch (format) {
    1 => 0,
    2 => data[1],
    _ => _bd.getUint16(0x22, Endian.little),
  };

  /// Gen 1's catch rate byte (the Time Capsule's held item).
  int get catchRate => format == 1 ? data[7] : 0;

  List<int> get moves => switch (format) {
    1 => [data[8], data[9], data[10], data[11]],
    2 => [data[2], data[3], data[4], data[5]],
    _ => [
      for (var i = 0; i < 4; i++) _bd.getUint16(0x2C + i * 2, Endian.little),
    ],
  };

  int get language => format == 3 ? data[0x12] : 2;
  int get version =>
      format == 3 ? (_bd.getUint16(0x46, Endian.little) >> 7) & 0xF : 0;
  int get ball =>
      format == 3 ? (_bd.getUint16(0x46, Endian.little) >> 11) & 0xF : 0;

  bool get isShiny {
    if (format == 3) {
      return ((tid ^ sid) >> 3) == (((pid >> 16) ^ (pid & 0xFFFF)) >> 3);
    }
    return (dv16 & 0x2FFF) == 0x2AAA;
  }

  int get gender {
    final gv = genderRatio(species);
    switch (gv) {
      case 255:
        return 2;
      case 254:
        return 1;
      case 0:
        return 0;
    }
    if (format == 3) {
      return (pid & 0xFF) < gv ? 1 : 0;
    }
    final atk = (dv16 >> 12) & 0xF;
    return atk > (gv >> 4) ? 0 : 1;
  }

  int get form {
    if (species != 201) {
      return 0;
    }
    if (format == 3) {
      final p = pid;
      return (((p & 0x3000000) >> 18) |
              ((p & 0x30000) >> 12) |
              ((p & 0x300) >> 6) |
              (p & 0x3)) %
          28;
    }
    final d = dv16;
    final atk = (d >> 12) & 0xF,
        def = (d >> 8) & 0xF,
        spe = (d >> 4) & 0xF,
        spc = d & 0xF;
    final v =
        ((atk & 6) << 5) |
        ((def & 6) << 3) |
        ((spe & 6) << 1) |
        ((spc & 6) >> 1);
    return v ~/ 10;
  }

  int get ability => format == 3 ? gen3Ability(species, iv32 >> 31 == 1) : -1;

  String get nickname => format == 3
      ? decodeGba(data.sublist(8, 18), language: language)
      : decodeGb(nick, gen2: format == 2);
  String get otName => format == 3
      ? decodeGba(data.sublist(0x14, 0x1B), language: language)
      : decodeGb(ot, gen2: format == 2);

  bool get isNicknamed {
    if (format == 3) {
      // PKHeX compares with the species name in capitals (so an Egg's
      // "タマゴ" counts as a nickname, as Gen 2's "EGG" does).
      return nickname != gbaSpeciesName(species);
    }
    // Every byte of the nickname buffer must be what the game writes for an
    // un-nicknamed Pokémon (the name, then 0x50s).
    final expect = encodeGb(
      gbSpeciesName(species),
      gbNameLength,
      gen2: format == 2,
    );
    if (expect == null) {
      return true;
    }
    for (var i = 0; i < expect.length; i++) {
      if (expect[i] == 0xF2) {
        expect[i] = 0xE8;
      }
    }
    for (var i = 0; i < gbNameLength; i++) {
      if (nick[i] != expect[i]) {
        return true;
      }
    }
    return false;
  }

  String get itemName => switch (format) {
    1 => '',
    2 => gen2ItemName(heldItem),
    _ => gen3ItemName(heldItem),
  };

  int get generation {
    if (format < 3) {
      return format;
    }
    final v = version;
    return (v >= 1 && v <= 5) || v == 15 ? 3 : 0;
  }

  String get originName {
    if (format == 1) {
      return 'RBY';
    }
    if (format == 2) {
      return 'GSC';
    }
    return switch (version) {
      0 => 'Any',
      1 => 'Sapphire',
      2 => 'Ruby',
      3 => 'Emerald',
      4 => 'FireRed',
      5 => 'LeafGreen',
      7 => 'HeartGold',
      8 => 'SoulSilver',
      10 => 'Diamond',
      11 => 'Pearl',
      12 => 'Platinum',
      15 => 'Colosseum/XD',
      final v => '$v',
    };
  }

  /// The summary the PC's helper stores in box.json as `mon` (without the
  /// `from` / `from_save` the PC adds itself).
  Map<String, Object?> get summary {
    final s = species;
    return {
      'species': s,
      'form': form,
      'name': speciesName(s),
      'nickname': isNicknamed ? nickname : '',
      'level': level,
      'shiny': isShiny,
      'gender': gender,
      'egg': isEgg,
      'item': itemName,
      'ot': otName,
      'generation': generation,
      'format': ext,
      'origin': originName,
      'pid': pid,
      'moves': [
        for (final m in moves)
          if (m > 0 && moveName(m).isNotEmpty) moveName(m),
      ],
      if (s > 0 && s <= maxSpecies3) 'types': speciesTypeNames(s),
      if (s > 0 && s <= maxSpecies3) 'stats': speciesBaseStats(s),
      'nature': format == 3 ? natureNames[pid % 25] : '',
      'ability': format == 3 ? abilityName(ability) : '',
      'ball': ball < ballNames.length ? ballNames[ball] : '',
      'v': 3,
    };
  }

  // ------------------------------------------------------------ files

  /// The PKHeX file: a single-entry list for .pk1/.pk2 (count, species mark,
  /// 0xFF, party struct, trainer, nickname), the 80 decrypted bytes for .pk3
  /// (checksum refreshed, as PKHeX writes it).
  Uint8List get bytes {
    if (format == 3) {
      refreshChecksum3();
      return Uint8List.fromList(data.sublist(0, pk3Stored));
    }
    final body = data.length;
    final out = Uint8List(3 + body + 2 * gbNameLength);
    out[0] = 1;
    out[1] = listMark;
    out[2] = 0xFF;
    out.setRange(3, 3 + body, data);
    out.setRange(3 + body, 3 + body + gbNameLength, ot);
    out.setRange(3 + body + gbNameLength, out.length, nick);
    return out;
  }

  /// The species byte a Game Boy list holds for this Pokémon.
  int get listMark {
    if (format == 2 && isEgg2) {
      return 0xFD;
    }
    return data[0] == 0 ? 0xFF : data[0];
  }

  /// Gen 3: clears the bad-egg flag and recomputes the checksum.
  void refreshChecksum3() {
    data[0x13] &= ~1;
    _bd.setUint16(0x1C, pk3Sum(data), Endian.little);
  }

  /// Gen 3: the 80 stored bytes, encrypted as the save holds them.
  Uint8List encrypted3() {
    refreshChecksum3();
    final d = Uint8List.fromList(data.sublist(0, pk3Stored));
    gen3Encrypt(d);
    return d;
  }
}

// ------------------------------------------------------------ Gen 3 crypto

int pk3Sum(Uint8List d) {
  var sum = 0;
  for (var i = 0x20; i < pk3Stored; i += 2) {
    sum += d[i] | (d[i + 1] << 8);
  }
  return sum & 0xFFFF;
}

bool pk3ChecksumOk(Uint8List d) => pk3Sum(d) == (d[0x1C] | (d[0x1D] << 8));

// Position of block G/A/E/M in the stored order, for PID % 24.
const List<String> _orders = [
  'GAEM', 'GAME', 'GEAM', 'GEMA', 'GMAE', 'GMEA', 'AGEM', 'AGME', //
  'AEGM', 'AEMG', 'AMGE', 'AMEG', 'EGAM', 'EGMA', 'EAGM', 'EAMG',
  'EMGA', 'EMAG', 'MGAE', 'MGEA', 'MAGE', 'MAEG', 'MEGA', 'MEAG',
];

void _xor3(Uint8List d) {
  final bd = ByteData.sublistView(d);
  final key = bd.getUint32(0, Endian.little) ^ bd.getUint32(4, Endian.little);
  for (var i = 0x20; i < pk3Stored; i += 4) {
    bd.setUint32(i, bd.getUint32(i, Endian.little) ^ key, Endian.little);
  }
}

/// In place: stored (shuffled, encrypted) -> G A E M order, decrypted.
void gen3Decrypt(Uint8List d) {
  _xor3(d);
  final order =
      _orders[(d[0] | (d[1] << 8) | (d[2] << 16) | (d[3] << 24)) % 24];
  final src = Uint8List.fromList(d.sublist(0x20, pk3Stored));
  for (var i = 0; i < 4; i++) {
    final dest = 'GAEM'.indexOf(order[i]);
    d.setRange(0x20 + dest * 12, 0x20 + dest * 12 + 12, src, i * 12);
  }
}

/// In place: G A E M order, decrypted -> stored (shuffled, encrypted).
void gen3Encrypt(Uint8List d) {
  final order =
      _orders[(d[0] | (d[1] << 8) | (d[2] << 16) | (d[3] << 24)) % 24];
  final src = Uint8List.fromList(d.sublist(0x20, pk3Stored));
  for (var i = 0; i < 4; i++) {
    final from = 'GAEM'.indexOf(order[i]);
    d.setRange(0x20 + i * 12, 0x20 + i * 12 + 12, src, from * 12);
  }
  _xor3(d);
}
