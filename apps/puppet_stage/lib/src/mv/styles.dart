/// Music video styles: who is in it, where, how they move, how the camera
/// shoots and how often it cuts. Each is drawn from the general feel of a
/// band's videos (none copies a real one).
library;

import 'package:landscape/landscape.dart';

import '../animals.dart';
import '../cast.dart';
import '../movie.dart';
import '../props.dart';
import '../sets.dart';

/// Someone (or something) in the video.
class Member {
  const Member(
    this.role,
    this.kind,
    this.look, {
    this.name = '',
    this.place = 0,
    this.extras = const {},
    this.holds,
    this.body = const Body(),
    this.animal,
  });

  /// lead (sings/raps the vocal bars), crew, dj, feature (does the style's
  /// feature moves: a swordsman, a dancer) or pet.
  final String role;
  final Kind kind;
  final Look look;
  final String name;
  final int place;
  final Set<Extra> extras;
  final Prop? holds;
  final Body body;
  final Animal? animal;
}

/// A prop placed by the style.
typedef Dressing = ({
  Prop prop,
  int place,
  double x,
  double z,
  double facing,
  double scale,
});

class MvStyle {
  const MvStyle({
    required this.id,
    required this.name,
    required this.inspiredBy,
    required this.about,
    required this.places,
    required this.formation,
    required this.cast,
    required this.moves,
    required this.looks,
    required this.cutBars,
    required this.shots,
    this.props = const [],
    this.drift = 0.6,
    this.drifts = const {'push': 2, 'orbit': 1, 'crane': 1},
    this.symmetric = false,
    this.dances = const [],
    this.roam = 0.3,
    this.spins = 0,
  });

  final String id, name, inspiredBy, about;
  final List<Place> places;

  /// How people stand: line, circle, row or scatter.
  final String formation;
  final List<Member> cast;
  final List<Dressing> props;

  /// role → section → moves to pick from (by bar).
  final Map<String, Map<String, List<String>>> moves;

  /// section → film looks (preset names) to pick from.
  final Map<String, List<String>> looks;

  /// section → bars per shot (0.5: two shots a bar).
  final Map<String, double> cutBars;

  /// section → shot kind → weight. Kinds: wide, medium, close, low (fisheye
  /// from below), overhead, profile, insert (a prop), land (the landscape).
  final Map<String, Map<String, int>> shots;

  /// Share of shots that move, and how (push, orbit, crane, spin).
  final double drift;
  final Map<String, int> drifts;

  /// Dead-centre framing (no angled shots).
  final bool symmetric;

  /// Dances anyone (not the DJ) may mix into their moves.
  final List<String> dances;

  /// Chance someone walks somewhere new when a section starts.
  final double roam;

  /// Chance per bar of a spin (scaled by the bar's energy).
  final double spins;
}

Look _lk(
  int top,
  int bottom,
  int accent, {
  int skin = 0xFF8A5A3C,
  int hair = 0xFF1A1410,
  int shoes = 0xFF1A1A1A,
}) => Look(
  skin: skin,
  hair: hair,
  top: top,
  bottom: bottom,
  shoes: shoes,
  accent: accent,
);

Look _robot(int glow, int body) => Look(
  skin: 0xFF8A9098,
  hair: glow,
  top: body,
  bottom: 0xFF4A4E56,
  shoes: 0xFF2A2C30,
  accent: glow,
);

const _all = 'all';

final styles = <MvStyle>[
  // ---- Dead Prez: street, red/black/green, fists up. ----
  MvStyle(
    id: 'liberation',
    dances: ['fistPump', 'stomp', 'lean'],
    roam: 0.35,
    name: 'Liberation',
    inspiredBy: 'Dead Prez',
    about: 'Night street, hard contrast, red, black and green; raised fists, slow pushes in.',
    places: [
      const Place(
        set: StageSet.street,
        name: 'Night street',
        mood: Mood(
          sky: 0xFF06070A,
          horizon: 0xFF1A1014,
          ambient: 0xFF26222A,
          sun: 0xFF3A2020,
          fog: 0xFF0A0808,
          fogNear: 10,
          fogFar: 34,
          lamps: [
            (x: -2.5, y: 3.2, z: 1.5, color: 0xFFFF3020, range: 7, power: 1.6),
            (x: 2.5, y: 3.2, z: 1.5, color: 0xFF30C040, range: 7, power: 1.3),
            (x: 0, y: 3.8, z: 3.5, color: 0xFFFFE0C0, range: 8, power: 1.2),
          ],
        ),
      ),
      const Place(set: StageSet.rooftop, name: 'Rooftop'),
      Place(
        land: presets['canyon']!.$2.copyWith(seed: 7, time: 17.4, haze: 0.5),
        name: 'Canyon at dusk',
        mood: const Mood(ambient: 0xFF5A4A48),
      ),
    ],
    formation: 'line',
    cast: [
      Member(
        'lead',
        Kind.man,
        _lk(0xFF1A1A1A, 0xFF1E3A1E, 0xFFB02020),
        name: 'Voice One',
        holds: Prop.mic,
        extras: {Extra.cap},
      ),
      Member(
        'lead',
        Kind.bigMan,
        _lk(0xFFB02020, 0xFF161616, 0xFF1E3A1E, skin: 0xFF6A4430),
        name: 'Voice Two',
        holds: Prop.mic,
        extras: {Extra.beard},
      ),
      Member(
        'crew',
        Kind.man,
        _lk(0xFF161616, 0xFF161616, 0xFF2A6A2A, skin: 0xFF5A3A28),
        extras: {Extra.jacket},
      ),
      Member(
        'crew',
        Kind.woman,
        _lk(0xFF1E3A1E, 0xFF161616, 0xFFB02020, skin: 0xFF7A5038),
      ),
      Member(
        'crew',
        Kind.teen,
        _lk(0xFF161616, 0xFF3A2A1A, 0xFFB02020),
        extras: {Extra.cap},
      ),
      Member(
        'crew',
        Kind.man,
        _lk(0xFF2A2A2A, 0xFF161616, 0xFF1E3A1E, skin: 0xFF4A3020),
        extras: {Extra.jacket, Extra.glasses},
      ),
      Member(
        'feature',
        Kind.man,
        _lk(0xFF161616, 0xFF161616, 0xFFB02020),
        place: 2,
        name: 'Lone figure',
      ),
      Member(
        'lead',
        Kind.man,
        _lk(0xFF1A1A1A, 0xFF1E3A1E, 0xFFB02020),
        place: 1,
        name: 'Voice One (roof)',
        holds: Prop.mic,
        extras: {Extra.cap},
      ),
    ],
    moves: {
      'lead': {
        'verse': ['rap', 'rap2', 'point', 'rapMic'],
        'hook': ['punch', 'cheer'],
        'break': ['stance'],
        _all: ['stance', 'nod'],
      },
      'crew': {
        'hook': ['cheer', 'punch'],
        _all: ['stance', 'nod', 'bounce'],
      },
      'feature': {
        _all: ['stance', 'think', 'cheer'],
      },
    },
    looks: {
      'verse': ['Red & Black', 'Noir'],
      'hook': ['Red & Black', 'Black & White'],
      'break': ['Black & White', 'Noir'],
      _all: ['Red & Black'],
    },
    cutBars: {'intro': 2, 'verse': 2, 'hook': 1, 'break': 1, 'outro': 4},
    shots: {
      'verse': {'medium': 3, 'close': 2, 'low': 1, 'profile': 1, 'wide': 1},
      'hook': {'wide': 2, 'low': 2, 'close': 1, 'overhead': 1},
      'break': {'land': 2, 'wide': 1, 'profile': 1},
      _all: {'wide': 2, 'land': 1, 'medium': 1},
    },
    drift: 0.7,
    drifts: {'push': 3, 'crane': 1},
  ),

  // ---- Hieroglyphics: a crew cipher, fisheye, VHS. ----
  MvStyle(
    id: 'cipher',
    dances: ['twoStep', 'shimmy', 'armWave', 'clapHigh', 'lean'],
    roam: 0.5,
    spins: 0.06,
    name: 'Cipher',
    inspiredBy: 'Hieroglyphics',
    about: 'The crew in a circle in the park, fisheye from below, VHS colour, quick cuts.',
    places: [
      const Place(set: StageSet.park, name: 'Park'),
      const Place(set: StageSet.street, name: 'Street'),
    ],
    formation: 'circle',
    cast: [
      Member(
        'lead',
        Kind.teen,
        _lk(0xFF2A6ACA, 0xFF3A3A4A, 0xFFE0B020),
        name: 'MC One',
        extras: {Extra.cap},
      ),
      Member(
        'lead',
        Kind.man,
        _lk(0xFFE05A2A, 0xFF2A2A3A, 0xFF2A2A2A, skin: 0xFF6A4430),
        name: 'MC Two',
        extras: {Extra.jacket},
      ),
      Member(
        'lead',
        Kind.man,
        _lk(0xFF3A8A4A, 0xFF4A4A5A, 0xFFE0E0E0, skin: 0xFFC09070),
        name: 'MC Three',
        extras: {Extra.glasses},
      ),
      Member(
        'lead',
        Kind.woman,
        _lk(0xFFAA3A8A, 0xFF2A2A3A, 0xFF3A3A3A, skin: 0xFF8A5A3C),
        name: 'MC Four',
        extras: {Extra.cap},
      ),
      Member('crew', Kind.boy, _lk(0xFFE0D040, 0xFF3A4A6A, 0xFFAA2A2A)),
      Member(
        'crew',
        Kind.teen,
        _lk(0xFF6A6A7A, 0xFF2A2A3A, 0xFF2A6ACA, skin: 0xFF5A3A28),
        extras: {Extra.backpack},
      ),
      Member(
        'dj',
        Kind.man,
        _lk(0xFF2A2A2A, 0xFF3A3A4A, 0xFFE05A2A),
        name: 'DJ',
        extras: {Extra.cap, Extra.glasses},
      ),
      Member(
        'crew',
        Kind.man,
        _lk(0xFFE0E0E0, 0xFF2A3A6A, 0xFFAA2A2A, skin: 0xFF7A5038),
        place: 1,
        extras: {Extra.cap},
      ),
      Member(
        'lead',
        Kind.teen,
        _lk(0xFF2A6ACA, 0xFF3A3A4A, 0xFFE0B020),
        place: 1,
        name: 'MC One (street)',
        extras: {Extra.cap},
      ),
    ],
    props: [
      (prop: Prop.turntables, place: 0, x: 0, z: -3.2, facing: 0, scale: 1),
      (prop: Prop.boombox, place: 0, x: 2.4, z: 1.6, facing: -40, scale: 1),
      (prop: Prop.tree, place: 0, x: -4, z: -3, facing: 0, scale: 1.3),
    ],
    moves: {
      'lead': {
        'verse': ['rap', 'rap2', 'bounce'],
        'hook': ['rap2', 'bounce', 'dance'],
        _all: ['bounce', 'nod'],
      },
      'crew': {
        'hook': ['dance', 'bounce', 'clap'],
        _all: ['bounce', 'nod', 'stance'],
      },
      'dj': {
        _all: ['scratch', 'bounce'],
      },
    },
    looks: {
      _all: ['90s Video'],
    },
    cutBars: {'intro': 2, 'verse': 1, 'hook': 0.5, 'break': 1, 'outro': 2},
    shots: {
      'verse': {'low': 3, 'medium': 2, 'close': 2, 'wide': 1},
      'hook': {'low': 3, 'wide': 2, 'overhead': 1, 'close': 1},
      _all: {'wide': 2, 'low': 1, 'insert': 1},
    },
    drift: 0.6,
    drifts: {'orbit': 3, 'push': 1},
  ),

  // ---- People Under the Stairs: a backyard party, warm 70s film. ----
  MvStyle(
    id: 'backyard',
    dances: ['twoStep', 'sway', 'shimmy', 'lean', 'clapHigh'],
    roam: 0.6,
    spins: 0.03,
    name: 'Backyard',
    inspiredBy: 'People Under the Stairs',
    about: 'A sunny backyard party: records, turntables, a dog; warm 70s film, easy drifting shots.',
    places: [
      const Place(
        set: StageSet.park,
        name: 'Backyard',
        mood: Mood(
          sky: 0xFF8AB0D8,
          horizon: 0xFFF0C890,
          ambient: 0xFF8A7A68,
          sun: 0xFFFFD090,
          sunDir: [-0.7, -0.45, -0.3],
        ),
      ),
    ],
    formation: 'scatter',
    cast: [
      Member(
        'lead',
        Kind.man,
        _lk(0xFFE0A040, 0xFF3A4A6A, 0xFF8A3A2A, skin: 0xFF8A5A3C),
        name: 'MC One',
        extras: {Extra.cap},
      ),
      Member(
        'lead',
        Kind.man,
        _lk(0xFF4A8A9A, 0xFF5A4A3A, 0xFF2A2A2A, skin: 0xFF6A4430),
        name: 'MC Two',
        extras: {Extra.glasses, Extra.beard},
      ),
      Member(
        'dj',
        Kind.bigMan,
        _lk(0xFFCA5A3A, 0xFF3A3A4A, 0xFF2A2A2A, skin: 0xFF5A3A28),
        name: 'DJ',
        extras: {Extra.cap},
      ),
      Member(
        'crew',
        Kind.woman,
        _lk(0xFFE0D070, 0xFF4A6A9A, 0xFFAA4A2A, skin: 0xFF7A5038),
        extras: {Extra.dress},
      ),
      Member(
        'crew',
        Kind.oldMan,
        _lk(0xFFE8E0D0, 0xFF6A5A4A, 0xFF8A3A2A, skin: 0xFF6A4430),
        holds: Prop.cup,
      ),
      Member('crew', Kind.girl, _lk(0xFFE07AA0, 0xFF3A4A6A, 0xFFE0D040)),
      Member(
        'crew',
        Kind.teen,
        _lk(0xFF6AA05A, 0xFF4A4A5A, 0xFF2A2A2A),
        holds: Prop.cup,
      ),
      Member(
        'pet',
        Kind.man,
        _lk(0xFFB08A5A, 0xFF8A6A4A, 0xFF2A2A2A),
        animal: Animal.dog,
        name: 'Dog',
      ),
    ],
    props: [
      (prop: Prop.turntables, place: 0, x: 0, z: -2.2, facing: 0, scale: 1),
      (prop: Prop.speakers, place: 0, x: -1.9, z: -2.6, facing: 20, scale: 1),
      (prop: Prop.speakers, place: 0, x: 1.9, z: -2.6, facing: -20, scale: 1),
      (prop: Prop.box, place: 0, x: 1.2, z: -1.5, facing: 10, scale: 1),
      (prop: Prop.box, place: 0, x: 1.5, z: -1.2, facing: -15, scale: 1),
      (prop: Prop.chair, place: 0, x: -2.6, z: 0.6, facing: 60, scale: 1),
      (prop: Prop.boombox, place: 0, x: 2.8, z: 0.4, facing: -60, scale: 1),
      (prop: Prop.tree, place: 0, x: -4.5, z: -3.5, facing: 0, scale: 1.4),
      (prop: Prop.fence, place: 0, x: 0, z: -4.5, facing: 0, scale: 1),
    ],
    moves: {
      'lead': {
        'verse': ['rap', 'bounce', 'rap2'],
        'hook': ['bounce', 'clap'],
        _all: ['bounce', 'nod'],
      },
      'crew': {
        'hook': ['dance', 'clap', 'bounce'],
        _all: ['nod', 'bounce', 'talk', 'dance'],
      },
      'dj': {
        _all: ['scratch', 'scratch', 'bounce'],
      },
      'pet': {
        _all: ['wag', 'idle', 'sit'],
      },
    },
    looks: {
      _all: ['70s Film'],
    },
    cutBars: {'intro': 2, 'verse': 2, 'hook': 1, 'break': 2, 'outro': 4},
    shots: {
      'verse': {'medium': 3, 'wide': 2, 'insert': 2, 'close': 1, 'profile': 1},
      'hook': {'wide': 2, 'medium': 2, 'insert': 1, 'low': 1},
      _all: {'wide': 2, 'insert': 2, 'medium': 1},
    },
    drift: 0.85,
    drifts: {'orbit': 2, 'push': 2, 'crane': 1},
  ),

  // ---- Tool: dim, uneasy, stop motion. ----
  MvStyle(
    id: 'undertow',
    dances: ['robot', 'sway', 'headbang'],
    roam: 0.3,
    name: 'Undertow',
    inspiredBy: 'Tool',
    about: 'A dim green-brown hall and a dead desert at night; stop-motion jerks, flicker, slow uneasy moves.',
    places: [
      const Place(
        set: StageSet.dojo,
        name: 'The hall',
        mood: Mood(
          sky: 0xFF080A06,
          ambient: 0xFF1E2418,
          sun: 0xFF2A2A1A,
          fog: 0xFF0A0C08,
          fogNear: 4,
          fogFar: 14,
          lamps: [
            (x: 0, y: 3, z: 0.5, color: 0xFFC8D890, range: 6, power: 1.8),
          ],
        ),
      ),
      Place(
        land: presets['desert']!.$2.copyWith(seed: 13, time: 21.5, haze: 0.85),
        name: 'Dead desert',
        mood: const Mood(ambient: 0xFF4A4A38),
      ),
    ],
    formation: 'scatter',
    cast: [
      Member(
        'lead',
        Kind.robot,
        _robot(0xFF90C040, 0xFF5A5A4A),
        name: 'The engine',
      ),
      Member(
        'feature',
        Kind.oldMan,
        _lk(0xFF3A3A2A, 0xFF2A2A1E, 0xFF4A3A2A, skin: 0xFF9A8A70),
        name: 'Long arms',
        body: const Body(
          height: 1.3,
          build: 0.6,
          arms: 1.4,
          legs: 1.3,
          head: 0.7,
        ),
      ),
      Member(
        'feature',
        Kind.toddler,
        _lk(0xFF5A4A3A, 0xFF3A3A2A, 0xFF2A2A1A, skin: 0xFFB0A080),
        name: 'Big head',
        body: const Body(head: 1.8, build: 0.8),
      ),
      Member(
        'crew',
        Kind.man,
        _lk(0xFF2A2A22, 0xFF1E1E18, 0xFF2A2A22, skin: 0xFF8A7A60),
        body: const Body(build: 0.6, height: 1.2),
      ),
      Member(
        'feature',
        Kind.oldWoman,
        _lk(0xFF3A3028, 0xFF2A241E, 0xFF5A4A3A, skin: 0xFFA09070),
        place: 1,
        name: 'Walker',
        body: const Body(arms: 1.3, legs: 1.3, build: 0.7),
      ),
    ],
    props: [
      (prop: Prop.lantern, place: 0, x: -1.8, z: -1.5, facing: 0, scale: 1),
      (prop: Prop.candle, place: 0, x: 1.6, z: 1.4, facing: 0, scale: 1),
      (prop: Prop.chessKing, place: 0, x: 2.2, z: -2.0, facing: 0, scale: 2.2),
      (prop: Prop.rock, place: 1, x: 2.5, z: -2, facing: 30, scale: 2),
    ],
    moves: {
      'lead': {
        'hook': ['rapMic', 'shake'],
        _all: ['think', 'nod', 'stance'],
      },
      'feature': {
        'hook': ['shake', 'crouch', 'jump'],
        _all: ['crouch', 'kneel', 'think', 'lie', 'shrug'],
      },
      'crew': {
        _all: ['kneel', 'think', 'shake'],
      },
    },
    looks: {
      'hook': ['Stop Motion', 'Bile'],
      _all: ['Bile', 'Sepia Film'],
    },
    cutBars: {'intro': 4, 'verse': 2, 'hook': 1, 'break': 2, 'outro': 4},
    shots: {
      'verse': {'close': 3, 'overhead': 2, 'profile': 2, 'low': 1, 'land': 1},
      'hook': {'close': 2, 'low': 2, 'overhead': 1, 'wide': 1},
      _all: {'land': 2, 'overhead': 1, 'close': 1},
    },
    drift: 0.9,
    drifts: {'push': 2, 'crane': 2, 'spin': 1},
  ),

  // ---- Cake: deadpan, flat, still. ----
  MvStyle(
    id: 'deadpan',
    dances: ['sway', 'robot'],
    roam: 0.15,
    name: 'Deadpan',
    inspiredBy: 'Cake',
    about: 'Flat bright colours, people in a row staring at the camera, still dead-centre framing, rare cuts.',
    places: [
      const Place(
        set: StageSet.studio,
        name: 'Bright room',
        mood: Mood(ambient: 0xFFB0B0B0, sun: 0xFFF0F0E8, sky: 0xFFE8D870),
      ),
      const Place(set: StageSet.street, name: 'Street'),
    ],
    formation: 'row',
    symmetric: true,
    cast: [
      Member(
        'lead',
        Kind.man,
        _lk(0xFF3A6AB0, 0xFF2A2A2A, 0xFF2A2A2A, skin: 0xFFC09070),
        name: 'Singer',
        extras: {Extra.glasses},
      ),
      Member(
        'crew',
        Kind.man,
        _lk(0xFF3A6AB0, 0xFF2A2A2A, 0xFF2A2A2A, skin: 0xFFB08060),
        extras: {Extra.beard},
      ),
      Member(
        'crew',
        Kind.woman,
        _lk(0xFF3A6AB0, 0xFF2A2A2A, 0xFF2A2A2A, skin: 0xFF8A5A3C),
      ),
      Member(
        'crew',
        Kind.oldMan,
        _lk(0xFF3A6AB0, 0xFF2A2A2A, 0xFF2A2A2A, skin: 0xFFC8A080),
        holds: Prop.cup,
      ),
      Member(
        'crew',
        Kind.man,
        _lk(0xFFE0E0E0, 0xFF2A2A2A, 0xFF2A2A2A, skin: 0xFF6A4430),
        place: 1,
        extras: {Extra.hat},
      ),
    ],
    moves: {
      'lead': {
        'hook': ['nod', 'shrug'],
        _all: ['idle', 'idle', 'nod'],
      },
      'crew': {
        'hook': ['clap', 'bounce'],
        _all: ['idle', 'idle', 'idle', 'shrug', 'think'],
      },
    },
    looks: {
      _all: ['Flat Bright'],
    },
    cutBars: {'intro': 4, 'verse': 4, 'hook': 2, 'break': 4, 'outro': 8},
    shots: {
      'hook': {'medium': 2, 'close': 2, 'wide': 1},
      _all: {'wide': 3, 'medium': 2, 'close': 1},
    },
    drift: 0.1,
    drifts: {'push': 1},
  ),

  // ---- Parliament: space funk. ----
  MvStyle(
    id: 'mothership',
    dances: ['shimmy', 'armWave', 'clapHigh', 'twoStep', 'robot'],
    roam: 0.6,
    spins: 0.12,
    name: 'Mothership',
    inspiredBy: 'Parliament',
    about: 'Space funk on the moon and a stage in coloured lights; glitter colours that cycle, spinning cameras, everyone dancing.',
    places: [
      const Place(
        set: StageSet.spotlight,
        name: 'Cosmic stage',
        mood: Mood(
          ambient: 0xFF2A1A3A,
          lamps: [
            (x: -2.5, y: 2.5, z: 1.5, color: 0xFFFF40C0, range: 7, power: 1.6),
            (x: 2.5, y: 2.5, z: 1.5, color: 0xFF40E0FF, range: 7, power: 1.6),
            (x: 0, y: 3, z: -2, color: 0xFFFFE040, range: 7, power: 1.4),
          ],
        ),
      ),
      Place(
        land: presets['moon']!.$2.copyWith(seed: 5, time: 23),
        name: 'The moon',
        mood: const Mood(
          ambient: 0xFF6A6090,
          sun: 0xFFC0B0FF,
          lamps: [(x: 0, y: 3, z: 2, color: 0xFFFF60D0, range: 9, power: 1.5)],
        ),
      ),
    ],
    formation: 'line',
    cast: [
      Member(
        'lead',
        Kind.bigMan,
        _lk(0xFFE0B020, 0xFFAA2A8A, 0xFFE0E0F0, skin: 0xFF5A3A28),
        name: 'Star child',
        holds: Prop.mic,
        extras: {Extra.hat, Extra.glasses},
      ),
      Member(
        'lead',
        Kind.robot,
        _robot(0xFFFF40C0, 0xFFC0C8D8),
        name: 'Funkbot',
      ),
      Member(
        'crew',
        Kind.woman,
        _lk(0xFFC0C0D8, 0xFFE040A0, 0xFFE0B020, skin: 0xFF7A5038),
        extras: {Extra.dress},
      ),
      Member(
        'crew',
        Kind.man,
        _lk(0xFF40C0E0, 0xFFE0B020, 0xFFAA2A8A, skin: 0xFF6A4430),
        extras: {Extra.glasses},
      ),
      Member(
        'crew',
        Kind.woman,
        _lk(0xFFE0B020, 0xFF2A2A6A, 0xFFE040A0, skin: 0xFF8A5A3C),
        extras: {Extra.hat},
      ),
      Member('crew', Kind.robot, _robot(0xFF40E0FF, 0xFFE0B020)),
      Member(
        'feature',
        Kind.robot,
        _robot(0xFFFFE040, 0xFFC0C8D8),
        place: 1,
        name: 'Moonwalker',
      ),
      Member(
        'feature',
        Kind.bigMan,
        _lk(0xFFE0B020, 0xFFAA2A8A, 0xFFE0E0F0, skin: 0xFF5A3A28),
        place: 1,
        name: 'Star child (moon)',
        extras: {Extra.hat, Extra.glasses},
      ),
    ],
    moves: {
      'lead': {
        'verse': ['dance', 'rapMic', 'point'],
        'hook': ['cheer', 'dance', 'jump'],
        _all: ['dance', 'bounce'],
      },
      'crew': {
        'hook': ['dance', 'jump', 'cheer'],
        _all: ['dance', 'bounce', 'clap'],
      },
      'feature': {
        _all: ['dance', 'wave', 'jump'],
      },
    },
    looks: {
      _all: ['Cosmic'],
    },
    cutBars: {'intro': 2, 'verse': 1, 'hook': 0.5, 'break': 1, 'outro': 2},
    shots: {
      'verse': {'low': 2, 'wide': 2, 'medium': 2, 'land': 1},
      'hook': {'low': 2, 'overhead': 1, 'wide': 2, 'close': 1},
      _all: {'land': 2, 'wide': 2, 'low': 1},
    },
    drift: 0.8,
    drifts: {'spin': 2, 'orbit': 2, 'crane': 1},
  ),
];

MvStyle styleById(String id) =>
    styles.firstWhere((s) => s.id == id, orElse: () => styles.first);
