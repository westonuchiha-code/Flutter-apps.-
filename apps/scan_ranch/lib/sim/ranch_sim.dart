// The ranch simulation: creatures wander, look for food when hungry, eat,
// greet each other and react to being petted. Pure logic (no drawing), so
// it can be tested; the ranch screen draws whatever this describes.
//
// New behaviours (playing with toys, sleeping, making messes to clean up,
// leaving on adventures) slot in as new [ActorState]s and a branch in
// [RanchSim._decide].
import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import '../model/creature.dart';
import '../model/items.dart';

enum ActorState { idle, walking, seekFood, eating, greeting, petted }

enum ParticleKind { heart, note, crumb, sparkle, exclaim }

class Particle {
  Particle(this.kind, this.pos, this.vel, this.life) : maxLife = life;
  final ParticleKind kind;
  Offset pos;
  Offset vel;
  double life;
  final double maxLife;
}

class FoodDrop {
  FoodDrop(this.id, this.kind, this.pos) : bitesLeft = kind.bites;
  final int id;
  final ItemKind kind;
  final Offset pos;
  int bitesLeft;

  /// Time since dropped (for the drop animation).
  double age = 0;
}

/// One creature on the field.
class Actor {
  Actor(this.creature, this.pos);

  final Creature creature;
  Offset pos;
  Offset? target;
  ActorState state = ActorState.idle;
  double timer = 1;
  double facing = 1; // 1 = right, -1 = left
  double walkPhase = 0;
  double blinkIn = 3;
  double blinking = 0;
  double hop = 0; // vertical bounce in px (petting, greeting)
  double chew = 0; // mouth animation while eating
  FoodDrop? food;
  Actor? partner;

  String get id => creature.id;
  bool get moving =>
      state == ActorState.walking || state == ActorState.seekFood;
  bool get happyFace =>
      state == ActorState.petted ||
      state == ActorState.greeting ||
      state == ActorState.eating;
  bool get busy =>
      state == ActorState.eating ||
      state == ActorState.petted ||
      state == ActorState.greeting;
}

class RanchSim {
  RanchSim({math.Random? random, this.onAte, this.onPetted})
    : _random = random ?? math.Random();

  final math.Random _random;

  /// Called for every bite eaten.
  final void Function(Creature c, ItemKind food)? onAte;

  /// Called when a creature is petted.
  final void Function(Creature c)? onPetted;

  Size size = const Size(400, 600);
  final List<Actor> actors = [];
  final List<FoodDrop> food = [];
  final List<Particle> particles = [];
  int _nextFoodId = 0;

  /// Top of the walkable ground, as a fraction of the height.
  static const horizon = 0.3;

  double get groundTop => size.height * horizon;

  /// Perspective scale at height [y]: smaller further away.
  double depthScale(double y) {
    final t = ((y - groundTop) / (size.height - groundTop)).clamp(0.0, 1.0);
    return 0.65 + 0.45 * t;
  }

  /// Base drawing size of a creature in pixels (before depth scale).
  double baseSize(Creature c) =>
      math.min(size.width, size.height) * 0.16 * c.look.size;

  void resize(Size s) {
    if (s.width <= 0 || s.height <= 0) return;
    final old = size;
    size = s;
    if (old == s) return;
    for (final a in actors) {
      a.pos = Offset(
        a.pos.dx / old.width * s.width,
        a.pos.dy / old.height * s.height,
      );
      a.target = null;
      a.state = ActorState.idle;
    }
  }

  Offset _randomSpot() => Offset(
    size.width * (0.08 + 0.84 * _random.nextDouble()),
    groundTop + 20 + (size.height - groundTop - 40) * _random.nextDouble(),
  );

  /// Makes the field match the creatures that live in the ranch.
  void sync(List<Creature> ranch) {
    final ids = {for (final c in ranch) c.id};
    actors.removeWhere((a) => !ids.contains(a.id));
    for (final a in actors) {
      if (a.partner != null && !ids.contains(a.partner!.id)) a.partner = null;
    }
    final have = {for (final a in actors) a.id};
    for (final c in ranch) {
      if (!have.contains(c.id)) {
        final a = Actor(c, _randomSpot())
          ..timer = _random.nextDouble() * 2
          ..blinkIn = 1 + _random.nextDouble() * 3;
        actors.add(a);
        _burst(a.pos, ParticleKind.sparkle, 6);
      }
    }
  }

  /// The creature under [p], front-most first.
  Actor? hitTest(Offset p) {
    final sorted = [...actors]..sort((a, b) => b.pos.dy.compareTo(a.pos.dy));
    for (final a in sorted) {
      final r = baseSize(a.creature) * depthScale(a.pos.dy) * 0.6;
      final centre = a.pos.translate(0, -r * 0.8);
      if ((p - centre).distance < r * 1.2) return a;
    }
    return null;
  }

  void pet(Actor a) {
    if (a.state == ActorState.eating) a.food = null;
    a.state = ActorState.petted;
    a.timer = 1.0;
    a.partner = null;
    a.target = null;
    _burst(
      a.pos.translate(0, -baseSize(a.creature) * 0.9),
      ParticleKind.heart,
      3,
    );
    onPetted?.call(a.creature);
  }

  /// Drops food at [p] (clamped onto the ground). Hungry creatures notice.
  FoodDrop dropFood(ItemKind kind, Offset p) {
    final drop = FoodDrop(
      _nextFoodId++,
      kind,
      Offset(
        p.dx.clamp(size.width * 0.05, size.width * 0.95),
        p.dy.clamp(groundTop + 10, size.height - 10),
      ),
    );
    food.add(drop);
    for (final a in actors) {
      if (!a.busy && _isHungry(a)) {
        _goEat(a, drop);
        _burst(
          a.pos.translate(0, -baseSize(a.creature)),
          ParticleKind.exclaim,
          1,
        );
      }
    }
    return drop;
  }

  bool _isHungry(Actor a) =>
      a.creature.hunger < 0.6 + 0.35 * a.creature.individual.appetite;

  void _goEat(Actor a, FoodDrop f) {
    a
      ..state = ActorState.seekFood
      ..food = f
      ..partner = null
      ..target = f.pos.translate(
        (a.pos.dx < f.pos.dx ? -1 : 1) * baseSize(a.creature) * 0.45,
        2,
      );
  }

  double _speed(Actor a) =>
      (30 + 55 * a.creature.individual.energy) *
      depthScale(a.pos.dy) *
      (size.width / 400).clamp(0.8, 2.0);

  void step(double dt) {
    if (dt <= 0) return;
    dt = math.min(dt, 0.1);
    for (final f in food) {
      f.age += dt;
    }
    for (final a in actors) {
      _stepActor(a, dt);
    }
    _separate(dt);
    for (final p in particles) {
      p
        ..pos += p.vel * dt
        ..vel = p.kind == ParticleKind.crumb
            ? p.vel.translate(0, 300 * dt)
            : p.vel * (1 - 0.8 * dt)
        ..life -= dt;
    }
    particles.removeWhere((p) => p.life <= 0);
    food.removeWhere((f) => f.bitesLeft <= 0);
  }

  void _stepActor(Actor a, double dt) {
    // Blinking.
    a.blinking = math.max(0, a.blinking - dt);
    a.blinkIn -= dt;
    if (a.blinkIn <= 0) {
      a.blinking = 0.13;
      a.blinkIn = 2 + _random.nextDouble() * 4;
    }
    a.hop = 0;
    a.chew = 0;
    a.timer -= dt;

    switch (a.state) {
      case ActorState.idle:
        if (a.timer <= 0) _decide(a);
      case ActorState.walking:
      case ActorState.seekFood:
        if (a.state == ActorState.seekFood &&
            (a.food == null || a.food!.bitesLeft <= 0)) {
          a.state = ActorState.idle;
          a.timer = 0.5;
          break;
        }
        if (a.partner != null) {
          final p = a.partner!;
          if (p.busy && p.partner != a) {
            a.partner = null;
          } else {
            a.target = p.pos.translate(
              (a.pos.dx < p.pos.dx ? -1 : 1) * baseSize(a.creature) * 0.9,
              0,
            );
          }
        }
        if (_walkTowardTarget(a, dt)) _arrive(a);
        if (a.timer < -12) {
          // Took too long (blocked): give up.
          a.state = ActorState.idle;
          a.timer = 1;
        }
      case ActorState.eating:
        final f = a.food;
        if (f == null || f.bitesLeft <= 0) {
          a.state = ActorState.idle;
          a.timer = 1 + _random.nextDouble();
          break;
        }
        a.facing = f.pos.dx >= a.pos.dx ? 1 : -1;
        a.chew = (math.sin(a.timer * 18) + 1) / 2;
        if (a.timer <= 0) {
          f.bitesLeft--;
          onAte?.call(a.creature, f.kind);
          _burst(f.pos, ParticleKind.crumb, 4);
          if (f.bitesLeft > 0 && _isHungry(a)) {
            a.timer = 1.1;
          } else {
            a.state = ActorState.idle;
            a.timer = 1.5;
            _burst(
              a.pos.translate(0, -baseSize(a.creature)),
              ParticleKind.heart,
              1,
            );
          }
        }
      case ActorState.greeting:
        a.hop = math.max(0, math.sin(a.timer * 9)) * 6;
        if (a.partner != null) {
          a.facing = a.partner!.pos.dx >= a.pos.dx ? 1 : -1;
        }
        if (a.timer <= 0) {
          a
            ..state = ActorState.idle
            ..partner = null
            ..timer = 1 + _random.nextDouble() * 2;
        }
      case ActorState.petted:
        a.hop = math.max(0, math.sin((1 - a.timer) * math.pi * 3)) * 10;
        if (a.timer <= 0) {
          a.state = ActorState.idle;
          a.timer = 0.8 + _random.nextDouble();
        }
    }
  }

  /// Chooses what an idle creature does next.
  void _decide(Actor a) {
    final ind = a.creature.individual;
    // 1. Food, if hungry.
    if (food.isNotEmpty && _isHungry(a)) {
      final nearest = food.reduce(
        (x, y) => (x.pos - a.pos).distance < (y.pos - a.pos).distance ? x : y,
      );
      _goEat(a, nearest);
      return;
    }
    // 2. Say hello to someone.
    final others = actors.where((o) => o != a && !o.busy).toList();
    if (others.isNotEmpty &&
        _random.nextDouble() < 0.12 + 0.3 * ind.sociability) {
      final other = others[_random.nextInt(others.length)];
      a
        ..state = ActorState.walking
        ..partner = other
        ..timer = 0;
      return;
    }
    // 3. Rest a while, or 4. wander (curious ones go further).
    if (_random.nextDouble() < 0.35 - 0.2 * ind.energy) {
      a.timer = 1.5 + _random.nextDouble() * 3;
      return;
    }
    final reach = 0.25 + 0.6 * ind.curiosity;
    final spot = _randomSpot();
    a
      ..state = ActorState.walking
      ..target = Offset.lerp(a.pos, spot, reach)
      ..timer = 0;
  }

  /// Moves toward the target; returns true on arrival.
  bool _walkTowardTarget(Actor a, double dt) {
    final t = a.target;
    if (t == null) return true;
    final d = t - a.pos;
    final dist = d.distance;
    final speed = _speed(a);
    a.walkPhase += dt * speed / 9;
    if (d.dx.abs() > 2) a.facing = d.dx > 0 ? 1 : -1;
    if (dist <= speed * dt || dist < 3) {
      a.pos = t;
      return true;
    }
    a.pos += d / dist * speed * dt;
    return false;
  }

  void _arrive(Actor a) {
    a.target = null;
    if (a.state == ActorState.seekFood && a.food != null) {
      a
        ..state = ActorState.eating
        ..timer = 0.9;
      return;
    }
    final p = a.partner;
    if (p != null && !p.busy) {
      for (final x in [a, p]) {
        x
          ..state = ActorState.greeting
          ..timer = 1.6
          ..target = null;
      }
      a.partner = p;
      p.partner = a;
      final mid = Offset.lerp(
        a.pos,
        p.pos,
        0.5,
      )!.translate(0, -baseSize(a.creature));
      final kind =
          a.creature.individual.sociability +
                  p.creature.individual.sociability >
              1
          ? ParticleKind.heart
          : ParticleKind.note;
      _burst(mid, kind, 2);
      return;
    }
    a
      ..state = ActorState.idle
      ..partner = null
      ..timer = 1 + _random.nextDouble() * 3;
  }

  /// Gently pushes overlapping creatures apart.
  void _separate(double dt) {
    for (var i = 0; i < actors.length; i++) {
      for (var j = i + 1; j < actors.length; j++) {
        final a = actors[i], b = actors[j];
        final minD = (baseSize(a.creature) + baseSize(b.creature)) * 0.3;
        final d = b.pos - a.pos;
        final dist = d.distance;
        if (dist > 0.01 && dist < minD) {
          final push = d / dist * (minD - dist) * math.min(1, dt * 4);
          if (!a.busy) a.pos -= push;
          if (!b.busy) b.pos += push;
        }
      }
    }
    for (final a in actors) {
      a.pos = Offset(
        a.pos.dx.clamp(size.width * 0.04, size.width * 0.96),
        a.pos.dy.clamp(groundTop + 8, size.height - 6),
      );
    }
  }

  void _burst(Offset at, ParticleKind kind, int n) {
    for (var i = 0; i < n; i++) {
      final angle = -math.pi / 2 + (_random.nextDouble() - 0.5) * 1.6;
      final speed = kind == ParticleKind.crumb ? 60.0 : 35.0;
      particles.add(
        Particle(
          kind,
          at.translate((_random.nextDouble() - 0.5) * 16, 0),
          Offset(math.cos(angle), math.sin(angle)) *
              speed *
              (0.6 + _random.nextDouble()),
          kind == ParticleKind.crumb ? 0.5 : 1.4,
        ),
      );
    }
  }
}
