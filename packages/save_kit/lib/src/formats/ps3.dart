/// PS3 saves: RPCS3 keeps each as a folder
/// (`dev_hdd0/home/<user>/savedata/<SAVE>/`) holding PARAM.SFO (title, where
/// you are, details), ICON0.PNG (320×176), PIC1.PNG (the backdrop) and the
/// game's own files. One user's savedata folder counts as one "card"; so
/// does a USB stick's PS3/SAVEDATA. Where the other consoles pass one save
/// file around, PS3 passes a zip of the folder (stored, no compression).
/// Ported from the PC's Ps3Card.gd, Ps3Writer.gd and ConsoleScanner's
/// param_sfo.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../bytes.dart';
import '../model.dart';
import '../pictures.dart';

/// PARAM.SFO's keys: text, or numbers (format 0x0404).
Map<String, Object> paramSfo(List<int> data) {
  final out = <String, Object>{};
  if (data.length < 20 ||
      data[0] != 0 ||
      data[1] != 0x50 ||
      data[2] != 0x53 ||
      data[3] != 0x46) {
    return out;
  }
  final keysAt = Bytes.u32(data, 8), dataAt = Bytes.u32(data, 12);
  final n = Bytes.u32(data, 16);
  for (var i = 0; i < n; i++) {
    final e = 20 + i * 16;
    if (e + 16 > data.length) break;
    final keyOff = Bytes.u16(data, e), fmt = Bytes.u16(data, e + 2);
    final length = Bytes.u32(data, e + 4), dataOff = Bytes.u32(data, e + 12);
    final k0 = keysAt + keyOff;
    if (k0 >= data.length) break;
    final k1 = data.indexOf(0, k0);
    if (k1 < 0) break;
    final key = utf8.decode(data.sublist(k0, k1), allowMalformed: true);
    final v0 = dataAt + dataOff;
    if (fmt == 0x0404) {
      out[key] = Bytes.u32(data, v0);
    } else {
      final end = math.min(v0 + length, data.length);
      if (v0 > end) continue;
      final raw = data.sublist(v0, end);
      final nul = raw.indexOf(0);
      out[key] = utf8
          .decode(nul < 0 ? raw : raw.sublist(0, nul), allowMalformed: true)
          .trim();
    }
  }
  return out;
}

abstract final class Ps3Card {
  static const mark = 'PARAM.SFO',
      icon = 'ICON0.PNG',
      backdropFile = 'PIC1.PNG';

  /// The square picture the grid shows.
  static const tile = 256;
  static const regions = {
    'U': 'America',
    'E': 'Europe',
    'J': 'Japan',
    'A': 'Asia',
    'K': 'Korea',
    'H': 'Asia',
  };
  static const maxFiles = 400, iconMax = 4 << 20, roomyKb = 1 << 30;

  /// Where a real PS3 copies saves to a USB stick; RPCS3's stick is
  /// dev_usb000.
  static const usbSaves = 'dev_usb000/PS3/SAVEDATA';

  /// Is [dir] one user's savedata, or a USB stick's PS3/SAVEDATA? (The USB
  /// one counts even when empty: it's where copies go.)
  static bool isSavedata(String dir) {
    if (p.basename(dir).toLowerCase() != 'savedata') return false;
    if (isUsb(dir)) return true;
    try {
      return Directory(dir).listSync().whereType<Directory>().any(
        (d) => File(p.join(d.path, mark)).existsSync(),
      );
    } catch (_) {
      return false;
    }
  }

  static bool isUsb(String dir) => dir
      .replaceAll(r'\', '/')
      .toLowerCase()
      .endsWith('/${usbSaves.toLowerCase()}');

  /// ".../dev_hdd0/home/00000001/savedata" -> "PS3 User 1".
  static String cardName(String dir) {
    if (isUsb(dir)) return 'PS3 USB';
    final user = p.basename(p.dirname(dir));
    final n = int.tryParse(user);
    return n != null ? 'PS3 User $n' : 'PS3 Saves';
  }

  static MemoryCard parseFolder(String dir, MemoryCard card) {
    card
      ..system = 'PS3'
      ..isFolder = true
      ..path = dir;
    if (card.name.isEmpty) card.name = cardName(dir);
    List<String> subs;
    try {
      subs = [
        for (final d in Directory(dir).listSync().whereType<Directory>())
          d.path,
      ]..sort();
    } catch (_) {
      subs = [];
    }
    for (final sub in subs) {
      final s = readSave(sub, card);
      if (s != null) card.saves.add(s);
    }
    card
      ..total =
          0 // a hard drive or a stick: no fixed number of blocks
      ..free = roomyKb;
    return card;
  }

  static int usedKb(MemoryCard card) => card.saves.fold(0, (a, s) => a + s.kb);

  /// null = not a save (no PARAM.SFO, or one that can't be read).
  static CardSave? readSave(String dir, MemoryCard card) {
    final sfoFile = File(p.join(dir, mark));
    if (!sfoFile.existsSync()) return null;
    final sfo = paramSfo(sfoFile.readAsBytesSync());
    if (sfo.isEmpty) return null;
    final s = CardSave()
      ..system = 'PS3'
      ..card = card
      ..id = p.basename(dir)
      ..file = p.basename(dir);
    s.serial = serialOf(s.id);
    s.region = s.serial.isNotEmpty
        ? regions[s.serial.substring(2, 3)] ?? ''
        : '';
    s.ps3Title = clean('${sfo['TITLE'] ?? ''}');
    for (final key in ['SUB_TITLE', 'DETAIL']) {
      final line = clean('${sfo[key] ?? ''}');
      if (line.isNotEmpty) s.titleLines.add(line);
    }
    var newest = 0, bytes = 0;
    final names = [
      for (final f in Directory(dir).listSync().whereType<File>())
        p.basename(f.path),
    ]..sort();
    for (final f in names.take(maxFiles)) {
      final file = File(p.join(dir, f));
      final st = file.statSync();
      final when = st.modified.millisecondsSinceEpoch ~/ 1000;
      newest = math.max(newest, when);
      bytes += st.size;
      s.files.add((name: f, size: st.size, modified: when));
    }
    s
      ..kb = (bytes / 1024).ceil()
      ..modified = newest;
    s.blocks = s.kb;
    if (File(p.join(dir, backdropFile)).existsSync()) {
      s.backdrop = p.join(dir, backdropFile);
    }
    final pic = _image(p.join(dir, icon));
    if (pic != null) {
      s.wide = pic;
      s.frames.add(square(pic));
    } else {
      s.frames.add(CardPictures.standIn('PS3', s.id));
    }
    return s;
  }

  /// "BCES00052_SAVE_1" -> "BCES00052" ('' when not named after a game).
  static String serialOf(String folder) {
    final m = RegExp(r'^([A-Z]{4})-?(\d{5})').firstMatch(folder.toUpperCase());
    return m == null ? '' : '${m.group(1)}${m.group(2)}';
  }

  /// "BCES00052" -> "BCES-00052"
  static String serialText(String serial) => serial.length == 9
      ? '${serial.substring(0, 4)}-${serial.substring(4)}'
      : serial;

  /// Trademark signs and line breaks out.
  static String clean(String text) {
    var out = text
        .replaceAll('®', '')
        .replaceAll('™', '')
        .replaceAll('©', '')
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ');
    while (out.contains('  ')) {
      out = out.replaceAll('  ', ' ');
    }
    return out.trim();
  }

  static img.Image _toImage(Pixels px) => img.Image.fromBytes(
    width: px.w,
    height: px.h,
    bytes: px.rgba.buffer,
    numChannels: 4,
  );

  static Pixels _fromImage(img.Image im) {
    final rgba = im
        .convert(numChannels: 4)
        .getBytes(order: img.ChannelOrder.rgba);
    return Pixels(im.width, im.height, Uint8List.fromList(rgba));
  }

  /// The wide icon whole, in a square: on a soft, darkened blow-up of
  /// itself, so nothing is cut off.
  static Pixels square(Pixels icon) {
    final src = _toImage(icon);
    var back = img.copyResize(
      src,
      width: 12,
      height: 12,
      interpolation: img.Interpolation.linear,
    );
    back = img.copyResize(
      back,
      width: tile,
      height: tile,
      interpolation: img.Interpolation.linear,
    );
    img.fillRect(
      back,
      x1: 0,
      y1: 0,
      x2: tile,
      y2: tile,
      color: img.ColorRgba8(0, 0, 0, 97),
      alphaBlend: true,
    );
    final h = math.min(
      tile,
      math.max(1, (tile * icon.h / math.max(1, icon.w)).round()),
    );
    final fit = img.copyResize(
      src,
      width: tile,
      height: h,
      interpolation: img.Interpolation.cubic,
    );
    img.compositeImage(back, fit, dstX: 0, dstY: (tile - h) ~/ 2);
    return _fromImage(back);
  }

  static Pixels? _image(String path) {
    final f = File(path);
    if (!f.existsSync()) return null;
    final bytes = f.readAsBytesSync();
    if (bytes.isEmpty || bytes.length > iconMax) return null;
    final im = img.decodePng(bytes);
    return im == null ? null : _fromImage(im);
  }
}

/// PS3 saves as zips of their folder ("BCES00052_SAVE_1/PARAM.SFO", ...):
/// what backups hold and Export writes; any zip tool opens it. Built and
/// read in memory, stored (no compression), with a fixed date so the same
/// save always packs the same.
abstract final class Ps3Writer {
  static const maxBytes = 200 << 20, maxFiles = 400;
  static const _local = 0x04034b50, _central = 0x02014b50, _end = 0x06054b50;
  static const _dosDate = (2026 - 1980) << 9 | 1 << 5 | 1;

  /// [files] (one folder's files) -> zip bytes, or the reason not.
  static CardEdit pack(String folder, Map<String, List<int>> files) {
    if (!plain(folder)) {
      return CardEdit.fail("That save's folder has an odd name");
    }
    if (files.length > maxFiles || !files.containsKey(Ps3Card.mark)) {
      return CardEdit.fail("That isn't a whole PS3 save (no PARAM.SFO)");
    }
    final names = files.keys.toList()..sort();
    final out = BytesBuilder(copy: false), central = BytesBuilder(copy: false);
    var total = 0, at = 0;
    for (final n in names) {
      if (!plain(n)) {
        return CardEdit.fail('That save has a file with an odd name ($n)');
      }
      final data = files[n]!;
      total += data.length;
      if (total > maxBytes) {
        return CardEdit.fail('That save is too big to copy here');
      }
      final path = utf8.encode('$folder/$n');
      final crc = crc32(data);
      final local = _le([
        (_local, 4),
        (20, 2),
        (0, 2),
        (0, 2),
        (0, 2),
        (_dosDate, 2),
        (crc, 4),
        (data.length, 4),
        (data.length, 4),
        (path.length, 2),
        (0, 2),
      ]);
      out
        ..add(local)
        ..add(path)
        ..add(data);
      central
        ..add(
          _le([
            (_central, 4),
            (20, 2),
            (20, 2),
            (0, 2),
            (0, 2),
            (0, 2),
            (_dosDate, 2),
            (crc, 4),
            (data.length, 4),
            (data.length, 4),
            (path.length, 2),
            (0, 2),
            (0, 2),
            (0, 2),
            (0, 2),
            (0, 4),
            (at, 4),
          ]),
        )
        ..add(path);
      at += local.length + path.length + data.length;
    }
    final dir = central.takeBytes();
    out
      ..add(dir)
      ..add(
        _le([
          (_end, 4),
          (0, 2),
          (0, 2),
          (names.length, 2),
          (names.length, 2),
          (dir.length, 4),
          (at, 4),
          (0, 2),
        ]),
      );
    return CardEdit.done(out.takeBytes());
  }

  /// The folder's name and files, or why not. Every entry must sit in one
  /// plain folder.
  static ({String name, Map<String, Uint8List> files, String error}) unpack(
    Uint8List zip,
  ) {
    ({String name, Map<String, Uint8List> files, String error}) fail(
      String why,
    ) => (name: '', files: const {}, error: why);
    if (zip.length < 22 || zip.length > maxBytes) return fail('not a PS3 save');
    var end = -1;
    for (
      var at = zip.length - 22;
      at > math.max(-1, zip.length - 22 - 65557);
      at--
    ) {
      if (Bytes.u32(zip, at) == _end) {
        end = at;
        break;
      }
    }
    if (end < 0) return fail('not a zip');
    final count = Bytes.u16(zip, end + 10);
    var at = Bytes.u32(zip, end + 16);
    var name = '';
    final files = <String, Uint8List>{};
    for (var i = 0; i < count; i++) {
      if (at + 46 > zip.length || Bytes.u32(zip, at) != _central) {
        return fail('a damaged zip');
      }
      final method = Bytes.u16(zip, at + 10), crc = Bytes.u32(zip, at + 16);
      final packed = Bytes.u32(zip, at + 20), size = Bytes.u32(zip, at + 24);
      final nameLen = Bytes.u16(zip, at + 28);
      final extra = Bytes.u16(zip, at + 30) + Bytes.u16(zip, at + 32);
      final local = Bytes.u32(zip, at + 42);
      final entry = utf8.decode(
        zip.sublist(at + 46, math.min(zip.length, at + 46 + nameLen)),
        allowMalformed: true,
      );
      at += 46 + nameLen + extra;
      final parts = entry
          .replaceAll(r'\', '/')
          .split('/')
          .where((s) => s.isNotEmpty)
          .toList();
      if (entry.endsWith('/') && parts.length == 1) {
        continue; // the folder itself
      }
      if (parts.length != 2 || !plain(parts[0]) || !plain(parts[1])) {
        return fail('it has odd paths inside');
      }
      if (name.isEmpty) {
        name = parts[0];
      } else if (parts[0] != name) {
        return fail('it holds more than one save');
      }
      if (local + 30 > zip.length ||
          Bytes.u32(zip, local) != _local ||
          size > maxBytes) {
        return fail('a damaged zip');
      }
      final start =
          local + 30 + Bytes.u16(zip, local + 26) + Bytes.u16(zip, local + 28);
      if (method != 0) {
        return fail("it's a compressed zip: open it through Import");
      }
      if (start + packed > zip.length) return fail('a damaged zip');
      final data = Uint8List.fromList(zip.sublist(start, start + packed));
      if (data.length != size || crc32(data) != crc) {
        return fail('a damaged zip (${parts[1]})');
      }
      files[parts[1]] = data;
    }
    if (files.length > maxFiles || !files.containsKey(Ps3Card.mark)) {
      return fail("it isn't a whole PS3 save (no PARAM.SFO)");
    }
    return (name: name, files: files, error: '');
  }

  /// '' = these zip bytes are one whole PS3 save.
  static String check(Uint8List zip) {
    final got = unpack(zip);
    if (got.error.isNotEmpty) return got.error;
    return paramSfo(got.files[Ps3Card.mark]!).isNotEmpty
        ? ''
        : 'its PARAM.SFO is damaged';
  }

  /// The save's folder name: what "the same save" means on PS3.
  static String idIn(Uint8List zip) => unpack(zip).name;

  /// A name Windows and the PS3 both take.
  static bool plain(String name) {
    if (name.isEmpty || name == '.' || name == '..' || name.length > 64) {
      return false;
    }
    return RegExp(r'^[A-Za-z0-9\-_.$ ]+$').hasMatch(name);
  }

  static List<int>? _table;

  static int crc32(List<int> data) {
    final t = _table ??= [
      for (var n = 0; n < 256; n++)
        () {
          var c = n;
          for (var k = 0; k < 8; k++) {
            c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
          }
          return c;
        }(),
    ];
    var crc = 0xFFFFFFFF;
    for (final b in data) {
      crc = t[(crc ^ b) & 0xFF] ^ (crc >> 8);
    }
    return crc ^ 0xFFFFFFFF;
  }

  static Uint8List _le(List<(int, int)> parts) {
    final out = BytesBuilder(copy: false);
    for (final (v, n) in parts) {
      out.add([for (var i = 0; i < n; i++) v >> (8 * i) & 0xFF]);
    }
    return out.takeBytes();
  }
}
