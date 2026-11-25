import 'dart:math' as math;

import 'package:engine3d/engine3d.dart';

/// The kinds of people on the stage.
enum Kind {
  man('Man'),
  woman('Woman'),
  boy('Boy'),
  girl('Girl'),
  oldMan('Old man'),
  oldWoman('Old woman');

  const Kind(this.label);
  final String label;
}

/// An actor's colours.
class Look {
  const Look({
    required this.skin,
    required this.hair,
    required this.top,
    required this.bottom,
    this.shoes = 0xFF2A2420,
  });
  final int skin, hair, top, bottom, shoes;

  Map<String, Object?> toJson() => {
    'skin': skin,
    'hair': hair,
    'top': top,
    'bottom': bottom,
    'shoes': shoes,
  };
  factory Look.fromJson(Map j, Look fallback) {
    int c(String k, int d) => (j[k] as num?)?.toInt() ?? d;
    return Look(
      skin: c('skin', fallback.skin),
      hair: c('hair', fallback.hair),
      top: c('top', fallback.top),
      bottom: c('bottom', fallback.bottom),
      shoes: c('shoes', fallback.shoes),
    );
  }

  Look copyWith({int? skin, int? hair, int? top, int? bottom, int? shoes}) =>
      Look(
        skin: skin ?? this.skin,
        hair: hair ?? this.hair,
        top: top ?? this.top,
        bottom: bottom ?? this.bottom,
        shoes: shoes ?? this.shoes,
      );
}

const defaultLooks = {
  Kind.man: Look(
    skin: 0xFFD8A27A,
    hair: 0xFF3A2A1E,
    top: 0xFF3E6AB0,
    bottom: 0xFF2E3440,
  ),
  Kind.woman: Look(
    skin: 0xFFE8BC98,
    hair: 0xFF7A3A22,
    top: 0xFFC0485A,
    bottom: 0xFF384058,
  ),
  Kind.boy: Look(
    skin: 0xFFB87A54,
    hair: 0xFF1E1612,
    top: 0xFF4EA05A,
    bottom: 0xFF4A5A80,
  ),
  Kind.girl: Look(
    skin: 0xFFF0C8A8,
    hair: 0xFFE0B040,
    top: 0xFFE07AB0,
    bottom: 0xFF6A4AA0,
  ),
  Kind.oldMan: Look(
    skin: 0xFFE0B090,
    hair: 0xFFD8D8D8,
    top: 0xFF8A6A4A,
    bottom: 0xFF4A4A4A,
  ),
  Kind.oldWoman: Look(
    skin: 0xFFC89070,
    hair: 0xFFE8E8EE,
    top: 0xFF7A5A9A,
    bottom: 0xFF5A4A5A,
  ),
};

/// Joint names shared by every character (clips work on any of them).
const jointNames = [
  'hips', 'spine', 'chest', 'neck', 'head', //
  'upperArmL', 'lowerArmL', 'handL', 'upperArmR', 'lowerArmR', 'handR',
  'upperLegL', 'lowerLegL', 'footL', 'upperLegR', 'lowerLegR', 'footR',
];

/// A built character: its root (on the ground) and its joints.
class Character {
  Character(
    this.rig,
    this.root,
    this.joints,
    this.rest,
    this.hipsY, {
    this.liftRef = 0.95,
    this.span = 0,
    this.clearance = 0,
  });

  /// Four legs: hips-to-chest distance and the gap under the belly (for
  /// sitting, see the 'sit' pose key).
  final double span, clearance;

  /// Which moves fit: 'human', 'quad' (four legs) or 'bird'.
  final String rig;

  /// Hips height the rig's moves were written for (their lifts scale).
  final double liftRef;
  final Node root;
  final Map<String, Node> joints;

  /// Resting angles in degrees (x, y, z) per joint (e.g. an old person's stoop).
  final Map<String, (double, double, double)> rest;

  /// Resting height of the hips (moves lift and lower them from here).
  final double hipsY;
}

Quaternion euler(double x, double y, double z) {
  const k = math.pi / 180;
  return Quaternion.axisAngle(Vector3(0, 1, 0), y * k) *
      Quaternion.axisAngle(Vector3(1, 0, 0), x * k) *
      Quaternion.axisAngle(Vector3(0, 0, 1), z * k);
}

/// Builds a segmented, PS1-style person: boxes on a skeleton (each part
/// moves rigidly with its joint).
Character buildCharacter(Kind kind, Look look) {
  final child = kind == Kind.boy || kind == Kind.girl;
  final old = kind == Kind.oldMan || kind == Kind.oldWoman;
  final female =
      kind == Kind.woman || kind == Kind.girl || kind == Kind.oldWoman;
  final s = child ? 0.62 : 1.0; // overall scale
  final headScale = child ? 1.35 : 1.0;
  final shoulder = (female ? 0.17 : 0.2) * s;
  final hipW = (female ? 0.11 : 0.1) * s;

  Surface mat(int c) => Surface(color: c);
  final skin = mat(look.skin),
      hair = mat(look.hair),
      top = mat(look.top),
      bottom = mat(look.bottom),
      shoes = mat(look.shoes);
  final eyes = mat(0xFF1A1414);

  Node joint(String name, double x, double y, double z) =>
      Node(name: name, position: Vector3(x, y, z));
  Node part(Mesh m, Surface sf, double x, double y, double z) =>
      Node(name: 'part', mesh: m, material: sf, position: Vector3(x, y, z));

  final root = Node(name: 'actor');
  final hips = root.add(joint('hips', 0, 0.95 * s, 0));
  hips.add(
    part(
      boxMesh(hipW * 2 + 0.06 * s, 0.14 * s, 0.18 * s, split: 1),
      bottom,
      0,
      -0.02 * s,
      0,
    ),
  );
  final spine = hips.add(joint('spine', 0, 0.08 * s, 0));
  spine.add(
    part(
      boxMesh(shoulder * 1.6, 0.18 * s, 0.18 * s, split: 1),
      top,
      0,
      0.08 * s,
      0,
    ),
  );
  final chest = spine.add(joint('chest', 0, 0.17 * s, 0));
  chest.add(
    part(
      boxMesh(shoulder * 2, 0.24 * s, 0.21 * s, split: 1),
      top,
      0,
      0.1 * s,
      0,
    ),
  );
  final neck = chest.add(joint('neck', 0, 0.24 * s, 0));
  neck.add(
    part(boxMesh(0.08 * s, 0.08 * s, 0.08 * s, split: 1), skin, 0, 0.03 * s, 0),
  );
  final head = neck.add(joint('head', 0, 0.07 * s, 0));
  final hs = 0.2 * s * headScale;
  head.add(
    part(boxMesh(hs * 0.82, hs, hs * 0.9, split: 1), skin, 0, hs * 0.5, 0),
  );
  // Eyes and nose on the front (+Z).
  head.add(
    part(
      boxMesh(hs * 0.12, hs * 0.1, 0.01, split: 1),
      eyes,
      -hs * 0.18,
      hs * 0.55,
      hs * 0.455,
    ),
  );
  head.add(
    part(
      boxMesh(hs * 0.12, hs * 0.1, 0.01, split: 1),
      eyes,
      hs * 0.18,
      hs * 0.55,
      hs * 0.455,
    ),
  );
  // Hair.
  switch (kind) {
    case Kind.man || Kind.boy:
      head.add(
        part(
          boxMesh(hs * 0.88, hs * 0.22, hs * 0.96, split: 1),
          hair,
          0,
          hs * 1.02,
          -hs * 0.02,
        ),
      );
      head.add(
        part(
          boxMesh(hs * 0.88, hs * 0.5, hs * 0.2, split: 1),
          hair,
          0,
          hs * 0.8,
          -hs * 0.4,
        ),
      );
    case Kind.woman || Kind.girl:
      head.add(
        part(
          boxMesh(hs * 0.92, hs * 0.24, hs * 1.0, split: 1),
          hair,
          0,
          hs * 1.02,
          0,
        ),
      );
      head.add(
        part(
          boxMesh(
            hs * 0.96,
            hs * (kind == Kind.girl ? 0.9 : 1.15),
            hs * 0.3,
            split: 1,
          ),
          hair,
          0,
          hs * 0.5,
          -hs * 0.42,
        ),
      );
      if (kind == Kind.girl) {
        head.add(
          part(
            boxMesh(hs * 0.18, hs * 0.5, hs * 0.18, split: 1),
            hair,
            -hs * 0.52,
            hs * 0.55,
            -hs * 0.2,
          ),
        );
        head.add(
          part(
            boxMesh(hs * 0.18, hs * 0.5, hs * 0.18, split: 1),
            hair,
            hs * 0.52,
            hs * 0.55,
            -hs * 0.2,
          ),
        );
      }
    case Kind.oldMan:
      // Bald on top, a ring of white hair, and a moustache.
      head.add(
        part(
          boxMesh(hs * 0.9, hs * 0.3, hs * 0.5, split: 1),
          hair,
          0,
          hs * 0.55,
          -hs * 0.25,
        ),
      );
      head.add(
        part(
          boxMesh(hs * 0.4, hs * 0.07, 0.02, split: 1),
          hair,
          0,
          hs * 0.3,
          hs * 0.46,
        ),
      );
    case Kind.oldWoman:
      head.add(
        part(
          boxMesh(hs * 0.9, hs * 0.22, hs * 0.96, split: 1),
          hair,
          0,
          hs * 1.0,
          0,
        ),
      );
      head.add(
        part(
          sphereMesh(hs * 0.22, segments: 6, rings: 4),
          hair,
          0,
          hs * 1.05,
          -hs * 0.45,
        ),
      ); // bun
  }

  for (final side in [1.0, -1.0]) {
    final sfx = side > 0 ? 'L' : 'R';
    final upper = chest.add(
      joint('upperArm$sfx', side * (shoulder + 0.04 * s), 0.2 * s, 0),
    );
    upper.add(
      part(
        boxMesh(0.085 * s, 0.28 * s, 0.085 * s, split: 1),
        top,
        0,
        -0.13 * s,
        0,
      ),
    );
    final lower = upper.add(joint('lowerArm$sfx', 0, -0.27 * s, 0));
    lower.add(
      part(
        boxMesh(0.075 * s, 0.25 * s, 0.075 * s, split: 1),
        skin,
        0,
        -0.12 * s,
        0,
      ),
    );
    final hand = lower.add(joint('hand$sfx', 0, -0.25 * s, 0));
    hand.add(
      part(
        boxMesh(0.07 * s, 0.09 * s, 0.05 * s, split: 1),
        skin,
        0,
        -0.04 * s,
        0,
      ),
    );

    final thigh = hips.add(joint('upperLeg$sfx', side * hipW, -0.06 * s, 0));
    thigh.add(
      part(
        boxMesh(0.12 * s, 0.42 * s, 0.13 * s, split: 1),
        bottom,
        0,
        -0.2 * s,
        0,
      ),
    );
    final shin = thigh.add(joint('lowerLeg$sfx', 0, -0.42 * s, 0));
    shin.add(
      part(
        boxMesh(0.1 * s, 0.4 * s, 0.11 * s, split: 1),
        female && !child ? skin : bottom,
        0,
        -0.2 * s,
        0,
      ),
    );
    final foot = shin.add(joint('foot$sfx', 0, -0.41 * s, 0));
    foot.add(
      part(
        boxMesh(0.1 * s, 0.07 * s, 0.22 * s, split: 1),
        shoes,
        0,
        -0.01 * s,
        0.05 * s,
      ),
    );
  }
  if (female && !child) {
    // A skirt over the top of the legs.
    hips.add(
      part(
        boxMesh(hipW * 2 + 0.12 * s, 0.32 * s, 0.24 * s, split: 1),
        bottom,
        0,
        -0.2 * s,
        0,
      ),
    );
  }

  final rest = <String, (double, double, double)>{};
  if (old) {
    rest['spine'] = (10, 0, 0);
    rest['chest'] = (8, 0, 0);
    rest['head'] = (-12, 0, 0);
  }
  final all = root.byName();
  final joints = {for (final n in jointNames) n: all[n]!};
  rest.forEach((name, e) => joints[name]!.rotation = euler(e.$1, e.$2, e.$3));
  return Character('human', root, joints, rest, 0.95 * s);
}
