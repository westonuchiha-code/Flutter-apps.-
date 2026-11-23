import 'dart:convert';

import 'game_data.dart';
import 'models.dart';

/// Same id scheme as the original web app, so backups move between them.
String slug(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');

/// The player's progress. JSON layout matches the web app's backup:
/// `{"m": {missionSlug: 1}, "k": {itemId: 1}, "c": {itemId: count},
///   "f": {cheatName: 1}}`.
class Progress {
  Progress({
    Map<String, int>? missions,
    Map<String, int>? checks,
    Map<String, int>? counts,
    Map<String, int>? favorites,
  }) : missions = missions ?? {},
       checks = checks ?? {},
       counts = counts ?? {},
       favorites = favorites ?? {};

  /// Passed story missions (by [slug] of the name).
  final Map<String, int> missions;

  /// Ticked 100% items and export cars (`ex-<slug>`).
  final Map<String, int> checks;

  /// Collectible / side-job counters.
  final Map<String, int> counts;

  /// Favorite cheats (by name).
  final Map<String, int> favorites;

  bool missionPassed(Mission m) => missions.containsKey(slug(m.name));
  bool checked(String id) => checks.containsKey(id);
  int count(String id) => counts[id] ?? 0;
  bool isFavorite(Cheat c) => favorites.containsKey(c.name);

  static String exportId(String car) => 'ex-${slug(car)}';

  Map<String, Object> toJson() => {
    'm': missions,
    'k': checks,
    'c': counts,
    'f': favorites,
  };

  String encode() => jsonEncode(toJson());

  /// Parses a backup. Throws [FormatException] if it is not one.
  factory Progress.decode(String text) {
    final Object? json;
    try {
      json = jsonDecode(text.trim());
    } on FormatException {
      throw const FormatException('Not a backup');
    }
    if (json is! Map ||
        json['m'] is! Map ||
        json['k'] is! Map ||
        json['c'] is! Map) {
      throw const FormatException('Not a backup');
    }
    Map<String, int> ints(Object? m) => {
      if (m is Map)
        for (final e in m.entries)
          if (e.value is num) e.key.toString(): (e.value as num).toInt(),
    };
    return Progress(
      missions: ints(json['m']),
      checks: ints(json['k']),
      counts: ints(json['c']),
      favorites: ints(json['f']),
    );
  }
}

/// Totals shown in the HUD and on the home screen (same formula as the web
/// app: every story mission, collectible, side job and the export lists
/// weigh in as units).
class Stats {
  const Stats({
    required this.storyDone,
    required this.collected,
    required this.collectibleTotal,
    required this.sideDone,
    required this.sideTotal,
    required this.percent,
  });

  final int storyDone;
  final int collected;
  final int collectibleTotal;
  final double sideDone;
  final int sideTotal;
  final int percent;

  /// 0–6 wanted-level style stars.
  int get stars => percent * 6 ~/ 100;
}

final List<Cheat> allCheats = [for (final c in cheatCategories) ...c.cheats];

final int missionCount = chapters.fold(0, (a, c) => a + c.missions.length);

final int exportCount = exportLists.fold(0, (a, l) => a + l.cars.length);

final List<TrackItem> allTrackItems = [
  for (final s in trackSections) ...s.items,
];

String chapterOf(Mission m) =>
    chapters.firstWhere((c) => c.missions.contains(m)).name;

extension ProgressStats on Progress {
  int get storyDone =>
      chapters.fold(0, (a, c) => a + c.missions.where(missionPassed).length);

  int get exportsDone => exportLists.fold(
    0,
    (a, l) => a + l.cars.where((car) => checked(Progress.exportId(car))).length,
  );

  Stats get stats {
    final sd = storyDone;
    var collected = 0, collectibleTotal = 0, sideTotal = 0;
    var sideDone = 0.0, got = sd / missionCount, units = 1;
    for (var gi = 0; gi < trackSections.length; gi++) {
      for (final it in trackSections[gi].items) {
        final max = it.max;
        final f = max != null
            ? (count(it.id) / max).clamp(0.0, 1.0)
            : (checked(it.id) ? 1.0 : 0.0);
        units++;
        got += f;
        if (gi == 0) {
          collected += max != null ? count(it.id) : 0;
          collectibleTotal += max ?? 0;
        } else {
          sideTotal++;
          sideDone += f;
        }
      }
    }
    final ex = exportsDone / exportCount;
    units++;
    got += ex;
    sideTotal++;
    sideDone += ex;
    return Stats(
      storyDone: sd,
      collected: collected,
      collectibleTotal: collectibleTotal,
      sideDone: sideDone,
      sideTotal: sideTotal,
      percent: (got / units * 100).floor(),
    );
  }

  /// First mission not yet passed, in story order.
  Mission? get nextMission {
    for (final c in chapters) {
      for (final m in c.missions) {
        if (!missionPassed(m)) return m;
      }
    }
    return null;
  }
}
