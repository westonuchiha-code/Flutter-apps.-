// Generates lib/src/data/tables.g.dart from PokeAPI's CSV files
// (https://github.com/PokeAPI/pokeapi, data/v2/csv, BSD-3-Clause) plus the
// per-game tables PokeAPI doesn't have (Gen 2 / Gen 3 item lists, written
// below from the games' own item lists, spelled the way PKHeX shows them).
//
//   dart run tool/gen_tables.dart [csv folder]
//
// Without a folder the CSVs are downloaded (through HTTPS_PROXY if set) into a
// temporary folder that is deleted afterwards. Only the generated Dart file is
// committed, never the CSVs.
import 'dart:convert';
import 'dart:io';

const csvBase =
    'https://raw.githubusercontent.com/PokeAPI/pokeapi/master/data/v2/csv/';
const files = [
  'pokemon_species',
  'pokemon_species_names',
  'move_names',
  'ability_names',
  'type_names',
  'pokemon_types',
  'pokemon_types_past',
  'pokemon_stats',
  'pokemon_abilities',
  'pokemon_abilities_past',
  'experience',
  'pokemon_game_indices',
];

const english = '9';
const maxSpecies = 386;
const maxMove = 354;
const maxAbility = 77;

Future<void> main(List<String> args) async {
  Directory dir;
  var temp = false;
  if (args.isNotEmpty) {
    dir = Directory(args.first);
  } else {
    dir = await Directory.systemTemp.createTemp('pokeapi_csv');
    temp = true;
    await download(dir);
  }
  try {
    final out = File.fromUri(
      Platform.script.resolve('../lib/src/data/tables.g.dart'),
    );
    await out.writeAsString(generate(dir));
    stdout.writeln('wrote ${out.path}');
  } finally {
    if (temp) {
      await dir.delete(recursive: true);
    }
  }
}

Future<void> download(Directory dir) async {
  final client = HttpClient()..findProxy = HttpClient.findProxyFromEnvironment;
  try {
    for (final f in files) {
      final req = await client.getUrl(Uri.parse('$csvBase$f.csv'));
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('$f.csv: HTTP ${res.statusCode}');
      }
      await res.pipe(File('${dir.path}/$f.csv').openWrite());
    }
  } finally {
    client.close();
  }
}

List<Map<String, String>> readCsv(Directory dir, String name) {
  final lines = const LineSplitter().convert(
    File('${dir.path}/$name.csv').readAsStringSync(),
  );
  final head = splitCsv(lines.first);
  return [
    for (final l in lines.skip(1))
      if (l.trim().isNotEmpty)
        {
          for (var i = 0; i < head.length; i++)
            head[i]: i < splitCsv(l).length ? splitCsv(l)[i] : '',
        },
  ];
}

List<String> splitCsv(String line) {
  final out = <String>[];
  final b = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (quoted) {
      if (c == '"' && i + 1 < line.length && line[i + 1] == '"') {
        b.write('"');
        i++;
      } else if (c == '"') {
        quoted = false;
      } else {
        b.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',') {
      out.add(b.toString());
      b.clear();
    } else {
      b.write(c);
    }
  }
  out.add(b.toString());
  return out;
}

Map<int, String> englishNames(Directory dir, String file, String idCol) => {
  for (final r in readCsv(dir, file))
    if (r['local_language_id'] == english) int.parse(r[idCol]!): r['name']!,
};

String generate(Directory dir) {
  final species = englishNames(
    dir,
    'pokemon_species_names',
    'pokemon_species_id',
  );
  final moves = englishNames(dir, 'move_names', 'move_id');
  final abilities = englishNames(dir, 'ability_names', 'ability_id');
  final types = englishNames(dir, 'type_names', 'type_id');

  final speciesRows = {
    for (final r in readCsv(dir, 'pokemon_species')) int.parse(r['id']!): r,
  };

  // Types today (PokeAPI type id - 1 = PKHeX's type index) and in Gen 1.
  final typesNow = <int, List<int>>{};
  for (final r in readCsv(dir, 'pokemon_types')) {
    final p = int.parse(r['pokemon_id']!);
    if (p > maxSpecies) {
      continue;
    }
    (typesNow[p] ??= [0, 0])[int.parse(r['slot']!) - 1] = int.parse(
      r['type_id']!,
    );
  }
  final typesPast = <int, Map<int, List<int>>>{};
  for (final r in readCsv(dir, 'pokemon_types_past')) {
    final p = int.parse(r['pokemon_id']!);
    if (p > maxSpecies) {
      continue;
    }
    final g = int.parse(r['generation_id']!);
    ((typesPast[p] ??= {})[g] ??= [0, 0])[int.parse(r['slot']!) - 1] =
        int.parse(r['type_id']!);
  }
  List<int> typesIn(int s, int gen) {
    final past = typesPast[s];
    if (past != null) {
      final gens = past.keys.where((g) => g >= gen).toList()..sort();
      if (gens.isNotEmpty) {
        return past[gens.first]!;
      }
    }
    return typesNow[s]!;
  }

  final stats = <int, List<int>>{};
  for (final r in readCsv(dir, 'pokemon_stats')) {
    final p = int.parse(r['pokemon_id']!);
    if (p > maxSpecies) {
      continue;
    }
    // PokeAPI: 1 HP 2 Atk 3 Def 4 SpA 5 SpD 6 Spe (the order PKHeX's summary uses).
    (stats[p] ??= List.filled(6, 0))[int.parse(r['stat_id']!) - 1] = int.parse(
      r['base_stat']!,
    );
  }

  // Gen 3 abilities: today's slots 1 and 2, unless PokeAPI's past table says
  // they were different up to Gen 3 or later.
  final abilNow = <int, List<int>>{};
  for (final r in readCsv(dir, 'pokemon_abilities')) {
    final p = int.parse(r['pokemon_id']!);
    final slot = int.parse(r['slot']!);
    if (p > maxSpecies || slot > 2) {
      continue;
    }
    (abilNow[p] ??= [0, 0])[slot - 1] = int.parse(r['ability_id']!);
  }
  final abilPast = <int, Map<int, Map<int, int>>>{};
  for (final r in readCsv(dir, 'pokemon_abilities_past')) {
    final p = int.parse(r['pokemon_id']!);
    final slot = int.parse(r['slot']!);
    if (p > maxSpecies || slot > 2) {
      continue;
    }
    final g = int.parse(r['generation_id']!);
    final a = r['ability_id']!.isEmpty ? 0 : int.parse(r['ability_id']!);
    ((abilPast[p] ??= {})[slot] ??= {})[g] = a;
  }
  List<int> gen3Abilities(int s) {
    final res = [...abilNow[s]!];
    for (final slot in [1, 2]) {
      final past = abilPast[s]?[slot];
      if (past == null) {
        continue;
      }
      final gens = past.keys.where((g) => g >= 3).toList()..sort();
      if (gens.isNotEmpty) {
        res[slot - 1] = past[gens.first]!;
      }
    }
    if (res[1] == 0 || res[1] > maxAbility) {
      res[1] = res[0];
    }
    return res;
  }

  final exp = <int, List<int>>{};
  for (final r in readCsv(dir, 'experience')) {
    final g = int.parse(r['growth_rate_id']!);
    final lv = int.parse(r['level']!);
    (exp[g] ??= List.filled(101, 0))[lv] = int.parse(r['experience']!);
  }

  // Internal species numbers: Red (version 1) for Gen 1, Ruby (7) for Gen 3.
  final gen1Index = List.filled(152, 0);
  final gen3Index = List.filled(maxSpecies + 1, 0);
  for (final r in readCsv(dir, 'pokemon_game_indices')) {
    final p = int.parse(r['pokemon_id']!);
    final v = r['version_id'];
    if (v == '1' && p <= 151) {
      gen1Index[p] = int.parse(r['game_index']!);
    } else if (v == '7' && p <= maxSpecies) {
      gen3Index[p] = int.parse(r['game_index']!);
    }
  }

  final b = StringBuffer()
    ..writeln(
      '// GENERATED by tool/gen_tables.dart from PokeAPI data (BSD-3-Clause)',
    )
    ..writeln(
      '// and the per-game item lists in that script. Do not edit by hand.',
    )
    ..writeln('// dart format off')
    ..writeln();

  void strings(String name, List<String> list) {
    b.writeln('const $name = <String>[');
    for (final s in list) {
      b.writeln('  ${jsonEncode(s).replaceAll(r'$', r'\$')},');
    }
    b.writeln('];');
    b.writeln();
  }

  void ints(String name, List<int> list, {int perLine = 20}) {
    b.writeln('const $name = <int>[');
    for (var i = 0; i < list.length; i += perLine) {
      b.writeln(
        '  ${list.sublist(i, (i + perLine).clamp(0, list.length)).join(', ')},',
      );
    }
    b.writeln('];');
    b.writeln();
  }

  strings('speciesNames', [
    for (var i = 0; i <= maxSpecies; i++) i == 0 ? '' : species[i]!,
  ]);
  strings('moveNames', [
    for (var i = 0; i <= maxMove; i++) i == 0 ? '' : moves[i]!,
  ]);
  strings('abilityNames', [
    for (var i = 0; i <= maxAbility; i++) i == 0 ? '' : abilities[i]!,
  ]);
  strings('typeNames', [for (var i = 1; i <= 18; i++) types[i]!]);

  // Per species (index = national number), flattened.
  ints('speciesTypes', [
    0,
    0,
    for (var s = 1; s <= maxSpecies; s++) ...[
      typesNow[s]![0] - 1,
      (typesNow[s]![1] == 0 ? typesNow[s]![0] : typesNow[s]![1]) - 1,
    ],
  ]);
  ints('baseStats', [
    0,
    0,
    0,
    0,
    0,
    0,
    for (var s = 1; s <= maxSpecies; s++) ...stats[s]!,
  ], perLine: 24);
  ints('genderRates', [
    -1,
    for (var s = 1; s <= maxSpecies; s++)
      int.parse(speciesRows[s]!['gender_rate']!),
  ]);
  ints('growthRates', [
    0,
    for (var s = 1; s <= maxSpecies; s++)
      int.parse(speciesRows[s]!['growth_rate_id']!),
  ]);
  ints('gen3AbilityPairs', [
    0,
    0,
    for (var s = 1; s <= maxSpecies; s++) ...gen3Abilities(s),
  ]);
  ints('gen1InternalIndex', gen1Index);
  ints('gen3InternalIndex', gen3Index);

  // Gen 1 types, as the Gen 1 games number them.
  const gen1TypeIds = {
    1: 0x00,
    2: 0x01,
    3: 0x02,
    4: 0x03,
    5: 0x04,
    6: 0x05,
    7: 0x07,
    8: 0x08,
    10: 0x14,
    11: 0x15,
    12: 0x16,
    13: 0x17,
    14: 0x18,
    15: 0x19,
    16: 0x1A,
  };
  ints('gen1Types', [
    0,
    0,
    for (var s = 1; s <= 151; s++) ...[
      gen1TypeIds[typesIn(s, 1)[0]]!,
      gen1TypeIds[typesIn(s, 1)[1] == 0 ? typesIn(s, 1)[0] : typesIn(s, 1)[1]]!,
    ],
  ]);

  // Experience at each level (1..100) for growth rates 1..6, flattened: [rate * 101 + level].
  ints('expTable', [
    for (var i = 0; i <= 100; i++) 0,
    for (var g = 1; g <= 6; g++) ...exp[g]!,
  ], perLine: 101);

  strings('itemNamesGen2', gen2Items);
  strings('itemNamesGen3', gen3Items);
  return b.toString();
}

// The Gen 2 item list (international Gold/Silver/Crystal numbering), with the
// unused "Teru-sama" slots and unused TM/HM slots labelled the way PKHeX does.
const gen2Items = [
  '(None)',
  'Master Ball',
  'Ultra Ball',
  'BrightPowder',
  'Great Ball',
  'Poké Ball',
  'Teru-sama (0)',
  'Bicycle',
  'Moon Stone',
  'Antidote',
  'Burn Heal',
  'Ice Heal',
  'Awakening',
  'Parlyz Heal',
  'Full Restore',
  'Max Potion',
  'Hyper Potion',
  'Super Potion',
  'Potion',
  'Escape Rope',
  'Repel',
  'Max Elixer',
  'Fire Stone',
  'Thunder Stone',
  'Water Stone',
  'Teru-sama (1)',
  'HP Up',
  'Protein',
  'Iron',
  'Carbos',
  'Lucky Punch',
  'Calcium',
  'Rare Candy',
  'X Accuracy',
  'Leaf Stone',
  'Metal Powder',
  'Nugget',
  'Poké Doll',
  'Full Heal',
  'Revive',
  'Max Revive',
  'Guard Spec.',
  'Super Repel',
  'Max Repel',
  'Dire Hit',
  'Teru-sama (2)',
  'Fresh Water',
  'Soda Pop',
  'Lemonade',
  'X Attack',
  'Teru-sama (3)',
  'X Defend',
  'X Speed',
  'X Special',
  'Coin Case',
  'Itemfinder',
  'Teru-sama (4)',
  'Exp Share',
  'Old Rod',
  'Good Rod',
  'Silver Leaf',
  'Super Rod',
  'PP Up',
  'Ether',
  'Max Ether',
  'Elixer',
  'Red Scale',
  'SecretPotion',
  'S.S. Ticket',
  'Mystery Egg',
  'Clear Bell*',
  'Silver Wing',
  'Moomoo Milk',
  'Quick Claw',
  'PSNCureBerry',
  'Gold Leaf',
  'Soft Sand',
  'Sharp Beak',
  'PRZCureBerry',
  'Burnt Berry',
  'Ice Berry',
  'Poison Barb',
  "King's Rock",
  'Bitter Berry',
  'Mint Berry',
  'Red Apricorn',
  'TinyMushroom',
  'Big Mushroom',
  'SilverPowder',
  'Blu Apricorn',
  'Teru-sama (5)',
  'Amulet Coin',
  'Ylw Apricorn',
  'Grn Apricorn',
  'Cleanse Tag',
  'Mystic Water',
  'TwistedSpoon',
  'Wht Apricorn',
  'Black Belt',
  'Blk Apricorn',
  'Teru-sama (6)',
  'Pnk Apricorn',
  'BlackGlasses',
  'SlowpokeTail',
  'Pink Bow',
  'Stick',
  'Smoke Ball',
  'NeverMeltIce',
  'Magnet',
  'MiracleBerry',
  'Pearl',
  'Big Pearl',
  'Everstone',
  'Spell Tag',
  'RageCandyBar',
  'GS Ball*',
  'Blue Card*',
  'Miracle Seed',
  'Thick Club',
  'Focus Band',
  'Teru-sama (7)',
  'EnergyPowder',
  'Energy Root',
  'Heal Powder',
  'Revival Herb',
  'Hard Stone',
  'Lucky Egg',
  'Card Key',
  'Machine Part',
  'Egg Ticket*',
  'Lost Item',
  'Stardust',
  'Star Piece',
  'Basement Key',
  'Pass',
  'Teru-sama (8)',
  'Teru-sama (9)',
  'Teru-sama (10)',
  'Charcoal',
  'Berry Juice',
  'Scope Lens',
  'Teru-sama (11)',
  'Teru-sama (12)',
  'Metal Coat',
  'Dragon Fang',
  'Teru-sama (13)',
  'Leftovers',
  'Teru-sama (14)',
  'Teru-sama (15)',
  'Teru-sama (16)',
  'MysteryBerry',
  'Dragon Scale',
  'Berserk Gene',
  'Teru-sama (17)',
  'Teru-sama (18)',
  'Teru-sama (19)',
  'Sacred Ash',
  'Heavy Ball',
  'Flower Mail',
  'Level Ball',
  'Lure Ball',
  'Fast Ball',
  'Teru-sama (20)',
  'Light Ball',
  'Friend Ball',
  'Moon Ball',
  'Love Ball',
  'Normal Box',
  'Gorgeous Box',
  'Sun Stone',
  'Polkadot Bow',
  'Teru-sama (21)',
  'Up-Grade',
  'Berry',
  'Gold Berry',
  'SquirtBottle',
  'Teru-sama (22)',
  'Park Ball',
  'Rainbow Wing',
  'Teru-sama (23)',
  'Brick Piece',
  'Surf Mail',
  'Litebluemail',
  'Portraitmail',
  'Lovely Mail',
  'Eon Mail',
  'Morph Mail',
  'Bluesky Mail',
  'Music Mail',
  'Mirage Mail',
  'Teru-sama (24)',
  'TM01',
  'TM02',
  'TM03',
  'TM04',
  'TM04 (Unused)',
  'TM05',
  'TM06',
  'TM07',
  'TM08',
  'TM09',
  'TM10',
  'TM11',
  'TM12',
  'TM13',
  'TM14',
  'TM15',
  'TM16',
  'TM17',
  'TM18',
  'TM19',
  'TM20',
  'TM21',
  'TM22',
  'TM23',
  'TM24',
  'TM25',
  'TM26',
  'TM27',
  'TM28',
  'TM28 (Unused)',
  'TM29',
  'TM30',
  'TM31',
  'TM32',
  'TM33',
  'TM34',
  'TM35',
  'TM36',
  'TM37',
  'TM38',
  'TM39',
  'TM40',
  'TM41',
  'TM42',
  'TM43',
  'TM44',
  'TM45',
  'TM46',
  'TM47',
  'TM48',
  'TM49',
  'TM50',
  'HM01',
  'HM02',
  'HM03',
  'HM04',
  'HM05',
  'HM06',
  'HM07',
  'HM08 (Unused)',
  'HM09 (Unused)',
  'HM10 (Unused)',
  'HM11 (Unused)',
  'HM12 (Unused)',
];

// The Gen 3 item list (Ruby/Sapphire/Emerald/FireRed/LeafGreen numbering).
const gen3Items = [
  '(None)',
  'Master Ball',
  'Ultra Ball',
  'Great Ball',
  'Poké Ball',
  'Safari Ball',
  'Net Ball',
  'Dive Ball',
  'Nest Ball',
  'Repeat Ball',
  'Timer Ball',
  'Luxury Ball',
  'Premier Ball',
  'Potion',
  'Antidote',
  'Burn Heal',
  'Ice Heal',
  'Awakening',
  'Parlyz Heal',
  'Full Restore',
  'Max Potion',
  'Hyper Potion',
  'Super Potion',
  'Full Heal',
  'Revive',
  'Max Revive',
  'Fresh Water',
  'Soda Pop',
  'Lemonade',
  'Moomoo Milk',
  'EnergyPowder',
  'Energy Root',
  'Heal Powder',
  'Revival Herb',
  'Ether',
  'Max Ether',
  'Elixir',
  'Max Elixir',
  'Lava Cookie',
  'Blue Flute',
  'Yellow Flute',
  'Red Flute',
  'Black Flute',
  'White Flute',
  'Berry Juice',
  'Sacred Ash',
  'Shoal Salt',
  'Shoal Shell',
  'Red Shard',
  'Blue Shard',
  'Yellow Shard',
  'Green Shard',
  '???',
  '???',
  '???',
  '???',
  '???',
  '???',
  '???',
  '???',
  '???',
  '???',
  '???',
  'HP Up',
  'Protein',
  'Iron',
  'Carbos',
  'Calcium',
  'Rare Candy',
  'PP Up',
  'Zinc',
  'PP Max',
  '???',
  'Guard Spec.',
  'Dire Hit',
  'X Attack',
  'X Defend',
  'X Speed',
  'X Accuracy',
  'X Special',
  'Poké Doll',
  'Fluffy Tail',
  '???',
  'Super Repel',
  'Max Repel',
  'Escape Rope',
  'Repel',
  '???',
  '???',
  '???',
  '???',
  '???',
  '???',
  'Sun Stone',
  'Moon Stone',
  'Fire Stone',
  'Thunder Stone',
  'Water Stone',
  'Leaf Stone',
  '???',
  '???',
  '???',
  '???',
  'TinyMushroom',
  'Big Mushroom',
  '???',
  'Pearl',
  'Big Pearl',
  'Stardust',
  'Star Piece',
  'Nugget',
  'Heart Scale',
  '???',
  '???',
  '???',
  '???',
  '???',
  '???',
  '???',
  '???',
  '???',
  'Orange Mail',
  'Harbor Mail',
  'Glitter Mail',
  'Mech Mail',
  'Wood Mail',
  'Wave Mail',
  'Bead Mail',
  'Shadow Mail',
  'Tropic Mail',
  'Dream Mail',
  'Fab Mail',
  'Retro Mail',
  'Cheri Berry',
  'Chesto Berry',
  'Pecha Berry',
  'Rawst Berry',
  'Aspear Berry',
  'Leppa Berry',
  'Oran Berry',
  'Persim Berry',
  'Lum Berry',
  'Sitrus Berry',
  'Figy Berry',
  'Wiki Berry',
  'Mago Berry',
  'Aguav Berry',
  'Iapapa Berry',
  'Razz Berry',
  'Bluk Berry',
  'Nanab Berry',
  'Wepear Berry',
  'Pinap Berry',
  'Pomeg Berry',
  'Kelpsy Berry',
  'Qualot Berry',
  'Hondew Berry',
  'Grepa Berry',
  'Tamato Berry',
  'Cornn Berry',
  'Magost Berry',
  'Rabuta Berry',
  'Nomel Berry',
  'Spelon Berry',
  'Pamtre Berry',
  'Watmel Berry',
  'Durin Berry',
  'Belue Berry',
  'Liechi Berry',
  'Ganlon Berry',
  'Salac Berry',
  'Petaya Berry',
  'Apicot Berry',
  'Lansat Berry',
  'Starf Berry',
  'Enigma Berry',
  '???',
  '???',
  '???',
  'BrightPowder',
  'White Herb',
  'Macho Brace',
  'Exp. Share',
  'Quick Claw',
  'Soothe Bell',
  'Mental Herb',
  'Choice Band',
  "King's Rock",
  'SilverPowder',
  'Amulet Coin',
  'Cleanse Tag',
  'Soul Dew',
  'DeepSeaTooth',
  'DeepSeaScale',
  'Smoke Ball',
  'Everstone',
  'Focus Band',
  'Lucky Egg',
  'Scope Lens',
  'Metal Coat',
  'Leftovers',
  'Dragon Scale',
  'Light Ball',
  'Soft Sand',
  'Hard Stone',
  'Miracle Seed',
  'BlackGlasses',
  'Black Belt',
  'Magnet',
  'Mystic Water',
  'Sharp Beak',
  'Poison Barb',
  'NeverMeltIce',
  'Spell Tag',
  'TwistedSpoon',
  'Charcoal',
  'Dragon Fang',
  'Silk Scarf',
  'Up-Grade',
  'Shell Bell',
  'Sea Incense',
  'Lax Incense',
  'Lucky Punch',
  'Metal Powder',
  'Thick Club',
  'Stick',
  '???',
  '???',
  '???',
  '???',
  '???',
  '???',
  '???',
  '???',
  '???',
  '???',
  '???',
  '???',
  '???',
  '???',
  '???',
  '???',
  '???',
  '???',
  '???',
  '???',
  '???',
  '???',
  '???',
  '???',
  '???',
  '???',
  '???',
  '???',
  'Red Scarf',
  'Blue Scarf',
  'Pink Scarf',
  'Green Scarf',
  'Yellow Scarf',
  'Mach Bike',
  'Coin Case',
  'Itemfinder',
  'Old Rod',
  'Good Rod',
  'Super Rod',
  'S.S. Ticket',
  'Contest Pass',
  '???',
  'Wailmer Pail',
  'Devon Goods',
  'Soot Sack',
  'Basement Key',
  'Acro Bike',
  'Pokéblock Case',
  'Letter',
  'Eon Ticket',
  'Red Orb',
  'Blue Orb',
  'Scanner',
  'Go-Goggles',
  'Meteorite',
  'Rm. 1 Key',
  'Rm. 2 Key',
  'Rm. 4 Key',
  'Rm. 6 Key',
  'Storage Key',
  'Root Fossil',
  'Claw Fossil',
  'Devon Scope',
  'TM01',
  'TM02',
  'TM03',
  'TM04',
  'TM05',
  'TM06',
  'TM07',
  'TM08',
  'TM09',
  'TM10',
  'TM11',
  'TM12',
  'TM13',
  'TM14',
  'TM15',
  'TM16',
  'TM17',
  'TM18',
  'TM19',
  'TM20',
  'TM21',
  'TM22',
  'TM23',
  'TM24',
  'TM25',
  'TM26',
  'TM27',
  'TM28',
  'TM29',
  'TM30',
  'TM31',
  'TM32',
  'TM33',
  'TM34',
  'TM35',
  'TM36',
  'TM37',
  'TM38',
  'TM39',
  'TM40',
  'TM41',
  'TM42',
  'TM43',
  'TM44',
  'TM45',
  'TM46',
  'TM47',
  'TM48',
  'TM49',
  'TM50',
  'HM01',
  'HM02',
  'HM03',
  'HM04',
  'HM05',
  'HM06',
  'HM07',
  'HM08',
  '???',
  '???',
  "Oak's Parcel",
  'Poké Flute',
  'Secret Key',
  'Bike Voucher',
  'Gold Teeth',
  'Old Amber',
  'Card Key',
  'Lift Key',
  'Helix Fossil',
  'Dome Fossil',
  'Silph Scope',
  'Bicycle',
  'Town Map',
  'Vs. Seeker',
  'Fame Checker',
  'TM Case',
  'Berry Pouch',
  'Teachy TV',
  'Tri-Pass',
  'Rainbow Pass',
  'Tea',
  'MysticTicket',
  'AuroraTicket',
  'Powder Jar',
  'Ruby',
  'Sapphire',
  'Magma Emblem',
  'Old Sea Map',
];
