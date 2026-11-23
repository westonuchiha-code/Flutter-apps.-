// Procedural creature generation.
//
// A barcode always produces the same SPECIES (its genome): body plan,
// element, colours, features, base stats and name. Each scan also rolls an
// INDIVIDUAL seed that nudges shade, size and personality, so two creatures
// of the same species still feel different.
//
// Everything here is pure Dart and deterministic, so it can be unit tested
// and will produce the same creature on every phone.
import 'dart:math' as math;

/// Deterministic random numbers (SplitMix64-style, kept within 53 bits so it
/// behaves the same everywhere).
class SeededRandom {
  SeededRandom(int seed) : _state = seed & _mask;

  static const _mask = 0x1FFFFFFFFFFFFF; // 53 bits
  int _state;

  /// Next value in 0..2^32-1.
  int nextUint32() {
    // Mix a 53-bit state with multiply/xor-shift steps.
    _state = (_state + 0x9E3779B97F4A7) & _mask;
    var z = _state;
    z = ((z ^ (z >> 23)) * 0x2127599BF4325) & _mask;
    z = ((z ^ (z >> 19)) * 0x14C3B2F3B1C9D) & _mask;
    z = z ^ (z >> 27);
    return z & 0xFFFFFFFF;
  }

  /// 0 <= x < 1
  double nextDouble() => nextUint32() / 4294967296.0;

  /// 0 <= x < max
  int nextInt(int max) => (nextDouble() * max).floor();

  double range(double min, double max) => min + nextDouble() * (max - min);

  bool chance(double p) => nextDouble() < p;

  T pick<T>(List<T> items) => items[nextInt(items.length)];

  /// Picks using relative [weights].
  T weighted<T>(List<T> items, List<double> weights) {
    final total = weights.fold(0.0, (a, b) => a + b);
    var r = nextDouble() * total;
    for (var i = 0; i < items.length; i++) {
      r -= weights[i];
      if (r < 0) return items[i];
    }
    return items.last;
  }
}

/// FNV-1a hash of [text], folded to 53 bits.
int hashString(String text) {
  // 32-bit FNV-1a twice with different offsets, combined.
  var a = 0x811C9DC5;
  var b = 0x01000193 ^ 0x5BD1E995;
  for (final unit in text.codeUnits) {
    a = ((a ^ unit) * 0x01000193) & 0xFFFFFFFF;
    b = ((b ^ unit) * 0x01000193 + 0x7F4A7C15) & 0xFFFFFFFF;
  }
  return ((a << 21) ^ b) & SeededRandom._mask;
}

/// Normalizes a scanned code so the same product always maps to the same
/// creature (trims spaces; EAN-13 with a leading 0 equals the UPC-A code).
String normalizeBarcode(String raw) {
  var code = raw.trim().replaceAll(RegExp(r'\s+'), '');
  if (RegExp(r'^0\d{12}$').hasMatch(code)) code = code.substring(1);
  return code.toUpperCase();
}

// ---------------------------------------------------------------------------
// Building blocks
// ---------------------------------------------------------------------------

/// Number of monster sprites and colour palettes (see render/monster_art.dart).
const silhouetteCount = 2; // only the owner-approved designs (drake, hound)
const paletteCount = 12;

/// Three tribes. Future battles: Ember beats Grove, Grove beats Tide,
/// Tide beats Ember.
enum Tribe {
  ember('Ember', 0xFFE0533A),
  grove('Grove', 0xFF4FAE4A),
  tide('Tide', 0xFF3C8FD6);

  const Tribe(this.label, this.color);
  final String label;
  final int color;

  Tribe get beats => switch (this) {
    Tribe.ember => Tribe.grove,
    Tribe.grove => Tribe.tide,
    Tribe.tide => Tribe.ember,
  };
}

/// Elements, four per tribe. [hue] is the base colour (degrees).
enum Element {
  flame('Flame', Tribe.ember, 12, ['pyr', 'cin', 'emb', 'blaz', 'sco', 'ash']),
  spark('Spark', Tribe.ember, 52, ['zap', 'volt', 'jol', 'fiz', 'bzz', 'arc']),
  stone('Stone', Tribe.ember, 30, [
    'rok',
    'pebb',
    'grav',
    'bould',
    'cra',
    'lith',
  ]),
  metal('Metal', Tribe.ember, 210, [
    'ferr',
    'clank',
    'bolt',
    'chro',
    'rivet',
    'tin',
  ]),
  leaf('Leaf', Tribe.grove, 105, [
    'fern',
    'leaf',
    'sprou',
    'bud',
    'clov',
    'thist',
  ]),
  spore('Spore', Tribe.grove, 285, [
    'mush',
    'spor',
    'fung',
    'puff',
    'myc',
    'shroo',
  ]),
  venom('Venom', Tribe.grove, 300, [
    'tox',
    'veno',
    'sting',
    'fang',
    'ooz',
    'blight',
  ]),
  beast('Beast', Tribe.grove, 28, [
    'fur',
    'grow',
    'paw',
    'snarl',
    'tusk',
    'mane',
  ]),
  tide('Tide', Tribe.tide, 200, ['aqu', 'brin', 'wav', 'splas', 'cora', 'riv']),
  frost('Frost', Tribe.tide, 190, [
    'fros',
    'glac',
    'chil',
    'icy',
    'snow',
    'rim',
  ]),
  wind('Wind', Tribe.tide, 165, [
    'gus',
    'zeph',
    'breez',
    'wisp',
    'sky',
    'flutt',
  ]),
  shade('Shade', Tribe.tide, 265, [
    'umb',
    'nox',
    'gloom',
    'shad',
    'dusk',
    'murk',
  ]);

  const Element(this.label, this.tribe, this.hue, this.syllables);
  final String label;
  final Tribe tribe;
  final double hue;
  final List<String> syllables;
}

enum BodyPlan {
  blob('Blob', 2),
  biped('Biped', 2),
  quadruped('Quadruped', 4),
  serpent('Serpent', 0),
  avian('Avian', 2),
  insect('Insect', 6),
  floater('Floater', 0);

  const BodyPlan(this.label, this.legs);
  final String label;
  final int legs;
}

enum Rarity {
  common('Common', 1),
  uncommon('Uncommon', 2),
  rare('Rare', 3),
  legendary('Legendary', 4);

  const Rarity(this.label, this.stars);
  final String label;
  final int stars;
}

enum Pattern { none, spots, stripes, belly, mask, tips }

enum EyeStyle { round, sleepy, fierce, sparkle }

enum Mouth { smile, fangs, beak, tusks, tiny }

enum Ears { none, pointy, round, floppy, fins }

enum Horns { none, single, pair, curled, antennae, sprout }

enum Tail { none, thin, fluffy, flame, leaf, spiked, fin }

enum Wings { none, bat, feather, bug }

/// HSL colour (hue 0–360, saturation and lightness 0–1).
class Hsl {
  const Hsl(this.h, this.s, this.l);
  final double h, s, l;

  Hsl shift({double dh = 0, double ds = 0, double dl = 0}) =>
      Hsl((h + dh) % 360, (s + ds).clamp(0.0, 1.0), (l + dl).clamp(0.0, 1.0));

  /// ARGB integer.
  int get argb {
    final c = (1 - (2 * l - 1).abs()) * s;
    final hp = (h % 360) / 60;
    final x = c * (1 - (hp % 2 - 1).abs());
    final (r1, g1, b1) = switch (hp.floor()) {
      0 => (c, x, 0.0),
      1 => (x, c, 0.0),
      2 => (0.0, c, x),
      3 => (0.0, x, c),
      4 => (x, 0.0, c),
      _ => (c, 0.0, x),
    };
    final m = l - c / 2;
    int ch(double v) => ((v + m) * 255).round().clamp(0, 255);
    return 0xFF000000 | ch(r1) << 16 | ch(g1) << 8 | ch(b1);
  }

  List<double> toJson() => [h, s, l];
  factory Hsl.fromJson(List<dynamic> j) => Hsl(
    (j[0] as num).toDouble(),
    (j[1] as num).toDouble(),
    (j[2] as num).toDouble(),
  );
}

/// Base stats for future battles and adventures.
class Stats {
  const Stats(this.hp, this.attack, this.defense, this.speed);
  final int hp, attack, defense, speed;
  int get total => hp + attack + defense + speed;
}

// ---------------------------------------------------------------------------
// The species genome
// ---------------------------------------------------------------------------

/// Everything that defines a species. Derived from a barcode by [Genome.fromBarcode].
class Genome {
  Genome._({
    required this.code,
    required this.speciesName,
    required this.element,
    required this.plan,
    required this.rarity,
    required this.body,
    required this.belly,
    required this.accent,
    required this.eyeColor,
    required this.bodyWidth,
    required this.bodyHeight,
    required this.roundness,
    required this.headSize,
    required this.legLength,
    required this.pattern,
    required this.patternCount,
    required this.eyes,
    required this.eyeSize,
    required this.eyeStyle,
    required this.mouth,
    required this.ears,
    required this.horns,
    required this.tail,
    required this.wings,
    required this.size,
    required this.baseStats,
    required this.energy,
    required this.sociability,
    required this.appetite,
    required this.curiosity,
    required this.silhouette,
    required this.palette,
  });

  /// The normalized barcode this species comes from.
  final String code;
  final String speciesName;
  final Element element;
  final BodyPlan plan;
  final Rarity rarity;

  // Colours.
  final Hsl body, belly, accent, eyeColor;

  // Shape (relative units; ~1 is "normal").
  final double bodyWidth, bodyHeight, roundness, headSize, legLength;
  final Pattern pattern;
  final int patternCount;
  final int eyes;
  final double eyeSize;
  final EyeStyle eyeStyle;
  final Mouth mouth;
  final Ears ears;
  final Horns horns;
  final Tail tail;
  final Wings wings;

  /// Overall scale (0.75–1.35).
  final double size;

  final Stats baseStats;

  /// Species personality tendencies (0–1).
  final double energy, sociability, appetite, curiosity;

  /// Which monster sprite (index into the art manifest).
  final int silhouette;

  /// Which colour palette (index into the palette list).
  final int palette;

  Tribe get tribe => element.tribe;

  factory Genome.fromBarcode(String barcode) {
    final code = normalizeBarcode(barcode);
    final r = SeededRandom(hashString('species:$code'));

    final art = SeededRandom(hashString('art:$code'));
    final silhouette = art.nextInt(silhouetteCount);
    final palette = art.nextInt(paletteCount);
    final rarity = r.weighted(Rarity.values, const [70, 20, 8, 2]);
    final element = r.pick(Element.values);
    final plan = r.weighted(BodyPlan.values, const [
      16,
      18,
      20,
      10,
      12,
      10,
      10,
    ]);

    // Colours: element hue with a personal twist.
    final hue = (element.hue + r.range(-28, 28)) % 360;
    final sat = r.range(0.45, 0.85);
    final light = r.range(0.42, 0.62);
    final body = Hsl(hue, sat, light);
    final bellyStyle = r.nextInt(3);
    final belly = switch (bellyStyle) {
      0 => body.shift(dl: 0.22, ds: -0.15),
      1 => Hsl((hue + 30) % 360, sat * 0.6, 0.8),
      _ => const Hsl(40, 0.35, 0.88),
    };
    final accentHue = r.chance(0.5)
        ? (hue + 180) % 360
        : (hue + r.range(40, 90)) % 360;
    var accent = Hsl(accentHue, r.range(0.55, 0.95), r.range(0.45, 0.6));
    if (rarity == Rarity.legendary) accent = const Hsl(48, 0.95, 0.58); // gold
    final eyeColor = r.chance(0.7)
        ? const Hsl(0, 0, 0.12)
        : Hsl(r.range(0, 360), 0.8, 0.45);

    // Plan-specific shape tendencies.
    final (bw, bh) = switch (plan) {
      BodyPlan.blob => (r.range(0.9, 1.25), r.range(0.75, 1.05)),
      BodyPlan.biped => (r.range(0.7, 0.95), r.range(0.9, 1.2)),
      BodyPlan.quadruped => (r.range(1.05, 1.35), r.range(0.65, 0.85)),
      BodyPlan.serpent => (r.range(1.2, 1.5), r.range(0.4, 0.55)),
      BodyPlan.avian => (r.range(0.8, 1.0), r.range(0.8, 1.0)),
      BodyPlan.insect => (r.range(1.0, 1.3), r.range(0.55, 0.75)),
      BodyPlan.floater => (r.range(0.85, 1.1), r.range(0.85, 1.15)),
    };

    final eyes = r.weighted([1, 2, 3], const [12, 80, 8]);
    final ears = plan == BodyPlan.serpent || plan == BodyPlan.insect
        ? r.weighted(Ears.values, const [5, 1, 1, 0, 2])
        : r.weighted(Ears.values, const [3, 4, 3, 2, 1]);
    final horns = plan == BodyPlan.insect
        ? Horns.antennae
        : element == Element.leaf || element == Element.spore
        ? r.weighted(Horns.values, const [3, 1, 1, 1, 1, 4])
        : r.weighted(Horns.values, const [6, 2, 2, 2, 1, 0]);
    final tail = switch (element) {
      Element.flame => r.chance(0.6) ? Tail.flame : r.pick(Tail.values),
      Element.leaf => r.chance(0.5) ? Tail.leaf : r.pick(Tail.values),
      Element.tide => r.chance(0.5) ? Tail.fin : r.pick(Tail.values),
      _ => r.weighted(Tail.values, const [3, 3, 3, 0.5, 0.5, 2, 1]),
    };
    final wings = switch (plan) {
      BodyPlan.avian => Wings.feather,
      BodyPlan.insect => r.chance(0.6) ? Wings.bug : Wings.none,
      BodyPlan.floater => r.chance(0.3) ? Wings.bat : Wings.none,
      _ =>
        element == Element.wind || element == Element.shade
            ? r.weighted(Wings.values, const [4, 2, 2, 1])
            : r.weighted(Wings.values, const [12, 1, 1, 1]),
    };
    final mouth = plan == BodyPlan.avian
        ? Mouth.beak
        : r.weighted(
            [Mouth.smile, Mouth.fangs, Mouth.tusks, Mouth.tiny],
            const [5, 3, 1, 3],
          );

    final rarityBoost = (rarity.stars - 1) * 6;
    int stat(double planBias) =>
        (20 + r.nextInt(31) + planBias + rarityBoost).round().clamp(10, 99);
    final baseStats = Stats(
      stat(plan == BodyPlan.blob || plan == BodyPlan.quadruped ? 8 : 0),
      stat(element.tribe == Tribe.ember ? 6 : 0),
      stat(element == Element.stone || element == Element.metal ? 10 : 0),
      stat(plan == BodyPlan.avian || plan == BodyPlan.insect ? 8 : 0),
    );

    return Genome._(
      code: code,
      speciesName: _speciesName(r, element, silhouette),
      element: element,
      plan: plan,
      rarity: rarity,
      body: body,
      belly: belly,
      accent: accent,
      eyeColor: eyeColor,
      bodyWidth: bw,
      bodyHeight: bh,
      roundness: plan == BodyPlan.blob ? r.range(0.8, 1) : r.range(0.45, 1),
      headSize: r.range(0.75, 1.15),
      legLength: r.range(0.6, 1.25),
      pattern: r.weighted(Pattern.values, const [4, 3, 2, 3, 1, 2]),
      patternCount: 2 + r.nextInt(4),
      eyes: eyes,
      eyeSize: r.range(0.75, 1.3),
      eyeStyle: r.weighted(EyeStyle.values, const [6, 2, 2, 2]),
      mouth: mouth,
      ears: ears,
      horns: horns,
      tail: tail,
      wings: wings,
      size: r.range(0.8, 1.25) + (rarity == Rarity.legendary ? 0.1 : 0),
      baseStats: baseStats,
      energy: r.nextDouble(),
      sociability: r.nextDouble(),
      appetite: r.nextDouble(),
      curiosity: r.nextDouble(),
      silhouette: silhouette,
      palette: palette,
    );
  }

  static const _vowels = ['a', 'e', 'i', 'o', 'u', 'y', 'oo', 'ee', 'ai'];

  /// Name endings per silhouette (drake, hound, beetle, gargoyle, wyrm,
  /// brute, mantis, wraith, harpy, scorpion).
  static const _endings = [
    ['rax', 'drak', 'saur', 'fang'],
    ['hound', 'lupe', 'jaw', 'mutt'],
    ['carab', 'horn', 'shell', 'tusk'],
    ['goyle', 'gaunt', 'vex', 'wing'],
    ['wyrm', 'coil', 'zith', 'asp'],
    ['brute', 'gor', 'golth', 'mash'],
    ['mantis', 'scyth', 'reap', 'kriit'],
    ['wraith', 'shade', 'spect', 'hollow'],
    ['harp', 'talon', 'raptor', 'screech'],
    ['scorp', 'sting', 'pincer', 'claw'],
  ];
  static String _speciesName(SeededRandom r, Element e, int silhouette) {
    final start = r.pick(e.syllables);
    final middle = r.chance(0.45) ? r.pick(_vowels) : '';
    final end = r.pick(_endings[silhouette % _endings.length]);
    var name = '$start$middle$end';
    // Avoid triple letters from joins.
    name = name.replaceAllMapped(RegExp(r'(.)\1\1+'), (m) => '${m[1]}${m[1]}');
    return name[0].toUpperCase() + name.substring(1);
  }
}

// ---------------------------------------------------------------------------
// Individuals
// ---------------------------------------------------------------------------

/// What makes one creature differ from others of its species.
class Individuality {
  const Individuality({
    required this.seed,
    required this.hueShift,
    required this.sizeFactor,
    required this.energy,
    required this.sociability,
    required this.appetite,
    required this.curiosity,
    required this.shiny,
  });

  factory Individuality.roll(Genome g, int seed) {
    final r = SeededRandom(hashString('individual:$seed'));
    double jitter(double base) => (base + r.range(-0.2, 0.2)).clamp(0.0, 1.0);
    return Individuality(
      seed: seed,
      hueShift: r.range(-10, 10),
      sizeFactor: r.range(0.9, 1.1),
      energy: jitter(g.energy),
      sociability: jitter(g.sociability),
      appetite: jitter(g.appetite),
      curiosity: jitter(g.curiosity),
      shiny: r.nextInt(128) == 0,
    );
  }

  final int seed;
  final double hueShift;
  final double sizeFactor;
  final double energy, sociability, appetite, curiosity;

  /// Rare alternate colouring (1 in 128).
  final bool shiny;

  /// A one-word summary of the personality.
  String get nature {
    final traits = {
      'Energetic': energy,
      'Friendly': sociability,
      'Hungry': appetite,
      'Curious': curiosity,
    };
    final top = traits.entries.reduce((a, b) => a.value >= b.value ? a : b);
    if (top.value < 0.45) {
      return energy < 0.3 ? 'Lazy' : 'Calm';
    }
    if (top.key == 'Friendly' && energy < 0.35) return 'Gentle';
    if (top.key == 'Energetic' && sociability < 0.3) return 'Wild';
    if (top.key == 'Curious' && sociability < 0.3) return 'Shy';
    return top.key == 'Hungry' ? 'Greedy' : top.key;
  }
}

/// Genome + individuality, with final colours resolved.
class Appearance {
  Appearance(this.genome, this.individual);
  final Genome genome;
  final Individuality individual;

  Hsl _tint(Hsl c) {
    var t = c.shift(dh: individual.hueShift);
    if (individual.shiny) {
      t = Hsl((t.h + 150) % 360, math.min(1, t.s + 0.1), t.l);
    }
    return t;
  }

  Hsl get body => _tint(genome.body);
  Hsl get belly => _tint(genome.belly);
  Hsl get accent =>
      genome.rarity == Rarity.legendary ? genome.accent : _tint(genome.accent);
  double get size => genome.size * individual.sizeFactor;
}
