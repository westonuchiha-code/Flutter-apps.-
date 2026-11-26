/// Gen 1 (Red/Blue/Yellow) and Gen 2 (Gold/Silver/Crystal) saves, English and
/// the other western versions. Works like PKHeX's SAV1/SAV2: every box and the
/// party are unpacked into single-entry slots; writing packs them back into
/// the games' lists (no gaps), mirrors the current box and fixes checksums.
library;

import 'dart:typed_data';

import 'dex.dart';
import 'mon.dart';
import 'text.dart';

/// One unpacked slot: the list's species mark plus the party-sized body and
/// the two name buffers (what PKHeX keeps per slot).
class GbSlot {
  GbSlot(this.mark, this.body, this.ot, this.nick);
  GbSlot.empty(int bodySize)
    : mark = 0,
      body = Uint8List(bodySize),
      ot = Uint8List(gbNameLength),
      nick = Uint8List(gbNameLength);

  int mark;
  Uint8List body;
  Uint8List ot;
  Uint8List nick;

  bool get present => mark != 0 && mark != 0xFF;
}

class GbSave {
  GbSave._(this.data, this.gen, this.crystal) {
    _unpack();
  }

  final Uint8List data;
  final int gen;
  final bool crystal;

  static const int size = 0x8000;
  static const int capacity = 20;

  int get boxCount => gen == 1 ? 12 : 14;
  int get bodySize => gen == 1 ? pk1Body : pk2Body;
  int get boxBodySize => gen == 1 ? pk1Box : pk2Box;
  int get boxListSize => (gbNameLength * 2 + boxBodySize + 1) * capacity + 2;
  int get partyListSize => (gbNameLength * 2 + bodySize + 1) * 6 + 2;

  // Offsets (international).
  int get otOffset => gen == 1 ? 0x2598 : 0x200B;
  int get tidOffset => gen == 1 ? 0x2605 : 0x2009;
  int get partyOffset => gen == 1 ? 0x2F2C : (crystal ? 0x2865 : 0x288A);
  int get currentBoxOffset => gen == 1 ? 0x30C0 : (crystal ? 0x2D10 : 0x2D6C);
  int get currentBoxIndexOffset =>
      gen == 1 ? 0x284C : (crystal ? 0x2700 : 0x2724);
  int get boxNamesOffset => crystal ? 0x2703 : 0x2727;
  int get dexCaught => gen == 1 ? 0x25A3 : (crystal ? 0x2A27 : 0x2A4C);
  int get dexSeen => gen == 1 ? 0x25B6 : (crystal ? 0x2A47 : 0x2A6C);

  late final List<List<GbSlot>> boxes;
  late final List<GbSlot> party;

  /// Detects an international Gen 1 or Gen 2 save (PKHeX's list checks, in
  /// its order). Japanese and Korean saves are left out.
  static GbSave? detect(Uint8List bytes) {
    if (bytes.length != size) {
      return null;
    }
    bool list(int at, int max) {
      final n = bytes[at];
      return n <= max && bytes[at + 1 + n] == 0xFF;
    }

    // Gen 1: Japanese layout first (as PKHeX does), then international.
    if (list(0x2ED5, 30) && list(0x302D, 30)) {
      return null;
    }
    if (list(0x2F2C, 20) && list(0x30C0, 20)) {
      return GbSave._(Uint8List.fromList(bytes), 1, false);
    }
    if (list(0x288A, 20) && list(0x2D6C, 20)) {
      return GbSave._(Uint8List.fromList(bytes), 2, false);
    }
    if (list(0x2865, 20) && list(0x2D10, 20)) {
      return GbSave._(Uint8List.fromList(bytes), 2, true);
    }
    return null;
  }

  // ------------------------------------------------------------ the game

  bool get yellow {
    final starter = data[0x29C3];
    if (starter != 0) {
      return starter == 0x54;
    }
    return data[0x271C] != 0;
  }

  String get trainer =>
      decodeGb(data.sublist(otOffset, otOffset + 7), gen2: gen == 2);
  int get tid => (data[tidOffset] << 8) | data[tidOffset + 1];

  int get currentBox => gen == 1
      ? data[currentBoxIndexOffset] & 0x7F
      : data[currentBoxIndexOffset];
  set currentBox(int v) {
    if (gen == 1) {
      data[currentBoxIndexOffset] =
          (data[currentBoxIndexOffset] & 0x80) | (v & 0x7F);
    } else {
      data[currentBoxIndexOffset] = v;
    }
  }

  /// Gen 1: set once the game has written its box banks (first box change).
  bool get boxesInitialized => (data[currentBoxIndexOffset] & 0x80) != 0;
  set boxesInitialized(bool v) => data[currentBoxIndexOffset] =
      (data[currentBoxIndexOffset] & 0x7F) | (v ? 0x80 : 0);

  String boxName(int box) {
    if (gen == 1) {
      return 'Box ${box + 1}';
    }
    final at = boxNamesOffset + box * 9;
    return inflateGen2Ligatures(decodeGb(data.sublist(at, at + 9), gen2: true));
  }

  int boxRawOffset(int box) {
    final split = gen == 1 ? 6 : 7;
    final step = gen == 1 ? boxListSize : boxListSize + 2;
    return box < split ? 0x4000 + box * step : 0x6000 + (box - split) * step;
  }

  // ------------------------------------------------------------ slots

  void _unpack() {
    boxes = [
      for (var b = 0; b < boxCount; b++)
        [for (var s = 0; s < capacity; s++) GbSlot.empty(bodySize)],
    ];
    party = [for (var s = 0; s < 6; s++) GbSlot.empty(bodySize)];
    final current = currentBox;
    for (var b = 0; b < boxCount; b++) {
      if (gen == 1 && (!boxesInitialized || b == current)) {
        continue;
      }
      _unpackList(boxRawOffset(b), boxes[b], capacity, false);
    }
    if (gen == 1 && current < boxCount) {
      _unpackList(currentBoxOffset, boxes[current], capacity, false);
    }
    _unpackList(partyOffset, party, 6, true);
  }

  void _unpackList(int at, List<GbSlot> slots, int cap, bool isParty) {
    final len = isParty ? bodySize : boxBodySize;
    var body = at + 1 + cap + 1;
    var ot = body + cap * len;
    var nick = ot + cap * gbNameLength;
    final count = data[at] < cap ? data[at] : cap;
    for (var i = 0; i < count; i++) {
      final s = slots[i];
      s.mark = data[at + 1 + i];
      s.body = Uint8List(bodySize)..setRange(0, len, data, body);
      s.ot = Uint8List.fromList(data.sublist(ot, ot + gbNameLength));
      s.nick = Uint8List.fromList(data.sublist(nick, nick + gbNameLength));
      body += len;
      ot += gbNameLength;
      nick += gbNameLength;
    }
  }

  Mon monAt(GbSlot s) => Mon.gb(gen, s.body, s.ot, s.nick, egg: s.mark == 0xFD);

  int get partyCount => data[partyOffset];

  /// What PKHeX's SetBoxSlot does for these games: Pokédex flags, Gen 1's
  /// "box level", then the slot holds the Pokémon as a single-entry list.
  void setSlot(GbSlot slot, Mon pk) {
    _setDex(pk);
    if (gen == 1) {
      pk.data[3] =
          pk.level; // PKHeX: Stat_LevelBox = CurrentLevel (1 for a blank)
    }
    slot.mark = pk.listMark;
    slot.body = Uint8List.fromList(pk.data);
    slot.ot = Uint8List.fromList(pk.ot);
    slot.nick = Uint8List.fromList(pk.nick);
  }

  void _setDex(Mon pk) {
    final s = pk.species;
    if (s == 0 || s > (gen == 1 ? maxSpecies1 : maxSpecies2)) {
      return;
    }
    if (gen == 2 && pk.isEgg) {
      return;
    }
    void flag(int region) {
      final bit = s - 1;
      data[region + (bit >> 3)] |= 1 << (bit & 7);
    }

    flag(dexCaught);
    if (gen == 2 && s == 201) {
      // PKHeX gives every Unown letter so the Pokédex can't crash.
      for (var i = 1; i <= 26; i++) {
        data[dexSeen + 0x1F + i] = i;
      }
      if (data[dexSeen + 0x1F + 28] == 0) {
        data[dexSeen + 0x1F + 28] = 1;
      }
    }
    flag(dexSeen);
  }

  // ------------------------------------------------------------ writing

  /// Packs everything back and fixes the checksums (PKHeX's GetFinalData).
  Uint8List write() {
    if (gen == 1) {
      var init = boxesInitialized;
      var current = currentBox;
      if (!init) {
        var content = false;
        for (var b = 0; b < boxCount; b++) {
          if (b != current && boxes[b].any((s) => s.present)) {
            content = true;
          }
        }
        if (content) {
          boxesInitialized = init = true;
        } else {
          currentBox = current = 0;
        }
      }
      for (var b = 0; b < boxCount; b++) {
        final at = boxRawOffset(b);
        final written = _merge(boxes[b], at, capacity, false, init);
        if (b != current) {
          continue;
        }
        if (written) {
          data.setRange(
            currentBoxOffset,
            currentBoxOffset + boxListSize,
            data,
            at,
          );
        } else {
          _merge(boxes[b], currentBoxOffset, capacity, false, init);
        }
      }
      _merge(party, partyOffset, 6, true, true);
      var sum = 0;
      for (var i = 0x2598; i < 0x3523; i++) {
        sum += data[i];
      }
      data[0x3523] = ~sum & 0xFF;
    } else {
      final current = currentBox;
      for (var b = 0; b < boxCount; b++) {
        final at = boxRawOffset(b);
        final written = _merge(boxes[b], at, capacity, false, true);
        if (written && b == current) {
          data.setRange(
            currentBoxOffset,
            currentBoxOffset + boxListSize,
            data,
            at,
          );
        }
      }
      _merge(party, partyOffset, 6, true, true);
      final sum = gen2Checksum(data, crystal);
      final p1 = crystal ? 0x2D0D : 0x2D69, p2 = crystal ? 0x1F0D : 0x7E6D;
      for (final p in [p1, p2]) {
        data[p] = sum & 0xFF;
        data[p + 1] = sum >> 8;
      }
      if (crystal) {
        data.setRange(0x1209, 0x1209 + 0xB7A, data, 0x2009);
      } else {
        for (final (from, to, dest) in gsBackup) {
          data.setRange(dest, dest + (to - from), data, from);
        }
      }
    }
    return Uint8List.fromList(data);
  }

  /// GS keeps its backup copy in five pieces: (from, to exclusive, copy at).
  static const gsBackup = [
    (0x2009, 0x222F, 0x15C7),
    (0x222F, 0x23D9, 0x3D69),
    (0x23D9, 0x2856, 0x0C6B),
    (0x2856, 0x288A, 0x7E39),
    (0x288A, 0x2D69, 0x10E8),
  ];

  static int gen2Checksum(Uint8List d, bool crystal) {
    var sum = 0;
    final end = crystal ? 0x2B82 : 0x2D68;
    for (var i = 0x2009; i <= end; i++) {
      sum += d[i];
    }
    return sum & 0xFFFF;
  }

  // PKHeX's MergeSingles: Pokémon first in slot order, then the empty slots'
  // leftovers; the species list capped with 0xFF.
  bool _merge(
    List<GbSlot> slots,
    int at,
    int cap,
    bool isParty,
    bool destInitialized,
  ) {
    final count = slots.where((s) => s.present).length;
    final len = isParty ? bodySize : boxBodySize;
    final listSize = isParty ? partyListSize : boxListSize;
    if (count == 0) {
      var allZero = true;
      for (var i = at; i < at + listSize; i++) {
        if (data[i] != 0) {
          allZero = false;
          break;
        }
      }
      if (!destInitialized || allZero) {
        return false;
      }
    }
    data[at] = count;
    var ctr = 0, empty = count;
    final start = at + 1 + cap + 1;
    for (final s in slots) {
      final mark = s.mark == 0 ? 0xFF : s.mark;
      final i = s.present ? ctr++ : empty++;
      data[at + 1 + i] = mark;
      data.setRange(start + i * len, start + i * len + len, s.body);
      final ot = start + cap * len + i * gbNameLength;
      data.setRange(ot, ot + gbNameLength, s.ot);
      final nick = start + cap * len + cap * gbNameLength + i * gbNameLength;
      data.setRange(nick, nick + gbNameLength, s.nick);
    }
    data[at + 1 + cap] = 0xFF;
    return true;
  }

  // ------------------------------------------------------------ checks

  /// '' when the checksums PKHeX checks are right.
  String check() {
    if (gen == 1) {
      var sum = 0;
      for (var i = 0x2598; i < 0x3523; i++) {
        sum += data[i];
      }
      return data[0x3523] == (~sum & 0xFF) ? '' : 'the main checksum is wrong';
    }
    final sum = gen2Checksum(data, crystal);
    final p1 = crystal ? 0x2D0D : 0x2D69, p2 = crystal ? 0x1F0D : 0x7E6D;
    final problems = <String>[
      if ((data[p1] | (data[p1 + 1] << 8)) != sum) 'checksum 1 is wrong',
      if ((data[p2] | (data[p2 + 1] << 8)) != sum) 'checksum 2 is wrong',
    ];
    return problems.join(', ');
  }
}
