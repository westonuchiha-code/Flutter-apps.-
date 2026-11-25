import 'dart:typed_data';

import 'package:engine3d/engine3d.dart';

import 'cast.dart';

/// Joint angles in degrees (x: bend, y: twist, z: side). The special key
/// 'lift' moves the hips up/down in metres (adult size).
typedef Pose = Map<String, (double, double, double)>;

/// A move written as keyframes.
class Move {
  const Move(this.id, this.label, this.duration, this.keys, {this.loop = true});
  final String id, label;
  final double duration;
  final bool loop;
  final List<(double, Pose)> keys;
}

const _arms = {'upperArmL': (0.0, 0.0, 6.0), 'upperArmR': (0.0, 0.0, -6.0)};

const moves = <Move>[
  Move('idle', 'Stand', 2.4, [
    (0, {..._arms, 'chest': (0, 0, 0)}),
    (
      1.2,
      {
        'upperArmL': (0, 0, 9),
        'upperArmR': (0, 0, -9),
        'chest': (-2, 0, 0),
        'head': (2, 3, 0),
      },
    ),
    (2.4, {..._arms, 'chest': (0, 0, 0)}),
  ]),
  Move('walk', 'Walk', 1.0, [
    (
      0,
      {
        'upperLegL': (-25, 0, 0),
        'lowerLegL': (5, 0, 0),
        'upperLegR': (20, 0, 0),
        'lowerLegR': (25, 0, 0),
        'upperArmL': (20, 0, 6),
        'upperArmR': (-20, 0, -6),
        'lowerArmL': (-10, 0, 0),
        'lowerArmR': (-20, 0, 0),
        'spine': (0, 5, 0),
        'lift': (0, 0, 0),
      },
    ),
    (
      0.25,
      {
        'upperLegL': (0, 0, 0),
        'lowerLegL': (10, 0, 0),
        'upperLegR': (-10, 0, 0),
        'lowerLegR': (60, 0, 0),
        'upperArmL': (0, 0, 6),
        'upperArmR': (0, 0, -6),
        'lowerArmL': (-15, 0, 0),
        'lowerArmR': (-15, 0, 0),
        'lift': (0.025, 0, 0),
      },
    ),
    (
      0.5,
      {
        'upperLegL': (20, 0, 0),
        'lowerLegL': (25, 0, 0),
        'upperLegR': (-25, 0, 0),
        'lowerLegR': (5, 0, 0),
        'upperArmL': (-20, 0, 6),
        'upperArmR': (20, 0, -6),
        'lowerArmL': (-20, 0, 0),
        'lowerArmR': (-10, 0, 0),
        'spine': (0, -5, 0),
        'lift': (0, 0, 0),
      },
    ),
    (
      0.75,
      {
        'upperLegL': (-10, 0, 0),
        'lowerLegL': (60, 0, 0),
        'upperLegR': (0, 0, 0),
        'lowerLegR': (10, 0, 0),
        'upperArmL': (0, 0, 6),
        'upperArmR': (0, 0, -6),
        'lowerArmL': (-15, 0, 0),
        'lowerArmR': (-15, 0, 0),
        'lift': (0.025, 0, 0),
      },
    ),
    (
      1.0,
      {
        'upperLegL': (-25, 0, 0),
        'lowerLegL': (5, 0, 0),
        'upperLegR': (20, 0, 0),
        'lowerLegR': (25, 0, 0),
        'upperArmL': (20, 0, 6),
        'upperArmR': (-20, 0, -6),
        'lowerArmL': (-10, 0, 0),
        'lowerArmR': (-20, 0, 0),
        'spine': (0, 5, 0),
        'lift': (0, 0, 0),
      },
    ),
  ]),
  Move('run', 'Run', 0.62, [
    (
      0,
      {
        'upperLegL': (-50, 0, 0),
        'lowerLegL': (30, 0, 0),
        'upperLegR': (25, 0, 0),
        'lowerLegR': (70, 0, 0),
        'upperArmL': (40, 0, 8),
        'upperArmR': (-45, 0, -8),
        'lowerArmL': (-80, 0, 0),
        'lowerArmR': (-80, 0, 0),
        'spine': (12, 6, 0),
        'lift': (0, 0, 0),
      },
    ),
    (
      0.155,
      {
        'upperLegL': (-10, 0, 0),
        'lowerLegL': (20, 0, 0),
        'upperLegR': (-20, 0, 0),
        'lowerLegR': (100, 0, 0),
        'upperArmL': (0, 0, 8),
        'upperArmR': (0, 0, -8),
        'lowerArmL': (-85, 0, 0),
        'lowerArmR': (-85, 0, 0),
        'spine': (12, 0, 0),
        'lift': (0.06, 0, 0),
      },
    ),
    (
      0.31,
      {
        'upperLegL': (25, 0, 0),
        'lowerLegL': (70, 0, 0),
        'upperLegR': (-50, 0, 0),
        'lowerLegR': (30, 0, 0),
        'upperArmL': (-45, 0, 8),
        'upperArmR': (40, 0, -8),
        'lowerArmL': (-80, 0, 0),
        'lowerArmR': (-80, 0, 0),
        'spine': (12, -6, 0),
        'lift': (0, 0, 0),
      },
    ),
    (
      0.465,
      {
        'upperLegL': (-20, 0, 0),
        'lowerLegL': (100, 0, 0),
        'upperLegR': (-10, 0, 0),
        'lowerLegR': (20, 0, 0),
        'upperArmL': (0, 0, 8),
        'upperArmR': (0, 0, -8),
        'lowerArmL': (-85, 0, 0),
        'lowerArmR': (-85, 0, 0),
        'spine': (12, 0, 0),
        'lift': (0.06, 0, 0),
      },
    ),
    (
      0.62,
      {
        'upperLegL': (-50, 0, 0),
        'lowerLegL': (30, 0, 0),
        'upperLegR': (25, 0, 0),
        'lowerLegR': (70, 0, 0),
        'upperArmL': (40, 0, 8),
        'upperArmR': (-45, 0, -8),
        'lowerArmL': (-80, 0, 0),
        'lowerArmR': (-80, 0, 0),
        'spine': (12, 6, 0),
        'lift': (0, 0, 0),
      },
    ),
  ]),
  Move('wave', 'Wave', 1.2, [
    (
      0,
      {
        'upperArmR': (0, 0, -160),
        'lowerArmR': (0, 0, -25),
        'upperArmL': (0, 0, 6),
        'head': (0, -10, 0),
      },
    ),
    (
      0.3,
      {
        'upperArmR': (0, 0, -160),
        'lowerArmR': (0, 0, 20),
        'upperArmL': (0, 0, 6),
        'head': (0, -10, 0),
      },
    ),
    (
      0.6,
      {
        'upperArmR': (0, 0, -160),
        'lowerArmR': (0, 0, -25),
        'upperArmL': (0, 0, 6),
        'head': (0, -10, 0),
      },
    ),
    (
      0.9,
      {
        'upperArmR': (0, 0, -160),
        'lowerArmR': (0, 0, 20),
        'upperArmL': (0, 0, 6),
        'head': (0, -10, 0),
      },
    ),
    (
      1.2,
      {
        'upperArmR': (0, 0, -160),
        'lowerArmR': (0, 0, -25),
        'upperArmL': (0, 0, 6),
        'head': (0, -10, 0),
      },
    ),
  ]),
  Move('dance', 'Dance', 1.6, [
    (
      0,
      {
        'upperArmL': (0, 0, 140),
        'upperArmR': (0, 0, -40),
        'lowerArmL': (0, 0, 20),
        'spine': (0, 0, 10),
        'head': (0, 0, -8),
        'upperLegL': (-10, 0, 0),
        'lowerLegL': (20, 0, 0),
        'lift': (-0.04, 0, 0),
      },
    ),
    (
      0.4,
      {
        'upperArmL': (0, 0, 60),
        'upperArmR': (0, 0, -60),
        'spine': (0, 15, 0),
        'lift': (0.02, 0, 0),
      },
    ),
    (
      0.8,
      {
        'upperArmL': (0, 0, 40),
        'upperArmR': (0, 0, -140),
        'lowerArmR': (0, 0, -20),
        'spine': (0, 0, -10),
        'head': (0, 0, 8),
        'upperLegR': (-10, 0, 0),
        'lowerLegR': (20, 0, 0),
        'lift': (-0.04, 0, 0),
      },
    ),
    (
      1.2,
      {
        'upperArmL': (0, 0, 60),
        'upperArmR': (0, 0, -60),
        'spine': (0, -15, 0),
        'lift': (0.02, 0, 0),
      },
    ),
    (
      1.6,
      {
        'upperArmL': (0, 0, 140),
        'upperArmR': (0, 0, -40),
        'lowerArmL': (0, 0, 20),
        'spine': (0, 0, 10),
        'head': (0, 0, -8),
        'upperLegL': (-10, 0, 0),
        'lowerLegL': (20, 0, 0),
        'lift': (-0.04, 0, 0),
      },
    ),
  ]),
  Move('jump', 'Jump', 1.1, loop: false, [
    (0, {..._arms}),
    (
      0.25,
      {
        'lift': (-0.18, 0, 0),
        'upperLegL': (-45, 0, 0),
        'upperLegR': (-45, 0, 0),
        'lowerLegL': (80, 0, 0),
        'lowerLegR': (80, 0, 0),
        'spine': (20, 0, 0),
        'upperArmL': (40, 0, 10),
        'upperArmR': (40, 0, -10),
      },
    ),
    (
      0.5,
      {
        'lift': (0.4, 0, 0),
        'upperArmL': (0, 0, 160),
        'upperArmR': (0, 0, -160),
        'lowerLegL': (20, 0, 0),
        'lowerLegR': (20, 0, 0),
      },
    ),
    (
      0.78,
      {
        'lift': (-0.12, 0, 0),
        'upperLegL': (-30, 0, 0),
        'upperLegR': (-30, 0, 0),
        'lowerLegL': (55, 0, 0),
        'lowerLegR': (55, 0, 0),
        'spine': (12, 0, 0),
      },
    ),
    (1.1, {..._arms}),
  ]),
  Move('sit', 'Sit down', 1.0, loop: false, [
    (0, {..._arms}),
    (
      1.0,
      {
        'lift': (-0.45, 0, 0),
        'upperLegL': (-90, 0, 0),
        'upperLegR': (-90, 0, 0),
        'lowerLegL': (90, 0, 0),
        'lowerLegR': (90, 0, 0),
        'upperArmL': (-30, 0, 5),
        'upperArmR': (-30, 0, -5),
        'lowerArmL': (-40, 0, 0),
        'lowerArmR': (-40, 0, 0),
      },
    ),
  ]),
  Move('clap', 'Clap', 0.5, [
    (
      0,
      {
        'upperArmL': (-55, 0, 25),
        'upperArmR': (-55, 0, -25),
        'lowerArmL': (-40, 0, -30),
        'lowerArmR': (-40, 0, 30),
      },
    ),
    (
      0.25,
      {
        'upperArmL': (-55, 0, 8),
        'upperArmR': (-55, 0, -8),
        'lowerArmL': (-40, 0, -50),
        'lowerArmR': (-40, 0, 50),
      },
    ),
    (
      0.5,
      {
        'upperArmL': (-55, 0, 25),
        'upperArmR': (-55, 0, -25),
        'lowerArmL': (-40, 0, -30),
        'lowerArmR': (-40, 0, 30),
      },
    ),
  ]),
  Move('bow', 'Bow', 2.0, loop: false, [
    (0, {..._arms}),
    (
      0.6,
      {
        'spine': (35, 0, 0),
        'chest': (20, 0, 0),
        'head': (10, 0, 0),
        'upperArmL': (-10, 0, 4),
        'upperArmR': (-10, 0, -4),
      },
    ),
    (
      1.3,
      {
        'spine': (35, 0, 0),
        'chest': (20, 0, 0),
        'head': (10, 0, 0),
        'upperArmL': (-10, 0, 4),
        'upperArmR': (-10, 0, -4),
      },
    ),
    (2.0, {..._arms}),
  ]),
  Move('point', 'Point', 1.6, loop: false, [
    (0, {..._arms}),
    (
      0.4,
      {
        'upperArmR': (-90, 0, -10),
        'lowerArmR': (-5, 0, 0),
        'head': (0, -15, 0),
        'chest': (0, -10, 0),
      },
    ),
    (
      1.6,
      {
        'upperArmR': (-90, 0, -10),
        'lowerArmR': (-5, 0, 0),
        'head': (0, -15, 0),
        'chest': (0, -10, 0),
      },
    ),
  ]),
  Move('cheer', 'Cheer', 0.8, [
    (
      0,
      {
        'upperArmL': (0, 0, 160),
        'upperArmR': (0, 0, -160),
        'lift': (0.0, 0, 0),
        'head': (-10, 0, 0),
      },
    ),
    (
      0.4,
      {
        'upperArmL': (0, 0, 130),
        'upperArmR': (0, 0, -130),
        'lowerArmL': (0, 0, 30),
        'lowerArmR': (0, 0, -30),
        'lift': (0.06, 0, 0),
        'head': (-15, 0, 0),
      },
    ),
    (
      0.8,
      {
        'upperArmL': (0, 0, 160),
        'upperArmR': (0, 0, -160),
        'lift': (0.0, 0, 0),
        'head': (-10, 0, 0),
      },
    ),
  ]),
  Move('kick', 'Kick', 1.0, loop: false, [
    (0, {..._arms}),
    (
      0.3,
      {
        'upperLegR': (20, 0, 0),
        'lowerLegR': (80, 0, 0),
        'upperArmL': (-30, 0, 20),
        'upperArmR': (30, 0, -20),
      },
    ),
    (
      0.45,
      {
        'upperLegR': (-85, 0, 0),
        'lowerLegR': (0, 0, 0),
        'spine': (-10, 0, 0),
        'upperArmL': (30, 0, 30),
        'upperArmR': (-30, 0, -30),
      },
    ),
    (1.0, {..._arms}),
  ]),
  Move('lie', 'Fall over', 1.4, loop: false, [
    (0, {..._arms}),
    (
      0.5,
      {
        'lift': (-0.3, 0, 0),
        'hips': (-40, 0, 0),
        'upperArmL': (0, 0, 60),
        'upperArmR': (0, 0, -60),
      },
    ),
    (
      1.0,
      {
        'lift': (-0.8, 0, 0),
        'hips': (-90, 0, 0),
        'upperArmL': (0, 0, 80),
        'upperArmR': (0, 0, -80),
        'head': (10, 0, 0),
      },
    ),
    (
      1.4,
      {
        'lift': (-0.8, 0, 0),
        'hips': (-90, 0, 0),
        'upperArmL': (0, 0, 70),
        'upperArmR': (0, 0, -70),
        'head': (5, 0, 0),
      },
    ),
  ]),
  Move('think', 'Think', 2.4, [
    (
      0,
      {
        'upperArmR': (-40, 0, -20),
        'lowerArmR': (-125, 0, 0),
        'upperArmL': (-20, 0, 25),
        'lowerArmL': (-80, 0, -30),
        'head': (8, 0, 6),
      },
    ),
    (
      1.2,
      {
        'upperArmR': (-40, 0, -20),
        'lowerArmR': (-125, 0, 0),
        'upperArmL': (-20, 0, 25),
        'lowerArmL': (-80, 0, -30),
        'head': (12, 8, -4),
      },
    ),
    (
      2.4,
      {
        'upperArmR': (-40, 0, -20),
        'lowerArmR': (-125, 0, 0),
        'upperArmL': (-20, 0, 25),
        'lowerArmL': (-80, 0, -30),
        'head': (8, 0, 6),
      },
    ),
  ]),
  Move('talk', 'Talk', 2.0, [
    (
      0,
      {
        'upperArmL': (-20, 0, 10),
        'lowerArmL': (-60, 20, 0),
        'upperArmR': (-5, 0, -8),
        'head': (0, 0, 0),
      },
    ),
    (
      0.5,
      {
        'upperArmL': (-5, 0, 8),
        'upperArmR': (-25, 0, -10),
        'lowerArmR': (-65, -20, 0),
        'head': (4, 6, 0),
      },
    ),
    (
      1.0,
      {
        'upperArmL': (-25, 0, 15),
        'lowerArmL': (-55, 30, 0),
        'upperArmR': (-10, 0, -8),
        'head': (-3, -4, 0),
      },
    ),
    (
      1.5,
      {
        'upperArmL': (-5, 0, 8),
        'upperArmR': (-20, 0, -12),
        'lowerArmR': (-60, -25, 0),
        'head': (3, 2, 0),
      },
    ),
    (
      2.0,
      {
        'upperArmL': (-20, 0, 10),
        'lowerArmL': (-60, 20, 0),
        'upperArmR': (-5, 0, -8),
        'head': (0, 0, 0),
      },
    ),
  ]),
  Move('shrug', 'Shrug', 1.4, loop: false, [
    (0, {..._arms}),
    (
      0.4,
      {
        'upperArmL': (-10, 0, 25),
        'upperArmR': (-10, 0, -25),
        'lowerArmL': (-80, 60, 0),
        'lowerArmR': (-80, -60, 0),
        'head': (0, 0, 12),
        'chest': (-4, 0, 0),
      },
    ),
    (
      1.0,
      {
        'upperArmL': (-10, 0, 25),
        'upperArmR': (-10, 0, -25),
        'lowerArmL': (-80, 60, 0),
        'lowerArmR': (-80, -60, 0),
        'head': (0, 0, 12),
        'chest': (-4, 0, 0),
      },
    ),
    (1.4, {..._arms}),
  ]),
  Move('nod', 'Nod yes', 0.8, [
    (0, {..._arms, 'head': (0, 0, 0)}),
    (0.2, {..._arms, 'head': (18, 0, 0)}),
    (0.4, {..._arms, 'head': (0, 0, 0)}),
    (0.6, {..._arms, 'head': (18, 0, 0)}),
    (0.8, {..._arms, 'head': (0, 0, 0)}),
  ]),
  Move('shake', 'Shake head', 0.8, [
    (0, {..._arms, 'head': (0, 0, 0)}),
    (0.2, {..._arms, 'head': (0, 28, 0)}),
    (0.6, {..._arms, 'head': (0, -28, 0)}),
    (0.8, {..._arms, 'head': (0, 0, 0)}),
  ]),
  Move('punch', 'Punch', 0.7, [
    (
      0,
      {
        'upperArmL': (-60, 0, 20),
        'lowerArmL': (-110, 0, 0),
        'upperArmR': (-60, 0, -20),
        'lowerArmR': (-110, 0, 0),
        'spine': (5, 15, 0),
      },
    ),
    (
      0.17,
      {
        'upperArmL': (-90, 0, 5),
        'lowerArmL': (-5, 0, 0),
        'upperArmR': (-60, 0, -20),
        'lowerArmR': (-110, 0, 0),
        'spine': (5, -20, 0),
      },
    ),
    (
      0.35,
      {
        'upperArmL': (-60, 0, 20),
        'lowerArmL': (-110, 0, 0),
        'upperArmR': (-60, 0, -20),
        'lowerArmR': (-110, 0, 0),
        'spine': (5, 0, 0),
      },
    ),
    (
      0.52,
      {
        'upperArmL': (-60, 0, 20),
        'lowerArmL': (-110, 0, 0),
        'upperArmR': (-90, 0, -5),
        'lowerArmR': (-5, 0, 0),
        'spine': (5, 20, 0),
      },
    ),
    (
      0.7,
      {
        'upperArmL': (-60, 0, 20),
        'lowerArmL': (-110, 0, 0),
        'upperArmR': (-60, 0, -20),
        'lowerArmR': (-110, 0, 0),
        'spine': (5, 15, 0),
      },
    ),
  ]),
  Move('crouch', 'Crouch', 0.8, loop: false, [
    (0, {..._arms}),
    (
      0.8,
      {
        'lift': (-0.38, 0, 0),
        'upperLegL': (-70, 0, -8),
        'upperLegR': (-70, 0, 8),
        'lowerLegL': (120, 0, 0),
        'lowerLegR': (120, 0, 0),
        'footL': (-50, 0, 0),
        'footR': (-50, 0, 0),
        'spine': (25, 0, 0),
        'upperArmL': (-40, 0, 10),
        'upperArmR': (-40, 0, -10),
        'lowerArmL': (-40, 0, 0),
        'lowerArmR': (-40, 0, 0),
      },
    ),
  ]),
];

Move? moveById(String id) {
  for (final m in moves) {
    if (m.id == id) return m;
  }
  return null;
}

/// Builds the clip of [m] for [c] (its joints, rest pose and size).
AnimationClip buildClip(Move m, Character c) {
  final names = <String>{for (final k in m.keys) ...k.$2.keys}..remove('lift');
  final hips = c.joints['hips']!;
  final restHips = Vector3(0, c.hipsY, 0);
  final size = c.hipsY / 0.95;
  final channels = <Channel>[];
  final times = Float32List.fromList([for (final k in m.keys) k.$1]);
  for (final name in names) {
    final node = c.joints[name];
    if (node == null) continue;
    final rest = c.rest[name] ?? (0.0, 0.0, 0.0);
    final values = Float32List(m.keys.length * 4);
    for (var i = 0; i < m.keys.length; i++) {
      final e = m.keys[i].$2[name] ?? (0.0, 0.0, 0.0);
      final q = euler(rest.$1 + e.$1, rest.$2 + e.$2, rest.$3 + e.$3);
      values.setAll(i * 4, [q.x, q.y, q.z, q.w]);
    }
    channels.add(Channel(node, AnimPath.rotation, times, values));
  }
  if (m.keys.any((k) => k.$2.containsKey('lift'))) {
    final values = Float32List(m.keys.length * 3);
    for (var i = 0; i < m.keys.length; i++) {
      final lift = (m.keys[i].$2['lift']?.$1 ?? 0) * size;
      values.setAll(i * 3, [restHips.x, restHips.y + lift, restHips.z]);
    }
    channels.add(Channel(hips, AnimPath.translation, times, values));
  }
  return AnimationClip(m.id, channels, duration: m.duration, loop: m.loop);
}

/// Every move for [c].
Map<String, AnimationClip> clipsFor(Character c) => {
  for (final m in moves) m.id: buildClip(m, c),
};

/// Puts every joint back to its resting pose.
void restPose(Character c) {
  for (final name in c.joints.keys) {
    final node = c.joints[name];
    if (node == null) continue;
    final r = c.rest[name];
    node.rotation = r == null ? Quaternion.identity() : euler(r.$1, r.$2, r.$3);
  }
  c.joints['hips']!.position = Vector3(0, c.hipsY, 0);
}
