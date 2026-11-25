import 'dart:math' as math;

import 'package:engine3d/engine3d.dart';

import 'animals.dart';

import 'package:landscape/landscape.dart';

import 'cast.dart';
import 'look.dart';
import 'props.dart';
import 'moves.dart';
import 'sets.dart';

enum ActionType { move, walk, run, turn, wait, pose }

/// One thing an actor does, in order.
class Action {
  Action(
    this.type, {
    this.move = 'idle',
    this.seconds = 2,
    this.x = 0,
    this.z = 0,
    this.angle = 0,
    Pose? pose,
  }) : pose = pose ?? {};

  final ActionType type;

  /// Move id (for [ActionType.move]).
  String move;

  /// Length (move, wait, pose, turn).
  double seconds;

  /// Walk/run target.
  double x, z;

  /// Turn by this many degrees.
  double angle;

  /// Stop-motion pose (joint → degrees).
  Pose pose;

  Map<String, Object?> toJson() => {
    'type': type.name,
    'move': move,
    'seconds': seconds,
    'x': x,
    'z': z,
    'angle': angle,
    if (pose.isNotEmpty)
      'pose': {
        for (final e in pose.entries)
          e.key: [e.value.$1, e.value.$2, e.value.$3],
      },
  };

  factory Action.fromJson(Map j) => Action(
    ActionType.values.firstWhere(
      (t) => t.name == j['type'],
      orElse: () => ActionType.wait,
    ),
    move: (j['move'] as String?) ?? 'idle',
    seconds: ((j['seconds'] as num?) ?? 2).toDouble(),
    x: ((j['x'] as num?) ?? 0).toDouble(),
    z: ((j['z'] as num?) ?? 0).toDouble(),
    angle: ((j['angle'] as num?) ?? 0).toDouble(),
    pose: {
      for (final e in ((j['pose'] as Map?) ?? const {}).entries)
        if (e.value is List && (e.value as List).length == 3)
          e.key as String: (
            ((e.value as List)[0] as num).toDouble(),
            ((e.value as List)[1] as num).toDouble(),
            ((e.value as List)[2] as num).toDouble(),
          ),
    },
  );

  Action copy() => Action.fromJson(toJson());

  /// [label]: the move's name for this figure (animals' moves differ).
  String describe([String? label]) => switch (type) {
    ActionType.move =>
      '${label ?? moveById(move)?.label ?? move.replaceFirst('own:', '')} '
          '${seconds.toStringAsFixed(1)} s',
    ActionType.walk => 'Walk',
    ActionType.run => 'Run',
    ActionType.turn => 'Turn ${angle.round()}°',
    ActionType.wait => 'Wait ${seconds.toStringAsFixed(1)} s',
    ActionType.pose => 'Pose ${seconds.toStringAsFixed(2)} s',
  };
}

/// A 3D file in the Asset Locker.
class ModelRef {
  const ModelRef(this.id, this.extension, this.name);
  final String id, extension, name;

  Map<String, Object?> toJson() => {'id': id, 'ext': extension, 'name': name};
  static ModelRef? fromJson(Object? j) => j is Map && j['id'] is String
      ? ModelRef(
          j['id'] as String,
          (j['ext'] as String?) ?? 'glb',
          (j['name'] as String?) ?? 'Model',
        )
      : null;
}

/// Someone in the movie.
class Actor {
  Actor({
    String? id,
    required this.kind,
    required this.name,
    Look? look,
    this.x = 0,
    this.z = 0,
    this.facing = 0,
    this.animal,
    this.prop,
    this.scale = 1,
    this.body = const Body(),
    Set<Extra>? extras,
    this.model,
    this.size = 1.75,
    this.turn = 0,
    this.ownWalk = true,
    this.place = 0,
    this.holds,
    List<Action>? actions,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toRadixString(36),
       look =
           look ??
           (prop != null
               ? propLooks[prop]!
               : animal != null
               ? animalLooks[animal]!
               : defaultLooks[kind]!),
       extras = extras ?? {},
       actions = actions ?? [];

  final String id;
  final Kind kind;
  String name;
  Look look;

  /// Starting spot and direction (degrees; 0 faces the camera, +Z).
  double x, z, facing;
  final List<Action> actions;

  /// An animal instead of a person.
  final Animal? animal;

  /// A plant or a thing instead of a person.
  final Prop? prop;

  /// Size of a built-in figure (1: as made).
  double scale;

  /// A person's proportions and what they wear.
  Body body;
  final Set<Extra> extras;

  /// An imported model instead of a built-in figure.
  ModelRef? model;

  /// A model's height in metres, and how far it is turned inside (for
  /// files that face away).
  double size, turn;

  /// A model plays its own walk / run / idle when it has them.
  bool ownWalk;

  /// Which of the movie's places this actor is in (0: the main set).
  int place;

  /// A prop in the right hand (a katana, a microphone…).
  Prop? holds;

  /// What it is, for lists.
  String get what => model?.name ?? prop?.label ?? animal?.label ?? kind.label;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'name': name,
    'look': look.toJson(),
    if (animal != null) 'animal': animal!.name,
    if (prop != null) 'prop': prop!.name,
    if (scale != 1) 'scale': scale,
    if (!body.isDefault) 'body': body.toJson(),
    if (extras.isNotEmpty) 'extras': [for (final e in extras) e.name],
    'x': x,
    'z': z,
    'facing': facing,
    'actions': [for (final a in actions) a.toJson()],
    if (place != 0) 'place': place,
    if (holds != null) 'holds': holds!.name,
    if (model != null) ...{
      'model': model!.toJson(),
      'size': size,
      'turn': turn,
      'ownWalk': ownWalk,
    },
  };

  factory Actor.fromJson(Map j) {
    final kind = Kind.values.firstWhere(
      (k) => k.name == j['kind'],
      orElse: () => Kind.man,
    );
    final animal = Animal.values
        .where((a) => a.name == j['animal'])
        .firstOrNull;
    final prop = Prop.values.where((p) => p.name == j['prop']).firstOrNull;
    final look = prop != null
        ? propLooks[prop]!
        : animal != null
        ? animalLooks[animal]!
        : defaultLooks[kind]!;
    return Actor(
      id: j['id'] as String?,
      kind: kind,
      animal: animal,
      prop: prop,
      scale: ((j['scale'] as num?) ?? 1).toDouble(),
      body: Body.fromJson(j['body']),
      extras: {
        for (final e in (j['extras'] as List?) ?? const [])
          ...Extra.values.where((x) => x.name == e),
      },
      name:
          (j['name'] as String?) ?? prop?.label ?? animal?.label ?? kind.label,
      look: j['look'] is Map ? Look.fromJson(j['look'] as Map, look) : look,
      x: ((j['x'] as num?) ?? 0).toDouble(),
      z: ((j['z'] as num?) ?? 0).toDouble(),
      facing: ((j['facing'] as num?) ?? 0).toDouble(),
      model: ModelRef.fromJson(j['model']),
      size: ((j['size'] as num?) ?? 1.75).toDouble(),
      turn: ((j['turn'] as num?) ?? 0).toDouble(),
      ownWalk: j['ownWalk'] != false,
      place: ((j['place'] as num?) ?? 0).toInt(),
      holds: Prop.values.where((p) => p.name == j['holds']).firstOrNull,
      actions: [
        for (final a in (j['actions'] as List?) ?? const [])
          Action.fromJson(a as Map),
      ],
    );
  }
}

/// A person saved to reuse: kind, colours, body and extras (Asset Locker
/// Presets, kind [templateKind]).
const templateKind = 'puppet_template';

Map<String, Object?> templateJson(Actor a) => {
  'kind': templateKind,
  'version': 1,
  'name': a.name,
  'actor': {
    ...a.toJson()
      ..remove('actions')
      ..remove('id'),
  },
};

/// A new actor from a template (null if it isn't one).
Actor? actorFromTemplate(Object? j, {double x = 0, double z = 0}) {
  if (j is! Map || j['kind'] != templateKind || j['actor'] is! Map) {
    return null;
  }
  final a = Actor.fromJson({...j['actor'] as Map, 'x': x, 'z': z});
  return a;
}

/// A camera angle that starts at [time].
class Shot {
  Shot(
    this.time,
    this.x,
    this.y,
    this.z,
    this.yaw,
    this.pitch, {
    this.fov = 55,
    this.place = 0,
    this.look,
    this.end,
  });
  double time;
  final double x, y, z, yaw, pitch, fov;

  /// Which place the camera is in.
  int place;

  /// This shot's film look (null: the movie's).
  FilmLook? look;

  /// Where the camera drifts to by the next cut (x, y, z, yaw, pitch):
  /// push-ins, dollies, slow pans. Null: it stays still.
  List<double>? end;

  Map<String, Object?> toJson() => {
    't': time,
    'p': [x, y, z, yaw, pitch, fov],
    if (place != 0) 'place': place,
    if (look != null) 'look': look!.toJson(),
    if (end != null) 'end': end,
  };
  factory Shot.fromJson(Map j) {
    final p = [for (final v in j['p'] as List) (v as num).toDouble()];
    final e = j['end'];
    return Shot(
      ((j['t'] as num?) ?? 0).toDouble(),
      p[0],
      p[1],
      p[2],
      p[3],
      p[4],
      fov: p.length > 5 ? p[5] : 55,
      place: ((j['place'] as num?) ?? 0).toInt(),
      look: j['look'] is Map ? FilmLook.fromJson(j['look']) : null,
      end: e is List && e.length == 5
          ? [for (final v in e) (v as num).toDouble()]
          : null,
    );
  }
}

/// One more place a movie happens in: a built-in set or a Vista landscape.
class Place {
  const Place({this.set, this.land, this.name = '', this.mood});

  final StageSet? set;

  /// Light and colour changes on top of the set or landscape (night,
  /// golden hour, coloured lamps).
  final Mood? mood;

  /// A Vista landscape (its settings, as Vista saves them).
  final LandSettings? land;
  final String name;

  String get label => name.isNotEmpty
      ? name
      : set?.label ?? (land == null ? 'Place' : 'Landscape: ${land!.preset}');

  Map<String, Object?> toJson() => {
    if (set != null) 'set': set!.name,
    if (land != null) 'land': land!.toJson(),
    if (name.isNotEmpty) 'name': name,
    if (mood != null) 'mood': mood!.toJson(),
  };
  factory Place.fromJson(Object? j) {
    if (j is! Map) return const Place(set: StageSet.studio);
    final land = j['land'];
    LandSettings? ls;
    if (land is Map) {
      try {
        ls = LandSettings.fromJson(land);
      } catch (_) {}
    }
    return Place(
      set: StageSet.values.where((s) => s.name == j['set']).firstOrNull,
      land: ls,
      name: '${j['name'] ?? ''}',
      mood: j['mood'] is Map ? Mood.fromJson(j['mood'] as Map) : null,
    );
  }
}

/// A lamp a [Mood] adds: position, colour, reach and strength.
typedef Lamp = ({
  double x,
  double y,
  double z,
  int color,
  double range,
  double power,
});

/// Light changes for a place (null fields: as built).
class Mood {
  const Mood({
    this.sky,
    this.horizon,
    this.ambient,
    this.sun,
    this.sunDir,
    this.fog,
    this.fogNear,
    this.fogFar,
    this.lamps = const [],
  });
  final int? sky, horizon, ambient, sun, fog;

  /// Where the sunlight points (x, y, z).
  final List<double>? sunDir;
  final double? fogNear, fogFar;
  final List<Lamp> lamps;

  Map<String, Object?> toJson() => {
    if (sky != null) 'sky': sky,
    if (horizon != null) 'horizon': horizon,
    if (ambient != null) 'ambient': ambient,
    if (sun != null) 'sun': sun,
    if (sunDir != null) 'sunDir': sunDir,
    if (fog != null) 'fog': fog,
    if (fogNear != null) 'fogNear': fogNear,
    if (fogFar != null) 'fogFar': fogFar,
    if (lamps.isNotEmpty)
      'lamps': [
        for (final l in lamps) [l.x, l.y, l.z, l.color, l.range, l.power],
      ],
  };

  factory Mood.fromJson(Map j) {
    int? c(String k) => (j[k] as num?)?.toInt();
    double? d(String k) => (j[k] as num?)?.toDouble();
    final dir = j['sunDir'];
    return Mood(
      sky: c('sky'),
      horizon: c('horizon'),
      ambient: c('ambient'),
      sun: c('sun'),
      fog: c('fog'),
      fogNear: d('fogNear'),
      fogFar: d('fogFar'),
      sunDir: dir is List && dir.length == 3
          ? [for (final v in dir) (v as num).toDouble()]
          : null,
      lamps: [
        for (final l in (j['lamps'] as List?) ?? const [])
          if (l is List && l.length == 6)
            (
              x: (l[0] as num).toDouble(),
              y: (l[1] as num).toDouble(),
              z: (l[2] as num).toDouble(),
              color: (l[3] as num).toInt(),
              range: (l[4] as num).toDouble(),
              power: (l[5] as num).toDouble(),
            ),
      ],
    );
  }
}

/// A music track from the Asset Locker that plays under the movie.
class MusicRef {
  const MusicRef(
    this.id,
    this.extension,
    this.name, {
    this.seconds = 0,
    this.start = 0,
  });
  final String id, extension, name;

  /// The track's length, and where in it the movie starts.
  final double seconds, start;

  Map<String, Object?> toJson() => {
    'id': id,
    'ext': extension,
    'name': name,
    'seconds': seconds,
    if (start != 0) 'start': start,
  };
  static MusicRef? fromJson(Object? j) => j is Map && j['id'] is String
      ? MusicRef(
          j['id'] as String,
          '${j['ext'] ?? 'wav'}',
          '${j['name'] ?? 'Music'}',
          seconds: ((j['seconds'] as num?) ?? 0).toDouble(),
          start: ((j['start'] as num?) ?? 0).toDouble(),
        )
      : null;
}

/// The whole movie.
class Movie {
  Movie({
    this.name = 'My movie',
    this.set = StageSet.studio,
    List<Actor>? actors,
    List<Shot>? shots,
    List<Place>? places,
    this.music,
    this.look = FilmLook.none,
    this.mood,
  }) : actors = actors ?? [],
       shots = shots ?? [],
       places = places ?? [];

  static const kind = 'puppet_movie';
  static const walkSpeed = 1.3, runSpeed = 3.6;

  String name;

  /// The main set (place 0).
  StageSet set;
  final List<Actor> actors;
  final List<Shot> shots;

  /// More places (1, 2, …): shots cut between them, actors stand in one.
  final List<Place> places;

  /// Plays under the movie (and goes into the video).
  MusicRef? music;

  /// The movie's film look (shots can have their own).
  FilmLook look;

  /// Light changes on the main set.
  Mood? mood;

  int get placeCount => 1 + places.length;
  Place placeAt(int i) =>
      i <= 0 || i > places.length ? Place(set: set, mood: mood) : places[i - 1];

  double get duration {
    var d = 0.0;
    for (final a in actors) {
      d = math.max(d, plan(a).fold<double>(0, (m, s) => math.max(m, s.end)));
    }
    for (final s in shots) {
      d = math.max(d, s.time + 1);
    }
    final m = music;
    if (m != null && m.seconds > 0) d = math.max(d, m.seconds - m.start);
    return math.max(d, 1);
  }

  Map<String, Object?> toJson() => {
    'kind': kind,
    'version': 1,
    'name': name,
    'set': set.name,
    'actors': [for (final a in actors) a.toJson()],
    'shots': [for (final s in shots) s.toJson()],
    if (places.isNotEmpty) 'places': [for (final p in places) p.toJson()],
    if (music != null) 'music': music!.toJson(),
    if (!look.isNone) 'look': look.toJson(),
    if (mood != null) 'mood': mood!.toJson(),
  };

  factory Movie.fromJson(Object? j) {
    if (j is! Map || j['kind'] != kind) {
      throw const FormatException('Not a Puppet Stage movie');
    }
    return Movie(
      name: (j['name'] as String?) ?? 'My movie',
      set: StageSet.values.firstWhere(
        (s) => s.name == j['set'],
        orElse: () => StageSet.studio,
      ),
      actors: [
        for (final a in (j['actors'] as List?) ?? const [])
          Actor.fromJson(a as Map),
      ],
      shots: [
        for (final s in (j['shots'] as List?) ?? const [])
          Shot.fromJson(s as Map),
      ],
      places: [
        for (final p in (j['places'] as List?) ?? const []) Place.fromJson(p),
      ],
      music: MusicRef.fromJson(j['music']),
      look: FilmLook.fromJson(j['look']),
      mood: j['mood'] is Map ? Mood.fromJson(j['mood'] as Map) : null,
    );
  }

  /// The shot in use at [t] (null: no shots, the user's camera).
  Shot? shotAt(double t) {
    Shot? best;
    for (final s in shots) {
      if (s.time <= t + 1e-6 && (best == null || s.time >= best.time)) {
        best = s;
      }
    }
    return best ??
        (shots.isEmpty
            ? null
            : shots.reduce((a, b) => a.time < b.time ? a : b));
  }
}

/// An action laid out in time, with where the actor is at its start/end.
class Step {
  Step(
    this.action,
    this.start,
    this.end,
    this.x0,
    this.z0,
    this.f0,
    this.x1,
    this.z1,
    this.f1,
  );
  final Action action;
  final double start, end, x0, z0, f0, x1, z1, f1;

  /// The move shown during this step.
  String get move => switch (action.type) {
    ActionType.move => action.move,
    ActionType.walk => 'walk',
    ActionType.run => 'run',
    ActionType.turn => 'walk',
    ActionType.wait || ActionType.pose => 'idle',
  };
}

/// Lays an actor's actions out in time.
List<Step> plan(Actor a) {
  final out = <Step>[];
  var t = 0.0, x = a.x, z = a.z, f = a.facing;
  for (final act in a.actions) {
    switch (act.type) {
      case ActionType.walk || ActionType.run:
        final dx = act.x - x,
            dz = act.z - z,
            dist = math.sqrt(dx * dx + dz * dz);
        final speed = act.type == ActionType.run
            ? Movie.walkSpeed * 0 + Movie.runSpeed
            : Movie.walkSpeed;
        final dur = math.max(0.3, dist / speed);
        final nf = dist > 1e-3 ? math.atan2(dx, dz) * 180 / math.pi : f;
        out.add(Step(act, t, t + dur, x, z, nf, act.x, act.z, nf));
        t += dur;
        x = act.x;
        z = act.z;
        f = nf;
      case ActionType.turn:
        final dur = math.max(0.3, act.angle.abs() / 180 * 0.8);
        out.add(Step(act, t, t + dur, x, z, f, x, z, f + act.angle));
        t += dur;
        f += act.angle;
      default:
        final dur = math.max(0.05, act.seconds);
        out.add(Step(act, t, t + dur, x, z, f, x, z, f));
        t += dur;
    }
  }
  return out;
}

/// Where an actor is and what they do at [t].
class ActorState {
  const ActorState(
    this.x,
    this.z,
    this.facing,
    this.move,
    this.moveTime, {
    this.previous,
    this.previousTime = 0,
    this.blend = 1,
    this.pose,
  });
  final double x, z, facing;
  final String move;
  final double moveTime;
  final String? previous;
  final double previousTime, blend;
  final Pose? pose;
}

const _fade = 0.25;

ActorState stateAt(Actor a, double t, [List<Step>? steps]) {
  final s = steps ?? plan(a);
  if (s.isEmpty || t < s.first.start) {
    return ActorState(a.x, a.z, a.facing, 'idle', t);
  }
  for (var i = 0; i < s.length; i++) {
    final st = s[i];
    if (t < st.end || i == s.length - 1) {
      final local = t - st.start;
      final k = st.end > st.start
          ? (local / (st.end - st.start)).clamp(0.0, 1.0)
          : 1.0;
      final over = t >= st.end;
      final move = over
          ? (st.action.type == ActionType.move ? st.move : 'idle')
          : st.move;
      final prev = i > 0 ? s[i - 1] : null;
      final blend = prev == null || local >= _fade ? 1.0 : local / _fade;
      return ActorState(
        st.x0 + (st.x1 - st.x0) * k,
        st.z0 + (st.z1 - st.z0) * k,
        st.f0 + (st.f1 - st.f0) * k,
        move,
        over && st.action.type != ActionType.move ? t - st.end : local,
        previous: prev?.move,
        previousTime: prev == null ? 0 : prev.end - prev.start + local,
        blend: blend,
        pose: st.action.type == ActionType.pose ? st.action.pose : null,
      );
    }
  }
  return ActorState(a.x, a.z, a.facing, 'idle', t);
}

/// Poses a built character for [st].
void applyState(Character c, Map<String, AnimationClip> clips, ActorState st) {
  c.root
    ..position = Vector3(st.x, 0, st.z)
    ..rotation = Quaternion.axisAngle(
      Vector3(0, 1, 0),
      st.facing * math.pi / 180,
    );
  restPose(c);
  final pose = st.pose;
  if (pose != null) {
    pose.forEach((name, e) {
      final node = c.joints[name];
      if (node == null) {
        return;
      }
      final r = c.rest[name] ?? (0.0, 0.0, 0.0);
      node.rotation = euler(r.$1 + e.$1, r.$2 + e.$2, r.$3 + e.$3);
    });
    return;
  }
  final clip = clips[st.move] ?? clips['idle']!;
  final prev = st.previous == null ? null : clips[st.previous];
  if (prev != null && st.blend < 1) {
    prev.apply(st.previousTime);
    clip.blend(st.moveTime, st.blend);
  } else {
    clip.apply(st.moveTime);
  }
}

/// The current joint angles of [c] as a pose (to start editing from).
Pose poseOf(Character c) {
  final out = <String, (double, double, double)>{};
  for (final name in c.joints.keys) {
    final node = c.joints[name];
    if (node == null) {
      continue;
    }
    final e = toEuler(node.rotation);
    final r = c.rest[name] ?? (0.0, 0.0, 0.0);
    final p = (e.$1 - r.$1, e.$2 - r.$2, e.$3 - r.$3);
    if (p.$1.abs() + p.$2.abs() + p.$3.abs() > 0.5) {
      out[name] = p;
    }
  }
  return out;
}

/// Degrees (x, y, z) of a rotation built as [euler] builds them (Y·X·Z).
(double, double, double) toEuler(Quaternion q) {
  final m = q.asRotationMatrix();
  // R = Ry·Rx·Rz: m(1,2) = -sin x.
  final sx = (-m.entry(1, 2)).clamp(-1.0, 1.0);
  final x = math.asin(sx);
  final y = math.atan2(m.entry(0, 2), m.entry(2, 2));
  final z = math.atan2(m.entry(1, 0), m.entry(1, 1));
  const k = 180 / math.pi;
  return (x * k, y * k, z * k);
}
