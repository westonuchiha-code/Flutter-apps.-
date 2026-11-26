/// Dreamcast VMUs: reading saves (descriptions, date, animated icon) and
/// changing card images in memory. Ported from the PC's VmuCard.gd and
/// VmuWriter.gd.
///
/// 256 blocks of 512: 255 root, 254 FAT, 253 down to 241 directory, saves
/// in 0..199. Little-endian. A save's header CRC is never enforced: plenty
/// of real saves get it wrong.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../bytes.dart';
import '../model.dart';
import '../pictures.dart';

/// Reads a Dreamcast VMU: each save's descriptions, date and animated
/// icon. Read only.
abstract final class VmuCard {
  /// The VMU's own picture, not a game's save.
  static const iconData = 'ICONDATA_VMS';
  static const iconBytes = 512;

  static MemoryCard parse(List<int> d, [MemoryCard? card]) {
    final c = card ?? MemoryCard();
    c.system = 'DC';
    if (!VmuWriter.isCard(d)) {
      c.error = 'not a formatted VMU';
      return c;
    }
    c.total = VmuWriter.user;
    c.free = VmuWriter.freeBlocks(d);
    for (final slot in VmuWriter.saves(d)) {
      c.saves.add(_save(d, slot, c));
    }
    return c;
  }

  static CardSave _save(List<int> d, int slot, MemoryCard card) {
    final e = VmuWriter.entryAt(slot);
    final s = CardSave()
      ..system = 'DC'
      ..card = card
      ..slot = slot;
    s.id = Bytes.ascii(d, e + VmuWriter.nameAt, VmuWriter.nameLen).trim();
    s.copyProtected = Bytes.u8(d, e + 1) == 0xFF;
    s.created = date(d, e + 0x10);
    s.modified = s.created > 0 ? s.created : card.modified;
    final held = VmuWriter.chain(d, slot);
    s.held.addAll(held);
    s.blocks = math.max(held.length, Bytes.u16(d, e + 0x18));
    s.kb = (s.blocks / 2).ceil();
    if (held.isEmpty || s.id == iconData) {
      if (s.id == iconData) s.titleLines.add("The VMU's own picture");
      s.frames.add(CardPictures.standIn('DC', s.id));
      return s;
    }
    final body = BytesBuilder(copy: false);
    for (final b in held) {
      body.add(d.sublist(b * VmuWriter.block, (b + 1) * VmuWriter.block));
    }
    final bytes = body.toBytes();
    final head = Bytes.u16(d, e + 0x1A) * VmuWriter.block;
    final longText = Bytes.title(bytes, head + 0x10, 32);
    final shortText = Bytes.title(bytes, head, 16);
    for (final line in [longText, shortText]) {
      if (line.isNotEmpty && !s.titleLines.contains(line)) {
        s.titleLines.add(line);
      }
    }
    final count = math.min(Bytes.u16(bytes, head + 0x40), 3);
    for (var i = 0; i < count; i++) {
      final at = head + 0x80 + i * iconBytes;
      if (Bytes.has(bytes, at, iconBytes)) {
        s.frames.add(CardPictures.dreamcast(bytes, at, head + 0x60));
      }
    }
    if (s.frames.isEmpty) s.frames.add(CardPictures.standIn('DC', s.id));
    return s;
  }

  /// A directory entry's BCD date (century, year, month, day, hour,
  /// minute, second), in the player's own time. 0 = not a date.
  static int date(List<int> d, int at) {
    final v = <int>[];
    for (var i = 0; i < 7; i++) {
      final b = Bytes.u8(d, at + i);
      if (b & 15 > 9 || b >> 4 > 9) return 0;
      v.add((b >> 4) * 10 + (b & 15));
    }
    return Bytes.localTime(v[0] * 100 + v[1], v[2], v[3], v[4], v[5], v[6]);
  }
}

/// Changes Dreamcast VMU images in memory; the caller does the writing. A
/// save is named by its directory index (slot).
abstract final class VmuWriter {
  static const size = 131072;
  static const block = 512;
  static const entrySize = 32;
  static const root = 255;
  static const fat = 254;
  static const dirFirst = 253;
  static const dirBlocks = 13;
  static const user = 200;
  static const slots = dirBlocks * 16;
  static const free = 0xFFFC;
  static const end = 0xFFFA;
  static const data = 0x33;
  static const game = 0xCC;
  static const nameAt = 4;
  static const nameLen = 12;
  static const vmi = 108;
  static const vmiGame = 2;
  static const vmiProtect = 1;

  /// Root +10 (custom colour) and +40 (sizes and where everything lives),
  /// as the real cards have them.
  static const look = [0x01, 0xff, 0xff, 0xff, 0x64];
  static const layout = [
    0xff, 0x00, 0x00, 0x00, 0xff, 0x00, 0xfe, 0x00, //
    0x01, 0x00, 0xfd, 0x00, 0x0d, 0x00, 0x05, 0x00,
    0xc8, 0x00, 0x1f, 0x00, 0x00, 0x00, 0x80, 0x00,
  ];

  /// A newly formatted VMU. [now] (Unix seconds) is for tests.
  static Uint8List blank([int? now]) {
    final d = Uint8List(size);
    final r = root * block;
    d.fillRange(r, r + 16, 0x55);
    d.setAll(r + 0x10, look);
    d.setAll(
      r + 0x30,
      _date(now ?? DateTime.now().millisecondsSinceEpoch ~/ 1000),
    );
    d.setAll(r + 0x40, layout);
    for (var b = 0; b < 256; b++) {
      _setNext(d, b, free);
    }
    for (var b = dirFirst - dirBlocks + 2; b <= dirFirst; b++) {
      _setNext(d, b, b - 1);
    }
    for (final b in [dirFirst - dirBlocks + 1, fat, root]) {
      _setNext(d, b, end);
    }
    return d;
  }

  static bool isCard(List<int> d) {
    if (d.length != size) return false;
    for (var i = 0; i < 16; i++) {
      if (d[root * block + i] != 0x55) return false;
    }
    return true;
  }

  /// '' = a card a console would accept.
  static String check(List<int> d) {
    if (!isCard(d)) return 'not a formatted VMU';
    const at = root * block;
    const wanted = [
      (0x46, fat),
      (0x48, 1),
      (0x4A, dirFirst),
      (0x4C, dirBlocks),
      (0x50, user),
    ];
    for (final (off, v) in wanted) {
      if (Bytes.u16(d, at + off) != v) return 'an unusual layout';
    }
    final owner = <int>{};
    final names = <String>{};
    for (final slot in saves(d)) {
      final held = chain(d, slot);
      if (held.isEmpty) return 'save $slot is broken';
      for (final b in held) {
        if (!owner.add(b)) return 'two saves share block $b';
      }
      if (!names.add(nameKey(d, slot))) return 'two saves have the same name';
    }
    return '';
  }

  static bool _used(int type) => type == data || type == game;

  /// The slots in use.
  static List<int> saves(List<int> d) {
    final out = <int>[];
    if (!isCard(d)) return out;
    for (var slot = 0; slot < slots; slot++) {
      if (_used(d[entryAt(slot)])) out.add(slot);
    }
    return out;
  }

  static int freeBlocks(List<int> d) {
    if (!isCard(d)) return 0;
    var n = 0;
    for (var b = 0; b < user; b++) {
      if (nextBlock(d, b) == free) n++;
    }
    return n;
  }

  /// Where a slot's 32-byte directory entry sits in the card.
  static int entryAt(int slot) =>
      (dirFirst - slot ~/ 16) * block + slot % 16 * entrySize;

  static int nextBlock(List<int> d, int b) => Bytes.u16(d, fat * block + b * 2);

  /// The save's blocks in order; empty = not a whole save.
  static List<int> chain(List<int> d, int slot) {
    const none = <int>[];
    if (!isCard(d) || slot < 0 || slot >= slots) return none;
    final e = entryAt(slot);
    if (!_used(d[e])) return none;
    final count = Bytes.u16(d, e + 0x18);
    if (count < 1 || count > user) return none;
    final out = <int>[];
    final seen = <int>{};
    var b = Bytes.u16(d, e + 2);
    for (var i = 0; i < count; i++) {
      if (b >= user || !seen.add(b)) return none;
      out.add(b);
      b = nextBlock(d, b);
    }
    return b == end ? out : none;
  }

  static CardEdit delete(List<int> d, int slot) {
    final held = chain(d, slot);
    if (held.isEmpty) {
      return CardEdit.fail("That save can't be found on the card");
    }
    final out = Uint8List.fromList(d);
    for (final b in held) {
      _setNext(out, b, free);
    }
    final e = entryAt(slot);
    out.fillRange(e, e + entrySize, 0);
    return CardEdit.done(out);
  }

  /// .dci: the directory entry, then the blocks with every four bytes
  /// turned round.
  static CardEdit exportSave(List<int> d, int slot) {
    final held = chain(d, slot);
    if (held.isEmpty) {
      return CardEdit.fail("That save can't be found on the card");
    }
    final e = entryAt(slot);
    final out = BytesBuilder(copy: false)..add(d.sublist(e, e + entrySize));
    for (final b in held) {
      out.add(turned(d.sublist(b * block, (b + 1) * block)));
    }
    return CardEdit.done(out.toBytes());
  }

  /// Copy between cards is export + import. Whether to replace a save of
  /// the same name is the caller's question.
  static CardEdit importSave(List<int> d, List<int> dci) {
    if (!isCard(d)) return CardEdit.fail("That isn't a formatted VMU");
    final body = dci.length - entrySize;
    if (body < block || body % block != 0 || !_used(dci[0])) {
      return CardEdit.fail("That isn't a Dreamcast save file");
    }
    final count = body ~/ block;
    if (count != Bytes.u16(dci, 0x18)) {
      return CardEdit.fail('That save file is the wrong size');
    }
    final key = _hex(dci.sublist(nameAt, nameAt + nameLen));
    var slot = -1;
    for (var i = 0; i < slots; i++) {
      if (_used(d[entryAt(i)])) {
        if (nameKey(d, i) == key) {
          return CardEdit.fail('A save with that name is already on the card');
        }
      } else if (slot < 0) {
        slot = i;
      }
    }
    if (slot < 0) return CardEdit.fail("That card can't list any more saves");
    final room = freeBlocks(d);
    if (room < count) {
      return CardEdit.fail(
        'Not enough room: it needs $count blocks and $room are free',
      );
    }
    final to = <int>[];
    if (dci[0] == game) {
      // A VMU game runs from the card, so it has to sit in one piece from
      // block 0.
      for (var b = 0; b < count; b++) {
        if (nextBlock(d, b) != free) {
          return CardEdit.fail(
            'A VMU game needs the first $count blocks, and something is in them',
          );
        }
        to.add(b);
      }
    } else {
      for (var b = user - 1; b >= 0 && to.length < count; b--) {
        if (nextBlock(d, b) == free) to.add(b);
      }
    }
    final out = Uint8List.fromList(d);
    final bytes = turned(dci.sublist(entrySize));
    for (var i = 0; i < count; i++) {
      out.setRange(to[i] * block, (to[i] + 1) * block, bytes, i * block);
      _setNext(out, to[i], i == count - 1 ? end : to[i + 1]);
    }
    final at = entryAt(slot);
    out.setRange(at, at + entrySize, dci);
    Bytes.put16(out, at + 2, to[0]);
    return CardEdit.done(out);
  }

  /// A .vmi + .vms pair (how saves are shared online) as a .dci.
  static CardEdit fromVmi(List<int> vmiBytes, List<int> vms) {
    if (vmiBytes.length != vmi ||
        vms.isEmpty ||
        vms.length % block != 0 ||
        vms.length > user * block) {
      return CardEdit.fail("That isn't a VMI and VMS pair");
    }
    if (Bytes.u32(vmiBytes, 0x68) != vms.length) {
      return CardEdit.fail('That VMI belongs to a different VMS');
    }
    final mode = Bytes.u16(vmiBytes, 0x64);
    final e = Uint8List(entrySize);
    e[0] = mode & vmiGame != 0 ? game : data;
    e[1] = mode & vmiProtect != 0 ? 0xFF : 0;
    e.setRange(nameAt, nameAt + nameLen, vmiBytes, 0x58);
    final year = Bytes.u16(vmiBytes, 0x44);
    e.setAll(0x10, [
      _bcd(year ~/ 100),
      _bcd(year % 100),
      _bcd(vmiBytes[0x46]),
      _bcd(vmiBytes[0x47]),
      _bcd(vmiBytes[0x48]),
      _bcd(vmiBytes[0x49]),
      _bcd(vmiBytes[0x4A]),
      vmiBytes[0x4B] % 7,
    ]);
    Bytes.put16(e, 0x18, vms.length ~/ block);
    Bytes.put16(e, 0x1A, e[0] == game ? 1 : 0);
    return CardEdit.done(
      (BytesBuilder(copy: false)
            ..add(e)
            ..add(turned(vms)))
          .toBytes(),
    );
  }

  static String nameKey(List<int> d, int slot) {
    final e = entryAt(slot);
    return _hex(d.sublist(e + nameAt, e + nameAt + nameLen));
  }

  /// Every four bytes turned round (a .dci's body); a short tail stays.
  static Uint8List turned(List<int> b) {
    final out = Uint8List.fromList(b);
    for (var i = 0; i + 3 < b.length; i += 4) {
      out[i] = b[i + 3];
      out[i + 1] = b[i + 2];
      out[i + 2] = b[i + 1];
      out[i + 3] = b[i];
    }
    return out;
  }

  static void _setNext(List<int> d, int b, int to) =>
      Bytes.put16(d, fat * block + b * 2, to);

  static int _bcd(int v) => (v ~/ 10 % 10) << 4 | v % 10;

  /// The root block's BCD date, from Unix seconds read as UTC (as the PC
  /// version does); the weekday has Monday = 0.
  static List<int> _date(int when) {
    final t = DateTime.fromMillisecondsSinceEpoch(when * 1000, isUtc: true);
    return [
      _bcd(t.year ~/ 100),
      _bcd(t.year % 100),
      _bcd(t.month),
      _bcd(t.day),
      _bcd(t.hour),
      _bcd(t.minute),
      _bcd(t.second),
      t.weekday - 1,
    ];
  }
}

String _hex(List<int> b) {
  final sb = StringBuffer();
  for (final v in b) {
    sb.write(v.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}
