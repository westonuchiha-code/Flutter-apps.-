/// The public face: open a Gen 1-3 save, list its boxes, take Pokémon out as
/// PKHeX files and put them back. Every change returns new save bytes; the
/// package never touches files.
library;

import 'dart:typed_data';

import 'dex.dart';
import 'gb_save.dart';
import 'gba_save.dart';
import 'mon.dart';

/// The games this package knows (western versions only).
enum PokeGame {
  redBlue('RB', 'RB', 1),
  yellow('YW', 'Yellow', 1),
  goldSilver('GS', 'GS', 2),
  crystal('C', 'Crystal', 2),
  rubySapphire('RS', 'RS', 3),
  emerald('E', 'Emerald', 3),
  fireRedLeafGreen('FRLG', 'FRLG', 3);

  const PokeGame(this.version, this.pkhexName, this.generation);

  /// PKHeX's GameVersion name for the save ("RB", "YW", "GS", "C", ...).
  final String version;

  /// What PKHeX's GameName gives for the save.
  final String pkhexName;
  final int generation;

  String get format => 'pk$generation';
}

/// A box of a save. Game Boy boxes are lists without gaps (20 slots).
class PokeBox {
  PokeBox(this.name, this.slots);
  final String name;

  /// One entry per slot; null = empty.
  final List<Mon?> slots;

  int get count => slots.where((m) => m != null).length;
}

/// The answer to a change: the new save bytes and the Pokémon, or why not.
class PokeResult {
  PokeResult.ok(this.save, this.mon, {this.reason = ''}) : error = '';
  PokeResult.fail(this.error) : save = null, mon = null, reason = '';

  /// The whole new save file (null when it failed).
  final Uint8List? save;
  final Mon? mon;
  final String error;

  /// "fits as it is" / "converted from pk1 to pk2" (puts), like the helper.
  final String reason;

  bool get ok => error.isEmpty;
}

class PokeSave {
  PokeSave._(
    this._bytes,
    this._footer,
    this.game,
    this.gameName,
    this._gb,
    this._gba,
    this._fileName,
  );

  final String? _fileName;

  final Uint8List _bytes;
  final Uint8List _footer;
  final GbSave? _gb;
  final GbaSave? _gba;

  final PokeGame game;

  /// PKHeX's game name for this save, sharpened by the file name where PKHeX
  /// can't tell from the data (FireRed vs LeafGreen, Ruby vs Sapphire, Red vs
  /// Blue: e.g. "LeafGreen"). Without a hint it is PKHeX's own answer.
  final String gameName;

  /// The original file bytes.
  Uint8List get bytes => Uint8List.fromList(_bytes);

  /// Opens a save: the game, or null when it isn't a Gen 1-3 Pokémon save
  /// this package can read (Japanese and Korean versions are left out).
  /// Emulator footers (RTC data) are kept as they are.
  static PokeSave? open(Uint8List bytes, {String? fileName}) {
    var body = bytes;
    var footer = Uint8List(0);
    final extra = bytes.length & 0x3F;
    if (extra != 0 &&
        (extra == 7 || (extra.isEven && extra >= 0x0C && extra <= 0x30))) {
      final base = bytes.length - extra;
      if (base == 0x8000 || base == 0x10000 || base == 0x20000) {
        body = Uint8List.sublistView(bytes, 0, base);
        footer = Uint8List.fromList(bytes.sublist(base));
      }
    }
    final name = (fileName ?? '').toLowerCase();
    final gb = GbSave.detect(body);
    if (gb != null) {
      PokeGame g;
      String n;
      if (gb.gen == 1) {
        g = gb.yellow ? PokeGame.yellow : PokeGame.redBlue;
        n = g.pkhexName;
        if (g == PokeGame.redBlue && name.contains('red')) {
          n = 'Red';
        } else if (g == PokeGame.redBlue && name.contains('blue')) {
          n = 'Blue';
        }
      } else {
        g = gb.crystal ? PokeGame.crystal : PokeGame.goldSilver;
        n = g.pkhexName;
        if (g == PokeGame.goldSilver && name.contains('gold')) {
          n = 'Gold';
        } else if (g == PokeGame.goldSilver && name.contains('silver')) {
          n = 'Silver';
        }
      }
      return PokeSave._(
        Uint8List.fromList(bytes),
        footer,
        g,
        n,
        gb,
        null,
        fileName,
      );
    }
    final gba = GbaSave.detect(body);
    if (gba != null) {
      final g = switch (gba.game) {
        GbaGame.rs => PokeGame.rubySapphire,
        GbaGame.emerald => PokeGame.emerald,
        GbaGame.frlg => PokeGame.fireRedLeafGreen,
      };
      var n = switch (g) {
        PokeGame.fireRedLeafGreen => 'FireRed', // PKHeX's default for FR/LG
        _ => g.pkhexName,
      };
      if (g == PokeGame.fireRedLeafGreen &&
          (name.contains('leaf') || name.contains('green'))) {
        n = 'LeafGreen';
      } else if (g == PokeGame.rubySapphire && name.contains('ruby')) {
        n = 'Ruby';
      } else if (g == PokeGame.rubySapphire && name.contains('sapphire')) {
        n = 'Sapphire';
      }
      return PokeSave._(
        Uint8List.fromList(bytes),
        footer,
        g,
        n,
        null,
        gba,
        fileName,
      );
    }
    return null;
  }

  int get generation => game.generation;

  /// The file type of this game's Pokémon: "pk1", "pk2" or "pk3".
  String get format => game.format;

  String get trainer => _gb?.trainer ?? _gba!.trainer;
  int get tid => _gb?.tid ?? _gba!.tid;
  int get boxCount => _gb?.boxCount ?? GbaSave.boxCount;
  int get boxSlots => _gb != null ? GbSave.capacity : GbaSave.boxSlots;
  int get currentBox => _gb?.currentBox ?? _gba!.currentBox;

  /// Game Boy boxes have no gaps: a Pokémon put anywhere goes after the
  /// others, and taking one moves the rest up.
  bool get packedBoxes => _gb != null;

  int get maxSpecies => switch (generation) {
    1 => maxSpecies1,
    2 => maxSpecies2,
    _ => maxSpecies3,
  };

  List<PokeBox> get boxes => [
    for (var b = 0; b < boxCount; b++)
      PokeBox(boxName(b), [for (var s = 0; s < boxSlots; s++) boxMon(b, s)]),
  ];

  String boxName(int box) => _gb?.boxName(box) ?? _gba!.boxName(box);

  /// The Pokémon in a box slot, or null.
  Mon? boxMon(int box, int slot) {
    _checkSlot(box, slot);
    final m = _gb != null
        ? _gb.monAt(_gb.boxes[box][slot])
        : _gba!.boxMon(box, slot);
    return m.species == 0 ? null : m;
  }

  List<Mon> get party {
    final out = <Mon>[];
    if (_gb != null) {
      final n = _gb.partyCount.clamp(0, 6);
      for (var i = 0; i < n; i++) {
        out.add(_gb.monAt(_gb.party[i]));
      }
    } else {
      final n = _gba!.partyCount.clamp(0, 6);
      for (var i = 0; i < n; i++) {
        out.add(_gba.partyMon(i));
      }
    }
    return out;
  }

  /// '' when the checksums are right (the ones PKHeX checks), else what's wrong.
  String check() => _gb?.check() ?? _gba!.check();

  /// Like the helper's `info` answer.
  Map<String, Object?> info() => {
    'game': gameName,
    'version': game.version,
    'generation': generation,
    'format': format,
    'trainer': trainer,
    'tid': tid,
    'max_species': maxSpecies,
    'box_slots': boxSlots,
    'packed_boxes': packedBoxes,
    'boxes': [
      for (final b in boxes)
        {
          'name': b.name,
          'slots': [for (final m in b.slots) m?.summary],
        },
    ],
    'party': [for (final m in party) m.summary],
  };

  void _checkSlot(int box, int slot) {
    if (box < 0 || box >= boxCount || slot < 0 || slot >= boxSlots) {
      throw RangeError('no box $box slot $slot in this save');
    }
  }

  bool _validSlot(int box, int slot) =>
      box >= 0 && box < boxCount && slot >= 0 && slot < boxSlots;

  // ------------------------------------------------------------ changes

  /// A fresh, editable copy of this save's data (every change starts from
  /// the bytes it was opened with, like the helper opening the file again).
  PokeSave _fresh() => PokeSave.open(_bytes, fileName: _fileName)!;

  Uint8List _finish() {
    final body = _gb != null ? _gb.write() : _gba!.write();
    if (_footer.isEmpty) {
      return body;
    }
    return Uint8List.fromList([...body, ..._footer]);
  }

  int _countBox(int box) => [
    for (var s = 0; s < boxSlots; s++) boxMon(box, s),
  ].where((m) => m != null).length;
  int _countAll() => [
    for (var b = 0; b < boxCount; b++) _countBox(b),
  ].fold(0, (a, b) => a + b);
  int _countSpecies(int species) {
    var n = 0;
    for (var b = 0; b < boxCount; b++) {
      for (var s = 0; s < boxSlots; s++) {
        if (boxMon(b, s)?.species == species) {
          n++;
        }
      }
    }
    return n;
  }

  void _setBox(int box, int slot, Mon? pk) {
    if (_gb != null) {
      _gb.setSlot(_gb.boxes[box][slot], pk ?? Mon.blankGb(generation));
    } else {
      _gba!.setBox(box, slot, pk);
    }
  }

  /// Takes the Pokémon in a box slot out: the new save (Game Boy boxes close
  /// the gap) and the Pokémon, whose [Mon.bytes] are the PKHeX file.
  PokeResult take(int box, int slot) {
    if (!_validSlot(box, slot)) {
      return PokeResult.fail('no box $box slot $slot in this save');
    }
    final pk = boxMon(box, slot);
    if (pk == null) {
      return PokeResult.fail('that slot is empty');
    }
    final file = pk.bytes;
    final back = Mon.fromFile(file, ext: pk.ext);
    if (back == null || back.species != pk.species || back.pid != pk.pid) {
      return PokeResult.fail('could not store that Pokémon safely');
    }
    final w = _fresh();
    final inBox = w._countBox(box), same = w._countSpecies(pk.species);
    w._setBox(box, slot, null);
    final out = w._finish();
    final again = PokeSave.open(out);
    if (again == null ||
        again._countBox(box) != inBox - 1 ||
        again._countSpecies(pk.species) != same - 1) {
      return PokeResult.fail(
        "the changed save didn't read back right, nothing was changed",
      );
    }
    return PokeResult.ok(out, Mon.fromFile(file, ext: pk.ext));
  }

  /// Puts a PKHeX file ([pkBytes], type [ext] or guessed from the size) into
  /// an empty box slot, converted the way PKHeX converts between Gen 1 and 2
  /// (the Time Capsule). Refuses what the games never allowed.
  PokeResult put(int box, int slot, Uint8List pkBytes, {String? ext}) {
    if (!_validSlot(box, slot)) {
      return PokeResult.fail('no box $box slot $slot in this save');
    }
    if (boxMon(box, slot) != null) {
      return PokeResult.fail('that slot is not empty');
    }
    if (packedBoxes && _countBox(box) >= boxSlots) {
      return PokeResult.fail('that box is full');
    }
    final pk = Mon.fromFile(pkBytes, ext: ext);
    if (pk == null) {
      return PokeResult.fail(
        'not a stored Pokémon this package can read (pk1, pk2 or pk3)',
      );
    }
    final w = _fresh();
    final (conv, why) = w.convert(pk);
    if (conv == null) {
      return PokeResult.fail(why);
    }
    final species = conv.species;
    final inBox = w._countBox(box), same = w._countSpecies(species);
    w._setBox(box, slot, conv);
    final out = w._finish();
    final again = PokeSave.open(out);
    if (again == null ||
        again._countBox(box) != inBox + 1 ||
        again._countSpecies(species) != same + 1) {
      return PokeResult.fail(
        "the changed save didn't read back right, nothing was changed",
      );
    }
    return PokeResult.ok(out, conv, reason: why);
  }

  /// Moves a Pokémon inside this save (onto a Pokémon = swap).
  PokeResult move(int box, int slot, int box2, int slot2) {
    if (!_validSlot(box, slot) || !_validSlot(box2, slot2)) {
      return PokeResult.fail('no such box slot in this save');
    }
    final p1 = boxMon(box, slot);
    if (box == box2 && slot == slot2) {
      return PokeResult.ok(_finishUnchanged(), p1);
    }
    if (p1 == null) {
      return PokeResult.fail('nothing there to move');
    }
    final w = _fresh();
    final p2 = w.boxMon(box2, slot2);
    final total = w._countAll(), same = w._countSpecies(p1.species);
    final a = w.boxMon(box, slot)!;
    w._setBox(box, slot, p2);
    w._setBox(box2, slot2, a);
    final out = w._finish();
    final again = PokeSave.open(out);
    if (again == null ||
        again._countAll() != total ||
        again._countSpecies(p1.species) != same) {
      return PokeResult.fail(
        "the changed save didn't read back right, nothing was changed",
      );
    }
    return PokeResult.ok(out, a, reason: p2 != null ? 'swapped' : '');
  }

  Uint8List _finishUnchanged() => bytes;

  /// The save written back without a change, the way PKHeX writes it (lists
  /// repacked, current box mirrored, checksums fixed). For a healthy save this
  /// is the same bytes.
  Uint8List rewrite() => _fresh()._finish();

  /// Could this Pokémon go into this game, and as what? Returns the Pokémon as
  /// it would be stored, or null and why not.
  (Mon?, String) convert(Mon pk) {
    final name = speciesName(pk.species);
    if (pk.species > maxSpecies) {
      return (null, "$name doesn't exist in $gameName");
    }
    final from = pk.format, to = generation;
    if (from <= 2 && to >= 3) {
      return (
        null,
        "Game Boy Pokémon can't go to $gameName: they only reach Gen 1-2 games, or Gen 7+ through the Virtual Console route",
      );
    }
    if (from >= 3 && to <= 2) {
      return (null, "$name can't go back to a Game Boy game");
    }
    Mon conv;
    var why = 'fits as it is';
    if (from == to) {
      conv = pk.clone();
    } else {
      final (c, note) = from == 1 ? _pk1ToPk2(pk) : _pk2ToPk1(pk);
      if (c == null) {
        return (null, note);
      }
      conv = c;
      why = 'converted from ${pk.ext} to ${conv.ext}';
      if (note.isNotEmpty) {
        why = '$why ($note)';
      }
    }
    final problems = <String>[];
    final held = conv.heldItem;
    if (to > 1 && held != 0) {
      final max = to == 2 ? 255 : _gba!.maxItem;
      final allowed = to == 2 ? heldItemsGen2 : heldItemsGen3;
      if (held > max) {
        problems.add('this game has no item $held');
      } else if (!allowed.contains(held)) {
        problems.add("it can't hold ${conv.itemName} in this game");
      }
    }
    final maxMove = switch (to) {
      1 => 165,
      2 => 251,
      _ => 354,
    };
    for (final m in conv.moves) {
      if (m > maxMove) {
        problems.add(
          'this game has no move ${moveName(m).isEmpty ? m : moveName(m)}',
        );
      }
    }
    if (to == 3 && conv.ability > 77) {
      problems.add('this game has no ability ${conv.ability}');
    }
    if (problems.isNotEmpty) {
      return (null, "$name can't go to $gameName: ${problems.join(', ')}");
    }
    return (conv, why);
  }

  // PKHeX's PK1.ConvertToPK2 (the Time Capsule from Gen 1 to Gen 2).
  static (Mon?, String) _pk1ToPk2(Mon pk1) {
    final pk2 = Mon.blankGb(2);
    pk2.data[0] = pk1.species;
    pk2.data.setRange(1, 1 + 0x1A, pk1.data, 7);
    pk2.ot.setAll(0, pk1.ot);
    pk2.nick.setAll(0, pk1.nick);
    pk2.data[1] = gen1CatchRateToGen2Item(pk1.catchRate);
    pk2.data[0x1B] = 70; // base friendship in Gen 2
    pk2.data[0x1F] = pk1.level;
    return (pk2, '');
  }

  // PKHeX's PK2.ConvertToPK1, refusing what the Time Capsule refuses.
  static (Mon?, String) _pk2ToPk1(Mon pk2) {
    final name = speciesName(pk2.species);
    if (pk2.isEgg) {
      return (null, "an Egg can't go through the Time Capsule to a Gen 1 game");
    }
    if (!isCatchRateHeldItem(pk2.heldItem)) {
      return (
        null,
        "$name holds ${pk2.itemName}, which can't go to a Gen 1 game",
      );
    }
    final pk1 = Mon.blankGb(1);
    pk1.data.setRange(7, 7 + 0x1A, pk2.data, 1);
    pk1.data[0] = nationalToGen1(pk2.species);
    final (t1, t2) = gen1TypesOf(pk2.species);
    pk1.data[5] = t1;
    pk1.data[6] = t2;
    final lvl = pk2.data[0x1F];
    int hp, level;
    if (lvl == 0) {
      hp = 5; // PKHeX regenerates it with level 0: always 5
      level = pk2.level;
    } else {
      hp = (pk2.data[0x22] << 8) | pk2.data[0x23];
      level = lvl;
    }
    pk1.data[1] = hp >> 8;
    pk1.data[2] = hp & 0xFF;
    pk1.data[0x21] = level;
    pk1.data[3] = level;
    pk1.ot.setAll(0, pk2.ot);
    pk1.nick.setAll(0, pk2.nick);
    // PKHeX's ClearInvalidMoves: Gen 2 moves are forgotten, the rest move up.
    final forgot = [
      for (final m in pk2.moves)
        if (m > 165) moveName(m),
    ];
    if (forgot.isNotEmpty) {
      final kept = <(int, int)>[
        for (var i = 0; i < 4; i++)
          if (pk1.data[8 + i] != 0 && pk1.data[8 + i] <= 165)
            (pk1.data[8 + i], pk1.data[0x1D + i]),
      ];
      if (forgot.length == 4) {
        final ups = pk1.data[0x1D] >> 6;
        kept.add((1, (ups << 6) | (35 + ups * 7))); // Pound
      }
      for (var i = 0; i < 4; i++) {
        pk1.data[8 + i] = i < kept.length ? kept[i].$1 : 0;
        pk1.data[0x1D + i] = i < kept.length ? kept[i].$2 : 0;
      }
    }
    return (pk1, forgot.isEmpty ? '' : 'forgot ${forgot.join(', ')}');
  }
}
