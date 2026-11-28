/// Bounds-checked reads from card data (ported from the PC's CardBytes.gd).
/// A card is someone else's file (or a half-written one): anything outside
/// the data reads as zero, never an error.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart';

abstract final class Bytes {
  /// PS2 timestamps are Japan time, whatever the console's region.
  static const jstOffset = 9 * 3600;

  static bool has(List<int> b, int at, int count) =>
      at >= 0 && count >= 0 && at + count <= b.length;

  static int u8(List<int> b, int at) => has(b, at, 1) ? b[at] : 0;

  static int u16(List<int> b, int at) =>
      has(b, at, 2) ? b[at] | b[at + 1] << 8 : 0;

  static int s16(List<int> b, int at) {
    final v = u16(b, at);
    return v >= 0x8000 ? v - 0x10000 : v;
  }

  static int u32(List<int> b, int at) => has(b, at, 4)
      ? b[at] | b[at + 1] << 8 | b[at + 2] << 16 | b[at + 3] << 24
      : 0;

  static int be16(List<int> b, int at) =>
      has(b, at, 2) ? b[at] << 8 | b[at + 1] : 0;

  static int be32(List<int> b, int at) => be16(b, at) << 16 | be16(b, at + 2);

  static double f32(List<int> b, int at) {
    if (!has(b, at, 4)) return 0;
    final v = ByteData.sublistView(
      Uint8List.fromList(b.sublist(at, at + 4)),
    ).getFloat32(0, Endian.little);
    return v.isFinite ? v : 0;
  }

  static void put16(List<int> b, int at, int v) {
    b[at] = v & 0xFF;
    b[at + 1] = v >> 8 & 0xFF;
  }

  static void put32(List<int> b, int at, int v) {
    b[at] = v & 0xFF;
    b[at + 1] = v >> 8 & 0xFF;
    b[at + 2] = v >> 16 & 0xFF;
    b[at + 3] = v >> 24 & 0xFF;
  }

  static void putBe16(List<int> b, int at, int v) {
    b[at] = v >> 8 & 0xFF;
    b[at + 1] = v & 0xFF;
  }

  static void putBe32(List<int> b, int at, int v) {
    putBe16(b, at, v >> 16 & 0xFFFF);
    putBe16(b, at + 2, v & 0xFFFF);
  }

  /// Bytes up to the first NUL, at most [count].
  static Uint8List untilNul(List<int> b, int at, int count) {
    if (at < 0 || at >= b.length || count <= 0) return Uint8List(0);
    final end = at + count < b.length ? at + count : b.length;
    var stop = end;
    for (var i = at; i < end; i++) {
      if (b[i] == 0) {
        stop = i;
        break;
      }
    }
    return Uint8List.fromList(b.sublist(at, stop));
  }

  /// Printable ASCII ('_' for anything else), up to a NUL.
  static String ascii(List<int> b, int at, int count) {
    final sb = StringBuffer();
    for (final v in untilNul(b, at, count)) {
      sb.writeCharCode(v >= 32 && v < 127 ? v : 0x5F);
    }
    return sb.toString();
  }

  /// Save titles are Shift-JIS, with Latin letters usually written
  /// full-width.
  static String title(List<int> b, int at, int count) {
    final raw = untilNul(b, at, count);
    if (raw.isEmpty) return '';
    String s;
    try {
      s = shiftJis.decode(raw);
    } catch (_) {
      s = latin1.decode(raw, allowInvalid: true);
    }
    return narrow(s).trim();
  }

  /// A title in Windows-1252 (GameCube games from outside Japan).
  static String western(List<int> b, int at, int count) {
    final raw = untilNul(b, at, count);
    if (raw.isEmpty) return '';
    const high = {
      0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E, 0x85: 0x2026, //
      0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02C6, 0x89: 0x2030, 0x8A: 0x0160,
      0x8B: 0x2039, 0x8C: 0x0152, 0x8E: 0x017D, 0x91: 0x2018, 0x92: 0x2019,
      0x93: 0x201C, 0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014,
      0x98: 0x02DC, 0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A, 0x9C: 0x0153,
      0x9E: 0x017E, 0x9F: 0x0178,
    };
    return String.fromCharCodes([for (final c in raw) high[c] ?? c]).trim();
  }

  /// Full-width Latin, digits, punctuation and spaces -> normal ones. Kana
  /// and kanji stay.
  static String narrow(String s) {
    final sb = StringBuffer();
    for (final c in s.runes) {
      if (c == 0x3000) {
        sb.write(' ');
      } else if (c >= 0xFF01 && c <= 0xFF5E) {
        sb.writeCharCode(c - 0xFEE0);
      } else {
        sb.writeCharCode(c);
      }
    }
    return sb.toString();
  }

  static bool _leap(int y) => (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;

  /// A clock reading with no time zone (Dreamcast, GameCube, Saturn): the
  /// player's own wall clock, so it's read as local time. 0 = not a date.
  static int localTime(int y, int m, int d, int h, int mi, int s) {
    if (y < 1980 || y > 2200 || m < 1 || m > 12 || d < 1) return 0;
    final days = [
      31,
      _leap(y) ? 29 : 28,
      31,
      30,
      31,
      30,
      31,
      31,
      30,
      31,
      30,
      31,
    ];
    if (d > days[m - 1] || h > 23 || mi > 59 || s > 59) return 0;
    return DateTime(y, m, d, h, mi, s).millisecondsSinceEpoch ~/ 1000;
  }

  /// The PS2's 8-byte time: -, second, minute, hour, day, month, year (u16).
  static int stamp(List<int> b, int at) {
    if (!has(b, at, 8)) return 0;
    final sec = b[at + 1], min = b[at + 2], hour = b[at + 3];
    final day = b[at + 4], month = b[at + 5], year = u16(b, at + 6);
    if (sec > 59 || min > 59 || hour > 23 || year < 1994 || year > 2200) {
      return 0;
    }
    if (month < 1 || month > 12 || day < 1) return 0;
    const days = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    if (day > days[month - 1]) return 0;
    if (month == 2 && day == 29 && !_leap(year)) return 0;
    return DateTime.utc(
              year,
              month,
              day,
              hour,
              min,
              sec,
            ).millisecondsSinceEpoch ~/
            1000 -
        jstOffset;
  }

  /// A stable hash of a string (FNV-1a), for tints and keys.
  static int hash(String s) {
    var h = 0x811C9DC5;
    for (final c in utf8.encode(s)) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  static bool same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
