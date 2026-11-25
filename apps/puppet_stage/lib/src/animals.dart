import 'package:engine3d/engine3d.dart';

import 'cast.dart';
import 'moves.dart';

/// Animals, built in code in the same blocky style as the people.
enum Animal {
  dog('Dog', 'quad', 'Bark'),
  cat('Cat', 'quad', 'Meow'),
  cow('Cow', 'quad', 'Moo'),
  horse('Horse', 'quad', 'Neigh'),
  pig('Pig', 'quad', 'Oink'),
  chicken('Chicken', 'bird', 'Cluck'),
  bird('Bird', 'bird', 'Tweet');

  const Animal(this.label, this.rig, this.call);
  final String label, rig, call;
}

/// Colours: top = coat / feathers, bottom = markings / wings, hair = mane,
/// ears, tail tip or comb, skin = nose, hooves, beak and legs.
const animalLooks = {
  Animal.dog: Look(
    skin: 0xFF2A2420,
    hair: 0xFF7A4A28,
    top: 0xFFC08A50,
    bottom: 0xFFF0E0C8,
  ),
  Animal.cat: Look(
    skin: 0xFFE8A0A0,
    hair: 0xFF5A5A62,
    top: 0xFF8A8A92,
    bottom: 0xFFE8E4E0,
  ),
  Animal.cow: Look(
    skin: 0xFFE8B0A8,
    hair: 0xFF2A2420,
    top: 0xFFF2F0EA,
    bottom: 0xFF2A2420,
  ),
  Animal.horse: Look(
    skin: 0xFF2A2420,
    hair: 0xFF2E1E16,
    top: 0xFF8A5432,
    bottom: 0xFF8A5432,
  ),
  Animal.pig: Look(
    skin: 0xFFD87A88,
    hair: 0xFFE89AA4,
    top: 0xFFF0AAB4,
    bottom: 0xFFF0AAB4,
  ),
  Animal.chicken: Look(
    skin: 0xFFE8B030,
    hair: 0xFFD83A30,
    top: 0xFFF4F0E6,
    bottom: 0xFFE4DCCC,
  ),
  Animal.bird: Look(
    skin: 0xFFE8A030,
    hair: 0xFF2A2A30,
    top: 0xFF4A7AC8,
    bottom: 0xFF2E4A80,
  ),
};

const quadJoints = [
  'hips', 'chest', 'neck', 'head', 'tail', //
  'legFL', 'shinFL', 'legFR', 'shinFR', 'legBL', 'shinBL', 'legBR', 'shinBR',
];
const birdJoints = [
  'hips', 'neck', 'head', 'tail', 'wingL', 'wingR', //
  'legL', 'footL', 'legR', 'footR',
];

/// Proportions of a four-legged animal (metres).
class _Quad {
  const _Quad({
    required this.length,
    required this.height,
    required this.width,
    required this.leg,
    required this.shin,
    required this.neck,
    required this.neckAngle,
    required this.head,
    required this.snout,
    required this.tail,
    required this.tailAngle,
  });
  final double length, height, width, leg, shin, neck, neckAngle;
  final double head, snout, tail, tailAngle;
}

const _cat = _Quad(
  length: 0.36,
  height: 0.14,
  width: 0.12,
  leg: 0.11,
  shin: 0.11,
  neck: 0.08,
  neckAngle: 25,
  head: 0.12,
  snout: 0.02,
  tail: 0.3,
  tailAngle: -25,
);

const _quads = {
  Animal.dog: _Quad(
    length: 0.5,
    height: 0.2,
    width: 0.18,
    leg: 0.17,
    shin: 0.17,
    neck: 0.14,
    neckAngle: 35,
    head: 0.15,
    snout: 0.09,
    tail: 0.2,
    tailAngle: -45,
  ),
  Animal.cat: _cat,
  Animal.cow: _Quad(
    length: 1.35,
    height: 0.58,
    width: 0.52,
    leg: 0.36,
    shin: 0.34,
    neck: 0.26,
    neckAngle: 70,
    head: 0.28,
    snout: 0.2,
    tail: 0.6,
    tailAngle: -165,
  ),
  Animal.horse: _Quad(
    length: 1.3,
    height: 0.52,
    width: 0.4,
    leg: 0.46,
    shin: 0.48,
    neck: 0.6,
    neckAngle: 35,
    head: 0.24,
    snout: 0.32,
    tail: 0.55,
    tailAngle: -150,
  ),
  Animal.pig: _Quad(
    length: 0.85,
    height: 0.4,
    width: 0.38,
    leg: 0.13,
    shin: 0.12,
    neck: 0.08,
    neckAngle: 80,
    head: 0.26,
    snout: 0.08,
    tail: 0.1,
    tailAngle: -40,
  ),
};

Node _joint(String name, double x, double y, double z) =>
    Node(name: name, position: Vector3(x, y, z));
Node _part(Mesh m, int color, double x, double y, double z) => Node(
  name: 'part',
  mesh: m,
  material: Surface(color: color),
  position: Vector3(x, y, z),
);
Mesh _box(double w, double h, double d) => boxMesh(w, h, d, split: 1);

Character buildAnimal(Animal a, Look look) =>
    a.rig == 'bird' ? _bird(a, look) : _quad(a, look, _quads[a]!);

Character _quad(Animal a, Look look, _Quad q) {
  final legTop = q.leg + q.shin + q.length * 0.02;
  final hipsY = legTop + q.height * 0.1;
  final root = Node(name: 'actor');
  final half = q.length / 2;
  // Hips over the back legs, chest over the front ones.
  final hips = root.add(_joint('hips', 0, hipsY, -half * 0.75));
  final chest = hips.add(_joint('chest', 0, 0, half * 1.5));
  hips.add(
    _part(_box(q.width, q.height, half * 1.05), look.top, 0, 0, half * 0.4),
  );
  chest.add(
    _part(
      _box(q.width * 1.04, q.height * 1.05, half * 1.05),
      look.top,
      0,
      0,
      -half * 0.25,
    ),
  );
  // Belly / markings.
  switch (a) {
    case Animal.cow:
      for (final (x, y, z, w, h, d) in [
        (q.width / 2 + 0.005, 0.05, 0.1, 0.01, 0.3, 0.35),
        (-q.width / 2 - 0.005, -0.05, 0.45, 0.01, 0.25, 0.3),
        (0.0, q.height / 2 + 0.005, 0.3, 0.3, 0.01, 0.25),
      ]) {
        hips.add(_part(_box(w, h, d), look.bottom, x, y, z));
      }
      chest.add(
        _part(_box(0.01, 0.28, 0.3), look.bottom, q.width / 2 + 0.006, 0, -0.1),
      );
      // Udder.
      hips.add(_part(_box(0.2, 0.1, 0.2), look.skin, 0, -q.height / 2, 0.15));
    case Animal.dog || Animal.cat:
      chest.add(
        _part(
          _box(q.width * 0.8, 0.012, half * 0.9),
          look.bottom,
          0,
          -q.height / 2 - 0.004,
          -half * 0.2,
        ),
      );
    default:
  }
  // Neck and head.
  final neck = chest.add(_joint('neck', 0, q.height * 0.3, half * 0.2));
  final nw = a == Animal.horse ? q.width * 0.55 : q.width * 0.6;
  neck.add(
    _part(_box(nw, q.neck + q.height * 0.2, nw), look.top, 0, q.neck / 2, 0),
  );
  if (a == Animal.horse) {
    neck.add(
      _part(_box(0.05, q.neck * 1.1, 0.12), look.hair, 0, q.neck / 2, -nw / 2),
    );
  }
  final head = neck.add(_joint('head', 0, q.neck, 0));
  final h = q.head;
  head.add(_part(_box(h * 0.95, h, h * 1.05), look.top, 0, h * 0.2, 0));
  // Snout (+Z is forward once the head is level).
  if (q.snout > 0.03) {
    head.add(
      _part(
        _box(h * 0.6, h * 0.55, q.snout),
        a == Animal.cow ? look.skin : look.top,
        0,
        -h * 0.05,
        h * 0.5 + q.snout / 2,
      ),
    );
  }
  // Nose.
  head.add(
    _part(
      _box(a == Animal.pig ? h * 0.55 : h * 0.3, h * 0.25, 0.02),
      look.skin,
      0,
      a == Animal.pig ? h * 0.1 : 0.0,
      h * 0.52 + (q.snout > 0.03 ? q.snout : 0),
    ),
  );
  // Eyes.
  for (final sx in [-1.0, 1.0]) {
    head.add(
      _part(
        _box(h * 0.14, h * 0.14, 0.01),
        0xFF141010,
        sx * h * 0.25,
        h * 0.35,
        h * 0.53,
      ),
    );
  }
  // Ears and horns.
  for (final sx in [-1.0, 1.0]) {
    switch (a) {
      case Animal.cat || Animal.horse:
        final e = head.add(
          _part(
            _box(h * 0.28, h * 0.4, h * 0.1),
            look.top,
            sx * h * 0.3,
            h * 0.85,
            -h * 0.1,
          ),
        );
        e.rotation = euler(0, 0, -sx * 12);
      case Animal.dog:
        final e = head.add(
          _part(
            _box(h * 0.18, h * 0.6, h * 0.35),
            look.hair,
            sx * h * 0.52,
            h * 0.3,
            -h * 0.1,
          ),
        );
        e.rotation = euler(0, 0, sx * 10);
      case Animal.pig:
        final e = head.add(
          _part(
            _box(h * 0.35, h * 0.06, h * 0.3),
            look.hair,
            sx * h * 0.35,
            h * 0.72,
            h * 0.1,
          ),
        );
        e.rotation = euler(25, 0, sx * 20);
      case Animal.cow:
        head.add(
          _part(
            _box(h * 0.4, h * 0.14, h * 0.18),
            look.top,
            sx * h * 0.6,
            h * 0.45,
            -h * 0.15,
          ),
        );
        final horn = head.add(
          _part(
            _box(h * 0.12, h * 0.35, h * 0.12),
            0xFFE8E0C8,
            sx * h * 0.32,
            h * 0.8,
            -h * 0.2,
          ),
        );
        horn.rotation = euler(0, 0, -sx * 35);
      default:
    }
  }
  // Tail.
  final tail = hips.add(_joint('tail', 0, q.height * 0.35, -half * 0.12));
  tail.add(
    _part(
      _box(
        a == Animal.horse ? 0.1 : q.width * 0.18,
        q.tail,
        a == Animal.horse ? 0.06 : q.width * 0.18,
      ),
      a == Animal.horse ? look.hair : look.top,
      0,
      q.tail / 2,
      0,
    ),
  );
  if (a == Animal.cow) {
    tail.add(_part(_box(0.06, 0.12, 0.06), look.hair, 0, q.tail, 0));
  }
  // Legs: thigh, shin, foot.
  for (final (front, sx) in [
    (true, -1.0),
    (true, 1.0),
    (false, -1.0),
    (false, 1.0),
  ]) {
    final id = '${front ? 'F' : 'B'}${sx < 0 ? 'R' : 'L'}';
    final parent = front ? chest : hips;
    final lw = q.width * (a == Animal.horse ? 0.26 : 0.3);
    final leg = parent.add(
      _joint(
        'leg$id',
        sx * (q.width / 2 - lw / 2),
        -q.height * 0.1,
        front ? -half * 0.1 : half * 0.15,
      ),
    );
    leg.add(
      _part(
        _box(lw, q.leg + q.height * 0.3, lw * 1.2),
        look.top,
        0,
        -q.leg / 2 + q.height * 0.1,
        0,
      ),
    );
    final shin = leg.add(_joint('shin$id', 0, -q.leg, 0));
    shin.add(
      _part(_box(lw * 0.8, q.shin, lw * 0.85), look.top, 0, -q.shin / 2, 0),
    );
    // Hooves for big animals, paws for the rest.
    final hoof = a == Animal.cow || a == Animal.horse || a == Animal.pig;
    shin.add(
      _part(
        _box(lw * 0.9, q.shin * 0.14, lw * (hoof ? 0.95 : 1.4)),
        hoof ? look.skin : (a == Animal.dog ? look.bottom : look.top),
        0,
        -q.shin,
        hoof ? 0 : lw * 0.25,
      ),
    );
  }
  final rest = <String, (double, double, double)>{'tail': (q.tailAngle, 0, 0)};
  // The neck leans forward from upright by neckAngle°; the head turns
  // back so it is level.
  rest['neck'] = (q.neckAngle, 0, 0);
  rest['head'] = (-q.neckAngle, 0, 0);
  final hy = legTop + q.height * 0.1;
  return _finish(
    'quad',
    root,
    quadJoints,
    rest,
    hy,
    0.43,
    span: half * 1.5,
    clearance: hy - q.height / 2,
  );
}

Character _bird(Animal a, Look look) {
  final chicken = a == Animal.chicken;
  final k = chicken ? 1.0 : 0.45;
  final legH = 0.14 * k;
  final bodyH = 0.2 * k, bodyL = 0.3 * k, bodyW = 0.2 * k;
  final hipsY = legH + bodyH * 0.35;
  final root = Node(name: 'actor');
  final hips = root.add(_joint('hips', 0, hipsY, 0));
  hips.add(_part(_box(bodyW, bodyH, bodyL), look.top, 0, 0, 0));
  hips.add(
    _part(
      _box(bodyW * 0.85, bodyH * 0.7, bodyL * 0.4),
      look.top,
      0,
      bodyH * 0.25,
      bodyL * 0.45,
    ),
  );
  final neck = hips.add(_joint('neck', 0, bodyH * 0.35, bodyL * 0.4));
  neck.add(_part(_box(0.08 * k, 0.12 * k, 0.08 * k), look.top, 0, 0.06 * k, 0));
  final head = neck.add(_joint('head', 0, 0.12 * k, 0));
  final hs = 0.1 * k;
  head.add(_part(_box(hs, hs * 1.1, hs * 1.1), look.top, 0, hs * 0.4, 0));
  head.add(
    _part(
      _box(hs * 0.4, hs * 0.3, hs * 0.5),
      look.skin,
      0,
      hs * 0.35,
      hs * 0.75,
    ),
  );
  for (final sx in [-1.0, 1.0]) {
    head.add(
      _part(
        _box(0.01, hs * 0.2, hs * 0.2),
        0xFF141010,
        sx * hs * 0.505,
        hs * 0.55,
        hs * 0.2,
      ),
    );
  }
  if (chicken) {
    // Comb and wattle.
    head.add(_part(_box(hs * 0.2, hs * 0.45, hs * 0.7), look.hair, 0, hs, 0));
    head.add(
      _part(_box(hs * 0.2, hs * 0.35, hs * 0.2), look.hair, 0, 0, hs * 0.55),
    );
  } else {
    head.add(
      _part(_box(hs * 1.02, hs * 0.3, hs * 0.6), look.hair, 0, hs, -0.1 * hs),
    );
  }
  final tail = hips.add(_joint('tail', 0, bodyH * 0.2, -bodyL * 0.45));
  tail.add(
    _part(
      _box(bodyW * (chicken ? 0.5 : 0.6), 0.02, bodyL * 0.6),
      look.bottom,
      0,
      0,
      -bodyL * 0.25,
    ),
  );
  if (chicken) {
    tail.add(
      _part(
        _box(bodyW * 0.4, bodyH * 0.6, 0.04),
        look.bottom,
        0,
        bodyH * 0.25,
        -0.02,
      ),
    );
  }
  for (final sx in [-1.0, 1.0]) {
    final s = sx > 0 ? 'L' : 'R';
    final wing = hips.add(_joint('wing$s', sx * bodyW / 2, bodyH * 0.35, 0));
    // A flat plate against the body: hangs down and back when folded.
    wing.add(
      _part(
        _box(0.02, bodyH * 0.8, bodyL * 0.75),
        look.bottom,
        sx * 0.012,
        -bodyH * 0.38,
        -bodyL * 0.05,
      ),
    );
    final leg = hips.add(_joint('leg$s', sx * bodyW * 0.22, -bodyH * 0.3, 0));
    leg.add(
      _part(_box(0.025 * k, legH, 0.025 * k), look.skin, 0, -legH / 2, 0),
    );
    final foot = leg.add(_joint('foot$s', 0, -legH + bodyH * 0.05, 0));
    foot.add(_part(_box(0.06 * k, 0.012, 0.08 * k), look.skin, 0, 0, 0.02 * k));
  }
  final rest = <String, (double, double, double)>{
    'tail': (chicken ? -30 : -10, 0, 0),
    'neck': (chicken ? 10 : 15, 0, 0),
    'head': (chicken ? -10 : -15, 0, 0),
  };
  return _finish('bird', root, birdJoints, rest, hipsY, 0.2);
}

Character _finish(
  String rig,
  Node root,
  List<String> names,
  Map<String, (double, double, double)> rest,
  double hipsY,
  double liftRef, {
  double span = 0,
  double clearance = 0,
}) {
  final all = root.byName();
  final joints = {for (final n in names) n: all[n]!};
  rest.forEach((n, e) => joints[n]!.rotation = euler(e.$1, e.$2, e.$3));
  return Character(
    rig,
    root,
    joints,
    rest,
    hipsY,
    liftRef: liftRef,
    span: span,
    clearance: clearance,
  );
}

typedef _K = (double, Pose);

// Four-legged moves. Legs: negative x swings forward; shins: positive bends
// a front knee back, negative bends a back hock forward. Lifts are for a
// dog-sized animal (hips 0.43 m) and scale with size.
const _stand = <String, (double, double, double)>{
  'legFL': (0, 0, 0), 'legFR': (0, 0, 0), 'legBL': (0, 0, 0), //
  'legBR': (0, 0, 0), 'shinFL': (0, 0, 0), 'shinFR': (0, 0, 0),
  'shinBL': (0, 0, 0), 'shinBR': (0, 0, 0), 'hips': (0, 0, 0),
  'lift': (0, 0, 0),
};

Pose _gait(
  double fl,
  double fr,
  double bl,
  double br, {
  Pose extra = const {},
}) => {
  'legFL': (fl, 0, 0),
  'legFR': (fr, 0, 0),
  'legBL': (bl, 0, 0),
  'legBR': (br, 0, 0),
  'shinFL': (fl > 5 ? 35 : 0, 0, 0),
  'shinFR': (fr > 5 ? 35 : 0, 0, 0),
  'shinBL': (bl < -5 ? -30 : 0, 0, 0),
  'shinBR': (br < -5 ? -30 : 0, 0, 0),
  ...extra,
};

final quadMoves = <Move>[
  Move('idle', 'Stand', 2.4, rig: 'quad', <_K>[
    (0, {..._stand, 'tail': (0, 10, 0), 'head': (0, 0, 0)}),
    (
      1.2,
      {..._stand, 'tail': (0, -10, 0), 'head': (4, 10, 0), 'chest': (-1, 0, 0)},
    ),
    (2.4, {..._stand, 'tail': (0, 10, 0), 'head': (0, 0, 0)}),
  ]),
  Move('walk', 'Walk', 0.9, rig: 'quad', <_K>[
    (
      0,
      _gait(-22, 18, 18, -22, extra: {'tail': (0, 10, 0), 'head': (3, 0, 0)}),
    ),
    (
      0.225,
      _gait(
        0,
        8,
        8,
        0,
        extra: {
          'shinFR': (45, 0, 0),
          'shinBL': (-40, 0, 0),
          'lift': (0.012, 0, 0),
        },
      ),
    ),
    (
      0.45,
      _gait(18, -22, -22, 18, extra: {'tail': (0, -10, 0), 'head': (-2, 0, 0)}),
    ),
    (
      0.675,
      _gait(
        8,
        0,
        0,
        8,
        extra: {
          'shinFL': (45, 0, 0),
          'shinBR': (-40, 0, 0),
          'lift': (0.012, 0, 0),
        },
      ),
    ),
    (
      0.9,
      _gait(-22, 18, 18, -22, extra: {'tail': (0, 10, 0), 'head': (3, 0, 0)}),
    ),
  ]),
  Move('run', 'Run', 0.5, rig: 'quad', <_K>[
    (
      0,
      {
        ..._gait(-45, -35, 40, 30),
        'hips': (-6, 0, 0),
        'lift': (0.06, 0, 0),
        'tail': (-20, 0, 0),
        'shinFL': (10, 0, 0),
        'shinFR': (10, 0, 0),
      },
    ),
    (
      0.25,
      {
        ..._gait(35, 25, -45, -35),
        'hips': (6, 0, 0),
        'lift': (0, 0, 0),
        'tail': (-10, 0, 0),
        'shinFL': (60, 0, 0),
        'shinFR': (50, 0, 0),
        'shinBL': (-50, 0, 0),
        'shinBR': (-45, 0, 0),
      },
    ),
    (
      0.5,
      {
        ..._gait(-45, -35, 40, 30),
        'hips': (-6, 0, 0),
        'lift': (0.06, 0, 0),
        'tail': (-20, 0, 0),
        'shinFL': (10, 0, 0),
        'shinFR': (10, 0, 0),
      },
    ),
  ]),
  Move('sit', 'Sit', 1.0, loop: false, rig: 'quad', <_K>[
    (0, {..._stand, 'sit': (0, 0, 0)}),
    (1.0, {..._stand, 'sit': (1, 0, 0), 'tail': (70, 0, 0)}),
  ]),
  Move('lie', 'Lie down', 1.2, loop: false, rig: 'quad', <_K>[
    (0, {..._stand}),
    (
      1.2,
      {
        'lift': (-0.27, 0, 0),
        'legFL': (-80, 0, 0),
        'legFR': (-80, 0, 0),
        'shinFL': (10, 0, 0),
        'shinFR': (10, 0, 0),
        'legBL': (-70, 0, 0),
        'legBR': (-70, 0, 0),
        'shinBL': (140, 0, 0),
        'shinBR': (140, 0, 0),
        'tail': (40, 25, 0),
      },
    ),
  ]),
  Move('sleep', 'Sleep', 3.0, rig: 'quad', <_K>[
    (
      0,
      {
        'lift': (-0.27, 0, 0),
        'legFL': (-80, 0, 0),
        'legFR': (-80, 0, 0),
        'legBL': (-70, 0, 0),
        'legBR': (-70, 0, 0),
        'shinBL': (140, 0, 0),
        'shinBR': (140, 0, 0),
        'neck': (25, 0, 0),
        'head': (20, 0, 8),
        'tail': (40, 40, 0),
        'chest': (0, 0, 0),
      },
    ),
    (
      1.5,
      {
        'lift': (-0.265, 0, 0),
        'legFL': (-80, 0, 0),
        'legFR': (-80, 0, 0),
        'legBL': (-70, 0, 0),
        'legBR': (-70, 0, 0),
        'shinBL': (140, 0, 0),
        'shinBR': (140, 0, 0),
        'neck': (25, 0, 0),
        'head': (20, 0, 8),
        'tail': (40, 40, 0),
        'chest': (-2, 0, 0),
      },
    ),
    (
      3.0,
      {
        'lift': (-0.27, 0, 0),
        'legFL': (-80, 0, 0),
        'legFR': (-80, 0, 0),
        'legBL': (-70, 0, 0),
        'legBR': (-70, 0, 0),
        'shinBL': (140, 0, 0),
        'shinBR': (140, 0, 0),
        'neck': (25, 0, 0),
        'head': (20, 0, 8),
        'tail': (40, 40, 0),
        'chest': (0, 0, 0),
      },
    ),
  ]),
  Move('eat', 'Eat', 1.6, rig: 'quad', <_K>[
    (0, {..._stand, 'neck': (70, 0, 0), 'head': (25, 0, 0)}),
    (0.4, {..._stand, 'neck': (72, 0, 0), 'head': (35, 0, 0)}),
    (0.8, {..._stand, 'neck': (68, 4, 0), 'head': (22, 0, 0)}),
    (1.2, {..._stand, 'neck': (72, 0, 0), 'head': (35, 0, 0)}),
    (1.6, {..._stand, 'neck': (70, 0, 0), 'head': (25, 0, 0)}),
  ]),
  Move('jump', 'Jump', 1.0, loop: false, rig: 'quad', <_K>[
    (0, {..._stand}),
    (
      0.25,
      {
        ..._gait(-20, -20, -30, -30),
        'shinBL': (-50, 0, 0),
        'shinBR': (-50, 0, 0),
        'lift': (-0.06, 0, 0),
        'hips': (-8, 0, 0),
      },
    ),
    (
      0.5,
      {
        ..._gait(-50, -50, 45, 45),
        'lift': (0.3, 0, 0),
        'hips': (-12, 0, 0),
        'tail': (-30, 0, 0),
      },
    ),
    (
      0.75,
      {..._gait(-10, -10, 10, 10), 'lift': (0.02, 0, 0), 'hips': (6, 0, 0)},
    ),
    (1.0, {..._stand}),
  ]),
  Move('look', 'Look around', 2.4, rig: 'quad', <_K>[
    (0, {..._stand, 'neck': (0, 0, 0), 'head': (0, 0, 0)}),
    (0.6, {..._stand, 'neck': (0, 30, 0), 'head': (-5, 25, 0)}),
    (1.4, {..._stand, 'neck': (0, -30, 0), 'head': (-5, -25, 0)}),
    (2.4, {..._stand, 'neck': (0, 0, 0), 'head': (0, 0, 0)}),
  ]),
  Move('wag', 'Happy (wag)', 0.4, rig: 'quad', <_K>[
    (
      0,
      {..._stand, 'tail': (-20, 40, 0), 'hips': (0, 4, 0), 'head': (-10, 0, 6)},
    ),
    (
      0.2,
      {
        ..._stand,
        'tail': (-20, -40, 0),
        'hips': (0, -4, 0),
        'head': (-10, 0, -6),
      },
    ),
    (
      0.4,
      {..._stand, 'tail': (-20, 40, 0), 'hips': (0, 4, 0), 'head': (-10, 0, 6)},
    ),
  ]),
  Move('call', 'Call', 1.0, rig: 'quad', <_K>[
    (0, {..._stand, 'neck': (0, 0, 0), 'head': (0, 0, 0)}),
    (
      0.15,
      {
        ..._stand,
        'neck': (-15, 0, 0),
        'head': (-25, 0, 0),
        'chest': (-4, 0, 0),
      },
    ),
    (0.3, {..._stand, 'neck': (-5, 0, 0), 'head': (-8, 0, 0)}),
    (
      0.45,
      {
        ..._stand,
        'neck': (-15, 0, 0),
        'head': (-25, 0, 0),
        'chest': (-4, 0, 0),
      },
    ),
    (0.7, {..._stand, 'neck': (0, 0, 0), 'head': (0, 0, 0)}),
    (1.0, {..._stand, 'neck': (0, 0, 0), 'head': (0, 0, 0)}),
  ]),
  Move('shake', 'Shake off', 0.3, rig: 'quad', <_K>[
    (
      0,
      {..._stand, 'hips': (0, 0, 14), 'chest': (0, 0, -24), 'head': (0, 0, 20)},
    ),
    (
      0.15,
      {
        ..._stand,
        'hips': (0, 0, -14),
        'chest': (0, 0, 24),
        'head': (0, 0, -20),
      },
    ),
    (
      0.3,
      {..._stand, 'hips': (0, 0, 14), 'chest': (0, 0, -24), 'head': (0, 0, 20)},
    ),
  ]),
];

// Bird moves: wings z opens (left +, right -), legs x like the people.
const _perch = <String, (double, double, double)>{
  'wingL': (0, 0, 0), 'wingR': (0, 0, 0), 'legL': (0, 0, 0), //
  'legR': (0, 0, 0), 'footL': (0, 0, 0), 'footR': (0, 0, 0),
  'hips': (0, 0, 0), 'lift': (0, 0, 0),
};

final birdMoves = <Move>[
  Move('idle', 'Stand', 2.0, rig: 'bird', <_K>[
    (0, {..._perch, 'head': (0, 0, 0), 'tail': (0, 0, 0)}),
    (0.7, {..._perch, 'head': (0, 25, 0), 'tail': (-5, 0, 0)}),
    (1.3, {..._perch, 'head': (0, -15, 5), 'tail': (0, 0, 0)}),
    (2.0, {..._perch, 'head': (0, 0, 0), 'tail': (0, 0, 0)}),
  ]),
  Move('walk', 'Walk', 0.6, rig: 'bird', <_K>[
    (
      0,
      {
        ..._perch,
        'legL': (-30, 0, 0),
        'legR': (25, 0, 0),
        'neck': (25, 0, 0),
        'head': (-25, 0, 0),
        'hips': (0, 0, 4),
      },
    ),
    (
      0.15,
      {
        ..._perch,
        'legL': (0, 0, 0),
        'legR': (-5, 0, 0),
        'footR': (30, 0, 0),
        'neck': (-5, 0, 0),
        'head': (5, 0, 0),
        'lift': (0.01, 0, 0),
      },
    ),
    (
      0.3,
      {
        ..._perch,
        'legL': (25, 0, 0),
        'legR': (-30, 0, 0),
        'neck': (25, 0, 0),
        'head': (-25, 0, 0),
        'hips': (0, 0, -4),
      },
    ),
    (
      0.45,
      {
        ..._perch,
        'legL': (-5, 0, 0),
        'legR': (0, 0, 0),
        'footL': (30, 0, 0),
        'neck': (-5, 0, 0),
        'head': (5, 0, 0),
        'lift': (0.01, 0, 0),
      },
    ),
    (
      0.6,
      {
        ..._perch,
        'legL': (-30, 0, 0),
        'legR': (25, 0, 0),
        'neck': (25, 0, 0),
        'head': (-25, 0, 0),
        'hips': (0, 0, 4),
      },
    ),
  ]),
  Move('run', 'Run', 0.36, rig: 'bird', <_K>[
    (
      0,
      {
        ..._perch,
        'hips': (20, 0, 0),
        'legL': (-50, 0, 0),
        'legR': (40, 0, 0),
        'wingL': (0, 0, 35),
        'wingR': (0, 0, -35),
        'neck': (20, 0, 0),
      },
    ),
    (
      0.18,
      {
        ..._perch,
        'hips': (20, 0, 0),
        'legL': (40, 0, 0),
        'legR': (-50, 0, 0),
        'wingL': (0, 0, 15),
        'wingR': (0, 0, -15),
        'neck': (20, 0, 0),
        'lift': (0.02, 0, 0),
      },
    ),
    (
      0.36,
      {
        ..._perch,
        'hips': (20, 0, 0),
        'legL': (-50, 0, 0),
        'legR': (40, 0, 0),
        'wingL': (0, 0, 35),
        'wingR': (0, 0, -35),
        'neck': (20, 0, 0),
      },
    ),
  ]),
  Move('peck', 'Peck', 0.8, rig: 'bird', <_K>[
    (0, {..._perch, 'neck': (0, 0, 0), 'head': (0, 0, 0), 'hips': (0, 0, 0)}),
    (
      0.3,
      {..._perch, 'hips': (25, 0, 0), 'neck': (60, 0, 0), 'head': (20, 0, 0)},
    ),
    (
      0.4,
      {..._perch, 'hips': (25, 0, 0), 'neck': (50, 0, 0), 'head': (10, 0, 0)},
    ),
    (
      0.5,
      {..._perch, 'hips': (25, 0, 0), 'neck': (60, 0, 0), 'head': (20, 0, 0)},
    ),
    (0.8, {..._perch, 'neck': (0, 0, 0), 'head': (0, 0, 0), 'hips': (0, 0, 0)}),
  ]),
  Move('flap', 'Flap wings', 0.3, rig: 'bird', <_K>[
    (
      0,
      {
        ..._perch,
        'wingL': (0, 0, 20),
        'wingR': (0, 0, -20),
        'hips': (-10, 0, 0),
      },
    ),
    (
      0.15,
      {
        ..._perch,
        'wingL': (0, 0, 110),
        'wingR': (0, 0, -110),
        'hips': (-12, 0, 0),
      },
    ),
    (
      0.3,
      {
        ..._perch,
        'wingL': (0, 0, 20),
        'wingR': (0, 0, -20),
        'hips': (-10, 0, 0),
      },
    ),
  ]),
  Move('hop', 'Hop', 0.5, rig: 'bird', <_K>[
    (
      0,
      {
        ..._perch,
        'lift': (-0.01, 0, 0),
        'legL': (-20, 0, 0),
        'legR': (-20, 0, 0),
        'footL': (20, 0, 0),
        'footR': (20, 0, 0),
      },
    ),
    (
      0.2,
      {
        ..._perch,
        'lift': (0.1, 0, 0),
        'wingL': (0, 0, 40),
        'wingR': (0, 0, -40),
        'legL': (20, 0, 0),
        'legR': (20, 0, 0),
      },
    ),
    (
      0.5,
      {
        ..._perch,
        'lift': (-0.01, 0, 0),
        'legL': (-20, 0, 0),
        'legR': (-20, 0, 0),
        'footL': (20, 0, 0),
        'footR': (20, 0, 0),
      },
    ),
  ]),
  Move('look', 'Look around', 1.6, rig: 'bird', <_K>[
    (0, {..._perch, 'head': (0, 0, 0)}),
    (0.3, {..._perch, 'head': (0, 70, 0)}),
    (0.75, {..._perch, 'head': (0, 70, 0)}),
    (0.9, {..._perch, 'head': (0, -70, 10)}),
    (1.35, {..._perch, 'head': (0, -70, 10)}),
    (1.6, {..._perch, 'head': (0, 0, 0)}),
  ]),
  Move('sit', 'Sit down', 0.8, loop: false, rig: 'bird', <_K>[
    (0, {..._perch}),
    (
      0.8,
      {
        ..._perch,
        'lift': (-0.11, 0, 0),
        'legL': (-80, 0, 0),
        'legR': (-80, 0, 0),
        'footL': (80, 0, 0),
        'footR': (80, 0, 0),
        'neck': (-10, 0, 0),
      },
    ),
  ]),
  Move('fly', 'Fly', 0.36, rig: 'bird', <_K>[
    (
      0,
      {
        ..._perch,
        'rise': (1.2, 0, 0),
        'hips': (15, 0, 0),
        'wingL': (0, 0, 20),
        'wingR': (0, 0, -20),
        'legL': (60, 0, 0),
        'legR': (60, 0, 0),
        'neck': (-15, 0, 0),
      },
    ),
    (
      0.18,
      {
        ..._perch,
        'rise': (1.24, 0, 0),
        'hips': (15, 0, 0),
        'wingL': (0, 0, 130),
        'wingR': (0, 0, -130),
        'legL': (60, 0, 0),
        'legR': (60, 0, 0),
        'neck': (-15, 0, 0),
      },
    ),
    (
      0.36,
      {
        ..._perch,
        'rise': (1.2, 0, 0),
        'hips': (15, 0, 0),
        'wingL': (0, 0, 20),
        'wingR': (0, 0, -20),
        'legL': (60, 0, 0),
        'legR': (60, 0, 0),
        'neck': (-15, 0, 0),
      },
    ),
  ]),
  Move('call', 'Call', 1.0, rig: 'bird', <_K>[
    (0, {..._perch, 'neck': (0, 0, 0), 'head': (0, 0, 0)}),
    (
      0.2,
      {
        ..._perch,
        'neck': (-25, 0, 0),
        'head': (-35, 0, 0),
        'wingL': (0, 0, 15),
        'wingR': (0, 0, -15),
        'hips': (-10, 0, 0),
      },
    ),
    (
      0.6,
      {
        ..._perch,
        'neck': (-25, 0, 0),
        'head': (-35, 0, 0),
        'wingL': (0, 0, 15),
        'wingR': (0, 0, -15),
        'hips': (-10, 0, 0),
      },
    ),
    (1.0, {..._perch, 'neck': (0, 0, 0), 'head': (0, 0, 0)}),
  ]),
];
