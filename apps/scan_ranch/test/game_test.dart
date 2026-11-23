import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:scan_ranch/model/creature.dart';
import 'package:scan_ranch/model/game_state.dart';
import 'package:scan_ranch/model/genome.dart';
import 'package:scan_ranch/model/items.dart';
import 'package:scan_ranch/sim/ranch_sim.dart';

import 'dart:math' as math;

GameState newGame({DateTime? now, MemorySaveStore? store}) {
  var t = now ?? DateTime(2026, 1, 1, 12);
  return GameState(
    store ?? MemorySaveStore(),
    clock: () => t,
    random: math.Random(1),
  );
}

/// Finds barcodes that hold a creature / an item.
String creatureCode([int start = 0]) {
  for (var i = start; ; i++) {
    final code = '${700000000000 + i}';
    if (newGame().scan(code) is CreatureFound) return code;
  }
}

String itemCode() {
  for (var i = 0; ; i++) {
    final code = '${700000000000 + i}';
    if (newGame().scan(code) is ItemFound) return code;
  }
}

void main() {
  test('only approved silhouettes are used', () {
    for (var i = 0; i < 200; i++) {
      expect(
        Genome.fromBarcode('$i').silhouette,
        inInclusiveRange(0, silhouetteCount - 1),
      );
      expect(
        Genome.fromBarcode('$i').palette,
        inInclusiveRange(0, paletteCount - 1),
      );
    }
  });

  test('scanning a creature then keeping it; ranch fills, then box', () {
    final game = newGame();
    for (var i = 0; i < ranchCapacity + 2; i++) {
      final r = game.scan(creatureCode(i * 50)) as CreatureFound;
      game.keep(r.creature, nickname: i == 0 ? 'Rex' : null);
    }
    expect(game.ranch, hasLength(ranchCapacity));
    expect(game.box, hasLength(2));
    expect(game.creatures.first.name, 'Rex');
    // Ranch full: moving a boxed one in fails until there is room.
    expect(game.moveTo(game.box.first, Home.ranch), isFalse);
    game.moveTo(game.ranch.first, Home.box);
    expect(game.moveTo(game.box.first, Home.ranch), isTrue);
  });

  test('same barcode twice: same species, different individual', () {
    final game = newGame();
    final code = creatureCode();
    final a = (game.scan(code) as CreatureFound).creature;
    game.keep(a);
    final again = game.scan(code) as CreatureFound;
    expect(again.alreadyOwned, 1);
    expect(again.creature.genome.speciesName, a.genome.speciesName);
    expect(again.creature.individualSeed, isNot(a.individualSeed));
  });

  test('item barcodes give food once per day', () {
    final game = newGame();
    final code = itemCode();
    final first = game.scan(code) as ItemFound;
    expect(game.count(first.kind), first.count);
    expect(game.scan(code), isA<ItemAlreadyClaimed>());
    expect(game.useItem(first.kind), isTrue);
    expect(game.useItem(berry), isTrue); // berries are unlimited
  });

  test('needs decay over time and save/load round trip', () async {
    var now = DateTime(2026, 1, 1, 12);
    final store = MemorySaveStore();
    final game = GameState(store, clock: () => now, random: math.Random(2));
    final c = (game.scan(creatureCode()) as CreatureFound).creature;
    game.keep(c, nickname: 'Fang');
    final before = c.hunger;
    now = now.add(const Duration(hours: 5));
    game.applyDecay();
    expect(c.hunger, lessThan(before));
    game.ate(c, meat);
    await game.saveNow();

    final loaded = GameState(store, clock: () => now);
    await loaded.load();
    expect(loaded.creatures.single.name, 'Fang');
    expect(loaded.creatures.single.hunger, closeTo(c.hunger, 1e-9));
  });

  group('ranch simulation', () {
    late GameState game;
    late List<Creature> ranch;
    setUp(() {
      game = newGame();
      for (var i = 0; i < 3; i++) {
        game.keep((game.scan(creatureCode(i * 40)) as CreatureFound).creature);
      }
      ranch = game.ranch;
    });

    test('creatures stay on the ground', () {
      final sim = RanchSim(random: math.Random(3))
        ..resize(const Size(400, 700))
        ..sync(ranch);
      for (var i = 0; i < 2000; i++) {
        sim.step(1 / 30);
      }
      for (final a in sim.actors) {
        expect(a.pos.dx, inInclusiveRange(0, 400));
        expect(a.pos.dy, inInclusiveRange(sim.groundTop, 700));
      }
    });

    test('hungry creatures find and eat dropped food', () {
      final eaten = <String>[];
      final sim =
          RanchSim(random: math.Random(4), onAte: (c, k) => eaten.add(c.id))
            ..resize(const Size(400, 700))
            ..sync(ranch);
      for (final c in ranch) {
        c.hunger = 0.1;
      }
      sim.dropFood(berry, const Offset(200, 500));
      for (var i = 0; i < 30 * 20 && eaten.isEmpty; i++) {
        sim.step(1 / 30);
      }
      expect(eaten, isNotEmpty);
    });

    test('petting triggers the callback and a happy hop', () {
      final petted = <String>[];
      final sim =
          RanchSim(random: math.Random(5), onPetted: (c) => petted.add(c.id))
            ..resize(const Size(400, 700))
            ..sync(ranch);
      final a = sim.actors.first;
      final hit = sim.hitTest(
        a.pos.translate(0, -sim.baseSize(a.creature) * 0.5),
      );
      expect(hit, isNotNull);
      sim.pet(hit!);
      expect(petted, [hit.id]);
      expect(hit.state, ActorState.petted);
    });
  });
}
