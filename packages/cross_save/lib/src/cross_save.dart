/// Cross saves: the Cross-Save repo's PROTOCOL.md, Android side. Per file,
/// compare this device's copy (L), the repo's (R) and what this device last
/// synced (S): take the repo's, send ours, or call it a conflict and change
/// nothing. Nothing is ever deleted; a local save is backed up before it is
/// overwritten. Hashes are git blob SHA-1s, so the repo's tree listing says
/// what changed without downloading anything.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// The tag in conflict copies' names (`<name>.from-repo-<stamp>.<ext>`).
const conflictTag = '.from-repo-';

/// Never synced, on any device (PROTOCOL.md): conflict copies, temp and
/// backup files.
const skipParts = [
  conflictTag,
  '.box-backup-',
  '.box-new',
  '.tmp',
  '.new',
  '.bak',
  'desktop.ini',
  'SRAM.raw',
  '.xs-new', // our own temp files
  '.xmb-new', // save_kit's CardStore (a change, mid-swap)
  '.xmb-old',
];

bool skipped(String name) => skipParts.any(name.contains);

/// Git's blob hash of [bytes] (what the repo's tree lists for each file).
String blobSha(List<int> bytes) {
  final header = utf8.encode('blob ${bytes.length}\u0000');
  return sha1.convert([...header, ...bytes]).toString();
}

/// One folder synced with one part of the repo.
class SyncMap {
  const SyncMap(
    this.repo,
    this.local, {
    this.exts = const [],
    this.skipDirs = const [],
    this.only,
  });

  /// This map limited to the files [names] (relative, '/').
  SyncMap limitedTo(Set<String> names) =>
      SyncMap(repo, local, exts: exts, skipDirs: skipDirs, only: names);

  /// Folder in the repo ("saves/retroarch").
  final String repo;

  /// Folder on this device.
  final String local;

  /// File types (lower case, no dot); empty: every file.
  final List<String> exts;

  /// Folder names left out.
  final List<String> skipDirs;

  /// Only these files (relative, '/' separators), on both sides; null:
  /// every file the other rules take. (The Pokéville app syncs only the
  /// Pokémon game saves it found under saves/retroarch.)
  final Set<String>? only;

  bool takes(String rel) {
    final parts = rel.split('/');
    if (parts
        .take(parts.length - 1)
        .any((d) => d.startsWith('.') || skipDirs.contains(d))) {
      return false;
    }
    final name = parts.last;
    if (skipped(name)) return false;
    if (only != null && !only!.contains(rel)) return false;
    if (exts.isEmpty) return true;
    final ext = p.extension(name).toLowerCase().replaceFirst('.', '');
    return exts.contains(ext);
  }
}

/// The protocol's table. l / r / s: hashes of this device's file, the
/// repo's, and what was last synced ('' = none). Returns
/// none · same (record it) · take · send · conflict.
String decide(String l, String r, String s) {
  if (l == r) return l.isEmpty ? 'none' : 'same';
  if (l.isEmpty) return 'take';
  if (r.isEmpty) return 'send';
  if (l == s) return 'take';
  if (r == s) return 'send';
  return 'conflict';
}

/// The repo, as the sync needs it (GitHub, or a fake for tests).
abstract class SaveRepo {
  /// The branch's newest commit and its tree.
  Future<({String commit, String tree})> head();

  /// Every file under the tree: repo path → blob hash.
  Future<Map<String, String>> files(String tree);
  Future<Uint8List> blob(String sha);
  Future<String> putBlob(Uint8List bytes);

  /// A tree like [base] with [files] (path → blob hash) changed.
  Future<String> putTree(String base, Map<String, String> files);
  Future<String> commit(String message, String tree, String parent);

  /// Moves the branch to [commit]; false if someone pushed meanwhile.
  Future<bool> moveBranch(String commit);
}

/// A conflict waiting for the player.
class Conflict {
  const Conflict(this.key, this.local, this.copy, this.repoSha);
  final String key, local, copy, repoSha;

  Map<String, String> toJson() => {
    'key': key,
    'local': local,
    'copy': copy,
    'repoSha': repoSha,
  };
  static Conflict? fromJson(Object? j) => j is Map
      ? Conflict(
          '${j['key']}',
          '${j['local']}',
          '${j['copy']}',
          '${j['repoSha']}',
        )
      : null;
}

class SyncReport {
  final took = <String>[];
  final sent = <String>[];
  final conflicts = <Conflict>[];
  String? error;
  bool get ok => error == null;

  /// A short line for the menu ('' = nothing worth saying).
  String get summary {
    final bits = <String>[
      if (took.isNotEmpty)
        '${took.length} save${took.length == 1 ? '' : 's'} from your other devices',
      if (sent.isNotEmpty) '${sent.length} sent',
      if (conflicts.isNotEmpty)
        'changed on both sides: ${p.basenameWithoutExtension(conflicts.first.key)}'
            '${conflicts.length > 1 ? ' and ${conflicts.length - 1} more' : ''}',
    ];
    if (bits.isEmpty) return error == null ? '' : 'Cross save: $error';
    return 'Cross save: ${bits.join(', ')}${error == null ? '' : ' ($error)'}';
  }
}

/// What a sync did, as lines for a panel (null: one was already running).
List<String> syncReportLines(SyncReport? rep) {
  if (rep == null) {
    return const ['A sync is already running; Sync Now shows how it went.'];
  }
  String plural(int n, String what) => '$n $what${n == 1 ? '' : 's'}';
  final names = [for (final t in rep.took) p.basenameWithoutExtension(t)];
  return [
    if (rep.took.isNotEmpty) ...[
      '${plural(rep.took.length, 'save')} arrived from your other devices:',
      for (final n in names.take(6)) '   $n',
      if (names.length > 6) '   and ${names.length - 6} more',
    ],
    if (rep.sent.isNotEmpty)
      '${plural(rep.sent.length, 'save')} from this device went to the repo.',
    if (rep.conflicts.isNotEmpty)
      '${plural(rep.conflicts.length, 'save')} changed on both sides: pick '
          'which to keep in Cross Save › Changed on Both Sides.',
    if (rep.took.isEmpty && rep.sent.isEmpty && rep.conflicts.isEmpty && rep.ok)
      'Everything is up to date: the repo has nothing this device is missing.',
    if (!rep.ok) 'Not finished: ${rep.error}',
    'From now on it syncs by itself: when the menu opens, before a game '
        'starts and when you come back from one.',
  ];
}

/// Local files under [dir] (relative, '/' separators) that [m] syncs.
List<String> localFiles(SyncMap m) {
  final dir = Directory(m.local);
  if (!dir.existsSync()) return [];
  final out = <String>[];
  for (final e in dir.listSync(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    final rel = p.relative(e.path, from: m.local).replaceAll(r'\', '/');
    if (m.takes(rel)) out.add(rel);
  }
  return out;
}

String _stamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}';
}

/// State keys (never repo paths) holding what a take replaced: `~was/<key>`
/// = the hash of the local file the repo's copy went over.
const _wasPrefix = '~was/';

/// Writes [bytes] to [path] safely: a temp file, checked, then swapped in.
/// With [unchanged] (the hash [path] had when it was read, '' = no file),
/// nothing is swapped in if the file has changed since (the game or the
/// other app saved meanwhile): it throws instead.
Future<void> _write(String path, Uint8List bytes, {String? unchanged}) async {
  await Directory(p.dirname(path)).create(recursive: true);
  final tmp = File('$path.xs-new');
  await tmp.writeAsBytes(bytes, flush: true);
  final back = await tmp.readAsBytes();
  if (blobSha(back) != blobSha(bytes)) {
    await tmp.delete();
    throw const FileSystemException('the copy did not read back the same');
  }
  final f = File(path);
  if (unchanged != null) {
    final now = await f.exists() ? blobSha(await f.readAsBytes()) : '';
    if (now != unchanged) {
      await tmp.delete();
      throw const FileSystemException(
        'it changed on this device meanwhile, so it was left as it is',
      );
    }
  }
  // A rename replaces the old file in one step (Windows too): there is never
  // a moment without the save.
  await tmp.rename(path);
}

/// One full sync (PROTOCOL.md). [state] (repo path → hash last synced) is
/// updated in place; save it afterwards. [conflicts] holds the unresolved
/// ones from earlier syncs (kept, not copied again).
Future<SyncReport> crossSync({
  required SaveRepo repo,
  required List<SyncMap> maps,
  required Map<String, String> state,
  required String device,
  required String backups,
  DateTime? now,
}) async {
  final rep = SyncReport();
  final stamp = _stamp(now ?? DateTime.now());
  for (var attempt = 0; attempt < 2; attempt++) {
    final ({String commit, String tree}) head;
    final Map<String, String> remote;
    try {
      head = await repo.head();
      remote = await repo.files(head.tree);
    } catch (e) {
      rep.error = "couldn't reach GitHub ($e)";
      return rep;
    }
    final send = <String, (String rel, Uint8List bytes, String sha)>{};
    rep.conflicts.clear(); // this pass lists them again
    // The repo's names in lower case: a local save named like one of them
    // but for case is the same save on a case-blind disk (Android's shared
    // storage, Windows). Sending it would put two names in the repo that
    // overwrite each other on the PC.
    final lower = {for (final k in remote.keys) k.toLowerCase(): k};
    for (final m in maps) {
      final names = <String>{...localFiles(m)};
      final prefix = '${m.repo}/';
      for (final key in remote.keys) {
        if (key.startsWith(prefix)) {
          final rel = key.substring(prefix.length);
          if (m.takes(rel)) names.add(rel);
        }
      }
      for (final rel in names) {
        final key = '${m.repo}/$rel';
        final lp = p.joinAll([m.local, ...rel.split('/')]);
        final lf = File(lp);
        Uint8List? lb;
        if (await lf.exists()) lb = await lf.readAsBytes();
        final l = lb == null ? '' : blobSha(lb);
        final r = remote[key] ?? '';
        var what = decide(l, r, state[key] ?? '');
        final other = lower[key.toLowerCase()];
        if (what == 'send' && r.isEmpty && other != null && other != key) {
          rep.error ??=
              '$rel is named ${other.substring(prefix.length)} in the repo: '
              'rename it here to match (it was not sent)';
          continue;
        }
        // The emulator wrote back the copy a take replaced (it was still
        // open with the old save): that is not a new save, so it isn't sent
        // over the other device's. The player picks.
        if (what == 'send' && r.isNotEmpty && state['$_wasPrefix$key'] == l) {
          what = 'conflict';
        }
        switch (what) {
          case 'same':
            state[key] = l;
          case 'take':
            try {
              final bytes = await repo.blob(r);
              if (blobSha(bytes) != r) {
                throw const FormatException('bad download');
              }
              if (lb != null) {
                await _write(
                  p.joinAll([backups, stamp, ...key.split('/')]),
                  lb,
                );
              }
              await _write(lp, bytes, unchanged: l);
              state[key] = r;
              if (l.isEmpty) {
                state.remove('$_wasPrefix$key');
              } else {
                state['$_wasPrefix$key'] = l;
              }
              if (!rep.took.contains(rel)) rep.took.add(rel);
            } catch (e) {
              rep.error ??= 'could not take $rel ($e)';
            }
          case 'send':
            send[key] = (rel, lb!, l);
          case 'conflict':
            try {
              final copy = await _keepRepoCopy(repo, lp, r, stamp);
              rep.conflicts.add(Conflict(key, lp, copy, r));
            } catch (e) {
              rep.error ??= 'could not keep the other copy of $rel ($e)';
            }
        }
      }
    }
    if (send.isEmpty) return rep;
    try {
      final files = <String, String>{};
      for (final e in send.entries) {
        files[e.key] = await repo.putBlob(e.value.$2);
      }
      final tree = await repo.putTree(head.tree, files);
      final names = <String>[];
      for (final v in send.values) {
        final b = p.basenameWithoutExtension(v.$1.split('/').last);
        if (!names.contains(b)) names.add(b);
      }
      final message =
          '$device: ${names.take(6).join(', ')}'
          '${names.length > 6 ? ' and ${names.length - 6} more' : ''}';
      final commit = await repo.commit(message, tree, head.commit);
      if (await repo.moveBranch(commit)) {
        for (final e in send.entries) {
          state[e.key] = e.value.$3;
          state.remove('$_wasPrefix${e.key}');
          rep.sent.add(e.value.$1);
        }
        return rep;
      }
      // Someone pushed meanwhile: read the repo again and redo the table.
    } catch (e) {
      rep.error = "saved here, but couldn't send to GitHub yet ($e)";
      return rep;
    }
  }
  rep.error = "the repo kept changing; try again";
  return rep;
}

/// The repo's side of a conflict goes next to ours, once.
Future<String> _keepRepoCopy(
  SaveRepo repo,
  String local,
  String r,
  String stamp,
) async {
  final dir = Directory(p.dirname(local));
  final base = p.basenameWithoutExtension(local);
  final ext = p.extension(local);
  if (await dir.exists()) {
    await for (final e in dir.list()) {
      final n = p.basename(e.path);
      if (e is File && n.startsWith('$base$conflictTag')) {
        if (blobSha(await e.readAsBytes()) == r) return e.path;
      }
    }
  }
  final copy = p.join(dir.path, '$base$conflictTag$stamp$ext');
  final bytes = await repo.blob(r);
  if (blobSha(bytes) != r) throw const FormatException('bad download');
  await _write(copy, bytes);
  return copy;
}

/// The player keeps this device's copy: the other one goes to backups and
/// the next sync sends ours.
Future<void> keepLocal(
  Conflict c,
  Map<String, String> state,
  String backups,
) async {
  final copy = File(c.copy);
  if (await copy.exists()) {
    final dest = p.join(backups, 'conflicts', p.basename(c.copy));
    await Directory(p.dirname(dest)).create(recursive: true);
    await copy.copy(dest);
    await copy.delete();
  }
  // R is now "what we last synced", so ours (changed) gets sent.
  state[c.key] = c.repoSha;
  state.remove('$_wasPrefix${c.key}');
}

/// The player takes the other device's copy: ours is backed up and replaced.
Future<void> keepOther(
  Conflict c,
  Map<String, String> state,
  String backups,
  DateTime now,
) async {
  final copy = File(c.copy);
  final bytes = await copy.readAsBytes();
  if (blobSha(bytes) != c.repoSha) {
    throw FileSystemException(
      "the other device's copy isn't the repo's any more, so nothing was "
      'changed (the next sync makes a new one)',
      c.copy,
    );
  }
  final local = File(c.local);
  if (await local.exists()) {
    await _write(
      p.joinAll([backups, _stamp(now), ...c.key.split('/')]),
      await local.readAsBytes(),
    );
  }
  await _write(c.local, bytes);
  await copy.delete();
  state[c.key] = blobSha(bytes);
  state.remove('$_wasPrefix${c.key}');
}
