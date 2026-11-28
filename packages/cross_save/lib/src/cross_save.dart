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
    this.downloadOnly = false,
    this.excludes = const [],
    this.renames = const {},
  });

  /// This map limited to the files [names] (relative, '/').
  SyncMap limitedTo(Set<String> names) => SyncMap(
    repo,
    local,
    exts: exts,
    skipDirs: skipDirs,
    only: names,
    downloadOnly: downloadOnly,
    excludes: excludes,
    renames: renames,
  );

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

  /// The repo's copies come down; nothing here is ever sent. For saves
  /// another device owns (the PC's PS2 cards and PS3 saves: no emulator
  /// here uses them, the phone keeps copies to look at and back up). A
  /// copy changed here is not a save to send or a conflict: the next full
  /// sync backs it up and puts the repo's back. Files only this device has
  /// are left alone.
  final bool downloadOnly;

  /// Folders inside [repo] (relative, '/') left out with all they hold,
  /// whatever their case: the parts other maps sync.
  final List<String> excludes;

  /// Local names for the first folder of a repo path (`pcsx2` → `PCSX2`),
  /// so copies sit beside the menu's own `Saves/<Emulator>` folders.
  final Map<String, String> renames;

  /// Where [rel] (a path inside [repo]) is on this device.
  String localPath(String rel) {
    final parts = rel.split('/');
    if (parts.length > 1) parts[0] = renames[parts[0]] ?? parts[0];
    return p.joinAll([local, ...parts]);
  }

  bool takes(String rel) {
    final low = rel.toLowerCase();
    if (excludes.any((e) => low.startsWith('${e.toLowerCase()}/'))) {
      return false;
    }
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

  /// Newer saves from the repo a send-only sync left alone (relative
  /// names): the next full sync takes them.
  final waiting = <String>[];
  String? error;
  bool get ok => error == null;

  /// A short line for the menu ('' = nothing worth saying).
  String get summary {
    final bits = <String>[
      if (took.isNotEmpty)
        '${took.length} save${took.length == 1 ? '' : 's'} from your other devices',
      if (sent.isNotEmpty) '${sent.length} sent',
      if (waiting.isNotEmpty)
        '${waiting.length} newer save${waiting.length == 1 ? '' : 's'} waiting',
      if (conflicts.isNotEmpty)
        'changed on both sides: ${p.basenameWithoutExtension(conflicts.first.key)}'
            '${conflicts.length > 1 ? ' and ${conflicts.length - 1} more' : ''}',
    ];
    if (bits.isEmpty) return error == null ? '' : 'Cross save: $error';
    return 'Cross save: ${bits.join(', ')}${error == null ? '' : ' ($error)'}';
  }
}

/// What a sync did, as lines for a panel (null: one was already running),
/// ending with [moments]: when the app syncs by itself.
List<String> syncReportLines(
  SyncReport? rep, {
  List<String> moments = syncMomentLines,
}) {
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
    if (rep.waiting.isNotEmpty)
      '${plural(rep.waiting.length, 'newer save')} from your other devices '
          '${rep.waiting.length == 1 ? 'is' : 'are'} waiting: '
          '${rep.waiting.length == 1 ? 'it arrives' : 'they arrive'} the next '
          'time saves are fetched.',
    if (rep.took.isEmpty &&
        rep.sent.isEmpty &&
        rep.conflicts.isEmpty &&
        rep.waiting.isEmpty &&
        rep.ok)
      'Everything is up to date: the repo has nothing this device is missing.',
    if (!rep.ok) 'Not finished: ${rep.error}',
    ...moments,
  ];
}

/// When the XMB Frontend syncs by itself (the default for
/// [syncReportLines]; an app with other moments passes its own).
const syncMomentLines = [
  'From now on it syncs by itself. Saves from your other devices only '
      'replace the ones here right before a game starts (or when you pick '
      'Sync Now), never while a game might still be open.',
  'When the menu opens, when you come back to it and after a game, it only '
      'sends what this device saved.',
];

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
/// other app saved meanwhile): it throws instead. With [stop], nothing is
/// swapped in once it says so (checked last, right before the swap).
Future<void> _write(
  String path,
  Uint8List bytes, {
  String? unchanged,
  bool Function()? stop,
}) async {
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
  if (stop?.call() ?? false) {
    await tmp.delete();
    throw const _Stopped();
  }
  // A rename replaces the old file in one step (Windows too): there is never
  // a moment without the save.
  await tmp.rename(path);
}

/// A take [crossSync] gave up on because its `stopTakes` said so.
class _Stopped implements Exception {
  const _Stopped();
}

/// One sync (PROTOCOL.md). [state] (repo path → hash last synced) is
/// updated in place; save it afterwards. [conflicts] holds the unresolved
/// ones from earlier syncs (kept, not copied again).
///
/// With [takes] false it only sends: nothing on this device is written
/// (no save replaced, no backup, no conflict copy). Saves the repo has newer
/// are left alone and not recorded, so the next full sync still takes them
/// ([SyncReport.waiting]); conflicts are still found and reported (with a
/// conflict copy only if an earlier full sync already left one, else
/// [Conflict.copy] is '').
///
/// [stopTakes]: once it returns true, no more saves are replaced (checked
/// right before each swap); the rest wait like a send-only sync's. The XMB
/// sets it when it stops waiting and starts a game.
Future<SyncReport> crossSync({
  required SaveRepo repo,
  required List<SyncMap> maps,
  required Map<String, String> state,
  required String device,
  required String backups,
  DateTime? now,
  bool takes = true,
  bool Function()? stopTakes,
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
    rep.waiting.clear();
    // The repo's names in lower case: a local save named like one of them
    // but for case is the same save on a case-blind disk (Android's shared
    // storage, Windows). Sending it would put two names in the repo that
    // overwrite each other on the PC.
    final lower = {for (final k in remote.keys) k.toLowerCase(): k};
    for (final m in maps) {
      // A download-only map leaves files only this device has alone, so
      // only the repo's names count.
      final names = <String>{if (!m.downloadOnly) ...localFiles(m)};
      final prefix = '${m.repo}/';
      for (final key in remote.keys) {
        if (key.startsWith(prefix)) {
          final rel = key.substring(prefix.length);
          if (m.takes(rel)) names.add(rel);
        }
      }
      for (final rel in names) {
        final key = '${m.repo}/$rel';
        final lp = m.localPath(rel);
        final lf = File(lp);
        Uint8List? lb;
        if (await lf.exists()) lb = await lf.readAsBytes();
        final l = lb == null ? '' : blobSha(lb);
        final r = remote[key] ?? '';
        var what = decide(l, r, state[key] ?? '');
        if (m.downloadOnly) {
          // The repo's copy is the save: one changed here (or not synced
          // before) is replaced by it, after a backup. Never sent.
          if (r.isEmpty) continue;
          if (what == 'send' || what == 'conflict') what = 'take';
        }
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
        if (what == 'take' && (!takes || (stopTakes?.call() ?? false))) {
          // Left for the next full sync: nothing written, nothing recorded.
          if (!rep.waiting.contains(rel)) rep.waiting.add(rel);
          continue;
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
              if (stopTakes?.call() ?? false) throw const _Stopped();
              if (lb != null) {
                await _write(
                  p.joinAll([backups, stamp, ...key.split('/')]),
                  lb,
                );
              }
              await _write(lp, bytes, unchanged: l, stop: stopTakes);
              state[key] = r;
              if (l.isEmpty) {
                state.remove('$_wasPrefix$key');
              } else {
                state['$_wasPrefix$key'] = l;
              }
              if (!rep.took.contains(rel)) rep.took.add(rel);
            } on _Stopped {
              if (!rep.waiting.contains(rel)) rep.waiting.add(rel);
            } catch (e) {
              rep.error ??= 'could not take $rel ($e)';
            }
          case 'send':
            send[key] = (rel, lb!, l);
          case 'conflict':
            try {
              final copy = takes
                  ? await _keepRepoCopy(repo, lp, r, stamp)
                  : await _findRepoCopy(lp, r) ?? '';
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

/// The conflict copy of [local] an earlier sync left with the repo's
/// [r], or null.
Future<String?> _findRepoCopy(String local, String r) async {
  final dir = Directory(p.dirname(local));
  final base = p.basenameWithoutExtension(local);
  if (await dir.exists()) {
    await for (final e in dir.list()) {
      final n = p.basename(e.path);
      if (e is File && n.startsWith('$base$conflictTag')) {
        if (blobSha(await e.readAsBytes()) == r) return e.path;
      }
    }
  }
  return null;
}

/// The repo's side of a conflict goes next to ours, once.
Future<String> _keepRepoCopy(
  SaveRepo repo,
  String local,
  String r,
  String stamp,
) async {
  final found = await _findRepoCopy(local, r);
  if (found != null) return found;
  final dir = Directory(p.dirname(local));
  final base = p.basenameWithoutExtension(local);
  final ext = p.extension(local);
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
/// A conflict a send-only sync found has no copy ([Conflict.copy] ''): then
/// [download] (the repo's bytes, [Conflict.repoSha]) is used instead.
Future<void> keepOther(
  Conflict c,
  Map<String, String> state,
  String backups,
  DateTime now, {
  Uint8List? download,
}) async {
  final copy = File(c.copy);
  final bytes = c.copy.isEmpty && download != null
      ? download
      : await copy.readAsBytes();
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
  if (c.copy.isNotEmpty) await copy.delete();
  state[c.key] = blobSha(bytes);
  state.remove('$_wasPrefix${c.key}');
}
