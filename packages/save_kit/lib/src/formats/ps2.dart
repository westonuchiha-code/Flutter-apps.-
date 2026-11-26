/// PS2 memory cards, ported from the PC's Ps2Card.gd (reading) and
/// Ps2Writer.gd (changing).
///
/// A file card (PCSX2 .ps2, MemCard PRO .mc2) is a small FAT file system:
/// a superblock, an indirect FAT, the FAT, and 512-byte directory entries.
/// Pages are 512 bytes, followed by 16 spare bytes of ECC on cards that
/// keep it. PCSX2 folder cards are plain folders, one per save.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../bytes.dart';
import '../model.dart';
import 'ps2_icon.dart';

/// One 512-byte directory entry.
typedef _Entry = ({
  int i,
  int mode,
  int size,
  int first,
  String name,
  int created,
  int modified,
});

_Entry _entryAt(List<int> b, int i) {
  final at = i * Ps2Card.entry;
  return (
    i: i,
    mode: Bytes.u16(b, at),
    size: Bytes.u32(b, at + 4),
    first: Bytes.u32(b, at + 0x10),
    name: Bytes.ascii(b, at + 0x40, 32),
    created: Bytes.stamp(b, at + 8),
    modified: Bytes.stamp(b, at + 0x18),
  );
}

/// Reads PS2 cards. Read only.
class Ps2Card {
  Ps2Card._(this._data);

  static const magic = 'Sony PS2 Memory Card Format';
  static const entry = 512;
  static const exists = 0x8000;
  static const isDir = 0x20;
  static const protectedFlag = 0x8;
  static const inUse = 0x80000000;
  static const chainEnd = 0xFFFFFFFF;
  static const iconSys = 'icon.sys';
  static const iconSysMin = 0x1C4;

  /// icon.sys: the list, copy and delete icons' file names.
  static const iconNameAt = [0x104, 0x144, 0x184];
  static const titleAt = 0xC0;
  static const titleLen = 68;
  static const maxEntries = 1000;
  static const folderMark = '_pcsx2_superblock';
  static const folderTotalKb = 8000;
  static const folderFileMax = 8 << 20;

  final Uint8List _data;
  int _page = 0, _per = 0, _stride = 0, _csize = 0, _total = 0, _alloc = 0;
  final _ifc = <int>[];

  /// FAT table number -> its cluster's bytes.
  final _fat = <int, Uint8List>{};

  static bool isCard(List<int> data) {
    if (data.length < 0x150) return false;
    for (var i = 0; i < magic.length; i++) {
      if (data[i] != magic.codeUnitAt(i)) return false;
    }
    return true;
  }

  static MemoryCard parse(
    Uint8List data,
    String name,
    String path,
    int modified,
  ) => Ps2Card._(data)._read(name, path, modified);

  /// A PCSX2 folder card: each sub-folder with an icon.sys is a save.
  static MemoryCard parseFolder(String dir, String name) {
    final card = _newCard(name, dir, _modifiedS(p.join(dir, folderMark)));
    var used = 0;
    final subs =
        Directory(
            dir,
          ).listSync(followLinks: false).whereType<Directory>().toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final sub in subs) {
      if (!File(p.join(sub.path, iconSys)).existsSync()) continue;
      final s = CardSave()
        ..system = 'PS2'
        ..card = card
        ..setId(p.basename(sub.path));
      final blobs = <String, Uint8List>{};
      var kb = 0;
      final files = sub.listSync(followLinks: false).whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final f in files) {
        final fileName = p.basename(f.path);
        if (fileName.startsWith('_pcsx2_')) continue;
        int size;
        try {
          size = f.lengthSync();
          if (size <= folderFileMax) blobs[fileName] = f.readAsBytesSync();
        } on FileSystemException {
          continue;
        }
        final when = _modifiedS(f.path);
        s.files.add((name: fileName, size: size, modified: when));
        s.modified = math.max(s.modified, when);
        kb += (size / 1024).ceil();
      }
      s.kb = kb + ((s.files.length + 2) / 2).ceil();
      used += s.kb;
      readIconSys(s, blobs);
      card.saves.add(s);
    }
    card.total = folderTotalKb;
    card.free = math.max(folderTotalKb - used, 0);
    return card;
  }

  static int _modifiedS(String path) {
    try {
      final f = File(path);
      if (!f.existsSync()) return 0;
      return f.lastModifiedSync().millisecondsSinceEpoch ~/ 1000;
    } on FileSystemException {
      return 0;
    }
  }

  static MemoryCard _newCard(String name, String path, int modified) =>
      MemoryCard()
        ..system = 'PS2'
        ..name = name
        ..path = path
        ..modified = modified;

  MemoryCard _read(String name, String path, int modified) {
    final card = _newCard(name, path, modified);
    final data = _data;
    if (!isCard(data)) {
      card.error = 'not a PS2 memory card';
      return card;
    }
    _page = Bytes.u16(data, 0x28);
    _per = Bytes.u16(data, 0x2A);
    _total = Bytes.u32(data, 0x30);
    _alloc = Bytes.u32(data, 0x34);
    final allocEnd = Bytes.u32(data, 0x38);
    final root = Bytes.u32(data, 0x3C);
    final sane =
        (_page == 512 || _page == 1024) &&
        _per >= 1 &&
        _per <= 16 &&
        _total > 0 &&
        _total <= 1 << 20 &&
        _alloc < _total &&
        root < _total &&
        allocEnd <= _total;
    if (!sane) {
      card.error = 'damaged header';
      return card;
    }
    for (var i = 0; i < 32; i++) {
      _ifc.add(Bytes.u32(data, 0x50 + i * 4));
    }
    _csize = _page * _per;
    final plain = _total * _csize;
    final eccSize = _page ~/ 32;
    _stride =
        _page + (data.length >= plain + _total * _per * eccSize ? eccSize : 0);
    if (data.length < _total * _per * _stride) {
      card.error = 'cut short';
      return card;
    }
    var usable = allocEnd;
    if (_total >= 1024) {
      // What the console reports: 8000 of 8192.
      usable = math.min(allocEnd, _total ~/ 1024 * 1000);
    }
    var freeClusters = 0;
    for (var c = 0; c < usable; c++) {
      if (_next(c) & inUse == 0) freeClusters++;
    }
    card.total = usable * _csize ~/ 1024;
    card.free = freeClusters * _csize ~/ 1024;
    final count = Bytes.u32(_cluster(root + _alloc), 4);
    for (final e in _entries(root, count)) {
      if (e.mode & exists != 0 &&
          e.mode & isDir != 0 &&
          !const ['.', '..', ''].contains(e.name)) {
        card.saves.add(_save(e, card));
      }
    }
    _fat.clear();
    return card;
  }

  CardSave _save(_Entry e, MemoryCard card) {
    final s = CardSave()
      ..system = 'PS2'
      ..card = card
      ..setId(e.name)
      ..copyProtected = e.mode & protectedFlag != 0
      ..created = e.created
      ..modified = e.modified;
    final blobs = <String, Uint8List>{};
    var clusters = (e.size / 2).ceil(); // its own directory
    for (final f in _entries(e.first, e.size)) {
      if (f.mode & exists == 0 || const ['.', '..', ''].contains(f.name)) {
        continue;
      }
      blobs[f.name] = _chain(f.first, f.size);
      s.files.add((name: f.name, size: f.size, modified: f.modified));
      s.modified = math.max(s.modified, f.modified);
      clusters += (f.size / _csize).ceil();
    }
    s.kb = clusters * _csize ~/ 1024;
    readIconSys(s, blobs);
    return s;
  }

  /// icon.sys: title, line break, background colours, lights, and the
  /// names of the three icon files.
  static void readIconSys(CardSave s, Map<String, List<int>> blobs) {
    final b = blobs[iconSys] ?? const <int>[];
    if (b.length < iconSysMin ||
        b[0] != 0x50 ||
        b[1] != 0x53 ||
        b[2] != 0x32 ||
        b[3] != 0x44) {
      return; // "PS2D"
    }
    final brk = Bytes.u16(b, 6);
    var lines = [Bytes.title(b, titleAt, titleLen)];
    if (brk > 0 && brk < titleLen) {
      final whole = Bytes.untilNul(b, titleAt, titleLen).length;
      lines = [Bytes.title(b, titleAt, brk)];
      if (brk < whole) lines.add(Bytes.title(b, titleAt + brk, whole - brk));
    }
    s.titleLines.addAll(lines.where((l) => l.isNotEmpty));
    s.backAlpha = math.min(Bytes.u32(b, 0xC) / 128, 1.0);
    for (var i = 0; i < 4; i++) {
      final at = 0x10 + i * 16;
      s.backColors.add(
        Rgb.from8(
          math.min(Bytes.u32(b, at), 255),
          math.min(Bytes.u32(b, at + 4), 255),
          math.min(Bytes.u32(b, at + 8), 255),
        ),
      );
    }
    for (var i = 0; i < 3; i++) {
      var d = _vec(b, 0x50 + i * 16);
      d = Vec3(d.x, -d.y, -d.z); // the same axis flip as the models
      s.lightDirs.add(d.length > 0.0001 ? d.normalized() : Vec3.back);
      final c = _vec(b, 0x80 + i * 16);
      s.lightColors.add(Rgb(c.x, c.y, c.z));
    }
    final amb = _vec(b, 0xB0);
    s.ambient = Rgb(amb.x, amb.y, amb.z);
    // Games often use one model for all three.
    final made = <String, Ps2Icon?>{};
    for (var k = 0; k < 3; k++) {
      final file = Bytes.ascii(b, iconNameAt[k], 64);
      s.icons[k] = made.putIfAbsent(
        file,
        () => Ps2IconFile.parse(blobs[file] ?? const <int>[]),
      );
    }
  }

  static Vec3 _vec(List<int> b, int at) =>
      Vec3(Bytes.f32(b, at), Bytes.f32(b, at + 4), Bytes.f32(b, at + 8));

  List<_Entry> _entries(int first, int count) {
    final b = _chain(first, math.min(count, maxEntries) * entry);
    return [for (var i = 0; i < b.length ~/ entry; i++) _entryAt(b, i)];
  }

  Uint8List _cluster(int c) {
    if (c < 0 || c >= _total) return Uint8List(0);
    final out = Uint8List(_csize);
    for (var i = 0; i < _per; i++) {
      final at = (c * _per + i) * _stride;
      out.setRange(i * _page, (i + 1) * _page, _data, at);
    }
    return out;
  }

  int _next(int c) {
    final n = _csize ~/ 4;
    final table = c ~/ n;
    final bytes = _fat.putIfAbsent(table, () {
      final slot = table ~/ n;
      var fatCluster = -1;
      if (slot < _ifc.length) {
        fatCluster = Bytes.u32(_cluster(_ifc[slot]), table % n * 4);
      }
      return _cluster(fatCluster);
    });
    if (bytes.isEmpty) return chainEnd;
    return Bytes.u32(bytes, c % n * 4);
  }

  /// A file's bytes. Loops and links outside the card end it.
  Uint8List _chain(int first, int length) {
    if (length <= 0 || length > _total * _csize) return Uint8List(0);
    final out = BytesBuilder(copy: false);
    final seen = <int>{};
    var c = first;
    while (out.length < length &&
        c >= 0 &&
        c + _alloc < _total &&
        seen.add(c)) {
      out.add(_cluster(c + _alloc));
      final v = _next(c);
      if (v == chainEnd || v & inUse == 0) break;
      c = v & 0x7FFFFFFF;
    }
    final all = out.takeBytes();
    return all.length <= length ? all : Uint8List.sublistView(all, 0, length);
  }
}

/// A directory read by the writer: its clusters, bytes and entries.
typedef _Folder = ({List<int> chain, Uint8List bytes, List<_Entry> entries});

/// Changes PS2 file cards in memory (the caller does the writing). A save
/// is named by its folder's name. Only pages that change are rewritten,
/// each with fresh ECC, so anything odd elsewhere on a card survives.
/// Every rule here was checked against a card PCSX2 wrote (FAT values,
/// directory entries, ECC).
class Ps2Writer {
  Ps2Writer._(Uint8List data, {bool copy = true})
    : _d = copy ? Uint8List.fromList(data) : data {
    _error = _open();
  }

  static const page = 512;
  static const spare = 16;
  static const cluster = 1024;
  static const entry = 512;

  /// FAT entries in a cluster.
  static const perTable = 256;

  /// An 8 MB card.
  static const total = 8192;
  static const alloc = 41;
  static const allocEnd = 8135;
  static const ifc = 8;

  /// The console only offers 8000 of each 1024 clusters.
  static const usablePer1024 = 1000;
  static const free = 0x7FFFFFFF;
  static const end = 0xFFFFFFFF;
  static const inUse = 0x80000000;
  static const maxEntries = 1000;
  static const exists = 0x8000;
  static const isDir = 0x20;
  static const isFile = 0x10;
  static const dirMode = 0x8427;
  static const rootUpMode = 0xA426;
  static const version = 'Sony PS2 Memory Card Format 1.2.0.0';
  static const nameAt = 0x40;
  static const nameLen = 32;
  static const _holds = [0x55, 0x33, 0x0F, 0x00, 0xAA, 0xCC, 0xF0];

  static final Uint8List _parity = _makeParity();
  static final Uint8List _column = _makeColumn();

  final Uint8List _d;
  int _stride = page, _total = 0, _alloc = 0, _usable = 0, _root = 0;

  /// FAT entries in play.
  int _end = 0;
  final _tables = <int>[];
  String _error = '';

  String _open() {
    final d = _d;
    if (!Ps2Card.isCard(d)) return "That isn't a PS2 memory card";
    if (Bytes.u16(d, 0x28) != page || Bytes.u16(d, 0x2A) != 2) {
      return "That kind of PS2 card can't be changed";
    }
    _total = Bytes.u32(d, 0x30);
    _alloc = Bytes.u32(d, 0x34);
    _end = Bytes.u32(d, 0x38);
    _root = Bytes.u32(d, 0x3C);
    if (d.length == _total * 2 * (page + spare)) {
      _stride = page + spare;
    } else if (d.length != _total * 2 * page) {
      return 'That PS2 card is the wrong size for its header';
    }
    if (_total <= 0 ||
        _alloc <= 0 ||
        _end <= 0 ||
        _alloc + _end > _total ||
        _root >= _end) {
      return "That PS2 card's header is damaged";
    }
    _usable = _total >= 1024
        ? math.min(_end, _total ~/ 1024 * usablePer1024)
        : _end;
    final wanted = (_end / perTable).ceil();
    for (var i = 0; i < 32 && _tables.length < wanted; i++) {
      final indirect = Bytes.u32(d, 0x50 + i * 4);
      if (indirect <= 0 || indirect >= _alloc) break;
      final list = _read(indirect);
      for (var k = 0; k < perTable && _tables.length < wanted; k++) {
        final t = Bytes.u32(list, k * 4);
        if (t <= 0 || t >= _alloc) return "That PS2 card's FAT is damaged";
        _tables.add(t);
      }
    }
    if (_tables.length < wanted) return "That PS2 card's FAT is damaged";
    return '';
  }

  // The public calls. Those that only look don't copy the card.

  /// A freshly formatted 8 MB card, with ECC (PCSX2) or without (.mc2).
  static Uint8List blank([bool withEcc = true, int? now]) {
    final stride = page + (withEcc ? spare : 0);
    final d = Uint8List(total * 2 * stride)
      ..fillRange(0, total * 2 * stride, 0xFF);
    final h = Uint8List(page);
    h.setAll(0, ascii.encode(version));
    Bytes.put16(h, 0x28, page);
    Bytes.put16(h, 0x2A, 2);
    Bytes.put16(h, 0x2C, 16);
    Bytes.put16(h, 0x2E, 0xFF00);
    // Sizes, root, the two backup blocks.
    const fields = [total, alloc, allocEnd, 0, 1023, 1022, 0, 0];
    for (var i = 0; i < fields.length; i++) {
      Bytes.put32(h, 0x30 + i * 4, fields[i]);
    }
    Bytes.put32(h, 0x50, ifc);
    for (var i = 0; i < 32; i++) {
      Bytes.put32(h, 0xD0 + i * 4, end);
    }
    h[0x150] = 2;
    h[0x151] = 0x2B;
    const tail = [0x400, 0x100, 8, end, 0, 0, 0];
    for (var i = 0; i < tail.length; i++) {
      Bytes.put32(h, 0x154 + i * 4, tail[i]);
    }
    _writePage(d, stride, 0, h);

    const tables = total ~/ perTable;
    final list = Uint8List(cluster)..fillRange(0, cluster, 0xFF);
    for (var i = 0; i < tables; i++) {
      Bytes.put32(list, i * 4, ifc + 1 + i);
    }
    _writeCluster(d, stride, ifc, list);
    for (var i = 0; i < tables; i++) {
      final part = Uint8List(cluster);
      for (var k = 0; k < perTable; k++) {
        final c = i * perTable + k;
        Bytes.put32(part, k * 4, c == 0 || c >= allocEnd ? end : free);
      }
      _writeCluster(d, stride, ifc + 1 + i, part);
    }
    final when = now ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final root = BytesBuilder()
      ..add(newEntry(dirMode, 2, '.', when))
      ..add(newEntry(rootUpMode, 0, '..', when));
    _writeCluster(d, stride, alloc, root.takeBytes());
    return d;
  }

  /// '' = every save and chain on it holds together.
  static String check(Uint8List d) {
    final w = Ps2Writer._(d, copy: false);
    return w._error.isNotEmpty ? w._error : w._check();
  }

  static int freeClusters(Uint8List d) {
    final w = Ps2Writer._(d, copy: false);
    return w._error.isEmpty ? w._freeList().length : 0;
  }

  /// The saves' folder names, in directory order.
  static List<String> saveNames(Uint8List d) {
    final w = Ps2Writer._(d, copy: false);
    if (w._error.isNotEmpty) return [];
    return [for (final e in w._liveFolders()) e.name];
  }

  static CardEdit delete(Uint8List d, String name) {
    final w = Ps2Writer._(d);
    return w._error.isNotEmpty ? CardEdit.fail(w._error) : w._delete(name);
  }

  /// .psu: the folder's entry, ".", "..", then each file's entry and its
  /// data padded to 1 KB.
  static CardEdit exportSave(Uint8List d, String name) {
    final w = Ps2Writer._(d, copy: false);
    return w._error.isNotEmpty ? CardEdit.fail(w._error) : w._export(name);
  }

  /// Copy between cards is export + import. Whether to replace a save of
  /// the same name is the caller's question: one is refused here.
  static CardEdit importSave(Uint8List d, Uint8List psu) {
    final w = Ps2Writer._(d);
    return w._error.isNotEmpty ? CardEdit.fail(w._error) : w._import(psu);
  }

  /// The 3 ECC bytes for 128 bytes of a page.
  static Uint8List ecc(List<int> page, int at) {
    var cp = 0x77, even = 0x7F, odd = 0x7F;
    for (var i = 0; i < 128; i++) {
      final b = page[at + i];
      cp ^= _column[b];
      if (_parity[b] != 0) {
        even ^= ~i;
        odd ^= i;
      }
    }
    return Uint8List.fromList([cp, even & 0x7F, odd]);
  }

  /// A directory entry, both times set to [when] (unix seconds) on the
  /// card's Japan clock.
  static Uint8List newEntry(int mode, int size, String name, int when) {
    final e = Uint8List(entry);
    Bytes.put16(e, 0, mode);
    Bytes.put32(e, 4, size);
    final t = DateTime.fromMillisecondsSinceEpoch(
      (when + Bytes.jstOffset) * 1000,
      isUtc: true,
    );
    for (final at in const [8, 0x18]) {
      e[at + 1] = t.second;
      e[at + 2] = t.minute;
      e[at + 3] = t.hour;
      e[at + 4] = t.day;
      e[at + 5] = t.month;
      Bytes.put16(e, at + 6, t.year);
    }
    final n = ascii.encode(name);
    e.setRange(nameAt, nameAt + math.min(n.length, entry - nameAt), n);
    return e;
  }

  static Uint8List _makeParity() => Uint8List.fromList([
    for (var v = 0; v < 256; v++)
      [for (var bit = 0; bit < 8; bit++) v >> bit & 1].reduce((a, b) => a ^ b),
  ]);

  static Uint8List _makeColumn() {
    final parity = _makeParity();
    return Uint8List.fromList([
      for (var v = 0; v < 256; v++)
        [
          for (var i = 0; i < _holds.length; i++) parity[v & _holds[i]] << i,
        ].reduce((a, b) => a | b),
    ]);
  }

  static void _writePage(Uint8List d, int stride, int pageNo, List<int> bytes) {
    final at = pageNo * stride;
    d.setRange(at, at + page, bytes);
    if (stride == page) return;
    for (var k = 0; k < 4; k++) {
      d.setAll(at + page + k * 3, ecc(bytes, k * 128));
    }
    Bytes.put32(d, at + page + 12, 0);
  }

  static void _writeCluster(Uint8List d, int stride, int c, Uint8List bytes) {
    for (var i = 0; i < 2; i++) {
      _writePage(
        d,
        stride,
        c * 2 + i,
        Uint8List.sublistView(bytes, i * page, (i + 1) * page),
      );
    }
  }

  Uint8List _read(int c) {
    final out = Uint8List(cluster);
    for (var i = 0; i < 2; i++) {
      final at = (c * 2 + i) * _stride;
      if (at + page <= _d.length) {
        out.setRange(i * page, (i + 1) * page, _d, at);
      }
    }
    return out;
  }

  /// Only the pages that really differ, so an untouched page keeps its own
  /// spare bytes.
  void _write(int c, Uint8List bytes) {
    for (var i = 0; i < 2; i++) {
      final part = Uint8List.sublistView(bytes, i * page, (i + 1) * page);
      final pageNo = c * 2 + i;
      final at = pageNo * _stride;
      final erased = _stride != page && Bytes.u32(_d, at + page + 12) == end;
      if (erased ||
          !Bytes.same(Uint8List.sublistView(_d, at, at + page), part)) {
        _writePage(_d, _stride, pageNo, part);
      }
    }
  }

  int _getFat(int c) {
    final table = _tables[c ~/ perTable];
    final offset = c % perTable * 4;
    return Bytes.u32(
      _d,
      (table * 2 + offset ~/ page) * _stride + offset % page,
    );
  }

  void _setFat(Map<int, int> values) {
    final byTable = <int, Uint8List>{};
    values.forEach((c, v) {
      final table = _tables[c ~/ perTable];
      Bytes.put32(
        byTable.putIfAbsent(table, () => _read(table)),
        c % perTable * 4,
        v,
      );
    });
    byTable.forEach(_write);
  }

  List<int> _freeList() => [
    for (var c = 0; c < _usable; c++)
      if (_getFat(c) & inUse == 0) c,
  ];

  /// null = broken (loops, leaves the card, or runs into free space).
  List<int>? _chain(int first) {
    final out = <int>[];
    final seen = <int>{};
    var c = first;
    while (true) {
      if (c < 0 || c >= _end || !seen.add(c)) return null;
      out.add(c);
      final v = _getFat(c);
      if (v == end) return out;
      if (v & inUse == 0) return null;
      c = v & free;
    }
  }

  /// null = broken.
  _Folder? _folder(int first, int count) {
    if (count < 2 || count > maxEntries) return null;
    final held = _chain(first);
    if (held == null || held.length * cluster < count * entry) return null;
    final bytes = Uint8List(held.length * cluster);
    for (var k = 0; k < held.length; k++) {
      bytes.setAll(k * cluster, _read(held[k] + _alloc));
    }
    return (
      chain: held,
      bytes: bytes,
      entries: [for (var i = 0; i < count; i++) _entryAt(bytes, i)],
    );
  }

  _Folder? _rootFolder() => _folder(_root, Bytes.u32(_read(_root + _alloc), 4));

  List<_Entry> _liveFolders() => [
    for (final e in _rootFolder()?.entries ?? const <_Entry>[])
      if (e.i >= 2 && e.mode & exists != 0 && e.mode & isDir != 0) e,
  ];

  _Entry? _find(String name) {
    for (final e in _liveFolders()) {
      if (e.name == name) return e;
    }
    return null;
  }

  /// A file's clusters. null = broken.
  List<int>? _fileChain(_Entry e) {
    if (e.size == 0 && e.first == end) return const [];
    final held = _chain(e.first);
    if (held == null || held.isEmpty || held.length * cluster < e.size) {
      return null;
    }
    return held;
  }

  String _check() {
    final top = _rootFolder();
    if (top == null) return "the card's main folder is broken";
    final chains = <List<int>>[top.chain];
    final names = <String>{};
    for (final e in _liveFolders()) {
      if (!names.add(e.name)) return 'two saves are named ${e.name}';
      final sub = _folder(e.first, e.size);
      if (sub == null) return '${e.name} has a broken folder';
      chains.add(sub.chain);
      for (final f in sub.entries) {
        if (f.i < 2 || f.mode & exists == 0 || f.mode & isDir != 0) continue;
        final held = _fileChain(f);
        if (held == null) return '${e.name} has a broken file';
        chains.add(held);
      }
    }
    final owner = <int>{};
    for (final held in chains) {
      for (final c in held) {
        if (!owner.add(c)) return 'two files share the same space';
      }
    }
    return '';
  }

  CardEdit _delete(String name) {
    final e = _find(name);
    if (e == null) return CardEdit.fail("That save can't be found on the card");
    final sub = _folder(e.first, e.size);
    const damaged = "That save is damaged, so it can't be deleted safely";
    if (sub == null) return CardEdit.fail(damaged);
    final freed = <int, int>{};
    final bytes = sub.bytes;
    for (final f in sub.entries) {
      if (f.i < 2 || f.mode & exists == 0) continue;
      if (f.mode & isDir != 0) {
        return CardEdit.fail(
          "That save has folders inside it, so it can't be changed here",
        );
      }
      final held = _fileChain(f);
      if (held == null) return CardEdit.fail(damaged);
      for (final c in held) {
        freed[c] = free;
      }
      Bytes.put16(bytes, f.i * entry, f.mode & ~exists);
    }
    for (var k = 0; k < sub.chain.length; k++) {
      _write(sub.chain[k] + _alloc, _part(bytes, k));
      freed[sub.chain[k]] = free;
    }
    final top = _rootFolder()!;
    Bytes.put16(top.bytes, e.i * entry, e.mode & ~exists);
    final part = e.i * entry ~/ cluster;
    _write(top.chain[part] + _alloc, _part(top.bytes, part));
    _setFat(freed);
    return CardEdit.done(_d);
  }

  static Uint8List _part(Uint8List bytes, int k) =>
      Uint8List.sublistView(bytes, k * cluster, (k + 1) * cluster);

  CardEdit _export(String name) {
    final e = _find(name);
    if (e == null) return CardEdit.fail("That save can't be found on the card");
    final sub = _folder(e.first, e.size);
    const damaged = "That save is damaged, so it can't be copied";
    if (sub == null) return CardEdit.fail(damaged);
    final bytes = sub.bytes;
    final body = BytesBuilder();
    var count = 2;
    for (final f in sub.entries) {
      if (f.i < 2 || f.mode & exists == 0) continue;
      if (f.mode & isDir != 0) {
        return CardEdit.fail(
          "That save has folders inside it, so it can't be copied",
        );
      }
      final held = _fileChain(f);
      if (held == null) return CardEdit.fail(damaged);
      final head = Uint8List.fromList(
        bytes.sublist(f.i * entry, (f.i + 1) * entry),
      );
      Bytes.put32(head, 0x10, 0);
      body.add(head);
      final data = Uint8List((f.size / cluster).ceil() * cluster);
      var at = 0;
      for (final c in held) {
        if (at >= f.size) break;
        final n = math.min(cluster, f.size - at);
        data.setRange(at, at + n, _read(c + _alloc));
        at += n;
      }
      body.add(data);
      count++;
    }
    final rootBytes = _rootFolder()!.bytes;
    final head = Uint8List.fromList(
      rootBytes.sublist(e.i * entry, (e.i + 1) * entry),
    );
    Bytes.put32(head, 4, count);
    Bytes.put32(head, 0x10, 0);
    final dots = Uint8List.fromList(bytes.sublist(0, entry * 2));
    for (var i = 0; i < 2; i++) {
      Bytes.put32(dots, i * entry + 4, 0);
      Bytes.put32(dots, i * entry + 0x10, 0);
      Bytes.put32(dots, i * entry + 0x14, 0);
    }
    final out = BytesBuilder(copy: false)
      ..add(head)
      ..add(dots)
      ..add(body.takeBytes());
    return CardEdit.done(out.takeBytes());
  }

  CardEdit _import(Uint8List psu) {
    final junk = CardEdit.fail("That isn't a PS2 save file");
    if (psu.length < entry * 3 || Bytes.u16(psu, 0) & isDir == 0) return junk;
    final count = Bytes.u32(psu, 4);
    final name = Bytes.ascii(psu, nameAt, nameLen);
    if (count < 2 || count > maxEntries || !_goodName(name)) return junk;
    final files = <({int at, int size, int clusters})>[];
    final usedNames = <String>{};
    var at = entry * 3;
    final dirClusters = (count / 2).ceil();
    var need = dirClusters;
    for (var i = 0; i < count - 2; i++) {
      if (at + entry > psu.length) return junk;
      final mode = Bytes.u16(psu, at);
      final size = Bytes.u32(psu, at + 4);
      final fileName = Bytes.ascii(psu, at + nameAt, nameLen);
      final clusters = (size / cluster).ceil();
      if (mode & isDir != 0 ||
          mode & isFile == 0 ||
          !_goodName(fileName) ||
          usedNames.contains(fileName)) {
        return junk;
      }
      if (at + entry + size > psu.length) return junk;
      usedNames.add(fileName);
      files.add((at: at, size: size, clusters: clusters));
      need += clusters;
      at += entry + clusters * cluster;
    }
    if (_find(name) != null) {
      return CardEdit.fail('A save with that name is already on the card');
    }
    final top = _rootFolder();
    if (top == null) return CardEdit.fail("That card's main folder is damaged");

    final rootEntries = top.entries;
    var index = rootEntries.length;
    for (final e in rootEntries) {
      if (e.i >= 2 && e.mode & exists == 0) {
        index = e.i;
        break;
      }
    }
    if (index >= maxEntries) {
      return CardEdit.fail("That card can't hold any more saves");
    }
    final rootChain = [...top.chain];
    final grows = (index + 1) * entry > rootChain.length * cluster;
    final freeList = _freeList();
    final want = need + (grows ? 1 : 0);
    if (freeList.length < want) {
      return CardEdit.fail(
        'Not enough room: it needs $want KB and ${freeList.length} are free',
      );
    }

    var next = 0;
    final fat = <int, int>{};
    var rootBytes = top.bytes;
    if (grows) {
      final extra = freeList[next++];
      fat[rootChain.last] = inUse | extra;
      fat[extra] = end;
      rootChain.add(extra);
      rootBytes = Uint8List(rootChain.length * cluster)..setAll(0, rootBytes);
    }
    final dirChain = freeList.sublist(next, next + dirClusters);
    next += dirChain.length;
    _link(fat, dirChain);

    // "." and ".." keep their times.
    final listing = Uint8List(dirChain.length * cluster)
      ..setRange(0, entry * 2, psu, entry);
    for (var i = 0; i < 2; i++) {
      Bytes.put16(listing, i * entry, dirMode);
      Bytes.put32(listing, i * entry + 4, 0);
      Bytes.put32(listing, i * entry + 0x10, i == 0 ? _root : 0);
      Bytes.put32(listing, i * entry + 0x14, i == 0 ? index : 0);
      for (var k = 0; k < nameLen; k++) {
        listing[i * entry + nameAt + k] = k <= i ? 0x2E : 0;
      }
    }
    var listed = entry * 2;
    for (final f in files) {
      final held = freeList.sublist(next, next + f.clusters);
      next += held.length;
      _link(fat, held);
      final e = Uint8List.fromList(psu.sublist(f.at, f.at + entry));
      Bytes.put16(e, 0, Bytes.u16(e, 0) | exists);
      Bytes.put32(e, 0x10, held.isEmpty ? end : held[0]);
      Bytes.put32(e, 0x14, 0);
      listing.setAll(listed, e);
      listed += entry;
      final body = Uint8List(held.length * cluster)
        ..setRange(0, f.size, psu, f.at + entry);
      for (var k = 0; k < held.length; k++) {
        _write(held[k] + _alloc, _part(body, k));
      }
    }
    for (var k = 0; k < dirChain.length; k++) {
      _write(dirChain[k] + _alloc, _part(listing, k));
    }

    final folder = Uint8List.fromList(psu.sublist(0, entry));
    Bytes.put16(folder, 0, Bytes.u16(folder, 0) | exists);
    Bytes.put32(folder, 0x10, dirChain[0]);
    Bytes.put32(folder, 0x14, 0);
    rootBytes.setAll(index * entry, folder);
    if (index >= rootEntries.length) Bytes.put32(rootBytes, 4, index + 1);
    for (var k = 0; k < rootChain.length; k++) {
      _write(rootChain[k] + _alloc, _part(rootBytes, k));
    }
    _setFat(fat);
    return CardEdit.done(_d);
  }

  static void _link(Map<int, int> fat, List<int> held) {
    for (var i = 0; i < held.length; i++) {
      fat[held[i]] = i == held.length - 1 ? end : inUse | held[i + 1];
    }
  }

  static bool _goodName(String name) =>
      !const ['', '.', '..'].contains(name) &&
      !name.contains('/') &&
      !name.contains(r'\');
}
