import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:engine3d/engine3d.dart';

import 'cast.dart';
import 'movie.dart';
import 'moves.dart';
import 'retarget.dart';

/// A move the Actions tab offers for a figure.
typedef MoveChoice = ({String id, String label});

/// Prefix of a model's own animations in move ids.
const ownPrefix = 'own:';

/// Something on the stage that actions drive: a built-in person or an
/// imported model.
abstract class Figure {
  /// Placed in the scene; moved and turned by the actions.
  Node get root;

  /// Joints that moves and stop-motion poses turn (null: nothing to pose).
  Character? get rig;

  /// What the Actions tab offers (not walk/run: those are actions).
  List<MoveChoice> get moves;

  /// Places and poses the figure for [st].
  void apply(ActorState st);

  void _place(ActorState st) => root
    ..position = Vector3(st.x, 0, st.z)
    ..rotation = Quaternion.axisAngle(
      Vector3(0, 1, 0),
      st.facing * math.pi / 180,
    );
}

List<MoveChoice> _humanMoves() => [
  for (final m in moves)
    if (m.id != 'walk' && m.id != 'run') (id: m.id, label: m.label),
];

/// One of the blocky people or animals.
class BuiltFigure extends Figure {
  BuiltFigure(this.character, {this.labels = const {}})
    : clips = clipsFor(character);
  final Character character;
  final Map<String, AnimationClip> clips;

  /// Move names for this figure (e.g. 'call' → 'Bark').
  final Map<String, String> labels;

  @override
  Node get root => character.root;
  @override
  Character get rig => character;
  @override
  List<MoveChoice> get moves => [
    for (final m in movesFor(character.rig))
      if (m.id != 'walk' && m.id != 'run')
        (id: m.id, label: labels[m.id] ?? m.label),
  ];
  @override
  void apply(ActorState st) => applyState(character, clips, st);
}

/// A plant or a thing: no moves, but plants sway, a car's wheels turn and
/// a ball rolls when they move along.
class PropFigure extends Figure {
  PropFigure(this.root, {this.scale = 1})
    : _sway = root.find('sway'),
      _wheels = [
        for (final n in _all(root))
          if (n.name == 'wheel') n,
      ],
      _spin = root.find('spin');

  @override
  final Node root;
  final double scale;
  final Node? _sway, _spin;
  final List<Node> _wheels;

  @override
  Character? get rig => null;
  @override
  List<MoveChoice> get moves => const [];

  @override
  void apply(ActorState st) {
    _place(st);
    final sway = _sway;
    if (sway != null) {
      // A gentle breeze (it is a puppet show: always a little wind).
      final t = st.moveTime + st.x * 0.7 + st.z * 0.4;
      sway.rotation =
          Quaternion.axisAngle(Vector3(0, 0, 1), math.sin(t * 1.3) * 0.025) *
          Quaternion.axisAngle(Vector3(1, 0, 0), math.sin(t * 0.9) * 0.02);
    }
    final moving = st.move == 'walk' || st.move == 'run';
    final speed = st.move == 'run' ? Movie.runSpeed : Movie.walkSpeed;
    final distance = moving ? st.moveTime * speed : 0.0;
    for (final w in _wheels) {
      w.rotation = Quaternion.axisAngle(Vector3(1, 0, 0), distance / 0.34);
    }
    _spin?.rotation = Quaternion.axisAngle(
      Vector3(1, 0, 0),
      distance / (0.15 * scale),
    );
  }
}

/// An imported model. People with a skeleton we understand do every
/// built-in move (through a hidden blocky stand-in, see [Retarget]); any
/// model also plays its own animations.
class ModelFigure extends Figure {
  ModelFigure._(this.root, this.model, this.own, this.retarget, this.ownWalk)
    : _bind = [
        for (final n in _all(model))
          (n, n.position.clone(), n.rotation.clone(), n.scale.clone()),
      ];

  @override
  final Node root;

  /// The loaded model (under [root]).
  final Node model;

  /// The model's own animations by name.
  final Map<String, AnimationClip> own;
  final Retarget? retarget;

  /// Use the model's own walk / run / idle (when it has them) instead of
  /// the built-in ones.
  final bool ownWalk;
  late final Map<String, AnimationClip> _proxyClips = retarget == null
      ? const {}
      : clipsFor(retarget!.proxy);
  final List<(Node, Vector3, Quaternion, Vector3)> _bind;

  bool get humanoid => retarget != null;

  @override
  Character? get rig => retarget?.proxy;

  @override
  List<MoveChoice> get moves => [
    if (humanoid) ..._humanMoves(),
    for (final name in own.keys) (id: '$ownPrefix$name', label: name),
  ];

  /// The model's own clip for a built-in move, if it has one.
  String? _ownFor(String move) {
    if (!ownWalk && humanoid) return null;
    final words = switch (move) {
      'walk' => ['walk'],
      'run' => ['run', 'sprint', 'jog'],
      'idle' => ['idle', 'stand', 'breath', 'survey'],
      _ => const <String>[],
    };
    for (final w in words) {
      for (final name in own.keys) {
        final n = name.toLowerCase();
        if (n.contains(w) &&
            !n.contains('back') &&
            !n.contains('left') &&
            !n.contains('right')) {
          return name;
        }
      }
    }
    return null;
  }

  AnimationClip? _clip(String move) {
    if (move.startsWith(ownPrefix)) {
      return own[move.substring(ownPrefix.length)];
    }
    final o = _ownFor(move);
    return o == null ? null : own[o];
  }

  void _resetBind() {
    for (final (n, p, r, s) in _bind) {
      n
        ..position = p.clone()
        ..rotation = r.clone()
        ..scale = s.clone();
    }
  }

  @override
  void apply(ActorState st) {
    _place(st);
    final clip = st.pose == null ? _clip(st.move) : null;
    if (clip != null) {
      _resetBind();
      final prev = st.previous == null ? null : _clip(st.previous!);
      if (prev != null && st.blend < 1) {
        prev.apply(st.previousTime);
        clip.blend(st.moveTime, st.blend);
      } else {
        clip.apply(st.moveTime);
      }
      return;
    }
    final r = retarget;
    if (r == null) {
      _resetBind();
      return;
    }
    final prevIsOwn = st.previous != null && _clip(st.previous!) != null;
    applyState(
      r.proxy,
      _proxyClips,
      prevIsOwn
          ? ActorState(
              0,
              0,
              0,
              st.move.startsWith(ownPrefix) ? 'idle' : st.move,
              st.moveTime,
              pose: st.pose,
            )
          : ActorState(
              0,
              0,
              0,
              st.move.startsWith(ownPrefix) ? 'idle' : st.move,
              st.moveTime,
              previous: st.previous,
              previousTime: st.previousTime,
              blend: st.blend,
              pose: st.pose,
            ),
    );
    r.apply();
  }
}

Iterable<Node> _all(Node n) sync* {
  yield n;
  for (final c in n.children) {
    yield* _all(c);
  }
}

/// Loads [bytes] (.glb, .gltf or .obj) as a figure [height] metres tall,
/// turned [turn] degrees inside (for models that face away).
Future<ModelFigure> loadModelFigure(
  Uint8List bytes,
  String extension, {
  double height = 1.75,
  double turn = 0,
  bool ownWalk = true,
  String name = 'model',
}) async {
  Node node;
  var own = <String, AnimationClip>{};
  if (extension.toLowerCase() == 'obj') {
    node = loadObj(utf8.decode(bytes, allowMalformed: true), name: name);
  } else {
    final m = await loadGltfModel(bytes, name: name);
    node = m.node;
    own = m.animations;
  }
  updateSkins(node);
  final fitted = fitModel(node, height: height);
  final bones = findHumanBones(node);
  if (bones != null) {
    // Facing +Z, a person's left arm is on the +X side; some files face
    // the other way.
    final worlds = <Node, Matrix4>{};
    fitted.visit(Matrix4.identity(), (n, w) => worlds[n] = w);
    final l = worlds[bones['upperArmL']]!.getTranslation();
    final r = worlds[bones['upperArmR']]!.getTranslation();
    if ((l - r).x < 0) turn += 180;
  }
  final turnNode = Node(
    name: 'turn',
    rotation: Quaternion.axisAngle(Vector3(0, 1, 0), turn * math.pi / 180),
    children: [fitted],
  );
  final root = Node(name: 'actor', children: [turnNode]);
  final retarget = bones == null
      ? null
      : Retarget(
          buildCharacter(Kind.man, defaultLooks[Kind.man]!),
          turnNode,
          bones,
        );
  return ModelFigure._(root, turnNode, own, retarget, ownWalk);
}
