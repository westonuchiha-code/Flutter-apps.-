import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'creature.dart';
import 'genome.dart';
import 'items.dart';

/// How many creatures can roam the ranch at once (the rest wait in the box).
const ranchCapacity = 8;

/// What a scan produced.
sealed class ScanResult {
  const ScanResult(this.code);
  final String code;
}

/// A new creature to name and keep (not yet added).
class CreatureFound extends ScanResult {
  const CreatureFound(super.code, this.creature, {required this.alreadyOwned});
  final Creature creature;

  /// How many of this species the player already has.
  final int alreadyOwned;
}

/// Some barcodes hold items instead of creatures (like the old handhelds).
class ItemFound extends ScanResult {
  const ItemFound(super.code, this.kind, this.count);
  final ItemKind kind;
  final int count;
}

/// This item barcode was already used today.
class ItemAlreadyClaimed extends ScanResult {
  const ItemAlreadyClaimed(super.code, this.kind);
  final ItemKind kind;
}

/// Persists the game as JSON.
abstract class SaveStore {
  Future<String?> load();
  Future<void> save(String json);
}

class FileSaveStore implements SaveStore {
  FileSaveStore(this.directory);
  final Directory directory;

  File get _file => File(p.join(directory.path, 'ranch.json'));

  @override
  Future<String?> load() async =>
      await _file.exists() ? _file.readAsString() : null;

  @override
  Future<void> save(String json) async {
    await directory.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(json);
    await tmp.rename(_file.path);
  }
}

class MemorySaveStore implements SaveStore {
  MemorySaveStore([this.saved]);
  String? saved;
  @override
  Future<String?> load() async => saved;
  @override
  Future<void> save(String json) async => saved = json;
}

/// All game data: creatures, inventory, and the rules for changing them.
class GameState extends ChangeNotifier {
  GameState(this.store, {DateTime Function()? clock, math.Random? random})
    : _clock = clock ?? DateTime.now,
      _random = random ?? math.Random() {
    _lastDecay = _clock();
  }

  final SaveStore store;
  final DateTime Function() _clock;
  final math.Random _random;

  final List<Creature> creatures = [];
  final Map<String, int> inventory = {};

  /// Item barcode → day it was last claimed (yyyy-mm-dd).
  final Map<String, String> claimedItems = {};
  late DateTime _lastDecay;
  Timer? _saveTimer;

  List<Creature> get ranch =>
      creatures.where((c) => c.home == Home.ranch).toList();
  List<Creature> get box => creatures.where((c) => c.home == Home.box).toList();
  bool get ranchFull => ranch.length >= ranchCapacity;

  Creature? byId(String id) {
    for (final c in creatures) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> load() async {
    try {
      final text = await store.load();
      if (text != null) _fromJson(jsonDecode(text) as Map<String, Object?>);
    } catch (_) {
      // Corrupt save: start fresh rather than crash.
    }
    applyDecay();
    notifyListeners();
  }

  /// Applies real-time need decay since the last update.
  void applyDecay() {
    final now = _clock();
    final elapsed = now.difference(_lastDecay);
    _lastDecay = now;
    if (elapsed.isNegative) return;
    for (final c in creatures) {
      c.decay(elapsed);
    }
  }

  // --- Scanning --------------------------------------------------------------

  /// Decides what a barcode contains. Does not change the game until the
  /// creature is kept ([keep]) or the item is claimed (done here).
  ScanResult scan(String raw) {
    final code = normalizeBarcode(raw);
    final itemRoll = SeededRandom(hashString('item:$code'));
    if (itemRoll.nextInt(100) < 12) {
      final kind = itemRoll.chance(0.6) ? cake : meat;
      final today = _day(_clock());
      if (claimedItems[code] == today) return ItemAlreadyClaimed(code, kind);
      final count = 1 + itemRoll.nextInt(3);
      claimedItems[code] = today;
      inventory[kind.id] = (inventory[kind.id] ?? 0) + count;
      _changed();
      return ItemFound(code, kind, count);
    }
    final creature = Creature(
      id: 'c${_clock().microsecondsSinceEpoch}${_random.nextInt(1000)}',
      barcode: code,
      individualSeed: _random.nextInt(1 << 31),
      caughtAt: _clock(),
      hunger: 0.6,
      happiness: 0.6,
    );
    final owned = creatures.where((c) => c.barcode == code).length;
    return CreatureFound(code, creature, alreadyOwned: owned);
  }

  /// Adds a scanned creature; it goes to the ranch if there is room.
  void keep(Creature c, {String? nickname}) {
    c.nickname = nickname;
    c.home = ranchFull ? Home.box : Home.ranch;
    creatures.add(c);
    _changed();
  }

  static String _day(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  // --- Care ------------------------------------------------------------------

  void rename(Creature c, String? nickname) {
    c.nickname = nickname?.trim().isEmpty ?? true ? null : nickname!.trim();
    _changed();
  }

  /// Returns false if the ranch is full.
  bool moveTo(Creature c, Home home) {
    if (home == Home.ranch && c.home != Home.ranch && ranchFull) return false;
    c.home = home;
    _changed();
    return true;
  }

  void release(Creature c) {
    creatures.remove(c);
    _changed();
  }

  void pet(Creature c) {
    c.happiness = math.min(1, c.happiness + 0.04);
    c.affection++;
    _changed(notify: false);
  }

  void ate(Creature c, ItemKind food) {
    c.hunger = math.min(1, c.hunger + food.nutrition);
    c.happiness = math.min(1, c.happiness + food.joy);
    _changed(notify: false);
  }

  /// Takes one of [kind] from the inventory. Returns false if none left.
  bool useItem(ItemKind kind) {
    if (kind.unlimited) return true;
    final n = inventory[kind.id] ?? 0;
    if (n <= 0) return false;
    inventory[kind.id] = n - 1;
    _changed();
    return true;
  }

  int count(ItemKind kind) => kind.unlimited ? -1 : inventory[kind.id] ?? 0;

  // --- Saving ----------------------------------------------------------------

  void _changed({bool notify = true}) {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), saveNow);
    if (notify) notifyListeners();
  }

  Future<void> saveNow() async {
    _saveTimer?.cancel();
    await store.save(jsonEncode(toJson()));
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'lastDecay': _lastDecay.toIso8601String(),
    'creatures': [for (final c in creatures) c.toJson()],
    'inventory': inventory,
    'claimed': claimedItems,
  };

  void _fromJson(Map<String, Object?> j) {
    creatures
      ..clear()
      ..addAll([
        for (final c in (j['creatures'] as List? ?? const []))
          Creature.fromJson((c as Map).cast<String, Object?>()),
      ]);
    inventory
      ..clear()
      ..addAll({
        for (final e in ((j['inventory'] as Map?) ?? const {}).entries)
          e.key as String: (e.value as num).toInt(),
      });
    claimedItems
      ..clear()
      ..addAll((j['claimed'] as Map? ?? const {}).cast<String, String>());
    final last = DateTime.tryParse(j['lastDecay'] as String? ?? '');
    if (last != null) _lastDecay = last;
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
