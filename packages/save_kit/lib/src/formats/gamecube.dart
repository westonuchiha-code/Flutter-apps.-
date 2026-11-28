/// GameCube memory cards: reading (card images and Dolphin's folders of
/// .gci) and changing card images in memory. Ported from the PC's
/// GcCard.gd and GcWriter.gd.
///
/// 8 KB blocks: 0 header, 1-2 directory, 3-4 block table (BAT), saves from
/// 5. Big-endian throughout. A change goes into the copy that isn't
/// current, with a higher counter, as the console does it.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../bytes.dart';
import '../model.dart';
import '../pictures.dart';

/// Reads GameCube saves, from a card image or a folder of .gci files:
/// comments, date, icons, locks. Read only.
abstract final class GcCard {
  static const entrySize = 64;

  /// 1 Jan 2000.
  static const epoch = 946684800;
  static const regions = {
    'E': 'America',
    'J': 'Japan',
    'P': 'Europe',
    'D': 'Germany',
    'F': 'France',
    'I': 'Italy',
    'S': 'Spain',
    'U': 'Europe',
    'K': 'Korea',
  };
  static const noCopy = 0x08;
  static const icons = 8;
  static const pixelsCi8 = 1024;
  static const pixelsRgb = 2048;
  static const palette = 512;
  static const folderMax = 16 << 20;
  static const folderBlocks = 2043;

  /// A card image as a [MemoryCard] (filled into [card] when given).
  static MemoryCard parse(List<int> d, [MemoryCard? card]) {
    final c = card ?? MemoryCard();
    c.system = 'GC';
    if (!GcWriter.isCard(d) ||
        GcWriter.directory(d) == 0 ||
        GcWriter.blockTable(d) == 0) {
      c.error = 'damaged GameCube card';
      return c;
    }
    c.total = d.length ~/ GcWriter.block - GcWriter.firstData;
    c.free = GcWriter.freeBlocks(d);
    for (final slot in GcWriter.saves(d)) {
      final file = GcWriter.exportSave(d, slot);
      final bytes = file.ok ? file.data : GcWriter.entry(d, slot);
      final s = saveFrom(bytes, c);
      s.slot = slot;
      c.saves.add(s);
    }
    return c;
  }

  /// Dolphin's other kind of card: a folder with one .gci per save.
  static MemoryCard parseFolder(String dir, [MemoryCard? card]) {
    final c = card ?? MemoryCard();
    c.system = 'GC';
    c.isFolder = true;
    c.total = folderBlocks;
    var used = 0;
    final names = <String>[];
    try {
      for (final f in Directory(dir).listSync(followLinks: true)) {
        if (f is File) names.add(p.basename(f.path));
      }
    } on FileSystemException {
      // An unreadable folder reads as an empty one.
    }
    names.sort();
    for (final f in names) {
      if (f.startsWith('.') || p.extension(f).toLowerCase() != '.gci') {
        continue;
      }
      Uint8List bytes;
      try {
        final file = File(p.join(dir, f));
        final size = file.lengthSync();
        if (size < entrySize || size > folderMax) continue;
        bytes = file.readAsBytesSync();
      } on FileSystemException {
        continue;
      }
      final s = saveFrom(bytes, c);
      s.file = f;
      c.saves.add(s);
      used += s.blocks;
    }
    c.free = math.max(c.total - used, 0);
    // Files can repeat a name. Then every one of them says which file it
    // is, so none passes for another.
    final named = <String, int>{};
    for (final s in c.saves) {
      named[s.id] = (named[s.id] ?? 0) + 1;
    }
    for (final s in c.saves) {
      if (named[s.id]! > 1) s.id += ' [${s.file}]';
    }
    return c;
  }

  /// One save from its .gci bytes (entry + blocks).
  static CardSave saveFrom(List<int> gci, [MemoryCard? card]) {
    final s = CardSave()
      ..system = 'GC'
      ..card = card;
    final game = Bytes.ascii(gci, 0, 6);
    final name = Bytes.ascii(gci, GcWriter.nameAt, GcWriter.nameLen);
    s.id = '$game $name';
    s.serial = game;
    s.region = regions[game.length > 3 ? game[3] : ''] ?? '';
    s.copyProtected = Bytes.u8(gci, 0x34) & noCopy != 0;
    s.blocks = Bytes.be16(gci, 0x38);
    s.kb = s.blocks * 8;
    final seconds = Bytes.be32(gci, 0x28);
    if (seconds > 0) {
      final t = DateTime.fromMillisecondsSinceEpoch(
        (epoch + seconds) * 1000,
        isUtc: true,
      );
      s.created = Bytes.localTime(
        t.year,
        t.month,
        t.day,
        t.hour,
        t.minute,
        t.second,
      );
    }
    s.modified = s.created > 0 ? s.created : (card?.modified ?? 0);
    final body = gci.length > entrySize
        ? Uint8List.fromList(gci.sublist(entrySize))
        : Uint8List(0);
    final comment = Bytes.be32(gci, 0x3C);
    // Japanese games write their comments in Shift-JIS, the rest in
    // Windows-1252 ("POKéMON XD" read as Shift-JIS came out "POK餉ON").
    final japanese = gci.length > 3 && gci[3] == 0x4A; // game code's 'J'
    if (Bytes.has(body, comment, 64)) {
      for (var i = 0; i < 2; i++) {
        final line = japanese
            ? Bytes.title(body, comment + i * 32, 32)
            : Bytes.western(body, comment + i * 32, 32);
        if (line.isNotEmpty) s.titleLines.add(line);
      }
    }
    _icons(gci, body, s);
    if (s.frames.isEmpty) s.frames.add(CardPictures.standIn('GC', s.id));
    return s;
  }

  static void _icons(List<int> gci, Uint8List body, CardSave s) {
    var at = Bytes.be32(gci, 0x2C);
    if (at >= body.length) return;
    final banner = Bytes.u8(gci, 0x07) & 3;
    if (banner == 1) {
      at += 96 * 32 + palette;
    } else if (banner == 2) {
      at += 96 * 32 * 2;
    }
    final kinds = Bytes.be16(gci, 0x30);
    final delays = Bytes.be16(gci, 0x32);
    // Pixels, palette (-1 = none, -2 = the shared one after them all).
    final found = <(int, int)>[];
    for (var i = 0; i < icons; i++) {
      if ((delays >> (i * 2)) & 3 == 0) break;
      switch ((kinds >> (i * 2)) & 3) {
        case 1:
          found.add((at, -2));
          at += pixelsCi8;
        case 2:
          found.add((at, -1));
          at += pixelsRgb;
        case 3:
          found.add((at, at + pixelsCi8));
          at += pixelsCi8 + palette;
      }
    }
    for (final (pixels, pal) in found) {
      final paletteAt = pal == -2 ? at : pal;
      final size = paletteAt < 0 ? pixelsRgb : pixelsCi8;
      if (Bytes.has(body, pixels, size) &&
          (paletteAt < 0 || Bytes.has(body, paletteAt, palette))) {
        s.frames.add(CardPictures.gamecube(body, pixels, paletteAt));
      }
    }
  }
}

/// Changes GameCube card images in memory; the caller does the writing.
/// A save is named by its directory index (slot).
abstract final class GcWriter {
  static const block = 8192;
  static const mbit = 131072;

  /// Card sizes, in Mbit.
  static const sizes = [4, 8, 16, 32, 64, 128];
  static const firstData = 5;
  static const dirs = [1, 2];
  static const bats = [3, 4];
  static const slots = 127;
  static const entrySize = 64;
  static const end = 0xFFFF;
  static const dirCountAt = 0x1FFA;
  static const dirSumAt = 0x1FFC;
  static const batCountAt = 4;
  static const batFreeAt = 6;
  static const batLastAt = 8;
  static const mapAt = 0x0A;
  static const headerSumAt = 0x1FC;
  static const nameAt = 8;
  static const nameLen = 32;
  static const ticks = 40500000;

  /// 1 Jan 2000.
  static const epoch = 946684800;

  /// These games sign their saves with the card's serial, so a plain copy
  /// wouldn't load on another card.
  static const tiedToCard = [
    'GFZE',
    'GFZJ',
    'GFZP',
    'GPOE',
    'GPOJ',
    'GPOP',
    'GPSE',
    'GPSJ',
    'GPSP',
  ];

  /// A newly formatted card of [mbitSize] Mbit; empty for a size no card
  /// has. [now] (Unix seconds) and [random] are for tests.
  static Uint8List blank([
    int mbitSize = 16,
    bool japanese = false,
    int? now,
    math.Random? random,
  ]) {
    if (!sizes.contains(mbitSize)) return Uint8List(0);
    final d = Uint8List(mbitSize * mbit)..fillRange(0, mbitSize * mbit, 0xFF);
    d.fillRange(0, 0x26, 0);
    final rng = random ?? math.Random();
    for (var i = 0; i < 12; i++) {
      d[i] = rng.nextInt(256);
    }
    final seconds = now ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final t = math.max(seconds - epoch, 0) * ticks;
    for (var i = 0; i < 8; i++) {
      d[0x0C + i] = t >> (56 - i * 8) & 0xFF;
    }
    Bytes.putBe16(d, 0x22, mbitSize);
    Bytes.putBe16(d, 0x24, japanese ? 1 : 0);
    _stamp(d, headerSumAt, sum(d, 0, headerSumAt));
    for (final b in dirs) {
      Bytes.putBe16(d, b * block + dirCountAt, 0);
      _sealDir(d, b);
    }
    for (final b in bats) {
      d.fillRange(b * block, (b + 1) * block, 0);
      Bytes.putBe16(d, b * block + batFreeAt, d.length ~/ block - firstData);
      Bytes.putBe16(d, b * block + batLastAt, firstData - 1);
      _sealBat(d, b);
    }
    return d;
  }

  static bool isCard(List<int> d) {
    if (d.length % mbit != 0 || !sizes.contains(d.length ~/ mbit)) {
      return false;
    }
    return Bytes.be16(d, 0x22) == d.length ~/ mbit &&
        _stamped(d, headerSumAt, sum(d, 0, headerSumAt));
  }

  /// '' = a card a console would accept.
  static String check(List<int> d) {
    if (!isCard(d)) return 'not a GameCube memory card';
    if (directory(d) == 0 || blockTable(d) == 0) {
      return 'both copies of its directory are damaged';
    }
    final owner = <int>{};
    final names = <String>{};
    for (final slot in saves(d)) {
      final held = chain(d, slot);
      if (held.isEmpty) return 'save $slot is broken';
      for (final b in held) {
        if (!owner.add(b)) return 'two saves share block $b';
      }
      if (!names.add(keyOf(entry(d, slot)))) {
        return 'two saves have the same name';
      }
    }
    return '';
  }

  /// The current directory's block, 0 = both copies damaged.
  static int directory(List<int> d) {
    var best = 0;
    for (final b in dirs) {
      final at = b * block;
      if (!Bytes.has(d, at, block)) continue;
      if (!_stamped(d, at + dirSumAt, sum(d, at, dirSumAt))) continue;
      if (best == 0 ||
          signed16(d, at + dirCountAt) >
              signed16(d, best * block + dirCountAt)) {
        best = b;
      }
    }
    return best;
  }

  /// The current block table's block, 0 = both copies damaged.
  static int blockTable(List<int> d) {
    var best = 0;
    for (final b in bats) {
      final at = b * block;
      if (!Bytes.has(d, at, block)) continue;
      if (!_stamped(d, at, sum(d, at + 4, block - 4))) continue;
      if (best == 0 ||
          signed16(d, at + batCountAt) >
              signed16(d, best * block + batCountAt)) {
        best = b;
      }
    }
    return best;
  }

  /// The slots in use.
  static List<int> saves(List<int> d) {
    final out = <int>[];
    if (!isCard(d)) return out;
    final table = directory(d);
    if (table == 0) return out;
    for (var slot = 0; slot < slots; slot++) {
      if (Bytes.u32(d, table * block + slot * entrySize) != 0xFFFFFFFF) {
        out.add(slot);
      }
    }
    return out;
  }

  /// The slot's 64-byte directory entry.
  static Uint8List entry(List<int> d, int slot) {
    final at = directory(d) * block + slot * entrySize;
    return _slice(d, at, at + entrySize);
  }

  /// The save's blocks in order; empty = not a whole save.
  static List<int> chain(List<int> d, int slot) {
    const none = <int>[];
    if (!saves(d).contains(slot)) return none;
    final bat = blockTable(d);
    if (bat == 0) return none;
    final e = entry(d, slot);
    final count = Bytes.be16(e, 0x38);
    final blocks = d.length ~/ block;
    if (count < 1 || count > blocks - firstData) return none;
    final out = <int>[];
    final seen = <int>{};
    var b = Bytes.be16(e, 0x36);
    for (var i = 0; i < count; i++) {
      if (b < firstData || b >= blocks || !seen.add(b)) return none;
      out.add(b);
      b = _link(d, bat, b);
    }
    return b == end ? out : none;
  }

  static int freeBlocks(List<int> d) {
    if (!isCard(d)) return 0;
    final bat = blockTable(d);
    if (bat == 0) return 0;
    var n = 0;
    for (var b = firstData; b < d.length ~/ block; b++) {
      if (_link(d, bat, b) == 0) n++;
    }
    return n;
  }

  /// The card's own 12-byte serial (saves of [tiedToCard] games are signed
  /// with it).
  static Uint8List serial(List<int> d) => _slice(d, 0, 12);

  static CardEdit delete(List<int> d, int slot) {
    final held = chain(d, slot);
    if (held.isEmpty) {
      return CardEdit.fail("That save can't be found on the card");
    }
    final out = Uint8List.fromList(d);
    final table = _nextDir(out);
    final bat = _nextBat(out);
    final at = table * block + slot * entrySize;
    out.fillRange(at, at + entrySize, 0xFF);
    for (final b in held) {
      _setLink(out, bat, b, 0);
    }
    Bytes.putBe16(out, bat * block + batFreeAt, freeBlocks(d) + held.length);
    _sealDir(out, table);
    _sealBat(out, bat);
    return CardEdit.done(out);
  }

  /// .gci: the directory entry, then the blocks in order.
  static CardEdit exportSave(List<int> d, int slot) {
    final held = chain(d, slot);
    if (held.isEmpty) {
      return CardEdit.fail("That save can't be found on the card");
    }
    final out = BytesBuilder(copy: false)..add(entry(d, slot));
    for (final b in held) {
      out.add(_slice(d, b * block, (b + 1) * block));
    }
    return CardEdit.done(out.toBytes());
  }

  /// Copy between cards is export + import. [fromSerial] = the card it
  /// came off, when that's known.
  static CardEdit importSave(
    List<int> d,
    List<int> gci, [
    List<int> fromSerial = const [],
  ]) {
    if (!isCard(d)) return CardEdit.fail("That isn't a GameCube memory card");
    final table = directory(d);
    final bat = blockTable(d);
    if (table == 0 || bat == 0) {
      return CardEdit.fail("That card's directory is damaged");
    }
    final body = gci.length - entrySize;
    if (body < block ||
        body % block != 0 ||
        Bytes.u32(gci, 0) == 0xFFFFFFFF ||
        Bytes.be16(gci, 0x38) != body ~/ block) {
      return CardEdit.fail("That isn't a GameCube save file");
    }
    if (tiedToCard.contains(Bytes.ascii(gci, 0, 4)) &&
        !Bytes.same(fromSerial, serial(d))) {
      return CardEdit.fail(
        "This game locks its save to the card it was made on, so a copy wouldn't load",
      );
    }
    final key = keyOf(gci);
    var slot = -1;
    for (var i = 0; i < slots; i++) {
      final at = table * block + i * entrySize;
      if (Bytes.u32(d, at) == 0xFFFFFFFF) {
        if (slot < 0) slot = i;
      } else if (keyOf(_slice(d, at, at + entrySize)) == key) {
        return CardEdit.fail('A save with that name is already on the card');
      }
    }
    if (slot < 0) {
      return CardEdit.fail(
        'A GameCube card holds 127 saves, and this one is full',
      );
    }
    final count = body ~/ block;
    final free = freeBlocks(d);
    if (free < count) {
      return CardEdit.fail(
        'Not enough room: it needs $count blocks and $free are free',
      );
    }
    final blocks = d.length ~/ block;
    final to = <int>[];
    // Carry on after the last one handed out.
    var b = Bytes.be16(d, bat * block + batLastAt);
    for (var i = 0; i < blocks; i++) {
      b += 1;
      if (b < firstData || b >= blocks) b = firstData;
      if (_link(d, bat, b) == 0) {
        to.add(b);
        if (to.length == count) break;
      }
    }
    if (to.length != count) {
      return CardEdit.fail("That card's free space doesn't add up");
    }
    final out = Uint8List.fromList(d);
    final newTable = _nextDir(out);
    final newBat = _nextBat(out);
    for (var i = 0; i < count; i++) {
      out.setRange(
        to[i] * block,
        (to[i] + 1) * block,
        gci,
        entrySize + i * block,
      );
      _setLink(out, newBat, to[i], i == count - 1 ? end : to[i + 1]);
    }
    final at = newTable * block + slot * entrySize;
    out.setRange(at, at + entrySize, gci);
    Bytes.putBe16(out, at + 0x36, to[0]);
    Bytes.putBe16(out, newBat * block + batFreeAt, free - count);
    Bytes.putBe16(out, newBat * block + batLastAt, to[count - 1]);
    _sealDir(out, newTable);
    _sealBat(out, newBat);
    return CardEdit.done(out);
  }

  /// Game, maker and file name together make a save the same save.
  static String keyOf(List<int> e) =>
      _hex(_slice(e, 0, 6)) + _hex(Bytes.untilNul(e, nameAt, nameLen));

  /// The card's two sums over 16-bit words: plain and inverted, with FFFF
  /// written as 0.
  static (int, int) sum(List<int> d, int from, int length) {
    var a = 0, z = 0;
    for (var i = from; i < from + length; i += 2) {
      final v = Bytes.be16(d, i);
      a += v;
      z += v ^ 0xFFFF;
    }
    a &= 0xFFFF;
    z &= 0xFFFF;
    return (a == 0xFFFF ? 0 : a, z == 0xFFFF ? 0 : z);
  }

  static int signed16(List<int> b, int at) {
    final v = Bytes.be16(b, at);
    return v >= 0x8000 ? v - 0x10000 : v;
  }

  static bool _stamped(List<int> d, int at, (int, int) sums) =>
      Bytes.be16(d, at) == sums.$1 && Bytes.be16(d, at + 2) == sums.$2;

  static void _stamp(List<int> d, int at, (int, int) sums) {
    Bytes.putBe16(d, at, sums.$1);
    Bytes.putBe16(d, at + 2, sums.$2);
  }

  static void _sealDir(List<int> d, int b) =>
      _stamp(d, b * block + dirSumAt, sum(d, b * block, dirSumAt));

  static void _sealBat(List<int> d, int b) =>
      _stamp(d, b * block, sum(d, b * block + 4, block - 4));

  /// Copies the current directory over the other one, one count newer,
  /// and returns that block.
  static int _nextDir(Uint8List d) {
    final now = directory(d);
    final next = now == dirs[0] ? dirs[1] : dirs[0];
    d.setRange(next * block, (next + 1) * block, d, now * block);
    Bytes.putBe16(
      d,
      next * block + dirCountAt,
      signed16(d, now * block + dirCountAt) + 1,
    );
    return next;
  }

  static int _nextBat(Uint8List d) {
    final now = blockTable(d);
    final next = now == bats[0] ? bats[1] : bats[0];
    d.setRange(next * block, (next + 1) * block, d, now * block);
    Bytes.putBe16(
      d,
      next * block + batCountAt,
      signed16(d, now * block + batCountAt) + 1,
    );
    return next;
  }

  static int _link(List<int> d, int bat, int b) =>
      Bytes.be16(d, bat * block + mapAt + (b - firstData) * 2);

  static void _setLink(List<int> d, int bat, int b, int to) =>
      Bytes.putBe16(d, bat * block + mapAt + (b - firstData) * 2, to);
}

/// [from, to) clamped to the data, like Godot's slice.
Uint8List _slice(List<int> b, int from, int to) {
  final s = from.clamp(0, b.length);
  final e = to.clamp(s, b.length);
  return Uint8List.fromList(b.sublist(s, e));
}

String _hex(List<int> b) {
  final sb = StringBuffer();
  for (final v in b) {
    sb.write(v.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}
