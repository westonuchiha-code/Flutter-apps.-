import 'dart:async';

import 'package:app_shell/app_shell.dart';
import 'package:flutter/foundation.dart';

import 'cross_save.dart';
import 'github.dart';
import 'setup.dart';

/// The menu's cross saves: the token, what was last synced, conflicts.
/// Kept in the app's private storage (never in the repo).
class CrossSaveController extends ChangeNotifier {
  CrossSaveController(this.storage, {this.makeRepo, this.only});

  /// Repo folders this app syncs (e.g. `['pokeville']`); null: all of
  /// [XmbFolders.maps].
  final List<String>? only;

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

  Future<void> forgetToken() async {
    token = '';
    await save();
    notifyListeners();
  }

  /// One sync. Null when not set up or already running.
  Future<SyncReport?> sync() async {
    final f = folders;
    if (token.isEmpty || f == null || busy) return null;
    busy = true;
    notifyListeners();
    try {
      f.create();
      final rep = await crossSync(
        repo: _repo(),
        maps: [
          for (final m in f.maps)
            if (only == null ||
                only!.any((o) => m.repo == o || m.repo.startsWith('$o/')))
              m,
        ],
        state: state,
        device: device,
        backups: f.backups,
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
      notifyListeners();
    }
  }

  /// The player picked a side of [c]; the next sync sends or settles it.
  Future<void> resolve(Conflict c, {required bool keepThisDevice}) async {
    final f = folders;
    if (f == null) return;
    if (keepThisDevice) {
      await keepLocal(c, state, f.backups);
    } else {
      await keepOther(c, state, f.backups, DateTime.now());
    }
    conflicts = [
      for (final o in conflicts)
        if (o.key != c.key) o,
    ];
    await save();
    notifyListeners();
    unawaited(sync());
  }
}
