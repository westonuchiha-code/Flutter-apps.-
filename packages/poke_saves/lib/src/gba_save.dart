/// Gen 3 GBA saves (Ruby/Sapphire, Emerald, FireRed/LeafGreen; western
/// versions). Like PKHeX's SAV3: the newest of the two 14-sector save slots
/// is read into its three blocks (small, large, PC storage), changed there,
/// and written back into the same slot with fresh sector checksums.
library;

import 'dart:typed_data';

import 'dex.dart';
import 'mon.dart';
import 'text.dart';

enum GbaGame { rs, emerald, frlg }

class GbaSave {
  GbaSave._(this.data, this.game, this.activeSlot) {
    _readSectors();
  }

  final Uint8List data;
  final GbaGame game;
  final int activeSlot;

  static const int sector = 0x1000;
  static const int used = 0xF80;
  static const int mainSize = 14 * sector;
  static const int boxCount = 14;
  static const int boxSlots = 30;

  final Uint8List small = Uint8List(used);
  final Uint8List large = Uint8List(4 * used);
  final Uint8List storage = Uint8List(9 * used);

  bool get halfSize => data.length < 0x20000;

  static bool _allSectors(Uint8List d, int slot) {
    var bits = 0;
    for (
      var ofs = slot * mainSize;
      ofs < (slot + 1) * mainSize;
      ofs += sector
    ) {
      final id = d[ofs + 0xFF4] | (d[ofs + 0xFF5] << 8);
      if (id >= 14) {
        return false;
      }
      bits |= 1 << id;
    }
    return bits == 0x3FFF;
  }

  static int _sector0(Uint8List d, int slot) {
    for (
      var ofs = slot * mainSize;
      ofs < (slot + 1) * mainSize;
      ofs += sector
    ) {
      if (d[ofs + 0xFF4] == 0 && d[ofs + 0xFF5] == 0) {
        return ofs;
      }
    }
    return slot * mainSize;
  }

  static int _u32(Uint8List d, int at) =>
      ByteData.sublistView(d).getUint32(at, Endian.little);

  static GbaSave? detect(Uint8List bytes) {
    if (bytes.length != 0x20000 && bytes.length != 0x10000) {
      return null;
    }
    final slots = bytes.length ~/ 0x10000;
    final v0 = _allSectors(bytes, 0);
    final v1 = slots > 1 && _allSectors(bytes, 1);
    if (!v0 && !v1) {
      return null;
    }
    int active;
    if (!v0) {
      active = 1;
    } else if (!v1) {
      active = 0;
    } else {
      final c1 = _u32(bytes, _sector0(bytes, 0) + 0xFFC),
          c2 = _u32(bytes, _sector0(bytes, 1) + 0xFFC);
      if (c1 == 0xFFFFFFFF && c2 != 0xFFFFFFFE) {
        active = 1;
      } else if (c2 == 0xFFFFFFFF && c1 != 0xFFFFFFFE) {
        active = 0;
      } else {
        active = c1 < c2 ? 1 : 0;
      }
    }
    // Which game: the word at small block 0xAC (PKHeX's rule).
    final s0 = _sector0(bytes, v0 ? 0 : 1);
    final code = _u32(bytes, s0 + 0xAC);
    GbaGame game;
    if (code == 1) {
      game = GbaGame.frlg;
    } else if (code == 0) {
      game = GbaGame.rs;
    } else {
      var more = false;
      for (var i = s0 + 0x890; i < s0 + 0xF2C; i++) {
        if (bytes[i] != 0) {
          more = true;
          break;
        }
      }
      game = more ? GbaGame.emerald : GbaGame.rs;
    }
    final save = GbaSave._(Uint8List.fromList(bytes), game, active);
    if (save.japanese) {
      return null; // Japanese saves are left out
    }
    return save;
  }

  Uint8List _chunk(int id) => id >= 5
      ? Uint8List.sublistView(storage, (id - 5) * used, (id - 4) * used)
      : id >= 1
      ? Uint8List.sublistView(large, (id - 1) * used, id * used)
      : small;

  void _readSectors() {
    for (
      var ofs = activeSlot * mainSize;
      ofs < (activeSlot + 1) * mainSize;
      ofs += sector
    ) {
      final id = data[ofs + 0xFF4] | (data[ofs + 0xFF5] << 8);
      _chunk(id).setRange(0, used, data, ofs);
    }
  }

  void _writeSectors() {
    for (
      var ofs = activeSlot * mainSize;
      ofs < (activeSlot + 1) * mainSize;
      ofs += sector
    ) {
      final id = data[ofs + 0xFF4] | (data[ofs + 0xFF5] << 8);
      data.setRange(ofs, ofs + used, _chunk(id));
    }
  }

  static int sectorSum(Uint8List d, int at) {
    final bd = ByteData.sublistView(d);
    var sum = 0;
    for (var i = 0; i < used; i += 4) {
      sum = (sum + bd.getUint32(at + i, Endian.little)) & 0xFFFFFFFF;
    }
    return ((sum >> 16) + (sum & 0xFFFF)) & 0xFFFF;
  }

  bool _uninitialized(int at) {
    for (var i = at; i < at + sector; i++) {
      if (data[i] != 0 && data[i] != 0xFF) {
        return false;
      }
    }
    return true;
  }

  // ------------------------------------------------------------ the game

  bool get japanese => small[6] == 0 && small[7] == 0;

  String get trainer => decodeGba(small.sublist(0, 7));
  int get tid => small[0x0A] | (small[0x0B] << 8);
  int get sid => small[0x0C] | (small[0x0D] << 8);

  int get currentBox => storage[0];

  String boxName(int box) {
    final at = 4 + pk3Stored * boxCount * boxSlots + box * 9;
    return decodeGba(storage.sublist(at, at + 9));
  }

  int get maxItem => switch (game) {
    GbaGame.rs => 346,
    GbaGame.frlg => 374,
    GbaGame.emerald => 376,
  };

  int get _partyCountAt => game == GbaGame.frlg ? 0x34 : 0x234;
  int get partyCount => large[_partyCountAt];
  int get _seen2 => switch (game) {
    GbaGame.rs => 0x938,
    GbaGame.frlg => 0x5F8,
    GbaGame.emerald => 0x988,
  };
  int get _seen3 => switch (game) {
    GbaGame.rs => 0x3A8C,
    GbaGame.frlg => 0x3A18,
    GbaGame.emerald => 0x3B24,
  };

  int _boxOffset(int box, int slot) => 4 + (box * boxSlots + slot) * pk3Stored;

  /// Reads a slot as PKHeX does: decrypt, and decrypt again if the checksum
  /// still doesn't match.
  static Mon readStored(List<int> stored) {
    final d = Uint8List.fromList(stored);
    gen3Decrypt(d);
    if (!pk3ChecksumOk(d)) {
      gen3Decrypt(d);
    }
    return Mon.gba(d);
  }

  Mon boxMon(int box, int slot) {
    final at = _boxOffset(box, slot);
    return readStored(storage.sublist(at, at + pk3Stored));
  }

  Mon partyMon(int i) {
    final at = (game == GbaGame.frlg ? 0x38 : 0x238) + i * pk3Party;
    final d = Uint8List.fromList(large.sublist(at, at + pk3Party));
    final stored = Uint8List.fromList(d.sublist(0, pk3Stored));
    gen3Decrypt(stored);
    if (!pk3ChecksumOk(stored)) {
      gen3Decrypt(stored);
    }
    d.setRange(0, pk3Stored, stored);
    return Mon.gba(d);
  }

  /// PKHeX's SetBoxSlot for Gen 3: Pokédex flags, then the encrypted bytes.
  void setBox(int box, int slot, Mon? pk) {
    final at = _boxOffset(box, slot);
    if (pk == null) {
      storage.fillRange(at, at + pk3Stored, 0);
      return;
    }
    _setDex(pk);
    storage.setRange(at, at + pk3Stored, pk.encrypted3());
  }

  bool _getFlag(Uint8List d, int at, int bit) =>
      (d[at + (bit >> 3)] >> (bit & 7)) & 1 == 1;
  void _setFlag(Uint8List d, int at, int bit) =>
      d[at + (bit >> 3)] |= 1 << (bit & 7);

  void _setDex(Mon pk) {
    final s = pk.species;
    if (s == 0 || s > maxSpecies3 || pk.isEgg) {
      return;
    }
    final bit = s - 1;
    final seen = _getFlag(small, 0x18 + 0x44, bit);
    if (!seen && (s == 201 || s == 327)) {
      final at = s == 201 ? 0x1C : 0x20;
      ByteData.sublistView(small).setUint32(at, pk.pid, Endian.little);
    }
    _setFlag(small, 0x18 + 0x10, bit);
    _setFlag(small, 0x18 + 0x44, bit);
    _setFlag(large, _seen2, bit);
    _setFlag(large, _seen3, bit);
  }

  Uint8List write() {
    _writeSectors();
    for (
      var ofs = activeSlot * mainSize;
      ofs < (activeSlot + 1) * mainSize;
      ofs += sector
    ) {
      final c = sectorSum(data, ofs);
      data[ofs + 0xFF6] = c & 0xFF;
      data[ofs + 0xFF7] = c >> 8;
    }
    if (!halfSize) {
      for (var i = 0; i < 4; i++) {
        final at = 0x1C000 + i * sector;
        if (_uninitialized(at)) {
          continue;
        }
        final c = sectorSum(data, at);
        data[at + 0xFF4] = c & 0xFF;
        data[at + 0xFF5] = c >> 8;
      }
    }
    return Uint8List.fromList(data);
  }

  String check() {
    final bad = <String>[];
    var n = 0;
    for (
      var ofs = activeSlot * mainSize;
      ofs < (activeSlot + 1) * mainSize;
      ofs += sector, n++
    ) {
      if (sectorSum(data, ofs) !=
          (data[ofs + 0xFF6] | (data[ofs + 0xFF7] << 8))) {
        bad.add('sector $n is wrong');
      }
    }
    if (!halfSize) {
      const names = [
        'Hall of Fame 1',
        'Hall of Fame 2',
        'e-Reader data',
        'extra data',
      ];
      for (var i = 0; i < 4; i++) {
        final at = 0x1C000 + i * sector;
        if (!_uninitialized(at) &&
            sectorSum(data, at) !=
                (data[at + 0xFF4] | (data[at + 0xFF5] << 8))) {
          bad.add('${names[i]} is wrong');
        }
      }
    }
    return bad.join(', ');
  }
}
