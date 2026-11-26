/// Game text: the Game Boy (Gen 1/2) and GBA (Gen 3) character sets, English
/// and the other western languages (Japanese and Korean are not supported).
library;

import 'dart:typed_data';

const int gbTerminator = 0x50;
const int gbTradeOt = 0x5D;
const int gbaTerminator = 0xFF;

/// U+2024, the period PKHeX shows for the Game Boy "." in MR.MIME and names.
const String gbDot = '․';

String _gbTable({required bool gen2}) {
  final t = List<String>.filled(256, '');
  void put(int at, String chars) {
    final runes = chars.runes.toList();
    for (var i = 0; i < runes.length; i++) {
      t[at + i] = String.fromCharCode(runes[i]);
    }
  }

  if (gen2) {
    put(0x4E, '⏎'); // mail line break
  }
  put(0x5D, '*');
  put(0x70, '@#“”');
  put(0x75, '…');
  put(0x79, '┌─┐│└┘ ');
  put(0x80, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ():;[]');
  put(0xA0, 'abcdefghijklmnopqrstuvwxyzàèéùÀÁ');
  put(0xC0, 'ÄÖÜäöüÈÉÌÍÑÒÓÙÚá');
  if (gen2) {
    put(0xD0, '０１２３４５６'); // ligatures 'd 'l 'm 'r 's 't 'v
    put(0xDF, '←');
    put(0xE0, '’{}-+');
  } else {
    put(0xD0, 'ìíñòóúº');
    put(0xDE, '←\'');
    put(0xE0, '’{}-');
  }
  put(0xE6, '?!$gbDot&%→▷▶▼♂¥×./,♀0123456789');
  return t.join('\u0000');
}

final List<String> _gen1 = _gbTable(gen2: false).split('\u0000');
final List<String> _gen2 = _gbTable(gen2: true).split('\u0000');

/// Decodes a Game Boy name buffer (stops at the 0x50 terminator or at a byte
/// the table doesn't know).
String decodeGb(List<int> bytes, {required bool gen2}) {
  if (bytes.isEmpty) {
    return '';
  }
  if (bytes[0] == gbTradeOt) {
    return '*';
  }
  final table = gen2 ? _gen2 : _gen1;
  final b = StringBuffer();
  for (final c in bytes) {
    final s = table[c];
    if (s.isEmpty) {
      break;
    }
    b.write(s);
  }
  return b.toString();
}

/// Encodes [text] into a Game Boy buffer of [length] bytes, filled with the
/// 0x50 terminator first (PKHeX's "Clear50"). Returns null if a character
/// can't be written.
Uint8List? encodeGb(String text, int length, {required bool gen2}) {
  final table = gen2 ? _gen2 : _gen1;
  final out = Uint8List(length)..fillRange(0, length, gbTerminator);
  var i = 0;
  for (final r in text.runes) {
    final c = String.fromCharCode(r);
    final at = table.indexOf(c);
    if (at <= 0 || i >= length) {
      return null;
    }
    out[i++] = at;
  }
  if (i < length) {
    out[i] = gbTerminator;
  }
  return out;
}

/// Gen 2 box names may hold the 'd 'l 'm ... ligature characters.
String inflateGen2Ligatures(String s) {
  const lig = 'dlmrstv';
  final b = StringBuffer();
  for (final r in s.runes) {
    final i = r - 0xFF10; // '０'
    if (i >= 0 && i < lig.length) {
      b.write('\'${lig[i]}');
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}

// The GBA (Gen 3) western character set. A few Japanese glyphs keep their
// place in the western table, as in the games.
const String _gbaRows =
    ' ÀÁÂÇÈÉÊËÌこÎÏÒÓÔ'
    'ŒÙÚÛÑßàáねçèéêëìま'
    'îïòóôœùúûñºª⑩&+あ'
    'ぃぅぇぉゃ=;がぎぐげござじずぜ'
    'ぞだぢづでどばびぶべぼぱぴぷぺぽ'
    'っ¿¡⒆⒇オカキクケÍ%()セソ'
    'タチツテトナニヌâノハヒフヘホí'
    'ミムメモヤユヨラリ↑↓←＋ヲンァ'
    'ィゥェォ⒅<>ガギグゲゴザジズゼ'
    'ゾダヂヅデドバビブベボパピプペポ'
    'ッ0123456789!?.-･'
    '⑬“”‘\'♂♀\$,⑧/ABCDE'
    'FGHIJKLMNOPQRSTU'
    'VWXYZabcdefghijk'
    'lmnopqrstuvwxyz►'
    ':ÄÖÜäöü';

final List<String> _gba = [
  for (final r in _gbaRows.runes) String.fromCharCode(r),
  for (var i = _gbaRows.runes.length; i < 256; i++) '',
];

/// Decodes a GBA text buffer (stops at 0xFF).
String decodeGba(List<int> bytes, {int language = 2}) {
  final b = StringBuffer();
  for (final c in bytes) {
    if (c == gbaTerminator) {
      break;
    }
    String s;
    if (c == 0xB1) {
      s = switch (language) {
        2 || 4 || 7 => '“',
        3 => '«',
        5 => '„',
        _ => '『',
      };
    } else if (c == 0xB2) {
      s = switch (language) {
        2 || 4 || 7 => '”',
        3 => '»',
        5 => '“',
        _ => '』',
      };
    } else if (language == 1 && _gbaJapanese.containsKey(c)) {
      s = _gbaJapanese[c]!;
    } else {
      s = _gba[c];
    }
    if (s.isEmpty) {
      break;
    }
    b.write(s);
  }
  return b.toString();
}

// Only what a Gen 3 Egg's name ("タマゴ", always Japanese) needs.
const Map<int, String> _gbaJapanese = {0x60: 'タ', 0x6F: 'マ', 0x8B: 'ゴ'};
