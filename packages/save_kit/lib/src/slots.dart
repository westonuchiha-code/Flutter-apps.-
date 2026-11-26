/// Which card is in which of the console's slots, and swapping them (Put in
/// console / Take out). Ported from the PC's CardSlots.gd.
///
/// The emulators read their cards when a game starts and keep them open
/// until it ends, and a Dreamcast save state carries the whole VMU, so cards
/// only change while the emulator is closed (CardStore asks CardOwners).
///
/// * Dreamcast (Flycast in RetroArch): fixed files, vmu_save_A1.bin to D1
///   (and slot 2 when Flycast's options make it a VMU). A card goes in by
///   its bytes. When another takes its place, what's on it goes back to its
///   own file.
/// * PS2 (PCSX2): its settings name the file in each slot, so a card goes in
///   by name. A card from outside PCSX2's memcards folder is copied in
///   first; the original stays as it was.
/// * PS1 (DuckStation): settings.ini [MemoryCards] CardNType / CardNPath. A
///   card goes in by setting that slot to Shared and pointing it at the
///   card's file, so every game reads and writes that one card (instead of a
///   card per game). Taking it out sets the slot to None.
/// * GameCube (Dolphin): Dolphin.ini [Core] SlotA / SlotB (1 = a card file,
///   8 = a folder of saves per game, 255 = nothing) and MemcardAPath /
///   MemcardBPath. Same idea as PS1: a card goes in by name.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'model.dart';
import 'store.dart';

/// What [CardSlots] needs from the card formats (the Dreamcast, PS1, PS2
/// and GameCube writers), handed in so this file depends on none of them.
/// The app wires it up as, for example:
///
/// ```dart
/// SlotFormats(
///   vmuBlank: VmuWriter.blank,
///   vmuCheck: VmuWriter.check,
///   vmuSaves: (b) => VmuWriter.saves(b).length,
///   ps1Saves: (b) => Ps1Writer.saves(b).length,
///   ps2Check: Ps2Writer.check,
///   ps2Saves: (b) => Ps2Writer.saveNames(b).length,
///   gcCheck: GcWriter.check,
///   gcSaves: (b) => GcWriter.saves(b).length,
/// )
/// ```
class SlotFormats {
  const SlotFormats({
    required this.vmuBlank,
    required this.vmuCheck,
    required this.vmuSaves,
    required this.ps1Saves,
    required this.ps2Check,
    required this.ps2Saves,
    required this.gcCheck,
    required this.gcSaves,
  });

  /// A newly formatted VMU.
  final Uint8List Function() vmuBlank;

  /// '' = a whole, working card; else what's wrong.
  final String Function(Uint8List) vmuCheck, ps2Check, gcCheck;

  /// How many saves are on a card.
  final int Function(Uint8List) vmuSaves, ps1Saves, ps2Saves, gcSaves;
}

/// One of a console's slots.
class CardSlot {
  const CardSlot({
    required this.id,
    required this.system,
    required this.short,
    required this.label,
    required this.path,
    required this.on,
    this.type = '',
  });

  /// "DC:A1", "PS2:1", "PS1:2", "GC:A".
  final String id;
  final String system;

  /// "A1", "slot 2", "slot A".
  final String short;

  /// "Controller 1, slot 1", "Slot 2".
  final String label;

  /// The card file that's in it (or would be).
  final String path;

  /// A card is in it.
  final bool on;

  /// PS1 / GameCube: the slot's setting as the emulator wrote it.
  final String type;
}

/// What's in a slot, for the picker.
class SlotDescription {
  const SlotDescription(this.slot, this.label, this.detail);
  final CardSlot slot;
  final String label, detail;
}

class CardSlots {
  /// [store] null = only for reading (tagging the cards on screen). The
  /// emulator folders: '' = that console has no slots here. [dolphinUser]
  /// is Dolphin's user folder when it isn't portable ('' = Documents/Dolphin
  /// Emulator). [windowsPaths] = card paths written into DuckStation's and
  /// Dolphin's settings use '\' (default: on Windows).
  CardSlots({
    required this.store,
    required this.recordFile,
    required this.formats,
    this.raRoot = '',
    this.pcsx2Dir = '',
    this.duckDir = '',
    this.dolphinDir = '',
    this.dolphinUser = '',
    bool? windowsPaths,
  }) : windowsPaths = windowsPaths ?? Platform.isWindows {
    reload();
  }

  static const systems = ['DC', 'PS2', 'PS1', 'GC'];

  /// Beside the VMUs: your own cards that were taken out.
  static const shelf = 'Out of the console';
  static const ports = 'ABCD';
  static const optPrefixes = ['reicast_', 'flycast_'];
  static const ps2Slots = 2, ps1Slots = 2;
  static const ps1CardBytes = 131072, vmuBytes = 131072;
  static const gcSlots = 'AB';
  static const gcCard = '1', gcFolder = '8', gcNone = '255';
  static const slotTags = {
    'DC': 'IN THE DREAMCAST, %s',
    'PS2': 'IN PCSX2 %s',
    'PS1': 'IN DUCKSTATION %s',
    'GC': 'IN DOLPHIN %s',
  };
  static const unreadable =
      "The list of which card is in which slot can't be read, so no card was moved";
  static const _unsaved =
      "The card went in, but the list of slots couldn't be saved: taking it out will keep it as a new card";

  final CardStore? store;
  final SlotFormats formats;
  final bool windowsPaths;

  /// The slot record (JSON): "DC:A1" -> the file of the card that's in it.
  String recordFile;

  /// RetroArch's folder ('' = no Dreamcast slots).
  String raRoot;

  /// Documents/PCSX2 ('' = no PS2 slots).
  String pcsx2Dir;

  /// DuckStation's folder, where its settings.ini is ('' = no PS1 slots).
  String duckDir;

  /// Dolphin's folder ('' = no GameCube slots).
  String dolphinDir;
  String dolphinUser;

  String error = '';
  Map<String, String> _record = {};

  void reload() {
    error = '';
    _record = {};
    final f = File(recordFile);
    if (!f.existsSync()) return;
    Object? got;
    try {
      got = jsonDecode(_text(recordFile));
    } catch (_) {
      got = null;
    }
    if (got is Map) {
      _record = {for (final e in got.entries) '${e.key}': '${e.value}'};
    } else {
      error = unreadable;
    }
  }

  String dcDir() => raRoot.isNotEmpty ? p.join(raRoot, 'system', 'dc') : '';

  String flycastOptions() => raRoot.isNotEmpty
      ? p.join(raRoot, 'config', 'Flycast', 'Flycast.opt')
      : '';

  String pcsx2Ini() =>
      pcsx2Dir.isNotEmpty ? p.join(pcsx2Dir, 'inis', 'PCSX2.ini') : '';

  String pcsx2Cards() =>
      pcsx2Dir.isNotEmpty ? p.join(pcsx2Dir, 'memcards') : '';

  /// Dolphin's settings: User/Config next to the exe when it's portable,
  /// else its user folder (Documents/Dolphin Emulator).
  String dolphinIni() {
    if (dolphinDir.isEmpty) return '';
    if (File(p.join(dolphinDir, 'portable.txt')).existsSync() ||
        !_isAbsolute(dolphinDir)) {
      return p.join(dolphinDir, 'User', 'Config', 'Dolphin.ini');
    }
    var user = dolphinUser;
    if (user.isEmpty) {
      final home =
          Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'] ??
          '';
      user = p.join(home, 'Documents', 'Dolphin Emulator');
    }
    return p.join(user, 'Config', 'Dolphin.ini');
  }

  String duckIni() => duckDir.isNotEmpty ? p.join(duckDir, 'settings.ini') : '';

  /// DuckStation's memcards folder: [Folders] MemoryCards, relative to its
  /// own folder unless it's a full path.
  String duckCards() {
    if (duckDir.isEmpty) return '';
    final ini = duckIni();
    var dir = File(ini).existsSync()
        ? iniGet(_text(ini), 'Folders', 'MemoryCards')
        : '';
    if (dir.isEmpty) dir = 'memcards';
    dir = dir.replaceAll(r'\', '/');
    return _isAbsolute(dir) ? dir : p.join(duckDir, dir);
  }

  // ---- what's where -----------------------------------------------------

  /// In the console's order.
  List<CardSlot> slots(String system) => switch (system) {
    'DC' => _dcSlots(),
    'PS2' => _ps2Slots(),
    'PS1' => _ps1Slots(),
    'GC' => _gcSlots(),
    _ => [],
  };

  List<CardSlot> allSlots() => [for (final s in systems) ...slots(s)];

  CardSlot? findSlot(String id) {
    for (final s in allSlots()) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Why that console's cards can't be swapped here, '' = they can.
  String whyNot(String system) {
    if (!systems.contains(system)) {
      return "Only PS1, PS2, Dreamcast and GameCube cards go into a console slot here: the other consoles' emulators keep a card per game";
    }
    if (system == 'DC') {
      if (raRoot.isEmpty || !Directory(dcDir()).existsSync()) {
        return "RetroArch's Dreamcast folder wasn't found, so there are no Dreamcast slots";
      }
      if (_perGameVmus()) {
        return 'Flycast is set to keep separate VMUs for every game (Per-Game VMUs), so there are no shared slots';
      }
    }
    if (system == 'PS2' && !_exists(pcsx2Ini())) {
      return "PCSX2's settings weren't found, so there are no PS2 slots";
    }
    if (system == 'PS1' && !_exists(duckIni())) {
      return "DuckStation's settings weren't found, so there are no PS1 slots";
    }
    if (system == 'GC' && !_exists(dolphinIni())) {
      return "Dolphin's settings weren't found, so there are no GameCube slots";
    }
    return '';
  }

  /// The slot a card's file is in, or that a Dreamcast card which went into
  /// one came from. null = neither.
  CardSlot? slotOf(String path) {
    final key = same(path);
    for (final s in allSlots()) {
      if (s.on && same(s.path) == key) return s;
      if (s.system == 'DC' && same(_record[s.id] ?? '') == key) return s;
    }
    return null;
  }

  String cameFrom(String slotId) => _record[slotId] ?? '';

  /// After the cards are read: the ones in a slot get tagged (slot cards
  /// first, in the console's order), and a Dreamcast card that went into a
  /// slot is shown there under its own name. Its file outside is left out:
  /// it's an old copy until the card comes back out.
  void dress(List<MemoryCard> cards, List<CardSave> saves) {
    var order = 0;
    final hidden = <MemoryCard>{};
    final byPath = <String, MemoryCard>{for (final c in cards) same(c.path): c};
    for (final s in allSlots()) {
      order++;
      if (!s.on) continue;
      final c = byPath[same(s.path)];
      if (c == null) continue;
      c.inSlot = slotTags[s.system]!.replaceFirst('%s', s.short.toUpperCase());
      c.slotOrder = order;
      final home = cameFrom(s.id);
      if (home.isNotEmpty) {
        final outside = byPath[same(home)];
        c.home = home;
        if (outside != null) {
          c.name = '${outside.name} (${s.short})';
          hidden.add(outside);
        }
      }
    }
    if (hidden.isEmpty) return;
    cards.removeWhere(hidden.contains);
    saves.removeWhere((s) => hidden.contains(s.card));
  }

  /// What's in each slot, for the picker.
  List<SlotDescription> describe(String system) {
    final out = <SlotDescription>[];
    for (final s in slots(system)) {
      var detail = 'Empty';
      if (system == 'PS2' && !s.on) {
        detail = 'Switched off in PCSX2: putting a card in switches it on';
      } else if (system == 'PS1' && !s.on) {
        detail = 'No card in it';
        if (s.type.startsWith('PerGame')) {
          detail =
              'Each game keeps its own card here now: put a card in and every game uses it';
        }
      } else if (system == 'GC' && !s.on) {
        detail = 'No card in it';
        if (s.type == gcFolder) {
          detail =
              'Dolphin keeps a folder of saves per game here now: put a card in and every game uses it';
        }
      } else if (_exists(s.path)) {
        final home = cameFrom(s.id);
        final who = cardName(
          p.basenameWithoutExtension(home.isNotEmpty ? home : s.path),
        );
        detail =
            'Now: $who, ${_countText(system, File(s.path).readAsBytesSync())}';
      }
      out.add(SlotDescription(s, '${s.label} (${s.short})', detail));
    }
    return out;
  }

  // ---- swapping ---------------------------------------------------------

  /// '' = it's in. Whatever was in that slot comes out first, nothing lost.
  String putIn(String slotId, MemoryCard? card) {
    final no = _readyToWrite();
    if (no.isNotEmpty) return no;
    final slot = findSlot(slotId);
    if (slot == null) return "That slot isn't there any more";
    if (card == null || card.system != slot.system) {
      return 'Only a ${CardSystems.info[slot.system]!['name']} card goes in there';
    }
    return switch (slot.system) {
      'DC' => _dcPut(slot, card),
      'PS1' => _ps1Put(slot, card),
      'GC' => _gcPut(slot, card),
      _ => _ps2Put(slot, card),
    };
  }

  /// '' = done. A Dreamcast slot gets an empty card; a PS2 slot is switched
  /// off; a PS1 or GameCube slot holds nothing.
  String takeOut(String slotId) {
    var no = _readyToWrite();
    if (no.isNotEmpty) return no;
    final slot = findSlot(slotId);
    if (slot == null) return "That slot isn't there any more";
    final n = slot.id.split(':')[1];
    if (slot.system == 'PS2') {
      if (!slot.on) return '${slot.label} is empty already';
      return _ps2Set(int.parse(n), '', false);
    }
    if (slot.system == 'PS1') {
      if (!slot.on) return '${slot.label} has no card in it already';
      return _ps1Set(int.parse(n), '');
    }
    if (slot.system == 'GC') {
      if (!slot.on) return '${slot.label} has no card in it already';
      return _gcSet(n, '');
    }
    final path = slot.path;
    final now = _exists(path) ? File(path).readAsBytesSync() : Uint8List(0);
    if (now.isEmpty ||
        (cameFrom(slot.id).isEmpty && formats.vmuSaves(now) == 0)) {
      return '${slot.short} has an empty card in it already';
    }
    no = _dcOut(slot, now);
    if (no.isNotEmpty) return no;
    no = store!.change(path, now, formats.vmuBlank(), 'replaced', _vmuCheck);
    if (no.isNotEmpty) return no;
    _record.remove(slot.id);
    return _saveRecord();
  }

  // ---- Dreamcast --------------------------------------------------------

  List<CardSlot> _dcSlots() {
    final out = <CardSlot>[];
    if (raRoot.isEmpty || !Directory(dcDir()).existsSync() || _perGameVmus()) {
      return out;
    }
    final opt = _options();
    for (var port = 0; port < ports.length; port++) {
      for (final n in const [1, 2]) {
        final kind = _option(
          opt,
          'device_port${port + 1}_slot$n',
          n == 1 ? 'VMU' : 'Purupuru',
        );
        if (kind != 'VMU') continue;
        final short = '${ports[port]}$n';
        out.add(
          CardSlot(
            id: 'DC:$short',
            system: 'DC',
            short: short,
            label: 'Controller ${port + 1}, slot $n',
            path: p.join(dcDir(), 'vmu_save_$short.bin'),
            on: true,
          ),
        );
      }
    }
    return out;
  }

  bool _perGameVmus() {
    final v = _option(_options(), 'per_content_vmus', 'disabled');
    return v != 'disabled' && v.isNotEmpty;
  }

  Map<String, String> _options() {
    final out = <String, String>{};
    final file = flycastOptions();
    if (!_exists(file)) return out;
    for (final line in _text(file).split('\n')) {
      final at = line.indexOf('=');
      if (at > 0) {
        var v = line.substring(at + 1).trim();
        if (v.startsWith('"')) v = v.substring(1);
        if (v.endsWith('"')) v = v.substring(0, v.length - 1);
        out[line.substring(0, at).trim()] = v;
      }
    }
    return out;
  }

  static String _option(Map<String, String> opt, String name, String fallback) {
    for (final prefix in optPrefixes) {
      final v = opt[prefix + name];
      if (v != null) return v;
    }
    return fallback;
  }

  String _dcPut(CardSlot slot, MemoryCard card) {
    if (card.isFolder || card.offset != 0 || card.gzip) {
      return "That card can't go in: it isn't a plain VMU file";
    }
    final incoming = _exists(card.path)
        ? File(card.path).readAsBytesSync()
        : Uint8List(0);
    if (incoming.length != vmuBytes || formats.vmuCheck(incoming).isNotEmpty) {
      return "That card can't go in: it isn't a whole, working VMU";
    }
    final other = slotOf(card.path);
    if (other != null) {
      if (other.id == slot.id) return 'That card is in ${slot.short} already';
      return _dcSwap(slot, other);
    }
    final path = slot.path;
    if (!_exists(path)) {
      final made = store!.create(path, incoming, _vmuCheck);
      if (made.isNotEmpty) return made;
    } else {
      final now = File(path).readAsBytesSync();
      var no = _dcOut(slot, now);
      if (no.isNotEmpty) return no;
      no = store!.change(path, now, incoming, 'replaced', _vmuCheck);
      if (no.isNotEmpty) return no;
    }
    _record[slot.id] = card.path;
    return _saveRecord();
  }

  /// What's in the slot now goes home: back to the card it came from, or,
  /// for the console's own card with saves on it, to a file of its own
  /// under "Out of the console". An empty card has nothing to keep (it's
  /// backed up when it's replaced anyway).
  String _dcOut(CardSlot slot, Uint8List now) {
    final home = cameFrom(slot.id);
    if (home.isNotEmpty) {
      if (_exists(home)) {
        return store!.change(
          home,
          File(home).readAsBytesSync(),
          now,
          'replaced',
          _vmuCheck,
        );
      }
      return store!.create(home, now, _vmuCheck);
    }
    if (formats.vmuSaves(now) == 0) return '';
    final dir = p.join(dcDir(), shelf);
    final no = store!.safety.refusal(p.join(dir, 'x'));
    if (no.isNotEmpty) return no;
    try {
      Directory(dir).createSync(recursive: true);
    } catch (_) {
      return "Couldn't make the folder for cards taken out, so nothing was moved";
    }
    return store!.create(
      freePath(p.join(dir, 'Your card from ${slot.short}'), 'bin'),
      now,
      _vmuCheck,
    );
  }

  /// Two slots trade cards. If the second write fails, the first is put
  /// back.
  String _dcSwap(CardSlot a, CardSlot b) {
    final pa = a.path, pb = b.path;
    if (!_exists(pa) || !_exists(pb)) {
      return "One of those VMUs isn't there any more";
    }
    final ba = File(pa).readAsBytesSync();
    final bb = File(pb).readAsBytesSync();
    var no = store!.change(pa, ba, bb, 'replaced', _vmuCheck);
    if (no.isNotEmpty) return no;
    no = store!.change(pb, bb, ba, 'replaced', _vmuCheck);
    if (no.isNotEmpty) {
      final undo = store!.change(pa, bb, ba, 'replaced', _vmuCheck);
      return undo.isEmpty
          ? no
          : '$no. Putting ${a.short} back failed too: Restore card brings it back';
    }
    final ra = _record.remove(a.id);
    final rb = _record.remove(b.id);
    if (rb != null) _record[a.id] = rb;
    if (ra != null) _record[b.id] = ra;
    return _saveRecord();
  }

  String _vmuCheck(Uint8List b) =>
      b.length != vmuBytes ? 'not a whole VMU' : formats.vmuCheck(b);

  // ---- PS2 --------------------------------------------------------------

  List<CardSlot> _ps2Slots() {
    final out = <CardSlot>[];
    final ini = pcsx2Ini();
    if (!_exists(ini)) return out;
    final text = _text(ini);
    for (var n = 1; n <= ps2Slots; n++) {
      final file = iniGet(text, 'MemoryCards', 'Slot${n}_Filename');
      final on =
          iniGet(text, 'MemoryCards', 'Slot${n}_Enable').toLowerCase() ==
              'true' &&
          file.isNotEmpty;
      out.add(
        CardSlot(
          id: 'PS2:$n',
          system: 'PS2',
          short: 'slot $n',
          label: 'Slot $n',
          path: file.isNotEmpty ? p.join(pcsx2Cards(), file) : '',
          on: on,
        ),
      );
    }
    return out;
  }

  String _ps2Put(CardSlot slot, MemoryCard card) {
    if (card.isFolder) {
      return "PCSX2 folder cards are set in PCSX2's own settings";
    }
    if (card.gzip || card.offset != 0) {
      return "That card can't go in: it isn't a plain PS2 card file";
    }
    final n = int.parse(slot.id.split(':')[1]);
    var file = p.basename(card.path);
    if (same(p.dirname(card.path)) != same(pcsx2Cards())) {
      final bytes = _exists(card.path)
          ? File(card.path).readAsBytesSync()
          : Uint8List(0);
      String check(Uint8List b) =>
          b.isEmpty ? 'empty' : (card.unformatted ? '' : formats.ps2Check(b));
      final dest = freePath(p.join(pcsx2Cards(), fileSafe(card.name)), 'ps2');
      final made = store!.create(dest, bytes, check);
      if (made.isNotEmpty) return made;
      file = p.basename(dest);
    } else if (slot.on && same(slot.path) == same(card.path)) {
      return 'That card is in ${slot.label} already';
    }
    return _ps2Set(n, file, true);
  }

  /// One slot's file and switch. A card already in the other slot moves
  /// over to where this one's was.
  String _ps2Set(int n, String file, bool on) {
    final ini = pcsx2Ini();
    if (!_exists(ini)) return "PCSX2's settings weren't found";
    final was = File(ini).readAsBytesSync();
    var text = utf8.decode(was, allowMalformed: true);
    final mine = iniGet(text, 'MemoryCards', 'Slot${n}_Filename');
    if (on) {
      for (var other = 1; other <= ps2Slots; other++) {
        if (other != n &&
            iniGet(
                  text,
                  'MemoryCards',
                  'Slot${other}_Filename',
                ).toLowerCase() ==
                file.toLowerCase()) {
          text = iniSet(text, 'MemoryCards', 'Slot${other}_Filename', mine);
        }
      }
      text = iniSet(text, 'MemoryCards', 'Slot${n}_Filename', file);
    }
    text = iniSet(
      text,
      'MemoryCards',
      'Slot${n}_Enable',
      on ? 'true' : 'false',
    );
    return _changeIni(
      ini,
      was,
      text,
      '[MemoryCards]',
      "PCSX2's settings came out damaged",
    );
  }

  // ---- PS1 --------------------------------------------------------------

  List<CardSlot> _ps1Slots() {
    final out = <CardSlot>[];
    final ini = duckIni();
    if (!_exists(ini)) return out;
    final text = _text(ini);
    for (var n = 1; n <= ps1Slots; n++) {
      final type = iniGet(text, 'MemoryCards', 'Card${n}Type');
      var path = iniGet(
        text,
        'MemoryCards',
        'Card${n}Path',
      ).replaceAll(r'\', '/');
      if (path.isEmpty) {
        path = p.join(duckCards(), 'shared_card_$n.mcd');
      } else if (!_isAbsolute(path)) {
        path = p.join(duckCards(), path);
      }
      out.add(
        CardSlot(
          id: 'PS1:$n',
          system: 'PS1',
          short: 'slot $n',
          label: 'Slot $n',
          path: path,
          on: type == 'Shared',
          type: type,
        ),
      );
    }
    return out;
  }

  String _ps1Put(CardSlot slot, MemoryCard card) {
    if (card.isFolder || card.gzip || card.offset != 0) {
      return "That card can't go in: it isn't a plain PS1 card file";
    }
    if (!_exists(card.path) || File(card.path).lengthSync() != ps1CardBytes) {
      return "That card can't go in: DuckStation wants a plain 128 KB card file";
    }
    if (slot.on && same(slot.path) == same(card.path)) {
      return 'That card is in ${slot.label} already';
    }
    return _ps1Set(int.parse(slot.id.split(':')[1]), card.path);
  }

  /// One slot's card: a file (Shared, so every game uses it) or '' (None).
  /// A card already in the other slot moves over to where this one's was.
  String _ps1Set(int n, String file) {
    final ini = duckIni();
    if (!_exists(ini)) return "DuckStation's settings weren't found";
    final was = File(ini).readAsBytesSync();
    var text = utf8.decode(was, allowMalformed: true);
    if (file.isNotEmpty) {
      final mine = iniGet(text, 'MemoryCards', 'Card${n}Path');
      final mineOn =
          iniGet(text, 'MemoryCards', 'Card${n}Type') == 'Shared' &&
          mine.isNotEmpty;
      for (var other = 1; other <= ps1Slots; other++) {
        final theirs = iniGet(text, 'MemoryCards', 'Card${other}Path');
        if (other != n &&
            same(theirs) == same(file) &&
            iniGet(text, 'MemoryCards', 'Card${other}Type') == 'Shared') {
          text = iniSet(text, 'MemoryCards', 'Card${other}Path', mine);
          text = iniSet(
            text,
            'MemoryCards',
            'Card${other}Type',
            mineOn ? 'Shared' : 'None',
          );
        }
      }
      text = iniSet(text, 'MemoryCards', 'Card${n}Path', _written(file));
    }
    text = iniSet(
      text,
      'MemoryCards',
      'Card${n}Type',
      file.isNotEmpty ? 'Shared' : 'None',
    );
    return _changeIni(
      ini,
      was,
      text,
      '[MemoryCards]',
      "DuckStation's settings came out damaged",
    );
  }

  // ---- GameCube ---------------------------------------------------------

  List<CardSlot> _gcSlots() {
    final out = <CardSlot>[];
    final ini = dolphinIni();
    if (!_exists(ini)) return out;
    final text = _text(ini);
    for (final x in gcSlots.split('')) {
      var type = iniGet(text, 'Core', 'Slot$x');
      // Dolphin's own defaults.
      if (type.isEmpty) type = x == 'A' ? gcFolder : gcNone;
      var path = iniGet(text, 'Core', 'Memcard${x}Path').replaceAll(r'\', '/');
      if (path.isEmpty) {
        path = p.join(p.dirname(p.dirname(ini)), 'GC', 'MemoryCard$x.USA.raw');
      }
      out.add(
        CardSlot(
          id: 'GC:$x',
          system: 'GC',
          short: 'slot $x',
          label: 'Slot $x',
          path: path,
          on: type == gcCard,
          type: type,
        ),
      );
    }
    return out;
  }

  String _gcPut(CardSlot slot, MemoryCard card) {
    if (card.isFolder || card.gzip || card.offset != 0) {
      return "That card can't go in: it isn't a plain GameCube card file (.raw)";
    }
    if (!_exists(card.path) ||
        formats.gcCheck(File(card.path).readAsBytesSync()).isNotEmpty) {
      return "That card can't go in: it isn't a whole, working GameCube card";
    }
    if (slot.on && same(slot.path) == same(card.path)) {
      return 'That card is in ${slot.label} already';
    }
    return _gcSet(slot.id.split(':')[1], card.path);
  }

  /// One slot's card: a file, or '' (nothing). A card already in the other
  /// slot moves over to where this one's was.
  String _gcSet(String x, String file) {
    final ini = dolphinIni();
    if (!_exists(ini)) return "Dolphin's settings weren't found";
    final was = File(ini).readAsBytesSync();
    var text = utf8.decode(was, allowMalformed: true);
    if (file.isNotEmpty) {
      final mine = iniGet(text, 'Core', 'Memcard${x}Path');
      final mineOn =
          iniGet(text, 'Core', 'Slot$x') == gcCard && mine.isNotEmpty;
      for (final other in gcSlots.split('')) {
        final theirs = iniGet(text, 'Core', 'Memcard${other}Path');
        if (other != x &&
            same(theirs) == same(file) &&
            iniGet(text, 'Core', 'Slot$other') == gcCard) {
          text = iniSet(text, 'Core', 'Memcard${other}Path', mine);
          text = iniSet(text, 'Core', 'Slot$other', mineOn ? gcCard : gcNone);
        }
      }
      text = iniSet(text, 'Core', 'Memcard${x}Path', _written(file));
    }
    text = iniSet(text, 'Core', 'Slot$x', file.isNotEmpty ? gcCard : gcNone);
    return _changeIni(
      ini,
      was,
      text,
      '[Core]',
      "Dolphin's settings came out damaged",
    );
  }

  // ---- small things -----------------------------------------------------

  String _readyToWrite() {
    final s = store;
    if (s == null) return 'Nothing can be moved from here';
    // A tool only ever keeps its list with the copies.
    final no = s.safety.refusal(recordFile);
    if (no.isNotEmpty) return no;
    reload();
    return error;
  }

  String _saveRecord() {
    final temp = '$recordFile.new';
    try {
      Directory(p.dirname(recordFile)).createSync(recursive: true);
      File(
        temp,
      ).writeAsStringSync(const JsonEncoder.withIndent('\t').convert(_record));
      final f = File(recordFile);
      if (f.existsSync()) f.deleteSync();
      File(temp).renameSync(recordFile);
    } catch (_) {
      return _unsaved;
    }
    return '';
  }

  /// A settings file changes through the store like a card: backed up,
  /// checked (it still has its [section]), swapped.
  String _changeIni(
    String ini,
    Uint8List was,
    String text,
    String section,
    String damaged,
  ) => store!.change(
    ini,
    was,
    Uint8List.fromList(utf8.encode(text)),
    'slot change',
    (b) =>
        utf8.decode(b, allowMalformed: true).contains(section) ? '' : damaged,
  );

  /// A card's path as the emulator's settings spell it.
  String _written(String path) =>
      windowsPaths ? path.replaceAll('/', r'\') : path;

  String _countText(String system, Uint8List bytes) {
    final n = switch (system) {
      'DC' => formats.vmuSaves(bytes),
      'PS1' => formats.ps1Saves(bytes),
      'GC' => formats.gcSaves(bytes),
      _ => formats.ps2Saves(bytes),
    };
    return n == 0 ? 'empty' : (n == 1 ? '1 save' : '$n saves');
  }

  /// One spelling per file: '/', no '..', lower case ('' stays '').
  static String same(String path) => path.isEmpty
      ? ''
      : p.posix.normalize(path.replaceAll(r'\', '/')).toLowerCase();

  static bool _isAbsolute(String path) =>
      p.posix.isAbsolute(path) || p.windows.isAbsolute(path);

  static bool _exists(String path) =>
      path.isNotEmpty && File(path).existsSync();

  static String _text(String path) =>
      utf8.decode(File(path).readAsBytesSync(), allowMalformed: true);

  /// "base.ext", or "base 2.ext", "base 3.ext"... whichever isn't taken.
  static String freePath(String base, String ext) {
    var path = '$base.$ext';
    var n = 1;
    while (File(path).existsSync()) {
      n++;
      path = '$base $n.$ext';
    }
    return path;
  }

  /// A name that's safe as a file name everywhere.
  static String fileSafe(String id) {
    final out = StringBuffer();
    for (final c in id.split('')) {
      final fine = RegExp(r'^[a-zA-Z0-9 \-_#()]$').hasMatch(c);
      out.write(fine ? c : '_');
    }
    var s = out.toString().trim();
    if (s.length > 80) s = s.substring(0, 80);
    final reserved = RegExp(
      r'^(con|prn|aux|nul|com\d|lpt\d)$',
      caseSensitive: false,
    ).hasMatch(s);
    return s.isEmpty || reserved ? 'save $s' : s;
  }

  /// A card's name from its file name (without extension): the emulators'
  /// own cards get their slot names.
  static String cardName(String file) {
    final pcsx2 = RegExp(
      r'^mcd0*(\d+)$',
      caseSensitive: false,
    ).firstMatch(file);
    if (pcsx2 != null) return 'PS2 Card ${pcsx2.group(1)}';
    final shared = RegExp(
      r'^shared_card_(\d+)$',
      caseSensitive: false,
    ).firstMatch(file);
    if (shared != null) return 'PS1 Card ${shared.group(1)}';
    final vmu = RegExp(
      r'^vmu_save_([a-d][12])$',
      caseSensitive: false,
    ).firstMatch(file);
    if (vmu != null) return 'VMU ${vmu.group(1)!.toUpperCase()}';
    final gc = RegExp(
      r'^memorycard([ab])\.(\w+)$',
      caseSensitive: false,
    ).firstMatch(file);
    if (gc != null) {
      return 'GC Card ${gc.group(1)!.toUpperCase()} (${gc.group(2)!.toUpperCase()})';
    }
    var s = file.replaceFirst(RegExp(r'_\d$'), '');
    s = s.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
    return s.isNotEmpty ? s : file;
  }

  /// key = value lines inside [section]. '' = not there.
  static String iniGet(String text, String section, String key) {
    var inside = false;
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.startsWith('[')) {
        inside = line == '[$section]';
      } else if (inside &&
          line.contains('=') &&
          line.split('=')[0].trim() == key) {
        return line.substring(line.indexOf('=') + 1).trim();
      }
    }
    return '';
  }

  /// Changes (or adds) one line, leaving every other byte as it was, line
  /// endings included.
  static String iniSet(String text, String section, String key, String value) {
    final lines = text.split('\n');
    var inside = false;
    var last = -1;
    final eol = text.contains('\r\n') ? '\r' : '';
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.startsWith('[')) {
        if (inside) break;
        inside = line == '[$section]';
        if (inside) last = i;
      } else if (inside) {
        if (line.contains('=') && line.split('=')[0].trim() == key) {
          lines[i] = '$key = $value$eol';
          return lines.join('\n');
        }
        if (line.isNotEmpty) last = i;
      }
    }
    if (last < 0) {
      final tail = text.endsWith('\n') || text.isEmpty ? '' : '\n';
      return '$text$tail[$section]$eol\n$key = $value$eol\n';
    }
    lines.insert(last + 1, '$key = $value$eol');
    return lines.join('\n');
  }
}
