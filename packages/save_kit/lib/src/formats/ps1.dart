/// PS1 memory cards (.mcd / .mcr / .srm, raw 128 KB): 16 blocks of 8 KB,
/// block 0 is the header and directory. Ported from the PC's Ps1Card.gd
/// and Ps1Writer.gd.
///
/// Directory frames 1..15: state (0x51 first block of a save, 0x52 middle,
/// 0x53 last; 0xA0 free; 0xA1..A3 deleted but recoverable), size, next
/// block - 1 (FFFF ends), the name (product code + file name), XOR checksum
/// in byte 0x7F. A save's first block starts "SC", its Shift-JIS title and
/// a 16×16 icon of 1 to 3 frames. The card stores no dates.
library;

import 'dart:typed_data';

import '../bytes.dart';
import '../model.dart';

abstract final class Ps1Card {
  static const size = 131072, block = 8192, frame = 128, slots = 15;
  static const stateFirst = 0x51, stateMiddle = 0x52, stateLast = 0x53;
  static const iconCount = {0x11: 1, 0x12: 2, 0x13: 3};

  static bool isCard(List<int> d) =>
      d.length == size && d[0] == 0x4D && d[1] == 0x43; // "MC"

  static MemoryCard parse(
    Uint8List data,
    String name,
    String path,
    int modified,
  ) {
    final card = MemoryCard()
      ..system = 'PS1'
      ..name = name
      ..path = path
      ..modified = modified
      ..total = slots;
    if (!isCard(data)) {
      card.error = 'not a PS1 memory card';
      return card;
    }
    var used = 0;
    for (var i = 1; i <= slots; i++) {
      final state = data[i * frame];
      if (state == stateFirst || state == stateMiddle || state == stateLast) {
        used++;
      }
      if (state == stateFirst) card.saves.add(_save(data, i, card));
    }
    card.free = slots - used;
    return card;
  }

  static CardSave _save(Uint8List data, int slot, MemoryCard card) {
    final entry = slot * frame, blk = slot * block;
    final s = CardSave()
      ..system = 'PS1'
      ..card = card
      ..slot = slot;
    s.setId(Bytes.ascii(data, entry + 10, 20));
    s.held.add(slot);
    var at = slot;
    for (var i = 0; i < slots; i++) {
      final next = Bytes.u16(data, at * frame + 8);
      if (next >= slots || s.held.contains(next + 1)) break;
      at = next + 1;
      s.held.add(at);
    }
    final stated = Bytes.u32(data, entry + 4) ~/ block;
    s.blocks = stated >= 1 && stated <= slots ? stated : s.held.length;
    s.kb = s.blocks * 8;
    s.modified = card.modified; // the card stores no dates
    if (data[blk] != 0x53 || data[blk + 1] != 0x43) return s; // "SC"
    final t = Bytes.title(data, blk + 4, 64);
    if (t.isNotEmpty) s.titleLines.add(t);
    final pal = [
      for (var i = 0; i < 16; i++) color(Bytes.u16(data, blk + 0x60 + i * 2)),
    ];
    for (var f = 0; f < (iconCount[data[blk + 2]] ?? 0); f++) {
      s.frames.add(_frame(data, blk + 0x80 + f * frame, pal));
    }
    return s;
  }

  /// 15-bit BGR; all-zero is see-through.
  static List<int> color(int v) => v == 0
      ? const [0, 0, 0, 0]
      : [
          (v & 31) * 255 ~/ 31,
          (v >> 5 & 31) * 255 ~/ 31,
          (v >> 10 & 31) * 255 ~/ 31,
          255,
        ];

  static Pixels _frame(Uint8List data, int at, List<List<int>> pal) {
    final img = Pixels(16, 16);
    var k = 0;
    for (var i = 0; i < frame; i++) {
      final v = Bytes.u8(data, at + i);
      for (final n in [v & 15, v >> 4]) {
        img.rgba.setRange(k, k + 4, pal[n]);
        k += 4;
      }
    }
    return img;
  }
}

/// Changes PS1 card images in memory (the store does the writing). A save
/// is named by its first block (1..15). Deleting only changes states
/// (51/52/53 -> A1/A2/A3), which is what makes Undelete possible.
abstract final class Ps1Writer {
  static const size = Ps1Card.size, frame = Ps1Card.frame;
  static const block = Ps1Card.block, slots = Ps1Card.slots;
  static const free = 0xA0;
  static const live = [0x51, 0x52, 0x53]; // first, middle, last
  static const gone = [0xA1, 0xA2, 0xA3];
  static const end = 0xFFFF;
  static const nameAt = 10, nameLen = 21;
  static const _brokenFirst = 16, _brokenLast = 35, _copyFrame = 63;

  static Uint8List blank() {
    final d = Uint8List(size);
    for (final f in [0, _copyFrame]) {
      d[f * frame] = 0x4D;
      d[f * frame + 1] = 0x43;
      _seal(d, f);
    }
    for (var slot = 1; slot <= slots; slot++) {
      _clear(d, slot);
    }
    for (var f = _brokenFirst; f <= _brokenLast; f++) {
      Bytes.put32(d, f * frame, 0xFFFFFFFF);
      Bytes.put16(d, f * frame + 8, end);
      _seal(d, f);
    }
    return d;
  }

  /// '' = a card a console would accept.
  static String check(Uint8List d) {
    if (!Ps1Card.isCard(d)) return 'not a PS1 memory card';
    for (var f = 0; f <= slots; f++) {
      if (d[f * frame + frame - 1] != _sum(d, f)) {
        return 'directory checksum $f is wrong';
      }
    }
    final owned = <int>{};
    final names = <String>{};
    for (final slot in saves(d)) {
      final held = chain(d, slot, live);
      if (held.isEmpty) return 'the save in block $slot is broken';
      for (final b in held) {
        if (!owned.add(b)) return 'two saves share block $b';
      }
      if (!names.add(nameKey(d, slot))) return 'two saves have the same name';
    }
    for (var slot = 1; slot <= slots; slot++) {
      if (live.contains(d[slot * frame]) && !owned.contains(slot)) {
        return 'block $slot belongs to no save';
      }
    }
    return '';
  }

  static List<int> saves(Uint8List d) => _slotsInState(d, live[0]);

  static List<int> deleted(Uint8List d) {
    if (!Ps1Card.isCard(d)) return [];
    return [
      for (final slot in _slotsInState(d, gone[0]))
        if (chain(d, slot, gone).isNotEmpty) slot,
    ];
  }

  static int freeBlocks(Uint8List d) {
    if (!Ps1Card.isCard(d)) return 0;
    var n = 0;
    for (var slot = 1; slot <= slots; slot++) {
      if (!live.contains(d[slot * frame])) n++;
    }
    return n;
  }

  /// The blocks a save holds, in order. Empty = not a whole save in that
  /// set of [states].
  static List<int> chain(Uint8List d, int slot, List<int> states) {
    if (!Ps1Card.isCard(d) ||
        slot < 1 ||
        slot > slots ||
        d[slot * frame] != states[0]) {
      return [];
    }
    final sz = Bytes.u32(d, slot * frame + 4);
    if (sz < block || sz > slots * block || sz % block != 0) return [];
    final out = [slot];
    var at = slot;
    final n = sz ~/ block;
    for (var i = 1; i < n; i++) {
      final next = Bytes.u16(d, at * frame + 8);
      if (next >= slots || out.contains(next + 1)) return [];
      at = next + 1;
      if (d[at * frame] != (i == n - 1 ? states[2] : states[1])) return [];
      out.add(at);
    }
    return Bytes.u16(d, at * frame + 8) == end ? out : [];
  }

  static CardEdit delete(Uint8List d, int slot) {
    final held = chain(d, slot, live);
    if (held.isEmpty) {
      return CardEdit.fail("That save can't be found on the card");
    }
    return CardEdit.done(_restate(d, held, live, gone));
  }

  static CardEdit undelete(Uint8List d, int slot) {
    final held = chain(d, slot, gone);
    if (held.isEmpty) {
      return CardEdit.fail("That save was written over, so it can't come back");
    }
    if (slotNamed(d, nameKey(d, slot)) > 0) {
      return CardEdit.fail('A save with that name is already on the card');
    }
    return CardEdit.done(_restate(d, held, gone, live));
  }

  /// .mcs: the first directory frame, then the blocks in order.
  static CardEdit exportSave(Uint8List d, int slot) {
    final held = chain(d, slot, live);
    if (held.isEmpty) {
      return CardEdit.fail("That save can't be found on the card");
    }
    final out = BytesBuilder(copy: false)
      ..add(d.sublist(slot * frame, (slot + 1) * frame));
    for (final b in held) {
      out.add(d.sublist(b * block, (b + 1) * block));
    }
    return CardEdit.done(out.takeBytes());
  }

  /// Copy between cards is export + import. Whether to replace a save of
  /// the same name is the caller's question.
  static CardEdit importSave(Uint8List d, Uint8List mcs) {
    if (!Ps1Card.isCard(d)) {
      return CardEdit.fail("That isn't a PS1 memory card");
    }
    final body = mcs.length - frame;
    if (body < block ||
        body > slots * block ||
        body % block != 0 ||
        mcs[0] != live[0]) {
      return CardEdit.fail("That isn't a PS1 save file");
    }
    final name = mcs.sublist(nameAt, nameAt + nameLen);
    if (slotNamed(d, _key(name)) > 0) {
      return CardEdit.fail('A save with that name is already on the card');
    }
    final count = body ~/ block;
    final freeN = freeBlocks(d);
    if (freeN < count) {
      return CardEdit.fail(
        'Not enough room: it needs $count blocks and $freeN are free',
      );
    }
    final out = Uint8List.fromList(d);
    // Never-used blocks first, so deleted saves stay recoverable longest.
    final to = <int>[];
    for (final wantedFree in [true, false]) {
      for (var slot = 1; slot <= slots; slot++) {
        final state = d[slot * frame];
        if (to.length < count &&
            !live.contains(state) &&
            (state == free) == wantedFree) {
          to.add(slot);
        }
      }
    }
    for (final slot in deleted(d)) {
      final held = chain(d, slot, gone);
      if (held.any(to.contains)) {
        // Part of it is being written over: it can't be undeleted now.
        for (final part in held) {
          _clear(out, part);
        }
      }
    }
    for (var i = 0; i < count; i++) {
      final slot = to[i];
      _clear(out, slot);
      out[slot * frame] = i == 0
          ? live[0]
          : (i == count - 1 ? live[2] : live[1]);
      Bytes.put32(out, slot * frame + 4, i == 0 ? body : 0);
      Bytes.put16(out, slot * frame + 8, i == count - 1 ? end : to[i + 1] - 1);
      if (i == 0) {
        out.setRange(
          slot * frame + nameAt,
          slot * frame + nameAt + nameLen,
          name,
        );
      }
      _seal(out, slot);
      out.setRange(
        slot * block,
        (slot + 1) * block,
        mcs.sublist(frame + i * block, frame + (i + 1) * block),
      );
    }
    return CardEdit.done(out);
  }

  static int slotNamed(Uint8List d, String key) {
    for (final slot in saves(d)) {
      if (nameKey(d, slot) == key) return slot;
    }
    return 0;
  }

  static String nameKey(Uint8List d, int slot) =>
      _key(d.sublist(slot * frame + nameAt, slot * frame + nameAt + nameLen));

  static String _key(List<int> name) => Bytes.untilNul(
    name,
    0,
    name.length,
  ).map((v) => v.toRadixString(16).padLeft(2, '0')).join();

  static List<int> _slotsInState(Uint8List d, int state) {
    if (!Ps1Card.isCard(d)) return [];
    return [
      for (var slot = 1; slot <= slots; slot++)
        if (d[slot * frame] == state) slot,
    ];
  }

  static Uint8List _restate(
    Uint8List d,
    List<int> held,
    List<int> from,
    List<int> to,
  ) {
    final out = Uint8List.fromList(d);
    for (final slot in held) {
      out[slot * frame] = to[from.indexOf(d[slot * frame])];
      _seal(out, slot);
    }
    return out;
  }

  static void _clear(Uint8List d, int slot) {
    d.fillRange(slot * frame, slot * frame + frame, 0);
    d[slot * frame] = free;
    Bytes.put16(d, slot * frame + 8, end);
    _seal(d, slot);
  }

  static int _sum(Uint8List d, int f) {
    var x = 0;
    for (var i = f * frame; i < f * frame + frame - 1; i++) {
      x ^= d[i];
    }
    return x;
  }

  static void _seal(Uint8List d, int f) =>
      d[f * frame + frame - 1] = _sum(d, f);
}
