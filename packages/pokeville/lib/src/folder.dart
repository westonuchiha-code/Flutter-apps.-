// Reading and writing a Pokéville folder's box.json.
//
// Writes are atomic (box.json.tmp, then swapped in) and careful: a sync
// (Cross-Save) can bring a new box.json in at any time, so before writing,
// the file on disk must still be exactly what was last read or written here.
// If it isn't, nothing is written: the new one is read instead and the
// change is refused, so the PC never loses a sync.
import 'dart:io';

import 'package:app_shell/app_shell.dart' show runInBackground;
import 'package:path/path.dart' as p;

import 'store.dart';

/// Runs `work(arg)` somewhere (a background isolate in the apps; right away
/// in tests).
typedef BackgroundRunner = Future<R> Function<A, R>(
  R Function(A arg) work,
  A arg,
);

/// Runs the work on this isolate (tests, or tiny jobs).
Future<R> runHere<A, R>(R Function(A arg) work, A arg) async => work(arg);

/// What reading box.json found.
enum BoxState { missing, broken, ready }

/// A read of box.json.
class BoxRead {
  const BoxRead(this.state, {this.data, this.text, this.error});

  final BoxState state;
  final BoxData? data;

  /// The file's text exactly as read (null when there's none).
  final String? text;
  final String? error;
}

/// How a write went.
enum WriteOutcome {
  /// Written.
  saved,

  /// box.json changed on disk since it was read: nothing was written, and
  /// [WriteResult.read] holds the new one.
  changed,

  /// The file couldn't be written ([WriteResult.error]).
  failed,
}

class WriteResult {
  const WriteResult(this.outcome, {this.read, this.error});

  final WriteOutcome outcome;
  final BoxRead? read;
  final String? error;
}

/// One Pokéville folder (box.json + mons/).
class PokevilleFolder {
  PokevilleFolder(this.dir, {BackgroundRunner? runner})
    : _run = runner ?? runInBackground;

  final String dir;
  final BackgroundRunner _run;

  /// Where this folder's (and its games') work runs.
  BackgroundRunner get runner => _run;

  /// box.json's text as last read or written here (null: there was none).
  String? _seen;
  bool _known = false;

  String get indexPath => p.join(dir, PokeBoxStore.index);

  bool get exists => File(indexPath).existsSync();

  /// Reads box.json (and remembers it, for the changed-on-disk check).
  Future<BoxRead> read() async {
    final r = _decode(await _run(_readText, indexPath));
    _seen = r.text;
    _known = true;
    return r;
  }

  /// Is box.json no longer what was last read or written here?
  Future<bool> changedOnDisk() async {
    if (!_known) return true;
    final (text, _) = await _run(_readText, indexPath);
    return text != _seen;
  }

  /// Writes [data], unless box.json changed on disk since it was read.
  Future<WriteResult> write(BoxData data) async {
    if (!_known) await read();
    final (outcome, text, error) = await _run(_writeBox, (
      dir: dir,
      data: data,
      expected: _seen,
    ));
    switch (outcome) {
      case WriteOutcome.saved:
        _seen = text;
        return const WriteResult(WriteOutcome.saved);
      case WriteOutcome.changed:
        final r = _decode((text, null));
        _seen = r.text;
        return WriteResult(WriteOutcome.changed, read: r);
      case WriteOutcome.failed:
        return WriteResult(WriteOutcome.failed, error: error);
    }
  }
}

BoxRead _decode((String?, String?) got) {
  final (text, error) = got;
  if (text == null) {
    return error == null
        ? const BoxRead(BoxState.missing)
        : BoxRead(BoxState.broken, error: error);
  }
  final data = PokeBoxStore.parse(text);
  if (data == null) {
    return BoxRead(
      BoxState.broken,
      text: text,
      error: "box.json isn't a Pokéville Box",
    );
  }
  return BoxRead(BoxState.ready, data: data, text: text);
}

// ---- the work (top-level: it runs in a background isolate) -----------------

/// (text, error): text null and no error = no file.
(String?, String?) _readText(String path) {
  final f = File(path);
  try {
    if (!f.existsSync()) return (null, null);
    return (f.readAsStringSync(), null);
  } on Object catch (e) {
    return (null, '$e');
  }
}

(WriteOutcome, String?, String?) _writeBox(
  ({String dir, BoxData data, String? expected}) a,
) {
  final path = p.join(a.dir, PokeBoxStore.index);
  final (now, readError) = _readText(path);
  if (readError != null) return (WriteOutcome.failed, null, readError);
  if (now != a.expected) return (WriteOutcome.changed, now, null);
  final text = PokeBoxStore.encode(a.data);
  final tmp = File('$path.tmp');
  try {
    Directory(a.dir).createSync(recursive: true);
    tmp.writeAsStringSync(text, flush: true);
    tmp.renameSync(path); // replaces box.json (Windows too)
    return (WriteOutcome.saved, text, null);
  } on Object catch (e) {
    try {
      if (tmp.existsSync()) tmp.deleteSync();
    } on Object {
      // leave it: the next write replaces it
    }
    return (WriteOutcome.failed, null, '$e');
  }
}
