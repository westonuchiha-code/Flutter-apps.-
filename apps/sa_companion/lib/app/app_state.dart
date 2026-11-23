import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models.dart';
import '../data/progress.dart';
import 'progress_store.dart';

/// Holds the player's progress and saves every change.
class AppState extends ChangeNotifier {
  AppState(this.store);

  final ProgressStore store;
  Progress progress = Progress();
  bool loaded = false;

  /// Name of a mission just passed, for the "Mission passed" banner.
  final ValueNotifier<String?> missionPassed = ValueNotifier(null);

  Future<void> load() async {
    try {
      final saved = await store.load();
      if (saved != null) progress = Progress.decode(saved);
    } catch (_) {
      // Unreadable data: start fresh rather than crash.
    }
    loaded = true;
    notifyListeners();
  }

  void _changed() {
    unawaited(store.save(progress.encode()));
    notifyListeners();
  }

  void toggleMission(Mission m) {
    final id = slug(m.name);
    if (progress.missions.remove(id) == null) {
      progress.missions[id] = 1;
      missionPassed.value = m.name;
    }
    _changed();
  }

  void passMission(Mission m) {
    progress.missions[slug(m.name)] = 1;
    missionPassed.value = m.name;
    _changed();
  }

  void toggleCheck(String id) {
    if (progress.checks.remove(id) == null) progress.checks[id] = 1;
    _changed();
  }

  void step(TrackItem item, int by) {
    final max = item.max ?? 1;
    progress.counts[item.id] = (progress.count(item.id) + by).clamp(0, max);
    _changed();
  }

  void setCount(TrackItem item, int value) {
    progress.counts[item.id] = value.clamp(0, item.max ?? 1);
    _changed();
  }

  void toggleFavorite(Cheat c) {
    if (progress.favorites.remove(c.name) == null) {
      progress.favorites[c.name] = 1;
    }
    _changed();
  }

  /// Backup text (same format as the web version's backup).
  String get backup => progress.encode();

  /// Restores a backup. Returns false if [text] is not a backup.
  bool restore(String text) {
    try {
      progress = Progress.decode(text);
    } on FormatException {
      return false;
    }
    _changed();
    return true;
  }

  /// Erases progress but keeps favorite cheats (as the web version did).
  void resetAll() {
    progress = Progress(favorites: progress.favorites);
    _changed();
  }

  @override
  void dispose() {
    missionPassed.dispose();
    super.dispose();
  }
}
