/// Saturn backup memory: internal (32 KB in 64-byte blocks) and the
/// cartridge (512 KB in 512-byte blocks), bare (.bkr / .bcr / .srm),
/// byte-expanded as MiSTer writes it (every byte padded to two, the card's
/// on the odd ones), or gzipped (Beetle Saturn's .bcr). Ported from the
/// PC's SaturnWriter.gd and the Saturn part of PlainCards.gd; internal
/// memory was checked there against 9 real images, the cartridge follows
/// the same rules.
///
/// Blocks 0-1 hold "BackUpRam Format". Every used block starts with a
/// 4-byte tag (0x80 000000 for a save's first block, 0 for the rest). The
/// first block holds the name (+4, 11 bytes), language (+0F), comment
/// (+10, 10 bytes), minutes since 1980 (+1A), data length (+1E), then from
/// +22 the list of the save's other blocks (u16s ending in 0), with the
/// data running on after the list, into the blocks it names. A save is
/// named by its first block.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../bytes.dart';
import '../model.dart';
import '../pictures.dart';

/// One save as [SaturnWriter.save] finds it.
class SaturnSave {
  SaturnSave({
    required this.blocks,
    required this.data,
    required this.key,
    required this.name,
    required this.language,
    required this.comment,
    required this.minutes,
  });

  /// Its blocks, the first one first.
  final List<int> blocks;
  final Uint8List data;

  /// What makes two saves the same save: the name, up to a NUL.
  final String key;

  /// 11 bytes.
  final Uint8List name;

  /// 0 Japanese, 1 English, 2 French, 3 German, 4 Spanish, 5 Italian.
  final int language;

  /// 10 bytes, Shift-JIS.
  final Uint8List comment;

  /// Since 1 Jan 1980, the player's own clock.
  final int minutes;
}

/// Changes Saturn backup memory in memory; nothing here touches a disk.
abstract final class SaturnWriter {
  static const internal = 32768;
  static const cart = 524288;
  static const magic = 'BackUpRam Format';

  /// First byte of a save's first block.
  static const tag = 0x80;
  static const listAt = 0x22;
  static const firstData = 2;

  /// A .bup's header.
  static const bup = 64;
  static const nameLen = 11;
  static const commentLen = 10;

  /// No gzipped card unpacks to more.
  static const unpackedMax = 1 << 20;

  static final _magic = ascii.encode(magic);

  static Uint8List blank([int size = internal]) {
    final d = Uint8List(size);
    for (var i = 0; i < blockSize(size); i++) {
      d[i] = _magic[i % _magic.length];
    }
    return d;
  }

  static int blockSize(int size) => size == internal ? 64 : 512;

  /// The card's own bytes, whether the file pads them or not. Empty = not
  /// Saturn memory.
  static Uint8List plain(Uint8List file) {
    if (isCard(file)) return file;
    if (file.length != internal * 2 && file.length != cart * 2) {
      return Uint8List(0);
    }
    for (var i = 0; i < _magic.length; i++) {
      if (file[i * 2 + 1] != _magic[i]) return Uint8List(0);
    }
    final out = Uint8List(file.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = file[i * 2 + 1];
    }
    return out;
  }

  /// The changed bytes in the file's own shape: its padding bytes stay as
  /// they were. Empty = it doesn't fit that file.
  static Uint8List packed(Uint8List file, Uint8List card) {
    if (file.length == card.length) return card;
    if (file.length != card.length * 2) return Uint8List(0);
    final out = Uint8List.fromList(file);
    for (var i = 0; i < card.length; i++) {
      out[i * 2 + 1] = card[i];
    }
    return out;
  }

  /// Is this a gzip stream (Beetle Saturn's cartridge file)?
  static bool isGzip(List<int> file) =>
      file.length >= 2 && file[0] == 0x1F && file[1] == 0x8B;

  /// A gzipped file's card ([plain]), or empty when it isn't one (or
  /// unpacks to more than [unpackedMax]).
  static Uint8List gunzip(Uint8List file) {
    if (!isGzip(file)) return Uint8List(0);
    try {
      final inner = const GZipDecoder().decodeBytes(file);
      if (inner.length > unpackedMax) return Uint8List(0);
      return plain(Uint8List.fromList(inner));
    } catch (_) {
      return Uint8List(0);
    }
  }

  static Uint8List gzip(Uint8List card) =>
      Uint8List.fromList(const GZipEncoder().encodeBytes(card));

  static bool isCard(List<int> d) {
    if (d.length != internal && d.length != cart) return false;
    for (var i = 0; i < _magic.length; i++) {
      if (d[i] != _magic[i]) return false;
    }
    return true;
  }

  /// '' = memory a Saturn would accept.
  static String check(Uint8List d) {
    if (!isCard(d)) return 'not Saturn backup memory';
    final size = blockSize(d.length);
    final owner = <int>{};
    final names = <String>{};
    for (final first in saves(d)) {
      final s = save(d, first);
      if (s == null) return 'the save in block $first is broken';
      for (final b in s.blocks) {
        if (owner.contains(b)) return 'two saves share block $b';
        if (b != first && Bytes.u32(d, b * size) != 0) {
          return 'block $b belongs to two saves';
        }
        owner.add(b);
      }
      if (!names.add(s.key)) return 'two saves have the same name';
    }
    return '';
  }

  /// Every block that starts a save.
  static List<int> saves(Uint8List d) {
    if (!isCard(d)) return const [];
    final size = blockSize(d.length);
    return [
      for (var b = firstData; b < d.length ~/ size; b++)
        if (d[b * size] == tag &&
            d[b * size + 1] == 0 &&
            d[b * size + 2] == 0 &&
            d[b * size + 3] == 0)
          b,
    ];
  }

  /// The save starting at block [first], or null when it's broken.
  static SaturnSave? save(Uint8List d, int first) {
    if (!isCard(d)) return null;
    final size = blockSize(d.length);
    final count = d.length ~/ size;
    if (first < firstData || first >= count || d[first * size] != tag) {
      return null;
    }
    final at = first * size;
    final length = Bytes.be32(d, at + 0x1E);
    if (length > d.length) return null;
    // The list, then the data.
    final run = BytesBuilder(copy: false)
      ..add(Uint8List.sublistView(d, at + listAt, at + size));
    var list = run.toBytes();
    final blocks = <int>[first];
    var k = 0, taken = 0;
    while (true) {
      if (k + 2 <= list.length) {
        final b = Bytes.be16(list, k);
        k += 2;
        if (b == 0) break;
        if (b < firstData || b >= count || blocks.contains(b)) return null;
        blocks.add(b);
      } else if (taken + 1 < blocks.length) {
        // The list runs on into the blocks it names.
        taken++;
        run.add(_body(d, blocks[taken], size));
        list = run.toBytes();
      } else {
        return null;
      }
    }
    for (var i = taken + 1; i < blocks.length; i++) {
      run.add(_body(d, blocks[i], size));
    }
    final all = run.toBytes();
    if (all.length < k + length) return null;
    final name = Uint8List.fromList(d.sublist(at + 4, at + 4 + nameLen));
    return SaturnSave(
      blocks: blocks,
      data: Uint8List.fromList(all.sublist(k, k + length)),
      key: keyOf(name),
      name: name,
      language: d[at + 0x0F],
      comment: Uint8List.fromList(d.sublist(at + 0x10, at + 0x10 + commentLen)),
      minutes: Bytes.be32(d, at + 0x1A),
    );
  }

  static Uint8List _body(Uint8List d, int b, int size) =>
      Uint8List.sublistView(d, b * size + 4, (b + 1) * size);

  static List<int> freeList(Uint8List d) {
    if (!isCard(d)) return const [];
    final used = <int>{};
    for (final first in saves(d)) {
      used.add(first);
      used.addAll(save(d, first)?.blocks ?? const []);
    }
    return [
      for (var b = firstData; b < d.length ~/ blockSize(d.length); b++)
        if (!used.contains(b)) b,
    ];
  }

  static CardEdit delete(Uint8List d, int first) {
    if (save(d, first) == null) {
      return CardEdit.fail("That save can't be found on the card");
    }
    final out = Uint8List.fromList(d);
    Bytes.put32(out, first * blockSize(d.length), 0);
    return CardEdit.done(out);
  }

  /// .bup: a 64-byte "Vmem" header, then the data.
  static CardEdit exportSave(Uint8List d, int first) {
    final s = save(d, first);
    if (s == null) return CardEdit.fail("That save can't be found on the card");
    final out = Uint8List(bup + s.data.length)
      ..setAll(0, ascii.encode('Vmem'))
      ..setAll(0x10, s.name)
      ..setAll(0x1C, s.comment);
    out[0x27] = s.language;
    Bytes.putBe32(out, 0x28, s.minutes);
    Bytes.putBe32(out, 0x2C, s.data.length);
    Bytes.putBe16(out, 0x30, s.blocks.length);
    Bytes.putBe32(out, 0x34, s.minutes);
    out.setAll(bup, s.data);
    return CardEdit.done(out);
  }

  /// Copy between cards is export + import. Whether to replace a save of
  /// the same name is the caller's question.
  static CardEdit importSave(Uint8List d, Uint8List file) {
    if (!isCard(d)) return CardEdit.fail("That isn't Saturn backup memory");
    if (file.length < bup ||
        !Bytes.same(file.sublist(0, 4), ascii.encode('Vmem')) ||
        Bytes.be32(file, 0x2C) != file.length - bup) {
      return CardEdit.fail("That isn't a Saturn save file");
    }
    final name = Uint8List.fromList(file.sublist(0x10, 0x10 + nameLen));
    final key = keyOf(name);
    if (key.isEmpty) return CardEdit.fail('That save file has no name');
    for (final first in saves(d)) {
      if (save(d, first)?.key == key) {
        return CardEdit.fail('A save with that name is already on the card');
      }
    }
    final size = blockSize(d.length);
    final length = file.length - bup;
    var need = 1;
    while (size - listAt + (need - 1) * (size - 4) < need * 2 + length) {
      need++;
    }
    final room = freeList(d);
    if (room.length < need) {
      return CardEdit.fail(
        'Not enough room: it needs $need blocks and ${room.length} are free',
      );
    }
    final run = Uint8List(need * 2 + length);
    for (var i = 1; i < need; i++) {
      Bytes.putBe16(run, (i - 1) * 2, room[i]);
    }
    run.setAll(need * 2, Uint8List.sublistView(file, bup));
    final out = Uint8List.fromList(d);
    var sent = 0;
    for (var i = 0; i < need; i++) {
      final at = room[i] * size;
      final head = i == 0 ? listAt : 4;
      out.fillRange(at, at + size, 0);
      if (i == 0) {
        out[at] = tag;
        out.setAll(at + 4, name);
        out[at + 0x0F] = file[0x27];
        out.setAll(at + 0x10, file.sublist(0x1C, 0x1C + commentLen));
        Bytes.putBe32(out, at + 0x1A, Bytes.be32(file, 0x28));
        Bytes.putBe32(out, at + 0x1E, length);
      }
      final from = sent < run.length ? sent : run.length;
      final to = sent + size - head < run.length
          ? sent + size - head
          : run.length;
      out.setRange(at + head, at + head + to - from, run, from);
      sent += size - head;
    }
    return CardEdit.done(out);
  }

  /// The name up to a NUL, as hex; '' = no name.
  static String keyOf(List<int> name) => Bytes.untilNul(
    name,
    0,
    name.length,
  ).map((v) => v.toRadixString(16).padLeft(2, '0')).join();

  /// The save on [d] with the same name as the .bup [file], or -1.
  static int saveNamed(Uint8List d, Uint8List file) {
    final key = keyOf(Bytes.untilNul(file, 0x10, nameLen));
    for (final first in saves(d)) {
      if (save(d, first)?.key == key) return first;
    }
    return -1;
  }
}

/// Reads Saturn backup memory into a [MemoryCard]. Read only.
abstract final class SaturnCard {
  static const languages = [
    'Japan',
    'English',
    'French',
    'German',
    'Spanish',
    'Italian',
  ];

  /// 1 Jan 1980, UTC.
  static const epoch = 315532800;

  /// [d] is the card's own bytes ([SaturnWriter.plain]).
  static MemoryCard parse(Uint8List d, MemoryCard card) {
    card.system = 'SATURN';
    if (!SaturnWriter.isCard(d)) {
      card.error = 'damaged Saturn memory';
      return card;
    }
    final size = SaturnWriter.blockSize(d.length);
    card.total = d.length ~/ size - SaturnWriter.firstData;
    card.free = SaturnWriter.freeList(d).length;
    for (final first in SaturnWriter.saves(d)) {
      final found = SaturnWriter.save(d, first);
      if (found == null) continue;
      final s = CardSave()
        ..system = 'SATURN'
        ..card = card
        ..slot = first;
      s.id = Bytes.ascii(found.name, 0, SaturnWriter.nameLen);
      if (found.language < languages.length) {
        s.region = languages[found.language];
      }
      final comment = Bytes.title(found.comment, 0, SaturnWriter.commentLen);
      if (comment.isNotEmpty) s.titleLines.add(comment);
      s.held.addAll(found.blocks);
      s.blocks = s.held.length;
      s.kb = (s.blocks * size / 1024).ceil();
      s.created = time(found.minutes);
      s.modified = s.created > 0 ? s.created : card.modified;
      s.frames.add(CardPictures.standIn('SATURN', s.id));
      card.saves.add(s);
    }
    return card;
  }

  /// Minutes since 1980 on the player's own clock -> Unix seconds, read as
  /// local time. 0 = no date.
  static int time(int minutes) {
    if (minutes <= 0) return 0;
    final t = DateTime.fromMillisecondsSinceEpoch(
      (epoch + minutes * 60) * 1000,
      isUtc: true,
    );
    return Bytes.localTime(t.year, t.month, t.day, t.hour, t.minute, t.second);
  }
}
