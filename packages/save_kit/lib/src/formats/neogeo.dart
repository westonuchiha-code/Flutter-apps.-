/// Neo Geo memory cards: a cartridge system's 2 KB card and the Neo Geo
/// CD's 8 KB one (up to 16 KB), bare (Geolith, MAME, Neo Geo CD), inside a
/// MiSTer save (cabinet RAM, then the card, the two bytes of every word
/// swapped), or on every odd byte of a padded file. Ported from the PC's
/// NeoWriter.gd and the Neo Geo part of PlainCards.gd.
///
/// Blocks of 64: the header (size word at 0x0A, two table checksums at
/// 0x0D/0x0E, the "NEO-GEO" magic at 0x20), then one 4-byte directory
/// entry per block (save number within its game, the game's NGH number,
/// first block), then the block table (one byte per block: next block,
/// 0 free, 1 last, 2 reserved) and its mirror. Each checksum is the byte
/// sum of exactly that table. 2 KB: 0 header, 1-2 directory, 3 table,
/// 4 mirror, saves from 5. 8 KB: 1-8, 9-10, 11-12, saves from 13.
///
/// The PC checked this against 7 real cards, but its notes say Neo Geo
/// writing was inferred, not proven on a real console.
library;

import 'dart:typed_data';

import '../bytes.dart';
import '../model.dart';
import '../pictures.dart';

/// Changes Neo Geo memory cards in memory; nothing here touches a disk. A
/// save is named by its directory index.
abstract final class NeoWriter {
  /// A cartridge system's card.
  static const size = 2048;
  static const sizeMax = 16384;
  static const cdSize = 8192;

  /// A MiSTer save: cabinet RAM, then the card, every word's bytes swapped.
  static const mister = 73728;
  static const misterAt = 0x10000;
  static const block = 64;
  static const dirAt = 0x40;
  static const entry = 4;

  /// Twice the card's length, big-endian.
  static const sizeAt = 0x0A;
  static const sum1At = 0x0D;
  static const sum2At = 0x0E;
  static const magicAt = 0x20;
  static const magic = [
    0x4e, 0x40, 0x45, 0x44, 0x4f, 0x48, 0x2d, 0x4c, //
    0x47, 0x50, 0x45, 0x54, 0x4f, 0x58, 0x80, 0x5c,
  ];
  static const free = 0;
  static const end = 1;
  static const reserved = 2;
  static const empty = 0xFF;

  /// Saves per game.
  static const subs = 16;
  static const titleLen = 20;

  /// Odd-byte files: twice a 2 KB card, or 128 KB.
  static const _oddSizes = [size * 2, 0x20000];

  /// A new, formatted card; empty when [bytes] isn't a card's size.
  /// [region]: 0 Japan, 1 USA, 2 Europe.
  static Uint8List blank([int region = 1, int bytes = size]) {
    if (!goodSize(bytes)) return Uint8List(0);
    final d = Uint8List(bytes);
    d[sizeAt] = bytes * 2 >> 8;
    d.setAll(magicAt, magic);
    d[0x30] = region.clamp(0, 2);
    for (var slot = 0; slot < blocksOf(d); slot++) {
      d[dirAt + slot * entry] = empty;
    }
    final first = firstData(d);
    for (var b = 0; b < first; b++) {
      d[fat1(d) + b] = reserved;
    }
    // An erased block reads as twice its own address.
    for (var at = first * block; at < bytes; at += 2) {
      d[at] = at * 2 >> 8 & 0xFF;
      d[at + 1] = at * 2 & 0xFF;
    }
    _seal(d);
    return d;
  }

  static bool goodSize(int bytes) =>
      bytes >= size && bytes <= sizeMax && bytes % size == 0;

  static int blocksOf(List<int> d) => d.length ~/ block;

  static int fat1(List<int> d) =>
      (1 + (blocksOf(d) * entry / block).ceil()) * block;

  static int fat2(List<int> d) =>
      fat1(d) + (blocksOf(d) / block).ceil() * block;

  static int firstData(List<int> d) =>
      fat2(d) ~/ block + (blocksOf(d) / block).ceil();

  /// The card's own bytes: bare, inside a MiSTer save, or on every odd
  /// byte only. Empty = not a Neo Geo card.
  static Uint8List plain(Uint8List file) {
    if (isCard(file)) return file;
    var out = Uint8List(0);
    if (file.length == mister) {
      out = Uint8List(file.length - misterAt);
      for (var i = 0; i + 1 < out.length; i += 2) {
        out[i] = file[misterAt + i + 1];
        out[i + 1] = file[misterAt + i];
      }
      // The core only reaches the first 2 KB unless it's a CD system's card.
      final cd = Bytes.be16(out, sizeAt) == cdSize * 2;
      out = Uint8List.fromList(out.sublist(0, cd ? cdSize : size));
    } else if (_oddSizes.contains(file.length)) {
      out = Uint8List(size);
      for (var i = 0; i < size; i++) {
        out[i] = file[i * 2 + 1];
      }
    }
    return isCard(out) ? out : Uint8List(0);
  }

  /// The changed card in the file's own shape. Empty = it doesn't fit.
  static Uint8List packed(Uint8List file, Uint8List card) {
    if (file.length == card.length) return card;
    if (!goodSize(card.length)) return Uint8List(0);
    final out = Uint8List.fromList(file);
    if (file.length == mister && card.length <= cdSize) {
      for (var i = 0; i < card.length; i += 2) {
        out[misterAt + i + 1] = card[i];
        out[misterAt + i] = card[i + 1];
      }
      return out;
    }
    if (!_oddSizes.contains(file.length) || card.length != size) {
      return Uint8List(0);
    }
    for (var i = 0; i < size; i++) {
      out[i * 2 + 1] = card[i];
    }
    return out;
  }

  static bool isCard(List<int> d) {
    if (!goodSize(d.length)) return false;
    // The bytes between the letters differ from card to card.
    for (var i = 0; i < magic.length; i += 2) {
      if (d[magicAt + i] != magic[i]) return false;
    }
    // A bigger image only counts when its size word agrees, or the tables
    // would be read from the wrong place.
    return d.length == size || Bytes.be16(d, sizeAt) == d.length * 2;
  }

  /// '' = a card that holds together.
  static String check(Uint8List d) {
    if (!isCard(d)) return 'not a formatted Neo Geo card';
    final fat = fatAt(d);
    if (fat == 0) return 'both copies of its block table are damaged';
    for (var b = 0; b < firstData(d); b++) {
      if (d[fat + b] != reserved) {
        return "its block table doesn't fit its size";
      }
    }
    final owner = <int>{};
    final names = <String>{};
    for (final slot in saves(d)) {
      final held = chain(d, slot);
      if (held.isEmpty) return 'save $slot is broken';
      for (final b in held) {
        if (!owner.add(b)) return 'two saves share block $b';
      }
      if (!names.add(keyOf(Uint8List.sublistView(d, dirAt + slot * entry)))) {
        return 'two saves have the same game and number';
      }
    }
    return '';
  }

  /// The table to trust: the first, else its mirror, else 0.
  static int fatAt(Uint8List d) {
    if (!goodSize(d.length)) return 0;
    if (_sum(d, fat1(d)) == d[sum1At]) return fat1(d);
    return _sum(d, fat2(d)) == d[sum2At] ? fat2(d) : 0;
  }

  /// Directory slots holding a save (its number within its game; FF =
  /// free).
  static List<int> saves(Uint8List d) {
    if (!isCard(d)) return const [];
    return [
      for (var slot = 0; slot < blocksOf(d); slot++)
        if (d[dirAt + slot * entry] < subs) slot,
    ];
  }

  /// The save's blocks in order. Empty = not a whole save.
  static List<int> chain(Uint8List d, int slot) {
    if (!saves(d).contains(slot)) return const [];
    final fat = fatAt(d);
    if (fat == 0) return const [];
    final first = firstData(d), total = blocksOf(d);
    final out = <int>[];
    var b = d[dirAt + slot * entry + 3];
    while (b >= first && b < total && !out.contains(b)) {
      out.add(b);
      b = d[fat + b];
    }
    return b == end ? out : const [];
  }

  static List<int> freeList(Uint8List d) {
    if (!isCard(d)) return const [];
    final fat = fatAt(d);
    if (fat == 0) return const [];
    final top = blocksOf(d) < 256 ? blocksOf(d) : 256;
    return [
      for (var b = firstData(d); b < top; b++)
        if (d[fat + b] == free) b,
    ];
  }

  /// The save's own title: Shift-JIS, the first 20 bytes of its data.
  static String title(Uint8List d, int slot) {
    final held = chain(d, slot);
    return held.isEmpty ? '' : Bytes.title(d, held[0] * block, titleLen);
  }

  static CardEdit delete(Uint8List d, int slot) {
    final held = chain(d, slot);
    if (held.isEmpty) {
      return CardEdit.fail("That save can't be found on the card");
    }
    final out = _workingCopy(d);
    final fat = fat1(out);
    for (final b in held) {
      out[fat + b] = free;
    }
    out[dirAt + slot * entry] = empty;
    _seal(out);
    return CardEdit.done(out);
  }

  /// No standard file exists for one Neo Geo save, so: its 4-byte
  /// directory entry (first block 0), then its blocks in order.
  static CardEdit exportSave(Uint8List d, int slot) {
    final held = chain(d, slot);
    if (held.isEmpty) {
      return CardEdit.fail("That save can't be found on the card");
    }
    final out = Uint8List(entry + held.length * block);
    out.setRange(0, entry, d, dirAt + slot * entry);
    out[3] = 0;
    for (var i = 0; i < held.length; i++) {
      out.setRange(
        entry + i * block,
        entry + (i + 1) * block,
        d,
        held[i] * block,
      );
    }
    return CardEdit.done(out);
  }

  static CardEdit importSave(Uint8List d, Uint8List file) {
    if (!isCard(d) || fatAt(d) == 0) {
      return CardEdit.fail('That Neo Geo card is damaged');
    }
    final body = file.length - entry;
    if (body < block || body % block != 0 || file[0] >= subs) {
      return CardEdit.fail("That isn't a Neo Geo save file");
    }
    final key = keyOf(file);
    var slot = -1;
    for (var i = 0; i < blocksOf(d); i++) {
      final at = dirAt + i * entry;
      if (d[at] >= subs) {
        if (slot < 0) slot = i;
      } else if (keyOf(Uint8List.sublistView(d, at)) == key) {
        return CardEdit.fail('That save is already on the card');
      }
    }
    if (slot < 0) return CardEdit.fail("That card can't list any more saves");
    final count = body ~/ block;
    final room = freeList(d);
    if (room.length < count) {
      return CardEdit.fail(
        'Not enough room: it needs $count blocks and ${room.length} are free',
      );
    }
    final out = _workingCopy(d);
    final fat = fat1(out);
    for (var i = 0; i < count; i++) {
      out.setRange(
        room[i] * block,
        (room[i] + 1) * block,
        file,
        entry + i * block,
      );
      out[fat + room[i]] = i == count - 1 ? end : room[i + 1];
    }
    out.setRange(dirAt + slot * entry, dirAt + slot * entry + 3, file);
    out[dirAt + slot * entry + 3] = room[0];
    _seal(out);
    return CardEdit.done(out);
  }

  /// Save number + the game's NGH number.
  static String keyOf(List<int> entryBytes) =>
      entryBytes.take(3).map((v) => v.toRadixString(16).padLeft(2, '0')).join();

  /// The save on [d] with the same game and number as [file], or -1.
  static int saveNamed(Uint8List d, Uint8List file) {
    final key = keyOf(file);
    for (final slot in saves(d)) {
      if (keyOf(Uint8List.sublistView(d, dirAt + slot * entry)) == key) {
        return slot;
      }
    }
    return -1;
  }

  static Uint8List _workingCopy(Uint8List d) {
    final out = Uint8List.fromList(d);
    final from = fatAt(d);
    if (from == fat2(d)) {
      out.setRange(fat1(d), fat1(d) + blocksOf(d), d, from);
    }
    return out;
  }

  /// One table byte per block, and not a byte more.
  static int _sum(Uint8List d, int at) {
    var n = 0;
    for (var i = 0; i < blocksOf(d); i++) {
      n += d[at + i];
    }
    return n & 0xFF;
  }

  static void _seal(Uint8List d) {
    final a = fat1(d), b = fat2(d);
    d.setRange(b, b + blocksOf(d), d, a);
    d[sum1At] = _sum(d, a);
    d[sum2At] = d[sum1At];
  }
}

/// Reads a Neo Geo card into a [MemoryCard]. Read only.
abstract final class NeoCard {
  /// [d] is the card's own bytes ([NeoWriter.plain]).
  static MemoryCard parse(Uint8List d, MemoryCard card) {
    card.system = 'NEO GEO';
    if (!NeoWriter.isCard(d) || NeoWriter.fatAt(d) == 0) {
      card.error = 'damaged Neo Geo card';
      return card;
    }
    card.total = NeoWriter.blocksOf(d) - NeoWriter.firstData(d);
    card.free = NeoWriter.freeList(d).length;
    for (final slot in NeoWriter.saves(d)) {
      final at = NeoWriter.dirAt + slot * NeoWriter.entry;
      final s = CardSave()
        ..system = 'NEO GEO'
        ..card = card
        ..slot = slot;
      s.serial =
          'NGH-${Bytes.be16(d, at + 1).toRadixString(16).toUpperCase().padLeft(3, '0')}';
      s.id = '${s.serial} #${d[at] + 1}';
      final t = NeoWriter.title(d, slot);
      if (t.isNotEmpty) s.titleLines.add(t);
      s.held.addAll(NeoWriter.chain(d, slot));
      s.blocks = s.held.length;
      s.kb = (s.blocks * NeoWriter.block / 1024).ceil();
      s.modified = card.modified; // the card stores no dates
      s.frames.add(CardPictures.standIn('NEO GEO', s.id));
      card.saves.add(s);
    }
    return card;
  }
}
