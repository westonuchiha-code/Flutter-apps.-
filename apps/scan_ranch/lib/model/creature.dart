import 'dart:math' as math;

import 'genome.dart';

/// Where a creature lives.
enum Home { ranch, box }

/// One caught creature. The species comes from [barcode]; [individualSeed]
/// makes it unique. Needs are 0 (bad) to 1 (good).
class Creature {
  Creature({
    required this.id,
    required this.barcode,
    required this.individualSeed,
    required this.caughtAt,
    this.nickname,
    this.home = Home.ranch,
    this.hunger = 0.7,
    this.happiness = 0.6,
    this.affection = 0,
    Map<String, double>? extraNeeds,
  }) : extraNeeds = extraNeeds ?? {};

  final String id;
  final String barcode;
  final int individualSeed;
  final DateTime caughtAt;
  String? nickname;
  Home home;

  /// 1 = full, 0 = starving.
  double hunger;

  /// 1 = overjoyed, 0 = miserable.
  double happiness;

  /// Grows with petting and care (no upper limit).
  int affection;

  /// Room for future needs (e.g. "clean", "energy") without a save change.
  final Map<String, double> extraNeeds;

  late final Genome genome = Genome.fromBarcode(barcode);
  late final Individuality individual = Individuality.roll(
    genome,
    individualSeed,
  );
  late final Appearance look = Appearance(genome, individual);

  String get name => nickname?.trim().isNotEmpty == true
      ? nickname!.trim()
      : genome.speciesName;

  /// Mood word for the UI.
  String get mood {
    if (hunger < 0.25) return 'Hungry';
    if (happiness > 0.8) return 'Overjoyed';
    if (happiness > 0.55) return 'Happy';
    if (happiness > 0.3) return 'Okay';
    return 'Sad';
  }

  /// Needs drift over real time while the app is closed or open.
  void decay(Duration elapsed) {
    final hours = elapsed.inSeconds / 3600;
    if (hours <= 0) return;
    // Empty in ~10 h (faster for big eaters).
    hunger = (hunger - hours * (0.08 + 0.04 * individual.appetite)).clamp(
      0.0,
      1.0,
    );
    // Happiness slides toward a baseline set by how well fed they are.
    final target = 0.35 + 0.3 * hunger;
    final k = 1 - math.exp(-hours / 6);
    happiness = (happiness + (target - happiness) * k).clamp(0.0, 1.0);
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'barcode': barcode,
    'seed': individualSeed,
    'caughtAt': caughtAt.toIso8601String(),
    'nickname': nickname,
    'home': home.name,
    'hunger': hunger,
    'happiness': happiness,
    'affection': affection,
    'extra': extraNeeds,
  };

  factory Creature.fromJson(Map<String, Object?> j) => Creature(
    id: j['id']! as String,
    barcode: j['barcode']! as String,
    individualSeed: (j['seed']! as num).toInt(),
    caughtAt: DateTime.parse(j['caughtAt']! as String),
    nickname: j['nickname'] as String?,
    home: Home.values.firstWhere(
      (h) => h.name == j['home'],
      orElse: () => Home.box,
    ),
    hunger: (j['hunger'] as num?)?.toDouble() ?? 0.7,
    happiness: (j['happiness'] as num?)?.toDouble() ?? 0.6,
    affection: (j['affection'] as num?)?.toInt() ?? 0,
    extraNeeds: {
      for (final e in ((j['extra'] as Map?) ?? const {}).entries)
        e.key as String: (e.value as num).toDouble(),
    },
  );
}
