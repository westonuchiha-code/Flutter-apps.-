/// The music video director: a song map + a style (+ a seed) → a Puppet
/// Stage movie. People are placed by the style's formation, move by
/// section (leads mouth the vocal bars, the DJ cuts on DJ bars), and the
/// camera cuts on the bar with shots described in words (close on X, low
/// fisheye, overhead...), placed around the people and kept clear of
/// anyone standing in the way.
library;

import 'dart:math' as math;

import '../cast.dart';
import '../look.dart';
import '../movie.dart';
import '../props.dart';
import '../sets.dart';
import 'song_map.dart';
import 'styles.dart';

/// Where a camera stands and looks.
typedef Frame = ({
  double x,
  double y,
  double z,
  double tx,
  double ty,
  double tz,
  double fov,
});

(double yaw, double pitch) aim(Frame f) {
  final dx = f.tx - f.x, dy = f.ty - f.y, dz = f.tz - f.z;
  final len = math.sqrt(dx * dx + dy * dy + dz * dz);
  return (math.atan2(-dx, -dz), math.asin((dy / len).clamp(-1.0, 1.0)));
}

/// Something in a place the camera must see past (people and props).
typedef Blocker = ({double x, double z, double top, double r, String id});

/// True when the segment from (ax, ay, az) to (bx, by, bz) passes through
/// [b]'s upright cylinder.
bool _blocks(
  Blocker b,
  double ax,
  double ay,
  double az,
  double bx,
  double by,
  double bz,
) {
  for (var k = 1; k < 12; k++) {
    final t = k / 12;
    final x = ax + (bx - ax) * t, y = ay + (by - ay) * t;
    final z = az + (bz - az) * t;
    if (y > b.top || y < 0) continue;
    if ((x - b.x) * (x - b.x) + (z - b.z) * (z - b.z) < b.r * b.r) {
      return true;
    }
  }
  return false;
}

class Director {
  Director(this.map, this.style, {this.seed = 1}) : _r = math.Random(seed);
  final SongMap map;
  final MvStyle style;
  final int seed;
  final math.Random _r;

  T _pick<T>(List<T> l) => l[_r.nextInt(l.length)];

  String _weighted(Map<String, int> w) {
    final total = w.values.fold<int>(0, (a, b) => a + b);
    var k = _r.nextInt(math.max(1, total));
    for (final e in w.entries) {
      k -= e.value;
      if (k < 0) return e.key;
    }
    return w.keys.first;
  }

  V _bySection<V>(Map<String, V> m, String section, V fallback) =>
      m[section] ?? m['all'] ?? fallback;

  /// Positions for [n] people in a place, by the style's formation.
  List<(double, double, double)> _layout(int n, {required bool main}) {
    final out = <(double, double, double)>[];
    if (!main) {
      for (var i = 0; i < n; i++) {
        out.add((i * 1.3 - (n - 1) * 0.65, 0.0, 180.0 + (i.isEven ? 10 : -10)));
      }
      return out;
    }
    switch (style.formation) {
      case 'circle':
        for (var i = 0; i < n; i++) {
          final a = i / n * math.pi * 2 + 0.4;
          final x = math.sin(a) * 1.7, z = math.cos(a) * 1.7;
          // Facing the middle.
          out.add((x, z, math.atan2(-x, -z) * 180 / math.pi));
        }
      case 'row':
        for (var i = 0; i < n; i++) {
          out.add((i * 1.15 - (n - 1) * 0.575, 0.2, 0.0));
        }
      case 'scatter':
        for (var i = 0; i < n; i++) {
          final a =
              (i / n) * math.pi * 1.6 - math.pi * 0.8 + _r.nextDouble() * 0.3;
          final rad = 1.2 + (i % 3) * 0.9 + _r.nextDouble() * 0.4;
          final x = math.sin(a) * rad, z = math.cos(a) * rad * 0.7 + 0.4;
          out.add((x, z, -x * 14 + (_r.nextDouble() - 0.5) * 30));
        }
      default: // line: front row, then a wider row behind
        final front = (n / 2).ceil().clamp(1, 3);
        for (var i = 0; i < n; i++) {
          if (i < front) {
            out.add((
              i * 1.4 - (front - 1) * 0.7,
              0.4,
              (i - (front - 1) / 2) * -8,
            ));
          } else {
            final k = i - front, m = n - front;
            out.add((k * 1.3 - (m - 1) * 0.65, -1.0, (k - (m - 1) / 2) * -6));
          }
        }
    }
    return out;
  }

  Movie direct({MusicRef? music, String name = ''}) {
    final places = style.places;
    final movie = Movie(
      name: name.isEmpty ? '${style.name} video' : name,
      set: places.first.set ?? StageSet.studio,
      mood: places.first.mood,
      places: places.skip(1).toList(),
      music: music,
      look:
          FilmLook.presets[_bySection(style.looks, 'verse', ['Clean']).first] ??
          FilmLook.none,
    );
    var id = 0;
    String nextId() => 'mv${id++}';

    // ---- Props. ----
    final blockers = <int, List<Blocker>>{};
    final turntables = <int, (double, double)>{};
    final propActors = <Actor>[];
    for (final d in style.props) {
      final a = Actor(
        id: nextId(),
        kind: Kind.man,
        prop: d.prop,
        name: d.prop.label,
        x: d.x,
        z: d.z,
        facing: d.facing,
        place: d.place,
        scale: d.scale,
      );
      movie.actors.add(a);
      propActors.add(a);
      if (d.prop == Prop.turntables) turntables[d.place] = (d.x, d.z);
      final tall = switch (d.prop) {
        Prop.tree || Prop.pine || Prop.palm || Prop.lampPost => 4.0,
        Prop.speakers => 2.1,
        Prop.chessKing || Prop.chessKnight || Prop.chessRook => 1.0,
        _ => 0.9,
      };
      blockers.putIfAbsent(d.place, () => []).add((
        x: d.x,
        z: d.z,
        top: tall * d.scale,
        r: (d.prop == Prop.turntables ? 0.7 : 0.45) * d.scale,
        id: a.id,
      ));
    }

    // ---- People. ----
    final people = <(Member, Actor)>[];
    final byPlace = <int, List<Member>>{};
    for (final m in style.cast) {
      if (m.role == 'dj' && turntables.containsKey(m.place)) continue;
      byPlace.putIfAbsent(m.place, () => []).add(m);
    }
    final spots = <Member, (double, double, double)>{};
    byPlace.forEach((place, members) {
      final lay = _layout(members.length, main: place == 0);
      for (var i = 0; i < members.length; i++) {
        spots[members[i]] = lay[i];
      }
    });
    for (final m in style.cast) {
      var spot = spots[m];
      if (spot == null) {
        // The DJ stands behind the decks.
        final t = turntables[m.place]!;
        spot = (t.$1, t.$2 - 0.55, 0.0);
      }
      final a = Actor(
        id: nextId(),
        kind: m.kind,
        name: m.name.isEmpty ? '${m.role} ${people.length + 1}' : m.name,
        x: spot.$1,
        z: spot.$2,
        facing: spot.$3,
        place: m.place,
        look: m.look,
        extras: m.extras,
        holds: m.holds,
        body: m.body,
        animal: m.animal,
      );
      movie.actors.add(a);
      people.add((m, a));
      blockers.putIfAbsent(m.place, () => []).add((
        x: a.x,
        z: a.z,
        top: 1.8 * m.body.height,
        r: 0.32,
        id: a.id,
      ));
    }

    // ---- Moves, bar by bar. ----
    final bar = map.barSeconds;
    for (final (m, a) in people) {
      final table =
          style.moves[m.role] ??
          const {
            'all': ['idle'],
          };
      String? current;
      var length = 0.0;
      void flush() {
        if (current != null && length > 0) {
          a.actions.add(
            Action(ActionType.move, move: current, seconds: length),
          );
        }
        length = 0;
      }

      if (map.offset > 0) {
        a.actions.add(
          Action(ActionType.move, move: 'idle', seconds: map.offset),
        );
      }
      // A move holds for 2 bars before it may change (less twitchy).
      String? held;
      for (var b = 0; b < map.bars.length; b++) {
        final info = map.bars[b];
        String move;
        if (m.role == 'lead' && info.vocal) {
          move = m.animal == null ? 'rapMic' : 'idle';
        } else if (m.role == 'dj' && info.dj) {
          move = 'scratch';
        } else if (b.isEven || held == null) {
          final list = _bySection(
            table,
            info.section,
            table['all'] ?? ['idle'],
          );
          move = _pick(list);
          held = move;
        } else {
          move = held;
        }
        if (move != current) {
          flush();
          current = move;
        }
        length += bar;
      }
      flush();
    }

    // ---- Shots. ----
    var b = 0.0;
    var lastKind = '';
    while (b < map.bars.length) {
      final info = map.bars[b.floor()];
      final per = _bySection(style.cutBars, info.section, 2.0);
      // Hotter bars cut faster in the faster styles.
      final len = per >= 2 && info.energy > 0.85 ? per / 2 : per;
      final weights = _bySection(style.shots, info.section, const {'wide': 1});
      var kind = _weighted(weights);
      if (kind == lastKind && weights.length > 1) kind = _weighted(weights);
      lastKind = kind;
      // Who to film.
      final landPlaces = [
        for (var i = 0; i < movie.placeCount; i++)
          if (movie.placeAt(i).land != null) i,
      ];
      int place;
      Actor? subject;
      if (kind == 'land' && landPlaces.isNotEmpty) {
        place = _pick(landPlaces);
        final there = people.where((p) => p.$2.place == place).toList();
        subject = there.isEmpty ? null : _pick(there).$2;
      } else {
        if (kind == 'land') kind = 'wide';
        Iterable<(Member, Actor)> pool = people.where((p) => p.$2.place == 0);
        if (info.vocal) {
          final leads = pool.where((p) => p.$1.role == 'lead');
          if (leads.isNotEmpty) pool = leads;
        } else if (info.dj) {
          final djs = people.where((p) => p.$1.role == 'dj');
          if (djs.isNotEmpty) pool = djs;
        } else if (_r.nextDouble() < 0.25) {
          // Now and then, somewhere else.
          pool = people;
        }
        final list = pool.toList();
        subject = list.isEmpty ? null : _pick(list).$2;
        place = subject?.place ?? 0;
      }
      if (kind == 'insert') {
        final ps = propActors.where((p) => p.place == place).toList();
        if (ps.isNotEmpty) {
          subject = _pick(ps);
        } else {
          kind = 'medium';
        }
      }
      final frame = _frameFor(
        kind,
        subject,
        people.where((p) => p.$2.place == place).map((p) => p.$2).toList(),
        blockers[place] ?? const [],
        land: movie.placeAt(place).land != null,
      );
      final (yaw, pitch) = aim(frame);
      List<double>? end;
      if (_r.nextDouble() < style.drift) {
        final e = _drift(frame, _weighted(style.drifts));
        final (y2, p2) = aim(e);
        end = [e.x, e.y, e.z, y2, p2];
      }
      var look =
          FilmLook.presets[_pick(
            _bySection(style.looks, info.section, ['Clean']),
          )] ??
          FilmLook.none;
      if (kind == 'low') {
        look = look.copyWith(fisheye: math.max(look.fisheye, 0.75));
      }
      movie.shots.add(
        Shot(
          map.timeOf(b),
          frame.x,
          frame.y,
          frame.z,
          yaw,
          pitch,
          fov: frame.fov,
          place: place,
          look: look,
          end: end,
        ),
      );
      b += len;
    }
    return movie;
  }

  /// A camera for a kind of shot on [subject] (with [group] in the same
  /// place), turned away from anything in the way.
  Frame _frameFor(
    String kind,
    Actor? subject,
    List<Actor> group,
    List<Blocker> blockers, {
    required bool land,
  }) {
    var sx = 0.0, sz = 0.0, facing = 0.0, height = 1.75, sc = 1.0;
    if (subject != null) {
      sx = subject.x;
      sz = subject.z;
      facing = subject.facing;
      sc = subject.scale;
      height = subject.prop != null
          ? 0.9 * sc
          : subject.animal != null
          ? 0.7 * sc
          : 1.75 * subject.body.height * sc;
    }
    if (kind == 'wide' && group.isNotEmpty) {
      sx = group.map((a) => a.x).reduce((a, b) => a + b) / group.length;
      sz = group.map((a) => a.z).reduce((a, b) => a + b) / group.length;
      facing = 0;
    }
    // (distance, camera height, target height, fov, side angle)
    var (dist, ch, th, fov, side) = switch (kind) {
      'close' => (1.4, height * 0.92, height * 0.88, 50.0, 15.0),
      'medium' => (2.8, height * 0.85, height * 0.7, 55.0, 20.0),
      'low' => (1.25, 0.4, height * 0.9, 75.0, 10.0),
      'overhead' => (0.35, 6.0, 0.0, 65.0, 0.0),
      'profile' => (2.3, height * 0.8, height * 0.75, 50.0, 80.0),
      'insert' => (1.5, height * 1.3, height * 0.8, 50.0, 25.0),
      'land' => (land ? 16.0 : 6.0, land ? 5.0 : 2.0, 1.2, 50.0, 25.0),
      _ => (land ? 9.0 : 6.5, 1.9, 1.0, 55.0, 12.0),
    };
    if (style.symmetric) side = 0;
    final sign = _r.nextBool() ? 1 : -1;
    final ignore = {subject?.id};
    for (final extra in [0.0, 25.0, -25.0, 50.0, -50.0, 80.0, -80.0, 120.0]) {
      final a = (facing + sign * side + extra) * math.pi / 180;
      var x = sx + math.sin(a) * dist, z = sz + math.cos(a) * dist;
      if (!land) {
        // Stay inside the set's walls.
        x = x.clamp(-7.0, 7.0);
        z = z.clamp(-5.5, 9.0);
      }
      final clear = blockers.every((b) {
        if (ignore.contains(b.id)) return true;
        // Never right up against something (it fills the frame).
        final near = (x - b.x) * (x - b.x) + (z - b.z) * (z - b.z);
        if (near < (b.r + 0.55) * (b.r + 0.55) && ch < b.top + 0.3) {
          return false;
        }
        if (kind == 'wide' && group.any((g) => g.id == b.id)) return true;
        return !_blocks(b, x, ch, z, sx, th, sz);
      });
      if (clear || extra == 120.0) {
        return (x: x, y: ch, z: z, tx: sx, ty: th, tz: sz, fov: fov);
      }
    }
    throw StateError('unreachable');
  }

  /// Where a moving shot ends.
  Frame _drift(Frame f, String how) {
    switch (how) {
      case 'push':
        return (
          x: f.x + (f.tx - f.x) * 0.35,
          y: f.y + (f.ty - f.y) * 0.2,
          z: f.z + (f.tz - f.z) * 0.35,
          tx: f.tx,
          ty: f.ty,
          tz: f.tz,
          fov: f.fov,
        );
      case 'crane':
        return (
          x: f.x,
          y: f.y + 1.6,
          z: f.z,
          tx: f.tx,
          ty: f.ty,
          tz: f.tz,
          fov: f.fov,
        );
      default: // orbit / spin: round the subject
        final turn =
            (how == 'spin' ? 70 : 30) *
            (_r.nextBool() ? 1 : -1) *
            math.pi /
            180;
        final dx = f.x - f.tx, dz = f.z - f.tz;
        final c = math.cos(turn), s = math.sin(turn);
        return (
          x: f.tx + dx * c - dz * s,
          y: f.y,
          z: f.tz + dx * s + dz * c,
          tx: f.tx,
          ty: f.ty,
          tz: f.tz,
          fov: f.fov,
        );
    }
  }
}
