/// The only way bytes reach a card file (ported from the PC's CardStore.gd
/// and CardSafety.gd). Every change goes: allowed? -> emulator closed? ->
/// unchanged since we read it? -> backup written and read back -> new card
/// written beside it and checked -> swapped -> read back. A failure at any
/// step leaves the card as it was and says why ('' = it worked).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'bytes.dart';

/// The one gate every card write goes through. Closed unless told
/// otherwise: a test or a tool can only ever change copies inside
/// [testRoots].
class CardSafety {
  CardSafety({required this.isApp, this.testRoots = const []});

  /// The app itself is running (it may change the player's real cards).
  final bool isApp;
  final List<String> testRoots;

  static const refused =
      'This can only change test copies, not your memory cards';

  /// '' = may write.
  String refusal(String path) {
    if (path.trim().isEmpty) return 'No memory card was chosen';
    if (isApp || isTestCopy(path)) return '';
    return refused;
  }

  bool isTestCopy(String path) {
    final full = _full(path);
    return testRoots.any((r) => full.startsWith('${_full(r)}/'));
  }

  /// One spelling per file: absolute, '/', no '..', lower case.
  static String _full(String path) =>
      p.normalize(p.absolute(path)).replaceAll(r'\', '/').toLowerCase();
}

/// One backup: when, which, what it was for.
class Backup {
  const Backup({
    required this.time,
    required this.n,
    required this.what,
    required this.size,
    required this.md5,
    required this.file,
    required this.path,
  });
  final int time, n, size;
  final String what, md5, file, path;
}

class CardStore {
  CardStore({required this.safety, required this.root, this.ownerRunning});

  static const tempExt = '.xmb-new', oldExt = '.xmb-old';
  static const dataExt = '.card', metaExt = '.json';

  final CardSafety safety;

  /// Where backups go.
  final String root;

  /// (path) -> '' or why the card is in use (its emulator is running). The
  /// app can't write without one.
  String Function(String path)? ownerRunning;

  bool get isApp => safety.isApp;

  /// [expected] = the bytes the change was made from; [check] = (bytes) ->
  /// '' or what's wrong with the new card.
  String change(
    String path,
    Uint8List expected,
    Uint8List bytes,
    String what,
    String Function(Uint8List) check,
  ) {
    var no = _mayWrite(path);
    if (no.isNotEmpty) return no;
    if (bytes.isEmpty) {
      return "That change couldn't be checked, so it wasn't made";
    }
    final bad = check(bytes);
    if (bad.isNotEmpty) {
      return "The changed card didn't pass its check ($bad), so nothing was written";
    }
    final f = File(path);
    if (!f.existsSync() || !Bytes.same(f.readAsBytesSync(), expected)) {
      return 'That card changed since it was read. Try again';
    }
    if (Bytes.same(bytes, expected)) return '';
    no = backUp(path, expected, what);
    if (no.isNotEmpty) return no;
    return _swap(path, expected, bytes);
  }

  /// A card that doesn't exist yet (new card, duplicate). Never replaces
  /// anything.
  String create(
    String path,
    Uint8List bytes,
    String Function(Uint8List) check,
  ) {
    final no = _mayWrite(path);
    if (no.isNotEmpty) return no;
    if (FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound) {
      return "There's already a card with that name";
    }
    if (bytes.isEmpty || check(bytes).isNotEmpty) {
      return "The new card didn't pass its check, so it wasn't made";
    }
    final temp = path + tempExt;
    if (!_write(temp, bytes)) {
      _drop(temp);
      return "Couldn't write the new card";
    }
    try {
      File(temp).renameSync(path);
    } catch (_) {
      _drop(temp);
      return "Couldn't name the new card";
    }
    return '';
  }

  /// For cards that keep one file per save. Backed up and read back first.
  String remove(String path, Uint8List expected, String what) {
    var no = _mayWrite(path);
    if (no.isNotEmpty) return no;
    final f = File(path);
    if (expected.isEmpty ||
        !f.existsSync() ||
        !Bytes.same(f.readAsBytesSync(), expected)) {
      return 'That save changed since it was read. Try again';
    }
    no = backUp(path, expected, what);
    if (no.isNotEmpty) return no;
    try {
      f.deleteSync();
    } catch (_) {
      return 'That save is in use, so nothing was changed';
    }
    return '';
  }

  /// PS3 saves are folders: one is made (with its parents) before its
  /// files arrive...
  String makeFolder(String dir) {
    final no = _mayWrite(p.join(dir, 'x'));
    if (no.isNotEmpty) return no;
    try {
      Directory(dir).createSync(recursive: true);
      return '';
    } catch (_) {
      return "Couldn't make that folder, so nothing was changed";
    }
  }

  /// ...and goes once its files have (only when empty).
  String removeFolder(String dir) {
    final no = _mayWrite(p.join(dir, 'x'));
    if (no.isNotEmpty) return no;
    final d = Directory(dir);
    if (d.existsSync() && d.listSync().isNotEmpty) {
      return "Something else is in that save's folder, so it was left there";
    }
    try {
      d.deleteSync();
      return '';
    } catch (_) {
      return "That save's folder is in use, so it was left there";
    }
  }

  /// A file inside a save folder (PS3), written safely: never over
  /// something different without a backup.
  String writeFile(String path, Uint8List bytes, String what) {
    final no = _mayWrite(path);
    if (no.isNotEmpty) return no;
    final f = File(path);
    if (f.existsSync()) {
      final old = f.readAsBytesSync();
      if (Bytes.same(old, bytes)) return '';
      final b = backUp(path, old, what);
      if (b.isNotEmpty) return b;
    }
    final temp = path + tempExt;
    if (!_write(temp, bytes)) {
      _drop(temp);
      return "Couldn't write to that save's folder, so nothing was changed";
    }
    try {
      if (f.existsSync()) f.deleteSync();
      File(temp).renameSync(path);
    } catch (_) {
      _drop(temp);
      return 'That save is in use, so nothing was changed';
    }
    return '';
  }

  String backUp(String path, Uint8List bytes, String what) {
    if (!_rootAllowed()) return CardSafety.refused;
    final dir = folderFor(path);
    try {
      Directory(dir).createSync(recursive: true);
    } catch (_) {
      return "Couldn't make the backup folder, so nothing was changed";
    }
    final stamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    var n = 0;
    var base = '';
    while (base.isEmpty ||
        File(base + dataExt).existsSync() ||
        File(base + metaExt).existsSync()) {
      n++;
      base = p.join(dir, '$stamp-${n.toString().padLeft(4, '0')}');
    }
    final meta = {
      'path': path,
      'what': what,
      'time': stamp,
      'n': n,
      'size': bytes.length,
      'md5': digest(bytes),
    };
    const failed = "Couldn't save a backup, so nothing was changed";
    final packed = Uint8List.fromList(const GZipEncoder().encode(bytes));
    if (!_write(base + dataExt, packed) ||
        !Bytes.same(_unpack(base + dataExt, bytes.length), bytes) ||
        !_write(base + metaExt, utf8.encode(jsonEncode(meta)))) {
      _drop(base + dataExt);
      _drop(base + metaExt);
      return failed;
    }
    return '';
  }

  /// Newest first.
  List<Backup> history(String path) => _entries(folderFor(path));

  /// Every backup there is, newest first.
  List<Backup> allBackups() {
    final d = Directory(root);
    if (!d.existsSync()) return [];
    final out = <Backup>[
      for (final sub in d.listSync().whereType<Directory>())
        ..._entries(sub.path),
    ]..sort(_newest);
    return out;
  }

  static int _newest(Backup a, Backup b) =>
      a.time != b.time ? b.time.compareTo(a.time) : b.n.compareTo(a.n);

  List<Backup> _entries(String dir) {
    final d = Directory(dir);
    if (!d.existsSync()) return [];
    final out = <Backup>[];
    for (final f in d.listSync().whereType<File>()) {
      if (!f.path.endsWith(metaExt)) continue;
      Object? j;
      try {
        j = jsonDecode(f.readAsStringSync());
      } catch (_) {
        continue;
      }
      if (j is! Map) continue;
      final dataFile =
          f.path.substring(0, f.path.length - metaExt.length) + dataExt;
      if (!['time', 'n', 'what', 'size', 'md5'].every(j.containsKey) ||
          !File(dataFile).existsSync()) {
        continue;
      }
      out.add(
        Backup(
          time: _int(j['time']),
          n: _int(j['n']),
          what: '${j['what']}',
          size: _int(j['size']),
          md5: '${j['md5']}',
          file: dataFile,
          path: '${j['path'] ?? ''}',
        ),
      );
    }
    return out..sort(_newest);
  }

  /// A record's number, as the PC reads it (a damaged one is 0, not fatal).
  static int _int(Object? v) => switch (v) {
    num() => v.toInt(),
    String() => int.tryParse(v.trim()) ?? 0,
    _ => 0,
  };

  /// Empty = that backup is damaged.
  Uint8List readBackup(Backup b) {
    final bytes = _unpack(b.file, b.size);
    return bytes.isNotEmpty && digest(bytes) == b.md5 ? bytes : Uint8List(0);
  }

  /// Restoring is a change like any other: what it replaces is backed up.
  String restore(String path, Backup b, String Function(Uint8List) check) {
    final bytes = readBackup(b);
    if (bytes.isEmpty) return 'That backup is damaged, so nothing was changed';
    final f = File(path);
    if (!f.existsSync()) return create(path, bytes, check);
    return change(path, f.readAsBytesSync(), bytes, 'before restore', check);
  }

  String folderFor(String path) {
    final full = p
        .normalize(p.absolute(path))
        .replaceAll(r'\', '/')
        .toLowerCase();
    return p.join(
      root,
      sha256.convert(utf8.encode(full)).toString().substring(0, 24),
    );
  }

  static String digest(List<int> bytes) => md5.convert(bytes).toString();

  String _mayWrite(String path) {
    final no = safety.refusal(path);
    if (no.isNotEmpty) return no;
    if (!_rootAllowed()) return CardSafety.refused;
    final owner = ownerRunning;
    if (owner != null) return owner(path);
    return isApp
        ? "Can't tell whether the emulator is closed, so nothing was changed"
        : '';
  }

  bool _rootAllowed() => isApp || safety.isTestCopy(p.join(root, 'x'));

  /// The old card steps aside and only goes once the new one reads back.
  String _swap(String path, Uint8List expected, Uint8List bytes) {
    final temp = path + tempExt, old = path + oldExt;
    if (File(old).existsSync()) {
      return 'An earlier change was interrupted: restore this card from its history first';
    }
    if (!_write(temp, bytes)) {
      _drop(temp);
      return "Couldn't write to that card's folder, so nothing was changed";
    }
    if (!Bytes.same(File(path).readAsBytesSync(), expected)) {
      _drop(temp);
      return 'That card changed since it was read. Try again';
    }
    try {
      File(path).renameSync(old);
    } catch (_) {
      _drop(temp);
      return 'The card is in use, so nothing was changed';
    }
    var ok = true;
    try {
      File(temp).renameSync(path);
      ok = Bytes.same(File(path).readAsBytesSync(), bytes);
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      _drop(path);
      _drop(temp);
      try {
        File(old).renameSync(path);
      } catch (_) {
        return 'The change failed. Restore this card from its history';
      }
      return 'The change failed, so the card was put back as it was';
    }
    _drop(old);
    return '';
  }

  bool _write(String path, List<int> bytes) {
    try {
      final f = File(path);
      f.writeAsBytesSync(bytes, flush: true);
      return Bytes.same(f.readAsBytesSync(), bytes);
    } catch (_) {
      return false;
    }
  }

  Uint8List _unpack(String file, int size) {
    final f = File(file);
    if (size <= 0 || !f.existsSync()) return Uint8List(0);
    try {
      final out = const GZipDecoder().decodeBytes(f.readAsBytesSync());
      return out.length == size ? Uint8List.fromList(out) : Uint8List(0);
    } catch (_) {
      return Uint8List(0);
    }
  }

  void _drop(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}
