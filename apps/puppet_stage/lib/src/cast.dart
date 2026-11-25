import 'dart:math' as math;

import 'package:engine3d/engine3d.dart';

/// The kinds of people on the stage.
enum Kind {
  man('Man'),
  woman('Woman'),
  boy('Boy'),
  girl('Girl'),
  oldMan('Old man'),
  oldWoman('Old woman'),
  bigMan('Big guy'),
  teen('Teen'),
  toddler('Toddler'),
  robot('Robot');

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
    this.accent = 0xFF3A3E48,
  });
  final int skin, hair, top, bottom, shoes;

  /// Hats, jackets and bags.
  final int accent;

  Map<String, Object?> toJson() => {
    'skin': skin,
    'hair': hair,
    'top': top,
    'bottom': bottom,
    'shoes': shoes,
    'accent': accent,
  };
  factory Look.fromJson(Map j, Look fallback) {
    int c(String k, int d) => (j[k] as num?)?.toInt() ?? d;
    return Look(
      skin: c('skin', fallback.skin),
      hair: c('hair', fallback.hair),
      top: c('top', fallback.top),
      bottom: c('bottom', fallback.bottom),
      shoes: c('shoes', fallback.shoes),
      accent: c('accent', fallback.accent),
    );
  }

  Look copyWith({
    int? skin,
    int? hair,
    int? top,
    int? bottom,
    int? shoes,
    int? accent,
  }) => Look(
    skin: skin ?? this.skin,
    hair: hair ?? this.hair,
    top: top ?? this.top,
    bottom: bottom ?? this.bottom,
    shoes: shoes ?? this.shoes,
    accent: accent ?? this.accent,
  );
}

/// Body proportions (1: as the kind is made).
class Body {
  const Body({
    this.height = 1,
    this.build = 1,
    this.head = 1,
    this.arms = 1,
    this.legs = 1,
  });
  final double height, build, head, arms, legs;

  static const ranges = {
    'height': (0.5, 1.4),
    'build': (0.6, 1.8),
    'head': (0.6, 1.8),
    'arms': (0.6, 1.4),
    'legs': (0.6, 1.4),
  };

  double operator [](String k) => switch (k) {
    'height' => height,
    'build' => build,
    'head' => head,
    'arms' => arms,
    _ => legs,
  };

  Body with_(String k, double v) => Body(
    height: k == 'height' ? v : height,
    build: k == 'build' ? v : build,
    head: k == 'head' ? v : head,
    arms: k == 'arms' ? v : arms,
    legs: k == 'legs' ? v : legs,
  );

  bool get isDefault =>
      height == 1 && build == 1 && head == 1 && arms == 1 && legs == 1;

  Map<String, double> toJson() => {
    'height': height,
    'build': build,
    'head': head,
    'arms': arms,
    'legs': legs,
  };
  factory Body.fromJson(Object? j) {
    if (j is! Map) return const Body();
    double v(String k) => ((j[k] as num?) ?? 1).toDouble();
    return Body(
      height: v('height'),
      build: v('build'),
      head: v('head'),
      arms: v('arms'),
      legs: v('legs'),
    );
  }
}

/// Clothes and things people can wear.
enum Extra {
  hat('Hat'),
  cap('Cap'),
  glasses('Glasses'),
  dress('Dress'),
  jacket('Jacket'),
  backpack('Backpack'),
  beard('Beard');

  const Extra(this.label);
  final String label;
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
  Kind.bigMan: Look(
    skin: 0xFFC08A64,
    hair: 0xFF2A1E16,
    top: 0xFF4A6A3A,
    bottom: 0xFF3A3A48,
  ),
  Kind.teen: Look(
    skin: 0xFFE0B090,
    hair: 0xFF4A3020,
    top: 0xFFE8A030,
    bottom: 0xFF3E5A90,
  ),
  Kind.toddler: Look(
    skin: 0xFFF0C8A8,
    hair: 0xFFC08A50,
    top: 0xFF6AB0E0,
    bottom: 0xFFE8E0D0,
  ),
  Kind.robot: Look(
    skin: 0xFF8A9098,
    hair: 0xFFE04A4A,
    top: 0xFFB8C0C8,
    bottom: 0xFF6A7078,
    shoes: 0xFF3E4248,
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
/// moves rigidly with its joint). [body] stretches the kind's proportions;
/// [extras] are clothes and things worn.
Character buildCharacter(
  Kind kind,
  Look look, {
  Body body = const Body(),
  Set<Extra> extras = const {},
}) {
  final small = kind == Kind.boy || kind == Kind.girl;
  final old = kind == Kind.oldMan || kind == Kind.oldWoman;
  final robot = kind == Kind.robot;
  final female =
      kind == Kind.woman || kind == Kind.girl || kind == Kind.oldWoman;
  final (base, baseHead, baseBuild, baseLegs) = switch (kind) {
    Kind.boy || Kind.girl => (0.62, 1.35, 1.0, 1.0),
    Kind.teen => (0.86, 1.08, 0.92, 1.03),
    Kind.toddler => (0.46, 1.6, 1.1, 0.82),
    Kind.bigMan => (1.04, 1.0, 1.45, 0.96),
    _ => (1.0, 1.0, 1.0, 1.0),
  };
  final s = base * body.height; // overall scale
  final w = baseBuild * body.build; // widths
  final legs = baseLegs * body.legs, arms = body.arms;
  final headScale = baseHead * body.head;
  final shoulder = (female ? 0.17 : 0.2) * s * (0.5 + w * 0.5);
  final hipW = (female ? 0.11 : 0.1) * s * w;
  final limb = s * (0.6 + w * 0.4); // limb thickness

  Surface mat(int c) => Surface(color: c);
  final skin = mat(robot ? look.top : look.skin),
      hair = mat(look.hair),
      top = mat(look.top),
      bottom = mat(look.bottom),
      shoes = mat(look.shoes),
      accent = mat(look.accent);
  final eyes = robot ? Surface(color: 0xFF60E0FF, lit: false) : mat(0xFF1A1414);
  final jacket = extras.contains(Extra.jacket);
  final sleeves = jacket ? accent : top;

  Node joint(String name, double x, double y, double z) =>
      Node(name: name, position: Vector3(x, y, z));
  Node part(Mesh m, Surface sf, double x, double y, double z, {double? bias}) =>
      Node(
        name: 'part',
        mesh: m,
        material: sf,
        position: Vector3(x, y, z),
        // Things worn flat on a body part sort a little nearer so they never
        // sink into it (the renderer has no depth buffer). Hair sits over the
        // head the same way.
        depthBias: (bias ?? (identical(sf, hair) ? 0.015 : 0.0)) * s,
      );
  // A hat or cap replaces the top of the hair (they fought otherwise).
  final covered = extras.contains(Extra.hat) || extras.contains(Extra.cap);
  Mesh box(double x, double y, double z) => boxMesh(x, y, z, split: 1);

  final thighLen = 0.42 * s * legs, shinLen = 0.41 * s * legs;
  final hipsY = 0.06 * s + thighLen + shinLen + 0.06 * s;
  final root = Node(name: 'actor');
  final hips = root.add(joint('hips', 0, hipsY, 0));
  hips.add(
    part(
      box(hipW * 2 + 0.06 * s, 0.14 * s, 0.18 * s * w),
      bottom,
      0,
      -0.02 * s,
      0,
    ),
  );
  final spine = hips.add(joint('spine', 0, 0.08 * s, 0));
  spine.add(
    part(
      box(shoulder * 1.6, 0.18 * s, 0.18 * s * w),
      jacket ? accent : top,
      0,
      0.08 * s,
      0,
    ),
  );
  if (kind == Kind.bigMan || w > 1.3) {
    // Belly.
    spine.add(
      part(
        box(shoulder * 1.5, 0.2 * s, 0.08 * s * w),
        top,
        0,
        0.06 * s,
        0.11 * s * w,
      ),
    );
  }
  final chest = spine.add(joint('chest', 0, 0.17 * s, 0));
  chest.add(
    part(
      box(shoulder * 2, 0.24 * s, 0.21 * s * (0.6 + w * 0.4)),
      jacket ? accent : top,
      0,
      0.1 * s,
      0,
    ),
  );
  if (jacket) {
    // Shirt showing down the front.
    chest.add(
      part(
        box(shoulder * 0.5, 0.22 * s, 0.01),
        top,
        0,
        0.1 * s,
        0.105 * s * (0.6 + w * 0.4) + 0.006,
        bias: 0.04,
      ),
    );
  }
  if (robot) {
    // Chest panel with lights.
    chest.add(
      part(
        box(shoulder * 0.9, 0.12 * s, 0.01),
        bottom,
        0,
        0.12 * s,
        0.106 * s + 0.004,
        bias: 0.03,
      ),
    );
    for (final x in [-0.05, 0.0, 0.05]) {
      chest.add(
        part(
          box(0.025 * s, 0.025 * s, 0.01),
          eyes,
          x * s,
          0.12 * s,
          0.106 * s + 0.01,
          bias: 0.05,
        ),
      );
    }
  }
  final neck = chest.add(joint('neck', 0, 0.24 * s, 0));
  neck.add(
    part(
      box(0.08 * s, 0.08 * s, 0.08 * s),
      robot ? bottom : skin,
      0,
      0.03 * s,
      0,
    ),
  );
  final head = neck.add(joint('head', 0, 0.07 * s, 0));
  final hs = 0.2 * s * headScale;
  head.add(
    part(box(hs * (robot ? 0.95 : 0.82), hs, hs * 0.9), skin, 0, hs * 0.5, 0),
  );
  if (robot) {
    // Visor eyes and an antenna.
    head.add(
      part(
        box(hs * 0.7, hs * 0.16, 0.01),
        eyes,
        0,
        hs * 0.58,
        hs * 0.46,
        bias: 0.03,
      ),
    );
    head.add(
      part(box(hs * 0.08, hs * 0.35, hs * 0.08), bottom, 0, hs * 1.15, 0),
    );
    head.add(part(box(hs * 0.16, hs * 0.16, hs * 0.16), hair, 0, hs * 1.36, 0));
    for (final sx in [-1.0, 1.0]) {
      head.add(
        part(
          box(hs * 0.08, hs * 0.3, hs * 0.3),
          bottom,
          sx * hs * 0.5,
          hs * 0.5,
          0,
        ),
      );
    }
  } else {
    // Eyes on the front (+Z).
    for (final sx in [-1.0, 1.0]) {
      head.add(
        part(
          box(hs * 0.12, hs * 0.1, 0.01),
          eyes,
          sx * hs * 0.18,
          hs * 0.55,
          hs * 0.455,
          bias: 0.02,
        ),
      );
    }
  }
  // Hair.
  switch (kind) {
    case Kind.man || Kind.boy || Kind.teen || Kind.bigMan:
      if (!covered) {
        head.add(
          part(
            box(hs * 0.88, hs * 0.22, hs * 0.96),
            hair,
            0,
            hs * 1.02,
            -hs * 0.02,
          ),
        );
      }
      head.add(
        part(box(hs * 0.88, hs * 0.5, hs * 0.2), hair, 0, hs * 0.8, -hs * 0.4),
      );
      if (kind == Kind.teen && !covered) {
        // A fringe.
        head.add(
          part(
            box(hs * 0.5, hs * 0.18, hs * 0.2),
            hair,
            hs * 0.12,
            hs * 0.92,
            hs * 0.38,
          ),
        );
      }
    case Kind.toddler:
      if (!covered) {
        head.add(
          part(
            box(hs * 0.86, hs * 0.14, hs * 0.94),
            hair,
            0,
            hs * 1.0,
            -hs * 0.02,
          ),
        );
        head.add(
          part(
            box(hs * 0.12, hs * 0.2, hs * 0.12),
            hair,
            0,
            hs * 1.12,
            hs * 0.1,
          ),
        );
      }
    case Kind.woman || Kind.girl:
      if (!covered) {
        head.add(
          part(box(hs * 0.92, hs * 0.24, hs * 1.0), hair, 0, hs * 1.02, 0),
        );
      }
      head.add(
        part(
          box(hs * 0.96, hs * (kind == Kind.girl ? 0.9 : 1.15), hs * 0.3),
          hair,
          0,
          hs * 0.5,
          -hs * 0.42,
        ),
      );
      if (kind == Kind.girl) {
        for (final sx in [-1.0, 1.0]) {
          head.add(
            part(
              box(hs * 0.18, hs * 0.5, hs * 0.18),
              hair,
              sx * hs * 0.52,
              hs * 0.55,
              -hs * 0.2,
            ),
          );
        }
      }
    case Kind.oldMan:
      // Bald on top, a ring of white hair, and a moustache.
      head.add(
        part(box(hs * 0.9, hs * 0.3, hs * 0.5), hair, 0, hs * 0.55, -hs * 0.25),
      );
      head.add(
        part(
          box(hs * 0.4, hs * 0.07, 0.02),
          hair,
          0,
          hs * 0.3,
          hs * 0.46,
          bias: 0.02,
        ),
      );
    case Kind.oldWoman:
      if (!covered) {
        head.add(
          part(box(hs * 0.9, hs * 0.22, hs * 0.96), hair, 0, hs * 1.0, 0),
        );
      }
      head.add(
        part(
          sphereMesh(hs * 0.22, segments: 6, rings: 4),
          hair,
          0,
          hs * 1.05,
          -hs * 0.45,
        ),
      ); // bun
    case Kind.robot:
  }
  // Things worn on the head.
  if (extras.contains(Extra.hat)) {
    head.add(
      part(
        box(hs * 1.3, hs * 0.05, hs * 1.3),
        accent,
        0,
        hs * 1.02,
        0,
        bias: 0.02,
      ),
    );
    head.add(
      part(
        box(hs * 0.9, hs * 0.42, hs * 0.96),
        accent,
        0,
        hs * 1.24,
        0,
        bias: 0.02,
      ),
    );
  } else if (extras.contains(Extra.cap)) {
    head.add(
      part(
        box(hs * 0.96, hs * 0.26, hs * 1.02),
        accent,
        0,
        hs * 1.04,
        -hs * 0.02,
        bias: 0.02,
      ),
    );
    head.add(
      part(
        box(hs * 0.8, hs * 0.05, hs * 0.45),
        accent,
        0,
        hs * 0.94,
        hs * 0.62,
        bias: 0.02,
      ),
    );
  }
  if (extras.contains(Extra.glasses)) {
    final frame = mat(0xFF1A1A1E);
    for (final sx in [-1.0, 1.0]) {
      head.add(
        part(
          box(hs * 0.28, hs * 0.2, hs * 0.06),
          frame,
          sx * hs * 0.2,
          hs * 0.56,
          hs * 0.49,
          bias: 0.04,
        ),
      );
      head.add(
        part(
          box(hs * 0.2, hs * 0.12, hs * 0.02),
          mat(0xFFB8D8F0),
          sx * hs * 0.2,
          hs * 0.56,
          hs * 0.515,
          bias: 0.06,
        ),
      );
    }
    head.add(
      part(
        box(hs * 0.14, hs * 0.04, hs * 0.04),
        frame,
        0,
        hs * 0.6,
        hs * 0.5,
        bias: 0.04,
      ),
    );
  }
  if (extras.contains(Extra.beard)) {
    head.add(
      part(
        box(hs * 0.86, hs * 0.4, hs * 0.24),
        hair,
        0,
        hs * 0.18,
        hs * 0.38,
        bias: 0.03,
      ),
    );
  }
  if (extras.contains(Extra.backpack)) {
    chest.add(
      part(
        box(shoulder * 1.4, 0.32 * s, 0.14 * s),
        accent,
        0,
        0.06 * s,
        -0.17 * s * (0.6 + w * 0.4),
        bias: 0.02,
      ),
    );
  }

  for (final side in [1.0, -1.0]) {
    final sfx = side > 0 ? 'L' : 'R';
    final upper = chest.add(
      joint('upperArm$sfx', side * (shoulder + 0.04 * limb), 0.2 * s, 0),
    );
    upper.add(
      part(
        box(0.085 * limb, 0.28 * s * arms, 0.085 * limb),
        sleeves,
        0,
        -0.13 * s * arms,
        0,
      ),
    );
    final lower = upper.add(joint('lowerArm$sfx', 0, -0.27 * s * arms, 0));
    lower.add(
      part(
        box(0.075 * limb, 0.25 * s * arms, 0.075 * limb),
        jacket ? accent : (robot ? bottom : skin),
        0,
        -0.12 * s * arms,
        0,
      ),
    );
    final hand = lower.add(joint('hand$sfx', 0, -0.25 * s * arms, 0));
    hand.add(
      part(box(0.07 * limb, 0.09 * s, 0.05 * limb), skin, 0, -0.04 * s, 0),
    );

    final thigh = hips.add(joint('upperLeg$sfx', side * hipW, -0.06 * s, 0));
    thigh.add(
      part(
        box(0.12 * limb, thighLen, 0.13 * limb),
        bottom,
        0,
        -thighLen * 0.48,
        0,
      ),
    );
    final shin = thigh.add(joint('lowerLeg$sfx', 0, -thighLen, 0));
    shin.add(
      part(
        box(0.1 * limb, shinLen * 0.98, 0.11 * limb),
        female && !small && !extras.contains(Extra.dress)
            ? skin
            : (extras.contains(Extra.dress) ? skin : bottom),
        0,
        -shinLen * 0.49,
        0,
      ),
    );
    final foot = shin.add(joint('foot$sfx', 0, -shinLen, 0));
    foot.add(
      part(box(0.1 * limb, 0.07 * s, 0.22 * s), shoes, 0, -0.01 * s, 0.05 * s),
    );
  }
  if (extras.contains(Extra.dress)) {
    // A long skirt to the knees, in the top's colour.
    hips.add(
      part(
        box(hipW * 2 + 0.16 * s, thighLen * 1.05, 0.26 * s * w),
        top,
        0,
        -thighLen * 0.5,
        0,
      ),
    );
  } else if (female && !small) {
    // A skirt over the top of the legs.
    hips.add(
      part(
        box(hipW * 2 + 0.12 * s, 0.32 * s * legs, 0.24 * s * w),
        bottom,
        0,
        -0.2 * s * legs,
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
  return Character('human', root, joints, rest, hipsY);
}
