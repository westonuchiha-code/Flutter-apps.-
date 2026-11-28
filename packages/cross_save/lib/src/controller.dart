import 'dart:async';

import 'package:app_shell/app_shell.dart';
import 'package:flutter/foundation.dart';

import 'cross_save.dart';
import 'github.dart';
import 'setup.dart';

/// The menu's cross saves: the token, what was last synced, conflicts.
/// Kept in the app's private storage (never in the repo).
class CrossSaveController extends ChangeNotifier {
  CrossSaveController(this.storage, {this.makeRepo, this.only, this.files});

  /// Repo folders this app syncs (e.g. `['pokeville']`); null: all of
  /// [XmbFolders.maps].
  final List<String>? only;

  /// Per repo folder (a [SyncMap.repo], e.g. `'saves/retroarch'`): the
  /// only files in it to sync, asked before each sync (relative to the
  /// folder, '/' separators). Folders not named here sync every file.
  final Map<String, Future<Set<String>> Function()>? files;

  final AppStorage storage;

  /// For tests: the repo to talk to (otherwise GitHub with [token]).
  final SaveRepo Function(String token)? makeRepo;

  String token = '';

  /// 'phone' / 'retroid' when the player chose; null: from the model.
  String? deviceOverride;
  String model = '';
  XmbFolders? folders;
  final Map<String, String> state = {};
  List<Conflict> conflicts = [];
  DateTime? last;
  String lastSummary = '';
  String? lastError;
  bool busy = false;

  bool get ready => token.isNotEmpty && folders != null;
  String get device => deviceOverride ?? deviceName(model);

  static const _file = 'cross_save.json';

  Future<void> load() async {
    final j = await storage.readJson(_file);
    if (j is! Map) return;
    token = '${j['token'] ?? ''}';
    deviceOverride = j['device'] as String?;
    state
      ..clear()
      ..addAll({
        for (final e in ((j['state'] as Map?) ?? const {}).entries)
          '${e.key}': '${e.value}',
      });
    conflicts = [
      for (final c in (j['conflicts'] as List?) ?? const [])
        ?Conflict.fromJson(c),
    ];
    final l = j['last'];
    last = l is num ? DateTime.fromMillisecondsSinceEpoch(l.toInt()) : null;
    lastSummary = '${j['summary'] ?? ''}';
    lastError = j['error'] as String?;
  }

  Future<void> save() => storage.writeJson(_file, {
    'token': token,
    'device': deviceOverride,
    'state': state,
    'conflicts': [for (final c in conflicts) c.toJson()],
    'last': last?.millisecondsSinceEpoch,
    'summary': lastSummary,
    'error': lastError,
  });

  SaveRepo _repo() => makeRepo?.call(token) ?? GitHubRepo(token: token);

  /// Checks a token before keeping it; returns an error or null.
  Future<String?> setToken(String t) async {
    final tok = t.trim();
    try {
      final repo = makeRepo?.call(tok) ?? GitHubRepo(token: tok);
      if (repo is GitHubRepo) await repo.check();
    } catch (e) {
      return '$e';
    }
    token = tok;
    await save();
    notifyListeners();
    return null;
  }

  /// Keeps a token another app already checked (the XMB Frontend's, on
  /// Android), without asking GitHub first (works offline too).
  Future<void> adoptToken(String t) async {
    final tok = t.trim();
    if (tok.isEmpty || tok == token) return;
    token = tok;
    await save();
    notifyListeners();
  }

  Future<void> forgetToken() async {
    token = '';
    await save();
    notifyListeners();
  }

  Completer<void>? _running;

  /// Done when no sync is running (at once if none is).
  Future<void> whenIdle() => _running?.future ?? Future.value();

  /// One sync. Null when not set up or already running.
  ///
  /// [takes] false: send-only ([crossSync]): this device's changes go to
  /// the repo, nothing here is written; newer saves wait for a full sync.
  /// [stopTakes]: once true, no more saves are replaced (see [crossSync]).
  Future<SyncReport?> sync({
    bool takes = true,
    bool Function()? stopTakes,
  }) async {
    final f = folders;
    if (token.isEmpty || f == null || busy) return null;
    busy = true;
    final running = _running = Completer<void>();
    notifyListeners();
    try {
      f.create();
      final maps = <SyncMap>[];
      for (final m in f.maps) {
        if (only != null &&
            !only!.any((o) => m.repo == o || m.repo.startsWith('$o/'))) {
          continue;
        }
        final pick = files?[m.repo];
        maps.add(pick == null ? m : m.limitedTo(await pick()));
      }
      final rep = await crossSync(
        repo: _repo(),
        maps: maps,
        state: state,
        device: device,
        backups: f.backups,
        takes: takes,
        stopTakes: stopTakes,
      );
      // An early failure (no network) compared nothing: keep the old list.
      if (!(rep.error ?? '').startsWith("couldn't reach")) {
        conflicts = rep.conflicts;
      }
      last = DateTime.now();
      lastSummary = rep.summary;
      lastError = rep.error;
      await save();
      return rep;
    } finally {
      busy = false;
      _running = null;
      running.complete();
      notifyListeners();
    }
  }

  /// Sends this device's changes and writes nothing here: [sync] with
  /// `takes: false`.
  Future<SyncReport?> sendOnly() => sync(takes: false);

  /// The player picked a side of [c]; the next sync sends or settles it.
  Future<void> resolve(Conflict c, {required bool keepThisDevice}) async {
    final f = folders;
    if (f == null) return;
    if (keepThisDevice) {
      await keepLocal(c, state, f.backups);
    } else {
      // Found by a send-only sync: no copy beside it yet, so fetch it.
      Uint8List? download;
      if (c.copy.isEmpty) download = await _repo().blob(c.repoSha);
      await keepOther(c, state, f.backups, DateTime.now(), download: download);
    }
    conflicts = [
      for (final o in conflicts)
        if (o.key != c.key) o,
    ];
    await save();
    notifyListeners();
    // Sends the kept side (or settles the taken one); takes nothing else.
    unawaited(sendOnly());
  }
}
