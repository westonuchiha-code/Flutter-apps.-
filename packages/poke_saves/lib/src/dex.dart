/// Lookups over the generated tables (species, moves, items, levels...).
library;

import 'data/tables.g.dart';

const int maxSpecies1 = 151;
const int maxSpecies2 = 251;
const int maxSpecies3 = 386;

String speciesName(int species) => species > 0 && species < speciesNames.length
    ? speciesNames[species]
    : '#$species';

String moveName(int move) =>
    move > 0 && move < moveNames.length ? moveNames[move] : '';

/// PKHeX's list starts with "—" for "no ability".
String abilityName(int ability) => ability == 0
    ? '—'
    : ability > 0 && ability < abilityNames.length
    ? abilityNames[ability]
    : '';

const natureNames = [
  'Hardy', 'Lonely', 'Brave', 'Adamant', 'Naughty', 'Bold', 'Docile', //
  'Relaxed', 'Impish', 'Lax', 'Timid', 'Hasty', 'Serious', 'Jolly', 'Naive',
  'Modest', 'Mild', 'Quiet', 'Bashful', 'Rash', 'Calm', 'Gentle', 'Sassy',
  'Careful', 'Quirky',
];

/// Ball names by the Gen 3 ball number (0 = none), as PKHeX names them.
const ballNames = [
  'None', 'Master Ball', 'Ultra Ball', 'Great Ball', 'Poké Ball', //
  'Safari Ball', 'Net Ball', 'Dive Ball', 'Nest Ball', 'Repeat Ball',
  'Timer Ball', 'Luxury Ball', 'Premier Ball', 'Dusk Ball', 'Heal Ball',
  'Quick Ball',
];

/// Today's types (PKHeX's summary uses the newest games' Pokédex).
List<String> speciesTypeNames(int species) {
  if (species <= 0 || species > maxSpecies3) {
    return const [];
  }
  final a = speciesTypes[species * 2], b = speciesTypes[species * 2 + 1];
  return [typeNames[a], if (b != a) typeNames[b]];
}

/// Today's base stats: HP, Atk, Def, SpA, SpD, Spe.
List<int> speciesBaseStats(int species) {
  if (species <= 0 || species > maxSpecies3) {
    return const [];
  }
  return baseStats.sublist(species * 6, species * 6 + 6);
}

/// Gender ratio as the games store it: 0 male only, 254 female only,
/// 255 genderless, otherwise the female threshold.
int genderRatio(int species) {
  if (species <= 0 || species > maxSpecies3) {
    return 255;
  }
  return switch (genderRates[species]) {
    -1 => 255,
    0 => 0,
    8 => 254,
    1 => 31,
    2 => 63,
    4 => 127,
    6 => 191,
    7 => 225,
    final r => r * 32 - 1,
  };
}

/// The level a Pokémon of [species] with [exp] experience points is at.
int levelFor(int species, int exp) {
  final g = species > 0 && species <= maxSpecies3 ? growthRates[species] : 1;
  final base = g * 101;
  if (exp >= expTable[base + 100]) {
    return 100;
  }
  var lv = 1;
  while (exp >= expTable[base + lv + 1]) {
    lv++;
  }
  return lv;
}

final Map<int, int> _gen1National = {
  for (var s = 1; s <= maxSpecies1; s++) gen1InternalIndex[s]: s,
};
final Map<int, int> _gen3National = {
  for (var s = 1; s <= maxSpecies3; s++) gen3InternalIndex[s]: s,
};

/// Gen 1 internal species number <-> national number (0 = none).
int gen1ToNational(int internal) => _gen1National[internal] ?? 0;
int nationalToGen1(int species) =>
    species > 0 && species <= maxSpecies1 ? gen1InternalIndex[species] : 0;

/// Gen 3 internal species number <-> national number (0 = none).
int gen3ToNational(int internal) => _gen3National[internal] ?? 0;
int nationalToGen3(int species) =>
    species > 0 && species <= maxSpecies3 ? gen3InternalIndex[species] : 0;

/// Gen 1 types (the Gen 1 games' type numbers) for the Time Capsule.
(int, int) gen1TypesOf(int species) =>
    (gen1Types[species * 2], gen1Types[species * 2 + 1]);

/// Gen 3 ability for [species] with the PID's ability bit.
int gen3Ability(int species, bool second) {
  if (species <= 0 || species > maxSpecies3) {
    return 0;
  }
  final a1 = gen3AbilityPairs[species * 2],
      a2 = gen3AbilityPairs[species * 2 + 1];
  return second && a1 != a2 ? a2 : a1;
}

String gen2ItemName(int item) =>
    item > 0 && item < itemNamesGen2.length ? itemNamesGen2[item] : '';
String gen3ItemName(int item) =>
    item > 0 && item < itemNamesGen3.length ? itemNamesGen3[item] : '';

// Held items, as the games' bag pockets allow them (PKHeX's lists).
final Set<int> heldItemsGen2 = {
  3, 8, 9, for (var i = 10; i <= 24; i++) i, 26, 27, 28, 29, //
  for (var i = 30; i <= 44; i++) i, 46, 47, 48, 49, 51, 52, 53, 57, 60, 62,
  63,
  64,
  65,
  for (var i = 72; i <= 89; i++) i,
  for (var i = 91; i <= 99; i++) i,
  for (var i = 101; i <= 114; i++) i, 117, 118, 119, 121, 122, 123, 124, 125,
  126, 131, 132, 138, 139, 140, 143, 144, 146, 150, 151, 152, 156, 158, 163,
  167, 168, 169, 170, 172, 173, 174, for (var i = 180; i <= 189; i++) i,
  // balls
  1, 2, 4, 5, 157, 159, 160, 161, 164, 165, 166,
  // TM01-TM50
  191, 192, 193, 194, for (var i = 196; i <= 219; i++) i,
  for (var i = 221; i <= 242; i++) i,
};

final Set<int> heldItemsGen3 = {
  for (var i = 13; i <= 51; i++) i, for (var i = 63; i <= 71; i++) i, //
  for (var i = 73; i <= 81; i++) i, for (var i = 83; i <= 86; i++) i,
  for (var i = 93; i <= 98; i++) i,
  103,
  104,
  for (var i = 106; i <= 111; i++) i,
  for (var i = 121; i <= 132; i++) i, for (var i = 179; i <= 225; i++) i,
  for (var i = 254; i <= 258; i++) i,
  for (var i = 1; i <= 12; i++) i, // balls
  for (var i = 133; i <= 175; i++) i, // berries
  for (var i = 289; i <= 338; i++) i, // TM01-TM50
};

/// Items that are a "held item" when sent through the Time Capsule (none or
/// a real Gen 2 held item); other Gen 1 catch rates become items by the
/// Time Capsule's own table.
bool isCatchRateHeldItem(int rate) => rate == 0 || heldItemsGen2.contains(rate);

int gen1CatchRateToGen2Item(int rate) {
  if (isCatchRateHeldItem(rate)) {
    return rate;
  }
  return switch (rate) {
    0x19 => 0x92, // Leftovers
    0x2D => 0x53, // Bitter Berry
    0x32 => 0xAE, // Gold Berry
    0x5A ||
    0x64 ||
    0x78 ||
    0x87 ||
    0xBE ||
    0xC3 ||
    0xDC ||
    0xFA ||
    0xFF => 0xAD, // Berry
    _ => rate,
  };
}

/// Gen 1/2 species name the way the games write it (all caps, MR.MIME).
String gbSpeciesName(int species) {
  var n = speciesName(species).toUpperCase();
  if (species == 122) {
    n = n.replaceFirst('. ', gbDotChar);
  }
  return n;
}

const String gbDotChar = '․';

/// Gen 3 species name the way the games write it.
String gbaSpeciesName(int species) {
  var n = speciesName(species).toUpperCase();
  if (species == 83) {
    n = n.replaceAll('’', '\'');
  }
  return n;
}

/// What a Pokémon of [generation] can be given to hold, "None" first, like
/// the helper's `items` (Gen 1 Pokémon hold nothing: empty list).
List<({int id, String name})> heldItemChoices(int generation) {
  if (generation <= 1) {
    return const [];
  }
  final names = generation == 2 ? itemNamesGen2 : itemNamesGen3;
  final allowed = generation == 2 ? heldItemsGen2 : heldItemsGen3;
  final max = generation == 2 ? 255 : 376;
  return [
    (id: 0, name: 'None'),
    for (var i = 1; i <= max && i < names.length; i++)
      if (names[i].trim().isNotEmpty &&
          !names[i].startsWith('(') &&
          !names[i].contains('???') &&
          allowed.contains(i) &&
          !(generation == 3 && (i == 5 || i == 44)))
        (id: i, name: names[i]),
  ];
}
