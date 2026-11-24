import 'dart:math' as math;

import 'mood.dart';

/// Needs change per hour by this much (awake / asleep).
const _foodAwake = -0.11, _foodAsleep = -0.03;
const _energyAwake = -0.06, _energyAsleep = 0.14;
const _funAwake = -0.07;

/// Most Asset Locker treats counted per day.
const maxTreatsPerDay = 6;

/// A pet and everything that has happened to it.
class PetState {
  PetState({
    this.species = 'slime',
    this.name = 'Pip',
    this.food = 0.8,
    this.energy = 0.8,
    this.fun = 0.7,
    DateTime? updated,
    DateTime? born,
    this.lastFed,
    this.lastPetted,
    this.lastPlayed,
    this.sleepUntil,
    this.awakeUntil,
    this.napping = false,
    this.bedMinutes = 22 * 60 + 30,
    this.wakeMinutes = 7 * 60 + 30,
    this.charging = false,
    this.battery = 100,
    Set<String>? seenAssets,
    this.treatsDay = '',
    this.treatsToday = 0,
    List<String>? log,
  }) : updated = updated ?? DateTime.now(),
       born = born ?? DateTime.now(),
       seenAssets = seenAssets ?? {},
       log = log ?? [];

  String species, name;

  /// 0 (starving) .. 1 (full).
  double food;

  /// 0 (exhausted) .. 1 (rested).
  double energy;

  /// 0 (bored stiff) .. 1 (delighted).
  double fun;
  DateTime updated;
  final DateTime born;
  DateTime? lastFed, lastPetted, lastPlayed;

  /// Put to bed by you: sleeps until then.
  DateTime? sleepUntil;

  /// Woken at night by you: stays up until then.
  DateTime? awakeUntil;

  /// Asleep in the day because it ran out of energy.
  bool napping;

  /// Bedtime and wake time, minutes after midnight.
  int bedMinutes, wakeMinutes;

  /// The device (last known).
  bool charging;
  int battery;

  /// Asset Locker items already counted as treats.
  final Set<String> seenAssets;
  String treatsDay;
  int treatsToday;

  /// Recent events, newest first.
  final List<String> log;

  int get ageDays => DateTime.now().difference(born).inDays;

  /// Wake time on this day (an hour later on weekends).
  int wakeOn(DateTime t) =>
      wakeMinutes +
      (t.weekday == DateTime.saturday || t.weekday == DateTime.sunday ? 60 : 0);

  /// Whether [t] is in the night window (after bedtime or before wake time).
  bool isNight(DateTime t) {
    final m = t.hour * 60 + t.minute;
    final wake = wakeOn(t);
    return bedMinutes > wake
        ? (m >= bedMinutes || m < wake)
        : (m >= bedMinutes && m < wake);
  }

  bool asleepAt(DateTime t) {
    if (sleepUntil != null && t.isBefore(sleepUntil!)) {
      return true;
    }
    if (awakeUntil != null && t.isBefore(awakeUntil!)) {
      return false;
    }
    return napping || isNight(t);
  }

  /// Lets time pass until [now], in 10-minute steps (at most two weeks).
  void advance(DateTime now) {
    if (!now.isAfter(updated)) {
      return;
    }
    var t = updated;
    final end = now.difference(t).inDays > 14
        ? now.subtract(const Duration(days: 14))
        : null;
    if (end != null) {
      t = end;
    }
    while (t.isBefore(now)) {
      final next = t.add(const Duration(minutes: 10));
      final step =
          (next.isAfter(now) ? now : next).difference(t).inSeconds / 3600;
      final asleep = asleepAt(t);
      food = (food + (asleep ? _foodAsleep : _foodAwake) * step).clamp(
        0.0,
        1.0,
      );
      energy = (energy + (asleep ? _energyAsleep : _energyAwake) * step).clamp(
        0.0,
        1.0,
      );
      if (!asleep) {
        fun = (fun + _funAwake * step * (charging ? 0.3 : 1)).clamp(0.0, 1.0);
      }
      if (!napping && !asleep && energy < 0.08) {
        napping = true;
      }
      if (napping && energy >= 0.6) {
        napping = false;
      }
      t = next.isAfter(now) ? now : next;
    }
    if (sleepUntil != null && !now.isBefore(sleepUntil!)) {
      sleepUntil = null;
    }
    if (awakeUntil != null && !now.isBefore(awakeUntil!)) {
      awakeUntil = null;
    }
    updated = now;
  }

  /// How it feels at [now] ([storm]: thunder outside).
  Mood moodAt(DateTime now, {bool storm = false}) {
    bool within(DateTime? t, int minutes) =>
        t != null && !now.isBefore(t) && now.difference(t).inMinutes < minutes;
    if (asleepAt(now)) {
      return Mood.asleep;
    }
    if (within(lastFed, 10)) {
      return Mood.eating;
    }
    if (storm) {
      return Mood.scared;
    }
    if (within(lastPetted, 15) || within(lastPlayed, 30)) {
      return Mood.happy;
    }
    if (food < 0.25) {
      return Mood.hungry;
    }
    final m = now.hour * 60 + now.minute;
    final nearBed = bedMinutes - m >= 0 && bedMinutes - m < 60;
    if (energy < 0.25 || nearBed || battery < 15 && !charging) {
      return Mood.sleepy;
    }
    if (fun < 0.3) {
      return Mood.bored;
    }
    if (fun > 0.75 && food > 0.5) {
      return Mood.happy;
    }
    return Mood.idle;
  }

  void _note(DateTime now, String text) {
    final hh = now.hour.toString().padLeft(2, '0'),
        mm = now.minute.toString().padLeft(2, '0');
    log.insert(0, '$hh:$mm $text');
    if (log.length > 30) {
      log.removeRange(30, log.length);
    }
  }

  // ---- What you can do ----

  void feed(DateTime now) {
    advance(now);
    if (food > 0.92) {
      fun = math.max(0, fun - 0.05);
      _note(now, '$name is too full to eat.');
      return;
    }
    food = math.min(1, food + 0.35);
    lastFed = now;
    _note(now, 'You fed $name.');
  }

  void pet(DateTime now) {
    advance(now);
    fun = math.min(1, fun + 0.15);
    lastPetted = now;
    _note(
      now,
      asleepAt(now) ? '$name smiled in their sleep.' : '$name loved that.',
    );
  }

  void play(DateTime now) {
    advance(now);
    if (asleepAt(now)) {
      _note(now, '$name is asleep.');
      return;
    }
    if (energy < 0.15) {
      _note(now, '$name is too tired to play.');
      return;
    }
    fun = math.min(1, fun + 0.3);
    energy = math.max(0, energy - 0.1);
    food = math.max(0, food - 0.05);
    lastPlayed = now;
    _note(now, 'You played with $name.');
  }

  /// Bed until the next wake time.
  void toBed(DateTime now) {
    advance(now);
    var wake = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(Duration(minutes: wakeOn(now)));
    if (!wake.isAfter(now)) {
      final tomorrow = now.add(const Duration(days: 1));
      wake = DateTime(
        tomorrow.year,
        tomorrow.month,
        tomorrow.day,
      ).add(Duration(minutes: wakeOn(tomorrow)));
    }
    sleepUntil = wake;
    awakeUntil = null;
    _note(now, '$name went to bed.');
  }

  void wakeUp(DateTime now) {
    advance(now);
    sleepUntil = null;
    napping = false;
    awakeUntil = now.add(const Duration(hours: 2));
    _note(now, 'You woke $name up.');
  }

  /// New Asset Locker items are treats (food and fun), a few a day.
  /// [items]: id → (type label, name). The first time, everything already
  /// there is only marked as seen.
  int treats(DateTime now, Map<String, (String, String)> items) {
    advance(now);
    if (seenAssets.isEmpty && items.isNotEmpty) {
      seenAssets.addAll(items.keys);
      seenAssets.add('_first');
      return 0;
    }
    final day = '${now.year}-${now.month}-${now.day}';
    if (treatsDay != day) {
      treatsDay = day;
      treatsToday = 0;
    }
    var n = 0;
    for (final e in items.entries) {
      if (seenAssets.contains(e.key)) {
        continue;
      }
      seenAssets.add(e.key);
      if (treatsToday >= maxTreatsPerDay) {
        continue;
      }
      treatsToday++;
      n++;
      food = math.min(1, food + 0.08);
      fun = math.min(1, fun + 0.12);
      _note(
        now,
        '$name loved your new ${e.value.$1.toLowerCase()} "${e.value.$2}".',
      );
    }
    if (n > 0) {
      lastPlayed = now;
    }
    return n;
  }

  /// The moods coming up (no one doing anything), every [step], for the
  /// widget. [stormAt] says when thunderstorms are forecast.
  List<(DateTime, Mood)> forecast(
    DateTime from, {
    Duration span = const Duration(hours: 24),
    Duration step = const Duration(minutes: 15),
    bool Function(DateTime t)? stormAt,
  }) {
    final copy = PetState.fromJson(toJson());
    final out = <(DateTime, Mood)>[];
    for (var t = from; !t.isAfter(from.add(span)); t = t.add(step)) {
      copy.advance(t);
      out.add((t, copy.moodAt(t, storm: stormAt?.call(t) ?? false)));
    }
    return out;
  }

  Map<String, Object?> toJson() => {
    'species': species,
    'name': name,
    'food': food,
    'energy': energy,
    'fun': fun,
    'updated': updated.toIso8601String(),
    'born': born.toIso8601String(),
    'lastFed': lastFed?.toIso8601String(),
    'lastPetted': lastPetted?.toIso8601String(),
    'lastPlayed': lastPlayed?.toIso8601String(),
    'sleepUntil': sleepUntil?.toIso8601String(),
    'awakeUntil': awakeUntil?.toIso8601String(),
    'napping': napping,
    'bed': bedMinutes,
    'wake': wakeMinutes,
    'charging': charging,
    'battery': battery,
    'seen': seenAssets.toList(),
    'treatsDay': treatsDay,
    'treatsToday': treatsToday,
    'log': log,
  };

  factory PetState.fromJson(Map j) {
    DateTime? d(Object? v) => v is String ? DateTime.tryParse(v) : null;
    double n(Object? v, double def) =>
        (v is num ? v.toDouble() : def).clamp(0.0, 1.0);
    return PetState(
      species: (j['species'] as String?) ?? 'slime',
      name: (j['name'] as String?) ?? 'Pip',
      food: n(j['food'], 0.8),
      energy: n(j['energy'], 0.8),
      fun: n(j['fun'], 0.7),
      updated: d(j['updated']),
      born: d(j['born']),
      lastFed: d(j['lastFed']),
      lastPetted: d(j['lastPetted']),
      lastPlayed: d(j['lastPlayed']),
      sleepUntil: d(j['sleepUntil']),
      awakeUntil: d(j['awakeUntil']),
      napping: j['napping'] == true,
      bedMinutes: (j['bed'] as num?)?.toInt() ?? 22 * 60 + 30,
      wakeMinutes: (j['wake'] as num?)?.toInt() ?? 7 * 60 + 30,
      charging: j['charging'] == true,
      battery: (j['battery'] as num?)?.toInt() ?? 100,
      seenAssets: {for (final s in (j['seen'] as List?) ?? const []) '$s'},
      treatsDay: (j['treatsDay'] as String?) ?? '',
      treatsToday: (j['treatsToday'] as num?)?.toInt() ?? 0,
      log: [for (final s in (j['log'] as List?) ?? const []) '$s'],
    );
  }
}
