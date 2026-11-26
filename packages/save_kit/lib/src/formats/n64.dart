/// N64 Controller Pak (.mpk / .cpk / .pak, and four paks inside a
/// mupen64plus-next .srm). Ported from the PC's PakWriter.gd and the pak
/// part of PlainCards.gd. Checked there against 16 real paks.
///
/// 128 pages of 256 bytes: 0 the ID (four copies, each with a sum and its
/// complement), 1 the index, 2 its backup, 3-4 the 16 notes (saves), 5..127
/// data. The index holds a big-endian u16 per page: the next page, 1 = the
/// last, 3 = free; its byte 1 is the sum of bytes 0x0A..0xFF. A save
/// ("note") is named by its directory index, 0..15. Paks store no dates.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../bytes.dart';
import '../model.dart';
import '../pictures.dart';

/// Changes Controller Pak images in memory; nothing here touches a disk.
abstract final class PakWriter {
  static const size = 32768;
  static const page = 256;
  static const firstData = 5;
  static const pages = 128;
  static const notes = 16;
  static const note = 32;
  static const notesAt = 0x300;
  static const idAt = [0x20, 0x60, 0x80, 0xC0];
  static const free = 3;
  static const end = 1;
  static const occupied = 2;

  /// The index checksum covers page 5's entry onward.
  static const sumFrom = 0x0A;

  /// Device 0001, one bank.
  static const idType = 0x00010100;

  /// What MPKEdit puts where a loose .note's first page would be.
  static const noStart = 0xCAFE;

  /// mupen64plus-next's .srm: EEPROM etc., then four paks from 0x800.
  static const combined = 296960;
  static const paksAt = 0x800;

  /// A new, empty pak. Every pak has its own serial: random bytes.
  static Uint8List blank([math.Random? random]) {
    final rng = random ?? math.Random();
    final d = Uint8List(size);
    final id = Uint8List(32);
    for (var i = 0; i < 0x18; i++) {
      id[i] = rng.nextInt(256);
    }
    Bytes.putBe16(id, 0x18, idType >> 16 & 0xFFFF);
    Bytes.putBe16(id, 0x1A, idType & 0xFFFF);
    var sum = 0;
    for (var i = 0; i < 14; i++) {
      sum += Bytes.be16(id, i * 2);
    }
    Bytes.putBe16(id, 0x1C, sum & 0xFFFF);
    Bytes.putBe16(id, 0x1E, (0xFFF2 - sum) & 0xFFFF);
    for (final at in idAt) {
      d.setAll(at, id);
    }
    for (var p = firstData; p < pages; p++) {
      Bytes.putBe16(d, page + p * 2, free);
    }
    _seal(d);
    return d;
  }

  /// Where the paks sit in a file: one per [size], up to four, or the four
  /// in a mupen64plus-next .srm. Only those whose ID holds up.
  static List<int> paksIn(Uint8List file) {
    var start = -1, count = 0;
    if (file.length == combined) {
      start = paksAt;
      count = 4;
    } else if (file.isNotEmpty &&
        file.length % size == 0 &&
        file.length <= size * 4) {
      start = 0;
      count = file.length ~/ size;
    }
    return [
      for (var i = 0; i < count; i++)
        if (idFine(Uint8List.sublistView(file, start + i * size)))
          start + i * size,
    ];
  }

  /// '' = a pak a game would accept.
  static String check(Uint8List d) {
    if (d.length != size) return 'not a Controller Pak';
    if (!idFine(d)) return 'its ID is damaged';
    if (indexPage(d) == 0) return 'both copies of its index are damaged';
    final owner = <int>{};
    final names = <String>{};
    for (final n in saves(d)) {
      final held = chain(d, n);
      if (held.isEmpty) return 'note $n is broken';
      for (final p in held) {
        if (!owner.add(p)) return 'two notes share page $p';
      }
      if (!names.add(keyOf(noteEntry(d, n)))) {
        return 'two notes have the same name';
      }
    }
    return '';
  }

  /// Any one of the four ID copies with a good sum and complement.
  static bool idFine(List<int> d) {
    for (final at in idAt) {
      var sum = 0;
      for (var i = 0; i < 14; i++) {
        sum += Bytes.be16(d, at + i * 2);
      }
      if (Bytes.be16(d, at + 0x1C) == sum & 0xFFFF &&
          Bytes.be16(d, at + 0x1E) == (0xFFF2 - sum) & 0xFFFF) {
        return true;
      }
    }
    return false;
  }

  /// The index copy to trust: 1, else its backup 2, else 0.
  static int indexPage(Uint8List d) {
    if (d.length < 3 * page) return 0;
    for (final p in const [1, 2]) {
      var sum = 0;
      for (var i = p * page + sumFrom; i < (p + 1) * page; i++) {
        sum += d[i];
      }
      if (sum & 0xFF == d[p * page + 1]) return p;
    }
    return 0;
  }

  /// A note's 32-byte directory entry (a copy).
  static Uint8List noteEntry(Uint8List d, int n) =>
      _slice(d, notesAt + n * note, notesAt + (n + 1) * note);

  /// The notes in use: a first page in range and some name bytes.
  static List<int> saves(Uint8List d) {
    if (d.length != size) return const [];
    return [
      for (var n = 0; n < notes; n++)
        if (_inUse(d, notesAt + n * note)) n,
    ];
  }

  static bool _inUse(Uint8List d, int at) {
    final start = Bytes.be16(d, at + 6);
    if (start < firstData || start >= pages) return false;
    for (var i = 0; i < 6; i++) {
      if (d[at + i] != 0) return true;
    }
    return false;
  }

  /// The note's pages in order. Empty = not a whole note.
  static List<int> chain(Uint8List d, int n) {
    if (!saves(d).contains(n)) return const [];
    final index = indexPage(d);
    if (index == 0) return const [];
    final out = <int>[];
    var p = Bytes.be16(d, notesAt + n * note + 6);
    while (p >= firstData && p < pages && !out.contains(p)) {
      out.add(p);
      p = Bytes.be16(d, index * page + p * 2);
    }
    return p == end ? out : const [];
  }

  static List<int> freeList(Uint8List d) {
    if (d.length != size) return const [];
    final index = indexPage(d);
    if (index == 0) return const [];
    return [
      for (var p = firstData; p < pages; p++)
        if (Bytes.be16(d, index * page + p * 2) == free) p,
    ];
  }

  static CardEdit delete(Uint8List d, int n) {
    final held = chain(d, n);
    if (held.isEmpty) {
      return CardEdit.fail("That save can't be found on the pak");
    }
    final out = _workingCopy(d);
    for (final p in held) {
      Bytes.putBe16(out, page + p * 2, free);
    }
    out.fillRange(notesAt + n * note, notesAt + (n + 1) * note, 0);
    _seal(out);
    return CardEdit.done(out);
  }

  /// .note: the 32-byte entry (first page set to [noStart]), then the pages
  /// in order.
  static CardEdit exportSave(Uint8List d, int n) {
    final held = chain(d, n);
    if (held.isEmpty) {
      return CardEdit.fail("That save can't be found on the pak");
    }
    final out = Uint8List(note + held.length * page)
      ..setAll(0, noteEntry(d, n));
    Bytes.putBe16(out, 6, noStart);
    for (var i = 0; i < held.length; i++) {
      out.setRange(note + i * page, note + (i + 1) * page, d, held[i] * page);
    }
    return CardEdit.done(out);
  }

  /// Copy between paks is export + import. Whether to replace a save of the
  /// same name is the caller's question.
  static CardEdit importSave(Uint8List d, Uint8List noteFile) {
    if (d.length != size || indexPage(d) == 0) {
      return CardEdit.fail('That Controller Pak is damaged');
    }
    final body = noteFile.length - note;
    if (body < page ||
        body % page != 0 ||
        body > (pages - firstData) * page ||
        noteFile.take(6).every((v) => v == 0)) {
      return CardEdit.fail("That isn't an N64 note file");
    }
    final key = keyOf(noteFile);
    final taken = saves(d);
    for (final n in taken) {
      if (keyOf(noteEntry(d, n)) == key) {
        return CardEdit.fail('A save with that name is already on the pak');
      }
    }
    if (taken.length >= notes) {
      return CardEdit.fail(
        'A Controller Pak holds 16 saves, and this one is full',
      );
    }
    final count = body ~/ page;
    final room = freeList(d);
    if (room.length < count) {
      return CardEdit.fail(
        'Not enough room: it needs $count pages and ${room.length} are free',
      );
    }
    var slot = 0;
    while (taken.contains(slot)) {
      slot++;
    }
    final out = _workingCopy(d);
    for (var i = 0; i < count; i++) {
      final p = room[i];
      out.setRange(p * page, (p + 1) * page, noteFile, note + i * page);
      Bytes.putBe16(out, page + p * 2, i == count - 1 ? end : room[i + 1]);
    }
    final at = notesAt + slot * note;
    out.setRange(at, at + note, noteFile);
    Bytes.putBe16(out, at + 6, room[0]);
    out[at + 8] |= occupied;
    _seal(out);
    return CardEdit.done(out);
  }

  /// Game, publisher, extension and name together make a note the same
  /// note.
  static String keyOf(List<int> entry) =>
      _hex([...entry.take(6), ...entry.skip(0x0C).take(note - 0x0C)]);

  /// The note on [d] with the same key as [noteFile], or -1.
  static int noteNamed(Uint8List d, Uint8List noteFile) {
    final key = keyOf(noteFile);
    for (final n in saves(d)) {
      if (keyOf(noteEntry(d, n)) == key) return n;
    }
    return -1;
  }

  /// Starts from the good index copy, in page 1.
  static Uint8List _workingCopy(Uint8List d) {
    final out = Uint8List.fromList(d);
    if (indexPage(d) == 2) out.setRange(page, 2 * page, d, 2 * page);
    return out;
  }

  static void _seal(Uint8List d) {
    var sum = 0;
    for (var i = page + sumFrom; i < page * 2; i++) {
      sum += d[i];
    }
    d[page + 1] = sum & 0xFF;
    d.setRange(2 * page, 3 * page, d, page);
  }
}

/// Reads a Controller Pak into a [MemoryCard]. Read only.
abstract final class PakCard {
  static const regions = {
    'E': 'America',
    'J': 'Japan',
    'P': 'Europe',
    'D': 'Germany',
    'F': 'France',
    'I': 'Italy',
    'S': 'Spain',
    'U': 'Australia',
    'X': 'Europe',
    'Y': 'Europe',
  };

  /// 0x34..0x41.
  static const symbols = '!"#\'*+,-./:=?@';

  /// 0x42 onward.
  static const kana =
      '。゛゜ァィゥェォッャュョヲンアイウエオカキクケコサシスセソタチツテトナニヌネノ'
      'ハヒフヘホマミムメモヤユヨラリルレロワガギグゲゴザジズゼゾダヂヅデドバビブベボ'
      'パピプペポ';

  static MemoryCard parse(Uint8List d, MemoryCard card) {
    card.system = 'N64';
    if (d.length != PakWriter.size ||
        !PakWriter.idFine(d) ||
        PakWriter.indexPage(d) == 0) {
      card.error = 'damaged Controller Pak';
      return card;
    }
    card.total = PakWriter.pages - PakWriter.firstData;
    card.free = PakWriter.freeList(d).length;
    for (final n in PakWriter.saves(d)) {
      final e = PakWriter.noteEntry(d, n);
      final code = Bytes.ascii(e, 0, 4);
      final s = CardSave()
        ..system = 'N64'
        ..card = card
        ..slot = n;
      var title = n64Text(e, 0x10, 16);
      final ext = n64Text(e, 0x0C, 4);
      if (ext.isNotEmpty) title += '.$ext';
      s.id = '$code${Bytes.ascii(e, 4, 2)} $title';
      s.serial = code;
      s.region = code.length > 3 ? regions[code[3]] ?? '' : '';
      if (title.isNotEmpty) s.titleLines.add(title);
      s.held.addAll(PakWriter.chain(d, n));
      s.blocks = s.held.length;
      s.kb = (s.blocks / 4).ceil();
      s.modified = card.modified; // paks store no dates
      s.frames.add(CardPictures.standIn('N64', s.id));
      card.saves.add(s);
    }
    return card;
  }

  /// The N64's own character set: 0 ends, 0x0F space, digits, A-Z,
  /// symbols, then kana.
  static String n64Text(List<int> b, int at, int count) {
    final sb = StringBuffer();
    for (var i = 0; i < count; i++) {
      final c = Bytes.u8(b, at + i);
      if (c == 0) break;
      if (c == 0x0F) {
        sb.write(' ');
      } else if (c >= 0x10 && c <= 0x19) {
        sb.write(c - 0x10);
      } else if (c >= 0x1A && c <= 0x33) {
        sb.writeCharCode(0x41 + c - 0x1A);
      } else if (c >= 0x34 && c < 0x34 + symbols.length) {
        sb.write(symbols[c - 0x34]);
      } else if (c >= 0x42 && c < 0x42 + kana.length) {
        sb.write(kana[c - 0x42]);
      } else {
        sb.write('_');
      }
    }
    return sb.toString().trim();
  }
}

Uint8List _slice(Uint8List d, int from, int to) {
  final a = from.clamp(0, d.length), b = to.clamp(0, d.length);
  return Uint8List.fromList(d.sublist(a, b < a ? a : b));
}

String _hex(List<int> b) =>
    b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
