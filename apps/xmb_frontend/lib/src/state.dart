import 'package:flutter/foundation.dart';

import 'library/scanner.dart';

/// Play history of one game.
class Played {
  const Played({this.last = 0, this.seconds = 0, this.sessions = 0});
  final int last, seconds, sessions;

  Map<String, int> toJson() => {
    'last': last,
    'seconds': seconds,
    'sessions': sessions,
  };
  factory Played.fromJson(Object? j) => j is Map
      ? Played(
          last: (j['last'] as num?)?.toInt() ?? 0,
          seconds: (j['seconds'] as num?)?.toInt() ?? 0,
          sessions: (j['sessions'] as num?)?.toInt() ?? 0,
        )
      : const Played();
}

enum SortBy { title, recent, system }

/// Everything the menu remembers (saved as one JSON file).
class MenuState extends ChangeNotifier {
  String? romsDir;
  List<Game> games = [];
  DateTime? scanned;

  /// Pinned games, in order (shown first on the Game row).
  final List<String> pins = [];
  final Map<String, Played> played = {};
  final Set<String> hidden = {};
  bool showHidden = false;
  SortBy sortBy = SortBy.title;

  /// Swap A and B (for Nintendo-style button layouts).
  bool swapAB = false;

  /// Which way the menu is drawn. 'auto' follows the device: the Retroid
  /// Pocket Classic's screen (1240×1080) is wider than tall, so Android
  /// calls it landscape even though the device is held upright; forcing
  /// "portrait" there turns everything sideways.
  String screen = 'auto';

  /// RetroArch build to use (null: the first one installed).
  String? retroArchPackage;

  /// Per console: a RetroArch core instead of the default, or RetroArch
  /// instead of a standalone emulator.
  final Map<String, String> cores = {};
  final Set<String> preferRetroArch = {};

  /// The game started last and when (to count play time on return).
  String? running;
  int runningSince = 0;

  void changed() => notifyListeners();

  Game? gameById(String id) {
    for (final g in games) {
      if (g.id == id) return g;
    }
    return null;
  }

  List<Game> get visibleGames => [
    for (final g in games)
      if (showHidden || !hidden.contains(g.id)) g,
  ];

  /// Games sorted for a list.
  List<Game> sorted(Iterable<Game> list) {
    final out = list.toList();
    switch (sortBy) {
      case SortBy.title:
        out.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      case SortBy.recent:
        out.sort((a, b) {
          final c = (played[b.id]?.last ?? 0).compareTo(
            played[a.id]?.last ?? 0,
          );
          return c != 0
              ? c
              : a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
      case SortBy.system:
        out.sort((a, b) {
          final c = a.system.compareTo(b.system);
          return c != 0
              ? c
              : a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
    }
    return out;
  }

  /// Pinned games, then the most recently played (no repeats), for the
  /// Game row.
  List<Game> front({int recent = 8}) {
    final out = <Game>[];
    for (final id in pins) {
      final g = gameById(id);
      if (g != null) out.add(g);
    }
    final rest = [
      for (final g in visibleGames)
        if (!pins.contains(g.id) && (played[g.id]?.last ?? 0) > 0) g,
    ]..sort((a, b) => played[b.id]!.last.compareTo(played[a.id]!.last));
    return out..addAll(rest.take(recent));
  }

  void togglePin(String id) {
    if (!pins.remove(id)) pins.insert(0, id);
    notifyListeners();
  }

  void movePin(String id, int by) {
    final i = pins.indexOf(id);
    if (i < 0) return;
    final j = (i + by).clamp(0, pins.length - 1);
    pins
      ..removeAt(i)
      ..insert(j, id);
    notifyListeners();
  }

  void toggleHidden(String id) {
    if (!hidden.remove(id)) hidden.add(id);
    notifyListeners();
  }

  /// A game was started.
  void started(String id, int now) {
    final p = played[id] ?? const Played();
    played[id] = Played(
      last: now,
      seconds: p.seconds,
      sessions: p.sessions + 1,
    );
    running = id;
    runningSince = now;
    notifyListeners();
  }

  /// The menu came back to the front: count the time since the game started.
  void returned(int now) {
    final id = running;
    if (id == null) return;
    final secs = ((now - runningSince) / 1000).round();
    final p = played[id] ?? const Played();
    // Under 10 s means the emulator didn't really start.
    if (secs >= 10) {
      played[id] = Played(
        last: p.last,
        seconds: p.seconds + secs,
        sessions: p.sessions,
      );
    }
    running = null;
    notifyListeners();
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'romsDir': romsDir,
    'games': [for (final g in games) g.toJson()],
    'scanned': scanned?.millisecondsSinceEpoch,
    'pins': pins,
    'played': {for (final e in played.entries) e.key: e.value.toJson()},
    'hidden': hidden.toList(),
    'showHidden': showHidden,
    'sortBy': sortBy.name,
    'swapAB': swapAB,
    'screen': screen,
    'retroArchPackage': retroArchPackage,
    'cores': cores,
    'preferRetroArch': preferRetroArch.toList(),
    'running': running,
    'runningSince': runningSince,
  };

  void load(Object? j) {
    if (j is! Map) return;
    romsDir = j['romsDir'] as String?;
    games = [
      for (final g in (j['games'] as List?) ?? const [])
        if (g is Map) Game.fromJson(g),
    ];
    final s = j['scanned'];
    scanned = s is num ? DateTime.fromMillisecondsSinceEpoch(s.toInt()) : null;
    pins
      ..clear()
      ..addAll([for (final p in (j['pins'] as List?) ?? const []) '$p']);
    played
      ..clear()
      ..addAll({
        for (final e in ((j['played'] as Map?) ?? const {}).entries)
          '${e.key}': Played.fromJson(e.value),
      });
    hidden
      ..clear()
      ..addAll([for (final h in (j['hidden'] as List?) ?? const []) '$h']);
    showHidden = j['showHidden'] == true;
    sortBy =
        SortBy.values.where((v) => v.name == j['sortBy']).firstOrNull ??
        SortBy.title;
    swapAB = j['swapAB'] == true;
    screen = screenChoices.containsKey(j['screen'])
        ? j['screen'] as String
        : 'auto';
    retroArchPackage = j['retroArchPackage'] as String?;
    cores
      ..clear()
      ..addAll({
        for (final e in ((j['cores'] as Map?) ?? const {}).entries)
          '${e.key}': '${e.value}',
      });
    preferRetroArch
      ..clear()
      ..addAll([
        for (final h in (j['preferRetroArch'] as List?) ?? const []) '$h',
      ]);
    running = j['running'] as String?;
    runningSince = (j['runningSince'] as num?)?.toInt() ?? 0;
  }
}

/// Screen orientation choices (value → label).
const screenChoices = {
  'auto': 'Follow the Device',
  'wide': 'Wide',
  'wideFlipped': 'Wide, Upside Down',
  'tall': 'Tall',
  'tallFlipped': 'Tall, Upside Down',
};

/// "380 MB", "1.2 GB".
String formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1 << 20) return '${(bytes / 1024).round()} KB';
  if (bytes < 1 << 30) return '${(bytes / (1 << 20)).round()} MB';
  return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
}

/// "Played just now", "Played yesterday", "Played 3 days ago"…
String playedAgo(int lastMs, DateTime now) {
  final then = DateTime.fromMillisecondsSinceEpoch(lastMs);
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(then.year, then.month, then.day)).inDays;
  if (days <= 0) {
    final mins = now.difference(then).inMinutes;
    if (mins < 2) return 'Played just now';
    if (mins < 60) return 'Played $mins minutes ago';
    final h = (mins / 60).floor();
    return 'Played $h hour${h == 1 ? '' : 's'} ago';
  }
  if (days == 1) return 'Played yesterday';
  if (days < 30) return 'Played $days days ago';
  final months = (days / 30).floor();
  if (months < 12) return 'Played $months month${months == 1 ? '' : 's'} ago';
  final years = (days / 365).floor();
  return 'Played $years year${years == 1 ? '' : 's'} ago';
}

/// "2 min", "5 hours", "1 h 20 min".
String formatPlayTime(int seconds) {
  final m = (seconds / 60).round();
  if (m < 60) return '$m min';
  final h = m ~/ 60, r = m % 60;
  if (r == 0 || h >= 10) return '$h hour${h == 1 ? '' : 's'}';
  return '$h h $r min';
}
