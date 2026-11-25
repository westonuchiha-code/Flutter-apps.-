import 'package:engine3d/engine3d.dart';

import 'cast.dart';
import 'moves.dart';

/// Our joint → the bone it drives in someone else's skeleton.
typedef BoneMap = Map<String, Node>;

const _skip = [
  'toe', 'finger', 'thumb', 'index', 'middle', 'ring', 'pinky', 'little', //
  'twist', 'end', 'ik', 'pole', 'target', 'roll', 'eye', 'jaw', 'tongue',
  'breast', 'hair', 'tail', 'nub', 'tip', 'socket', 'weapon', 'prop',
];

/// Which side a bone is on: -1 left, 1 right, 0 middle, and its name
/// without the side.
(int, String) _side(String raw) {
  var n = raw.toLowerCase();
  final colon = n.lastIndexOf(':');
  if (colon >= 0) n = n.substring(colon + 1); // mixamorig:LeftArm
  for (final p in ['def-', 'def_', 'org-', 'mch-', 'bip01', 'bip001']) {
    if (n.startsWith(p)) n = n.substring(p.length);
  }
  final tokens = n
      .split(RegExp('[^a-z0-9]+'))
      .where((t) => t.isNotEmpty)
      .toList();
  var side = 0;
  final rest = <String>[];
  for (var t in tokens) {
    if (t == 'l' || t == 'left') {
      side = -1;
      continue;
    }
    if (t == 'r' || t == 'right') {
      side = 1;
      continue;
    }
    if (t.startsWith('left')) {
      side = -1;
      t = t.substring(4);
    } else if (t.startsWith('right')) {
      side = 1;
      t = t.substring(5);
    } else if (t.length > 3 &&
        (t.endsWith('l') || t.endsWith('r')) &&
        _part(t.substring(0, t.length - 1)) != null) {
      side = t.endsWith('l') ? -1 : 1;
      t = t.substring(0, t.length - 1);
    }
    rest.add(t);
  }
  return (side, rest.join());
}

/// The kind of bone a (side-less) name is.
String? _part(String n) {
  if (n.isEmpty || _skip.any(n.contains)) return null;
  if (n.contains('hand') || n.contains('wrist') || n.contains('fist')) {
    return 'hand';
  }
  if (n.contains('forearm') ||
      n.contains('lowerarm') ||
      n.contains('elbow') ||
      n == 'lowarm') {
    return 'lowerArm';
  }
  if (n.contains('upperarm') || n == 'arm' || n == 'uparm') return 'upperArm';
  if (n.contains('foot') || n.contains('ankle')) return 'foot';
  if (n.contains('upleg') ||
      n.contains('upperleg') ||
      n.contains('thigh') ||
      n == 'femur') {
    return 'upperLeg';
  }
  if (n == 'leg' ||
      n.contains('lowerleg') ||
      n.contains('lowleg') ||
      n.contains('calf') ||
      n.contains('shin') ||
      n.contains('knee')) {
    return 'lowerLeg';
  }
  if (n == 'hips' || n == 'hip' || n == 'pelvis') return 'hips';
  if (n.contains('neck')) return 'neck';
  if (n == 'head') return 'head';
  if (n.contains('spine') ||
      n.contains('chest') ||
      n.contains('abdomen') ||
      n.contains('torso') ||
      n == 'waist') {
    return 'spine';
  }
  return null;
}

/// Finds a human skeleton's bones by their names (Mixamo, Blender's
/// Rigify / ".L" names, Quaternius, VRoid, Unreal and similar). Null if
/// the model doesn't look like a person with arms and legs.
BoneMap? findHumanBones(Node model) {
  final out = <String, Node>{};
  final spines = <Node>[];
  // Only real skeleton joints (models also name mesh pieces "Leg.L").
  final joints = <Node>{};
  void skins(Node n) {
    final s = n.skin;
    if (s != null) joints.addAll(s.joints);
    for (final c in n.children) {
      skins(c);
    }
  }

  skins(model);
  void walk(Node n) {
    final (side, name) = joints.isEmpty || joints.contains(n)
        ? _side(n.name)
        : (0, '');
    final part = _part(name);
    if (part != null) {
      if (part == 'spine') {
        spines.add(n);
      } else if (side == 0 && ['hips', 'neck', 'head'].contains(part)) {
        out.putIfAbsent(part, () => n);
      } else if (side != 0 &&
          !['hips', 'neck', 'head', 'spine'].contains(part)) {
        out.putIfAbsent('$part${side < 0 ? 'L' : 'R'}', () => n);
      }
    }
    for (final c in n.children) {
      walk(c);
    }
  }

  walk(model);
  if (spines.isNotEmpty) {
    out['spine'] = spines.first;
    if (spines.length > 1) out['chest'] = spines.last;
  }
  const needed = [
    'hips', 'upperArmL', 'upperArmR', 'lowerArmL', 'lowerArmR', //
    'upperLegL', 'upperLegR', 'lowerLegL', 'lowerLegR',
  ];
  if (!needed.every(out.containsKey)) return null;
  // A limb's bones must hang from each other (some rigs keep feet apart,
  // for IK); drop the ones that don't.
  for (final e in _childOf.entries) {
    final a = out[e.key], b = out[e.value];
    if (a != null && b != null && !_under(a, b)) out.remove(e.value);
  }
  if (!needed.every(out.containsKey)) return null;
  return out;
}

const _childOf = {
  'hips': 'spine',
  'spine': 'chest',
  'chest': 'neck',
  'neck': 'head',
  'upperArmL': 'lowerArmL',
  'lowerArmL': 'handL',
  'upperArmR': 'lowerArmR',
  'lowerArmR': 'handR',
  'upperLegL': 'lowerLegL',
  'lowerLegL': 'footL',
  'upperLegR': 'lowerLegR',
  'lowerLegR': 'footR',
};
const _parentOf = {
  'head': 'neck',
  'handL': 'lowerArmL',
  'handR': 'lowerArmR',
  'footL': 'lowerLegL',
  'footR': 'lowerLegR',
};

/// Plays our moves on someone else's skeleton: a hidden blocky [proxy]
/// does the move, and every mapped bone copies the turn each of its joints
/// made from standing still (in the character's own space), corrected for
/// how differently the two skeletons stand (a T-pose's arms point out,
/// ours hang down).
class Retarget {
  Retarget(this.proxy, this.model, this.bones) {
    proxy.root
      ..position = Vector3.zero()
      ..rotation = Quaternion.identity();
    restPose(proxy);
    final pw = _worlds(proxy.root);
    for (final e in proxy.joints.entries) {
      _proxyRest[e.key] = _rot(pw[e.value]!);
      _proxyPos[e.key] = pw[e.value]!.getTranslation();
    }
    final mw = _worlds(model);
    _modelBindWorld.addAll(mw);
    _walkBind(model, Quaternion.identity());
    final byNode = {for (final e in bones.entries) e.value: e.key};
    _jointOf.addAll(byNode);
    for (final e in bones.entries) {
      final childName = _childOf[e.key];
      final child = childName == null ? null : bones[childName];
      final pc = childName == null ? null : proxy.joints[childName];
      if (child != null && pc != null) {
        final a = (mw[child]!.getTranslation() - mw[e.value]!.getTranslation())
          ..normalize();
        final b = (_proxyPos[childName]! - _proxyPos[e.key]!)..normalize();
        _fix[e.key] = Quaternion.fromTwoVectors(a, b);
      }
    }
    for (final e in _parentOf.entries) {
      if (bones.containsKey(e.key)) {
        _fix[e.key] = _fix[e.value] ?? Quaternion.identity();
      }
    }
    final hips = bones['hips']!;
    _hipsBind = hips.position.clone();
    final hipsParent = _parentNode(model, hips);
    _hipsParentInverse = hipsParent == null
        ? Matrix4.identity()
        : Matrix4.inverted(mw[hipsParent]!);
    final targetHipsY = mw[hips]!.getTranslation().y;
    _size = targetHipsY / proxy.hipsY;
  }

  final Character proxy;

  /// The model, already fitted (its own transform is the "character space").
  final Node model;
  final BoneMap bones;

  final _proxyRest = <String, Quaternion>{};
  final _proxyPos = <String, Vector3>{};
  final _modelBindWorld = <Node, Matrix4>{};
  final _bindLocal = <Node, Quaternion>{};
  final _bindWorldRot = <Node, Quaternion>{};
  final _jointOf = <Node, String>{};
  final _fix = <String, Quaternion>{};
  late final Vector3 _hipsBind;
  late final Matrix4 _hipsParentInverse;
  late final double _size;

  void _walkBind(Node n, Quaternion parent) {
    _bindLocal[n] = n.rotation.clone();
    final w = parent * n.rotation;
    _bindWorldRot[n] = w;
    for (final c in n.children) {
      _walkBind(c, w);
    }
  }

  /// Puts every bone back as the model was loaded.
  void reset() {
    for (final e in _bindLocal.entries) {
      e.key.rotation = e.value.clone();
    }
    bones['hips']!.position = _hipsBind.clone();
  }

  /// Copies the proxy's current pose onto the model.
  void apply() {
    final saved = (proxy.root.position.clone(), proxy.root.rotation.clone());
    proxy.root
      ..position = Vector3.zero()
      ..rotation = Quaternion.identity();
    final pw = _worlds(proxy.root);
    proxy.root
      ..position = saved.$1
      ..rotation = saved.$2;
    void walk(Node n, Quaternion parentWorld) {
      final joint = _jointOf[n];
      Quaternion world;
      if (joint != null && proxy.joints[joint] != null) {
        final delta =
            _rot(pw[proxy.joints[joint]]!) * _proxyRest[joint]!.inverted();
        world =
            delta * (_fix[joint] ?? Quaternion.identity()) * _bindWorldRot[n]!;
        n.rotation = parentWorld.inverted() * world;
      } else {
        n.rotation = _bindLocal[n]!.clone();
        world = parentWorld * n.rotation;
      }
      for (final c in n.children) {
        walk(c, world);
      }
    }

    walk(model, Quaternion.identity());
    // Hips going up and down (jumps, sitting).
    final ph = proxy.joints['hips']!;
    final lift = (ph.position - Vector3(0, proxy.hipsY, 0)) * _size;
    bones['hips']!.position = _hipsBind + _hipsParentInverse.rotated3(lift);
  }
}

Map<Node, Matrix4> _worlds(Node root) {
  final out = <Node, Matrix4>{};
  root.visit(Matrix4.identity(), (n, w) => out[n] = w);
  return out;
}

Quaternion _rot(Matrix4 m) {
  final t = Vector3.zero(), s = Vector3.zero();
  final q = Quaternion.identity();
  m.decompose(t, q, s);
  return q;
}

bool _under(Node a, Node b) =>
    a.children.any((c) => identical(c, b) || _under(c, b));

Node? _parentNode(Node root, Node child) {
  for (final c in root.children) {
    if (identical(c, child)) return root;
    final p = _parentNode(c, child);
    if (p != null) return p;
  }
  return null;
}
