// Pokéville's screen logic, ported from the PC's PokeBoxScreen.gd: the
// cursor, LB / RB boxes, holding a Pokémon (pick up, put down, swap), Check
// (status, moves) with the Box Dex, and X: the Games list. The grid shows
// Pokéville or one game save (its party, then its boxes: 20 slots, 5 x 4, on
// Game Boy; 30 on GBA). A Pokémon moves between a game's boxes and
// Pokéville, inside a game, or from one game to another; those change the
// game's save (see games.dart for the safety order) and play the transfer.
// The party is shown (and its Pokémon renamed or given items) but not moved,
// as on the PC. Check's A opens the edit menu: Nickname (an on-screen
// keyboard) and Held item, for Pokémon in Pokéville (their mons/ file) and
// in a game save. Pure Dart: the widgets only draw it and feed it buttons.
//
// Every change is written at once (atomically). If box.json or a game save
// changed on disk since it was read (a sync came in), it is read again and
// the move is refused with a notice, rather than overwriting it.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:poke_saves/poke_saves.dart' as ps;

import 'folder.dart';
import 'games.dart';
import 'guard.dart';
import 'store.dart';
import 'transfer.dart';

enum PokeView { box, check }

/// A Pokémon being carried (picked up from [box], [slot] of Pokéville, or
/// of the game save at [save]).
class Held {
  const Held(
    this.box,
    this.slot,
    this.file,
    this.mon, {
    this.save = '',
    this.saveBytes,
    this.where = '',
  });

  final int box;
  final int slot;

  /// Pokéville: its box.json `file` ('' from a game).
  final String file;
  final Mon mon;

  /// The game save it came from ('' = Pokéville).
  final String save;

  /// That save's bytes when it was picked up (it must still be them).
  final Uint8List? saveBytes;

  /// "Box 2", "Gold BOX 3".
  final String where;

  bool get fromGame => save.isNotEmpty;
}

/// A row of the X menu (the Games list).
class MenuRow {
  const MenuRow(
    this.title,
    this.detail, {
    this.source,
    this.chip = '',
    this.enabled = true,
  });

  final String title;
  final String detail;

  /// What it shows: -1 Pokéville, else the game ([PokevilleController.
  /// games]' index); null: a row that isn't one.
  final int? source;

  /// gb / gbc / gba ('' for Pokéville and notes).
  final String chip;
  final bool enabled;
}

/// Where a host's Pokémon game saves are.
class PokeGames {
  const PokeGames(this.roots, {this.backups});

  /// Folders searched (recursively) for `.srm` / `.sav` saves.
  final List<String> roots;

  /// Where saves are copied before a change; null: `save backups` in
  /// Pokéville (as on the PC; Cross-Save leaves it out).
  final String? backups;
}

/// Things the PC does with its helper (PKHeX), which this side leaves out.
abstract final class OnThePc {
  static const games =
      'Moving Pokémon in and out of your games happens on the PC (it needs PKHeX)';

  /// Pokémon of newer games (pk4 and up) in Pokéville.
  static String edit(String format) =>
      '${format.isEmpty ? 'These' : format.toUpperCase()} Pokémon are '
      'changed on the PC (they need PKHeX)';
}

/// Check's A: the edit menu, the nickname keyboard, the item list.
enum EditStep { none, menu, keyboard, items }

/// The Pokémon being edited: in Pokéville ([file]) or in the game save
/// [save] (box [box], -1 = the party).
class EditTarget {
  const EditTarget({
    required this.box,
    required this.slot,
    required this.mon,
    this.file = '',
    this.save = '',
    this.saveBytes,
    this.game = '',
  });

  final int box;
  final int slot;
  final Mon mon;
  final String file;
  final String save;
  final Uint8List? saveBytes;

  /// "Gold" ('' = Pokéville).
  final String game;

  bool get inGame => save.isNotEmpty;

  /// 1, 2 or 3 (the file type: pk1 / pk2 / pk3).
  int get format => formatNumber(mon.format);

  EditTarget withMon(Mon m) => EditTarget(
    box: box,
    slot: slot,
    mon: m,
    file: file,
    save: save,
    saveBytes: saveBytes,
    game: game,
  );
}

/// 1, 2 or 3 for "pk1" / "pk2" / "pk3"; 0 for anything else.
int formatNumber(String format) => switch (format.toLowerCase()) {
  'pk1' => 1,
  'pk2' => 2,
  'pk3' => 3,
  _ => 0,
};

class PokevilleController extends ChangeNotifier {
  PokevilleController(
    this.folder, {
    this.games,
    SaveGuard? guard,
    this.animate = true,
  }) : guard = guard ?? SaveGuard.forPlatform();

  static const dexAll = 1025;
  static const dexPer = 60; // 10 x 6 (6 x 10 on a phone)

  final PokevilleFolder folder;

  /// The host's game saves (null: no games here; the menu says "on the PC").
  final PokeGames? games;

  /// Emulator safety before a game save changes.
  final SaveGuard guard;

  /// Play the transfer (tests: off, so moves finish at once).
  final bool animate;

  BoxState? _state; // null: still reading
  String? _error;
  BoxData _data = PokeBoxStore.blank();
  int _page = 0;
  int _boxPage = 0; // where each was left
  int _gamePage = 0;
  int _row = 0; // -1 = the banner (the box's name)
  int _col = 0;
  PokeView _view = PokeView.box;
  int _tab = 0; // Check: 0 status, 1 moves, 2 Box Dex (compact only)
  int _tabs = 2;
  int _dexPage = 0;
  Set<int> _owned = {};
  Held? _held;
  bool _menuOpen = false;
  int _menuI = 0;
  List<MenuRow> _menu = const [];
  String _notice = '';
  int _noticeId = 0;
  bool _busy = false;
  String _busyText = '';
  bool _disposed = false;

  // games
  List<GameSave> _saves = const [];
  bool _scanning = false;
  bool _scanned = false;
  int _source = -1; // -1 Pokéville, else _saves[_source]
  String _gamePath = ''; // the save _game was read from
  ps.PokeSave? _game;
  Uint8List? _gameBytes;
  List<List<Mon?>> _gameBoxes = const [];
  List<Mon> _gameParty = const [];
  ClosedQuestion? _asking;
  Transfer? _transfer;
  final _rnd = math.Random();

  // editing (Check's A)
  EditStep _edit = EditStep.none;
  int _editI = 0;
  EditTarget? _target;
  String _kbText = '';
  int _kbRow = 0;
  int _kbCol = 0;
  bool _kbLower = false;
  List<({int id, String name})> _items = const [];
  int _itemI = 0;
  int _typeId = 0;

  // ---- what there is to draw ------------------------------------------------

  /// null while reading, then missing / broken / ready.
  BoxState? get state => _state;
  String? get error => _error;
  BoxData get data => _data;
  int get page => _page;
  int get row => _row;
  int get col => _col;

  /// The grid: 6 x 5, or 5 x 4 for a Game Boy game's 20-slot boxes.
  int get cols => _gbGrid ? 5 : PokeBoxStore.cols;
  int get rows => _gbGrid ? 4 : PokeBoxStore.rows;
  int get slotCount => cols * rows;
  bool get _gbGrid {
    if (!onGame) return false;
    final g = _game;
    if (g != null && _gamePath == currentGame?.path) return g.boxSlots == 20;
    return (currentGame?.generation ?? 3) <= 2;
  }

  PokeView get view => _view;
  int get tab => _tab;
  int get dexPage => _dexPage;
  int get dexPages => (dexAll / dexPer).ceil();
  Set<int> get owned => _owned;
  Held? get held => _held;
  bool get holding => _held != null;
  bool get menuOpen => _menuOpen;
  int get menuIndex => _menuI;
  List<MenuRow> get menuRows => _menu;
  String get notice => _notice;

  /// Bumps with every new notice (the screen times each one out).
  int get noticeId => _noticeId;

  /// A read or write is under way: buttons wait.
  bool get busy => _busy;

  /// What it's doing ("Moving Pidgey…"), '' when nothing to say.
  String get busyText => _busy ? _busyText : '';

  /// The Pokémon game saves found (the Games list).
  List<GameSave> get gameSaves => _saves;
  bool get scanning => _scanning;

  /// The grid shows a game (else Pokéville).
  bool get onGame => _source >= 0;
  int get source => _source;
  GameSave? get currentGame =>
      onGame && _source < _saves.length ? _saves[_source] : null;

  /// The emulators-closed question showing now (null: none).
  ClosedQuestion? get asking => _asking;

  /// The transfer playing now (null: none).
  Transfer? get transfer => _transfer;
  bool get transferring => _transfer?.playing ?? false;

  /// A game's pages: the party first, then its boxes.
  int get pageCount =>
      onGame ? _gameBoxes.length + 1 : PokeBoxStore.boxCount(_data);

  /// A game's page [page] as its box number (-1: the party).
  static int gameBoxOf(int page) => page - 1;

  /// The grid shows a game's party (its first page).
  bool get onParty => onGame && _page == 0;

  /// Pokémon in what the grid shows (a game's boxes and party).
  int get total => onGame
      ? _gameBoxes.fold(0, (n, b) => n + b.where((m) => m != null).length) +
            _gameParty.length
      : PokeBoxStore.total(_data);
  int get slotIndex => _row < 0 ? -1 : _row * cols + _col;

  String pageTitle(int page) {
    if (!onGame) return PokeBoxStore.boxName(_data, page);
    final g = _game;
    if (page == 0) return 'PARTY';
    final box = gameBoxOf(page);
    if (g == null || box < 0 || box >= g.boxCount) return '';
    final name = g.boxName(box).trim();
    return name.isEmpty ? 'Box ${box + 1}' : name;
  }

  Mon? pageMon(int page, int slot) {
    if (!onGame) return Mon.of(PokeBoxStore.slot(_data, page, slot));
    if (page == 0) {
      return slot >= 0 && slot < _gameParty.length ? _gameParty[slot] : null;
    }
    final box = gameBoxOf(page);
    if (box < 0 || box >= _gameBoxes.length) return null;
    final b = _gameBoxes[box];
    return slot < 0 || slot >= b.length ? null : b[slot];
  }

  /// The Pokémon under the cursor.
  Mon? get hovered => _row < 0 ? null : pageMon(_page, slotIndex);

  /// What the data panel and Check show: the carried one, else the hovered.
  Mon? get shown => _held?.mon ?? hovered;

  String get _shownSave => onGame ? (currentGame?.path ?? '') : '';

  /// Is slot [i] of the shown box the carried one's own (drawn lifted out)?
  bool heldIsHere(int i) =>
      _held != null &&
      _held!.save == _shownSave &&
      _held!.box == (onGame ? gameBoxOf(_page) : _page) &&
      _held!.slot == i;

  /// Where the carried one came from ("Box 2", "Gold BOX 3").
  String get heldWhere => _held?.where ?? '';

  /// "Box 1 · slot 3" for the hovered slot.
  String get whereText {
    final g = currentGame;
    final box = pageTitle(_page);
    return '${g == null ? '' : '${g.game} '}$box · slot ${slotIndex + 1}';
  }

  /// The Check view has 2 tabs beside the Box Dex on wide screens, 3 when
  /// the Dex is a tab of its own (set by the layout).
  set tabCount(int n) {
    _tabs = n;
    if (_tab >= n) _tab = n - 1;
  }

  BackgroundRunner get _run => folder.runner;

  String get backups => games?.backups ?? p.join(folder.dir, backupsFolder);

  // ---- reading ----------------------------------------------------------------

  /// Reads box.json, then looks for game saves (call once; the screen does).
  Future<void> open() async {
    await _readNow();
    _fixPage();
    _notify();
    if (games != null) await rescan();
  }

  /// Reads box.json again (after a sync), dropping anything carried.
  Future<void> reload({String? notice}) async {
    await _readNow();
    _held = null;
    _menuOpen = false;
    _fixPage();
    if (notice != null) _say(notice);
    _notify();
  }

  /// Looks for Pokémon game saves again.
  Future<void> rescan() async {
    final g = games;
    if (g == null || _scanning) return;
    _scanning = true;
    _notify();
    final List<GameSave> found;
    try {
      found = await _run(findGameSaves, g.roots);
    } finally {
      _scanning = false;
    }
    final was = currentGame?.path;
    _saves = found;
    _scanned = true;
    if (was != null) {
      final i = _saves.indexWhere((s) => s.path == was);
      if (i < 0) {
        _source = -1;
        _page = _boxPage;
        _game = null;
        _gameBoxes = const [];
        _gameParty = const [];
      } else {
        _source = i;
      }
    }
    _owned = _ownedSpecies();
    if (_menuOpen) _menu = _menuRows();
    _fixPage();
    _notify();
  }

  /// When box.json or the shown game changed on disk (a sync came in),
  /// reads it again.
  Future<bool> refreshIfChanged() async {
    if (_busy || transferring) return false;
    var changed = false;
    if (await folder.changedOnDisk()) {
      await reload(notice: 'Pokéville was updated (a sync came in)');
      changed = true;
    }
    final g = currentGame;
    if (g != null && _gameBytes != null) {
      final now = await _run(readSaveBytes, g.path);
      if (now == null || !listEquals(now, _gameBytes)) {
        if (_held?.save == g.path) _held = null;
        await _loadGame(_source);
        _say('${g.title} changed (a sync came in), so it was read again');
        changed = true;
      }
    }
    if (games != null) unawaited(rescan());
    _notify();
    return changed;
  }

  Future<void> _readNow() async {
    final r = await folder.read();
    _apply(r);
  }

  void _apply(BoxRead r) {
    _state = r.state;
    _error = r.error;
    _data = r.data ?? PokeBoxStore.blank();
    _owned = _ownedSpecies();
  }

  Set<int> _ownedSpecies() =>
      {...PokeBoxStore.species(_data), for (final s in _saves) ...s.species}
        ..remove(0);

  void _fixPage() {
    if (onGame && _game == null) return; // still reading: keep its page
    _page = _page.clamp(0, (pageCount - 1).clamp(0, 1 << 20));
    _col = _col.clamp(0, cols - 1);
    _row = _row.clamp(-1, rows - 1);
  }

  bool get _ready =>
      _state == BoxState.ready && !_busy && !transferring && _asking == null;

  // ---- editing: what there is to draw -----------------------------------------

  /// The nickname keyboard: letters (Y or "abc" turns them lower case), the
  /// digits and signs, then [kbKeys]. Letters a game can't write are
  /// greyed out ([kbCanType]).
  static const kbRows = [
    'ABCDEFGHIJKLM',
    'NOPQRSTUVWXYZ',
    "0123456789.-'",
    '!?,/♂♀():;&+×',
  ];

  /// The keyboard's last row. "Type" opens the device's own keyboard.
  static const kbKeys = ['Space', 'abc', 'Delete', 'Type', 'OK'];

  /// The edit menu's rows.
  static const editRows = ['Nickname', 'Held item', 'Done'];

  EditStep get editStep => _edit;
  bool get editing => _edit != EditStep.none;
  int get editIndex => _editI;
  EditTarget? get editTarget => _target;
  String get kbText => _kbText;
  int get kbRow => _kbRow;
  int get kbCol => _kbCol;
  bool get kbLower => _kbLower;

  /// The most letters a nickname takes (10 up to Gen 5).
  int get nicknameMax => ps.maxNicknameLength;

  /// What the keyboard key at [row] / [col] types ('' for the last row).
  String kbChar(int row, int col) {
    if (row < 0 || row >= kbRows.length) return '';
    final keys = _letters(kbRows[row]);
    if (col < 0 || col >= keys.length) return '';
    final c = keys[col];
    return _kbLower ? c.toLowerCase() : c;
  }

  int kbCells(int row) =>
      row == kbRows.length ? kbKeys.length : _letters(kbRows[row]).length;

  /// Can the Pokémon being renamed have [char] in its name?
  bool kbCanType(String char) {
    final t = _target;
    if (t == null || char.isEmpty) return false;
    return ps.nicknameCanWrite(t.format, char);
  }

  /// The item list (None first) and the highlighted row.
  List<({int id, String name})> get editItems => _items;
  int get itemIndex => _itemI;

  /// Bumps when "Type" asks for the device's own keyboard (the screen opens
  /// a text field).
  int get typeRequestId => _typeId;

  /// "Gold" or "Pokéville": where the Pokémon being edited is.
  String get editWhere {
    final t = _target;
    if (t == null) return '';
    return t.inGame ? t.game : 'Pokéville';
  }

  // ---- what the grid shows: Pokéville or one game ------------------------------

  /// Shows Pokéville (-1) or the game [src]. Each keeps the box it was on.
  Future<void> showSource(int src) async {
    if (src >= _saves.length) return;
    if (onGame) {
      _gamePage = _page;
    } else {
      _boxPage = _page;
    }
    final load = src >= 0 && (_saves[src].path != _gamePath || _game == null);
    if (load && _saves[src].path != _gamePath) _gamePage = 1; // Box 1
    _source = src;
    _page = src >= 0 ? _gamePage : _boxPage;
    if (load) {
      await _loadGame(src);
    } else {
      _fixPage();
      _notify();
    }
  }

  Future<void> _loadGame(int src) async {
    final g = _saves[src];
    _game = null;
    _gameBytes = null;
    _gameBoxes = const [];
    _gameParty = const [];
    _gamePath = g.path;
    _busy = true;
    _busyText = 'Reading ${g.title}…';
    _notify();
    final bytes = await _run(readSaveBytes, g.path);
    _busy = false;
    final save = bytes == null
        ? null
        : ps.PokeSave.open(bytes, fileName: g.fileName);
    if (save == null) {
      _say("Couldn't read ${g.title} (${g.fileName})");
      _source = -1;
      _gamePath = '';
      _page = _boxPage;
    } else {
      _setGame(g.path, bytes!, save);
    }
    _fixPage();
    _notify();
  }

  void _setGame(String path, Uint8List bytes, ps.PokeSave save) {
    _gamePath = path;
    _game = save;
    _gameBytes = bytes;
    _gameBoxes = [
      for (final b in save.boxes)
        [for (final m in b.slots) m == null ? null : Mon(_map(m.summary))],
    ];
    _gameParty = [for (final m in save.party) Mon(_map(m.summary))];
  }

  static Map<String, dynamic> _map(Map<String, Object?> m) =>
      Map<String, dynamic>.from(m);

  /// A save changed here: its new bytes go everywhere they're shown.
  void _gameChanged(String path, Uint8List bytes) {
    final save = ps.PokeSave.open(bytes, fileName: p.basename(path));
    if (save == null) return;
    final i = _saves.indexWhere((s) => s.path == path);
    if (i >= 0) {
      _saves = [..._saves]..[i] = GameSave.of(path, save);
    }
    if (_gamePath == path) _setGame(path, bytes, save);
    _owned = _ownedSpecies();
  }

  // ---- buttons ----------------------------------------------------------------

  /// The d-pad / arrows.
  bool step(int dx, int dy) {
    final q = _asking;
    if (q != null) {
      final d = dx != 0 ? dx : dy;
      final i = (q.index + d).clamp(0, ClosedQuestion.answers.length - 1);
      if (i == q.index) return false;
      q.index = i;
      _notify();
      return true;
    }
    if (transferring) return false;
    if (_edit != EditStep.none) return _busy ? false : _editStep(dx, dy);
    if (_menuOpen) {
      final i = (_menuI + dy).clamp(0, _menu.length - 1);
      if (i == _menuI) return false;
      _menuI = i;
      _notify();
      return true;
    }
    if (!_ready) return false;
    if (_view == PokeView.check) return _checkStep(dx, dy);
    if (_row == -1) {
      if (dx != 0) return turnPage(dx);
      if (dy > 0) {
        _row = 0;
        _notify();
        return true;
      }
      return false;
    }
    var col = _col + dx;
    final row = (_row + dy).clamp(-1, rows - 1);
    if (col < 0) {
      if (!turnPage(-1)) return false;
      col = cols - 1;
    } else if (col >= cols) {
      if (!turnPage(1)) return false;
      col = 0;
    }
    if (row == _row && col == _col) return false;
    _row = row;
    _col = col.clamp(0, cols - 1);
    _notify();
    return true;
  }

  /// LB / RB: the boxes of whatever the grid shows (wrapping). In Check:
  /// the Box Dex's pages.
  bool turnPage(int dir) {
    if (_edit == EditStep.items && _ready) return _editStep(0, dir * 10);
    if (!_ready || _menuOpen || _edit != EditStep.none) return false;
    if (_view == PokeView.check) {
      _dexPage = (_dexPage + dir) % dexPages;
      _notify();
      return true;
    }
    final n = pageCount;
    if (n < 2) return false;
    _page = (_page + dir) % n;
    _notify();
    return true;
  }

  /// Shows box [p] (the strip, a tap).
  void goToPage(int p) {
    if (!_ready || p < 0 || p >= pageCount || _view != PokeView.box) return;
    if (_edit != EditStep.none) return;
    _page = p;
    _notify();
  }

  /// Puts the cursor on slot [i] (a tap).
  void select(int i) {
    if (!_ready || _menuOpen || i < 0 || i >= slotCount) return;
    _row = i ~/ cols;
    _col = i % cols;
    _notify();
  }

  /// A tap on a slot: the first selects it, the next picks up / puts down.
  Future<void> tap(int i) async {
    if (!_ready || _menuOpen || _view != PokeView.box) return;
    if (slotIndex != i) {
      select(i);
      return;
    }
    await confirm();
  }

  /// Y: Check the Pokémon under the cursor (or the carried one); Y again
  /// goes back.
  bool check() {
    if (_edit == EditStep.keyboard && _ready) {
      _kbLower = !_kbLower; // Y: upper / lower case
      _notify();
      return true;
    }
    if (_menuOpen || !_ready || _edit != EditStep.none) return false;
    if (_view == PokeView.check) {
      _view = PokeView.box;
    } else {
      _view = PokeView.check;
      _owned = _ownedSpecies();
      _dexToShown();
    }
    _notify();
    return true;
  }

  /// X: the Games list (X again closes it). Not in Check.
  bool menu() {
    if (!_ready || _view == PokeView.check || _edit != EditStep.none) {
      return false;
    }
    if (_menuOpen) {
      _menuOpen = false;
      _notify();
      return true;
    }
    _menu = _menuRows();
    _menuI = math.max(0, _menu.indexWhere((r) => r.source == _source));
    _menuOpen = true;
    _notify();
    return true;
  }

  List<MenuRow> _menuRows() => [
    MenuRow('Pokéville', _count(PokeBoxStore.total(_data)), source: -1),
    for (var i = 0; i < _saves.length; i++)
      MenuRow(
        _saves[i].title,
        '${_saves[i].trainer} · ${_count(_saves[i].count)}',
        source: i,
        chip: _saves[i].console,
      ),
    if (games == null)
      const MenuRow('Your games', 'on the PC', enabled: false)
    else if (_scanning && !_scanned)
      const MenuRow('Looking for Pokémon saves…', '', enabled: false)
    else if (_saves.isEmpty)
      const MenuRow('No Pokémon saves found yet', '', enabled: false),
  ];

  /// Puts the menu's highlight on row [i] (a tap).
  void menuSelect(int i) {
    if (!_menuOpen || i < 0 || i >= _menu.length) return;
    _menuI = i;
    _notify();
  }

  /// A: pick up / put down; in the menu, open the row; on the question,
  /// the highlighted answer; during the transfer, skip.
  Future<void> confirm() async {
    final q = _asking;
    if (q != null) return answer(q.index);
    if (transferring) {
      skipTransfer();
      return;
    }
    if (_menuOpen) {
      final r = _menu[_menuI];
      if (r.source != null) {
        _menuOpen = false;
        await showSource(r.source!);
      } else {
        _say(
          games == null
              ? OnThePc.games
              : _scanning
              ? 'Still looking for Pokémon saves…'
              : 'Play a Pokémon game and save in it, then come back',
        );
      }
      _notify();
      return;
    }
    if (!_ready) return;
    if (_edit != EditStep.none) return _editConfirm();
    if (_view == PokeView.check) {
      _openEdit();
      _notify();
      return;
    }
    if (_row < 0) return;
    if (_held == null) {
      _pickUp(slotIndex);
    } else {
      await _putDown(slotIndex);
    }
  }

  /// B: answers NOT YET, skips the transfer, closes the menu, leaves Check,
  /// lets go of a carried Pokémon. False when there's nothing left to back
  /// out of (the host leaves Pokéville).
  bool cancel() {
    if (_asking != null) {
      unawaited(answer(0));
      return true;
    }
    if (transferring) {
      skipTransfer();
      return true;
    }
    if (_edit != EditStep.none) {
      if (!_busy) _editBack();
      return true;
    }
    if (_menuOpen) {
      _menuOpen = false;
      _notify();
      return true;
    }
    if (_view == PokeView.check) {
      _view = PokeView.box;
      _notify();
      return true;
    }
    if (_held != null && !_busy) {
      _held = null;
      _notify();
      return true;
    }
    return false;
  }

  /// The emulators-closed question: 0 NOT YET, 1 YES.
  Future<void> answer(int i) async {
    final q = _asking;
    if (q == null) return;
    _asking = null;
    if (i == 1) {
      guard.yes();
      _notify();
      await q.run();
    } else {
      _say('Nothing was changed. Close ${q.name} fully, then try again.');
    }
    _notify();
  }

  /// Highlights answer [i] (a tap).
  void answerSelect(int i) {
    final q = _asking;
    if (q == null || i < 0 || i >= ClosedQuestion.answers.length) return;
    q.index = i;
    _notify();
  }

  /// Check: show tab [t] (a tap).
  void setTab(int t) {
    _tab = t.clamp(0, _tabs - 1);
    _notify();
  }

  void clearNotice() {
    if (_notice.isEmpty) return;
    _notice = '';
    _notify();
  }

  // ---- the transfer ----------------------------------------------------------

  /// The screen's clock: [dt] seconds later.
  void advanceTransfer(double dt) {
    final t = _transfer;
    if (t == null) return;
    t.advance(dt);
    if (!t.playing) _transfer = null;
    _notify();
  }

  void skipTransfer() {
    final t = _transfer;
    if (t == null) return;
    t.skip();
    if (!t.playing) _transfer = null;
    _notify();
  }

  void _play(Mon mon, GameSave? g, {required bool toBox}) {
    if (!animate || g == null) return;
    final trainer = g.trainer.isEmpty ? '' : ' · ${g.trainer.toUpperCase()}';
    _transfer = Transfer(
      mon: mon,
      console: g.console,
      toBox: toBox,
      gameName: g.game,
      label: '${g.game.toUpperCase()}$trainer',
    );
  }

  // ---- picking up and putting down -------------------------------------------

  /// Said when a party Pokémon is picked up (as on the PC, the party stays).
  static const partyStays =
      'Party Pokémon stay in the party here: move them to a box in the game';

  /// Said when one is put down on the party page.
  static const partyFull =
      "Pokémon can't join the party here: put it in one of the game's boxes";

  void _pickUp(int slot) {
    if (onGame) {
      final g = currentGame;
      final m = pageMon(_page, slot);
      if (g == null || m == null || _game == null) return;
      if (onParty) {
        _say(partyStays);
        _notify();
        return;
      }
      _held = Held(
        gameBoxOf(_page),
        slot,
        '',
        m,
        save: g.path,
        saveBytes: _gameBytes,
        where: '${g.game} ${pageTitle(_page)}',
      );
      _notify();
      return;
    }
    final s = PokeBoxStore.slot(_data, _page, slot);
    final m = Mon.of(s);
    if (m == null) return;
    _held = Held(
      _page,
      slot,
      '${s['file']}',
      m,
      where: PokeBoxStore.boxName(_data, _page),
    );
    _notify();
  }

  Future<void> _putDown(int slot) async {
    final h = _held!;
    if (!onGame) {
      if (!h.fromGame) return _boxMove(h, slot);
      if (!PokeBoxStore.isEmpty(_data, _page, slot)) {
        _say('Pick an empty spot in Pokéville');
        _notify();
        return;
      }
      return _guarded([h.save], () => _take(h, _page, slot));
    }
    final g = currentGame;
    if (g == null || _game == null) return;
    final box = gameBoxOf(_page);
    if (box < 0) {
      _say(partyFull);
      _notify();
      return;
    }
    final taken = pageMon(_page, slot) != null;
    if (h.fromGame && h.save == g.path) {
      if (h.box == box && h.slot == slot) {
        _held = null; // back where it was
        _notify();
        return;
      }
      return _guarded([g.path], () => _moveIn(h, g, box, slot));
    }
    if (taken) {
      _say("Pick an empty spot in the game's box");
      _notify();
      return;
    }
    if (h.fromGame) {
      return _guarded([h.save, g.path], () => _send(h, g, box, slot));
    }
    return _guarded([g.path], () => _put(h, g, box, slot));
  }

  Future<void> _boxMove(Held h, int slot) async {
    if (h.box == _page && h.slot == slot) {
      _held = null; // back where it was
      _notify();
      return;
    }
    // it must still be where it was picked up
    if ('${PokeBoxStore.slot(_data, h.box, h.slot)['file']}' != h.file) {
      _held = null;
      _say("That Pokémon isn't where it was any more");
      _notify();
      return;
    }
    final next = PokeBoxStore.copy(_data);
    if (!PokeBoxStore.move(next, h.box, h.slot, _page, slot)) {
      _held = null;
      _notify();
      return;
    }
    final before = _data;
    _data = next; // shown right away
    _held = null;
    _busy = true;
    _busyText = '';
    _notify();
    final r = await folder.write(next);
    _busy = false;
    switch (r.outcome) {
      case WriteOutcome.saved:
        break;
      case WriteOutcome.changed:
        _apply(r.read!);
        _fixPage();
        _say(
          'Pokéville changed on disk (a sync came in), so it was read again. '
          'Nothing moved: try again.',
        );
      case WriteOutcome.failed:
        _data = before;
        _say("Couldn't save Pokéville: ${r.error}");
    }
    _owned = _ownedSpecies();
    _notify();
  }

  /// Runs [run] once no emulator has [paths] open (asking on Android).
  Future<void> _guarded(List<String> paths, Future<void> Function() run) async {
    switch (guard.mode) {
      case GuardMode.none:
        return run();
      case GuardMode.processes:
        var cantTell = false;
        _busy = true;
        _busyText = 'Checking the emulator is closed…';
        _notify();
        for (final path in paths) {
          final why = await _run(guard.check!, path);
          if (why == null) {
            cantTell = true;
          } else if (why.isNotEmpty) {
            _busy = false;
            _say(why);
            _notify();
            return;
          }
        }
        _busy = false;
        if (!cantTell || guard.fresh) return run();
      case GuardMode.ask:
        if (guard.fresh) return run();
    }
    _asking = ClosedQuestion(SaveGuard.nameFor(paths.first), run);
    _notify();
  }

  /// box.json changed on disk: read again, refuse (true).
  Future<bool> _boxChanged() async {
    if (!await folder.changedOnDisk()) return false;
    await reload(
      notice:
          'Pokéville changed on disk (a sync came in), so it was read again. '
          'Nothing moved: try again.',
    );
    return true;
  }

  GameSave? _saveAt(String path) {
    for (final s in _saves) {
      if (s.path == path) return s;
    }
    return null;
  }

  void _fail(GameChange r, String save) {
    _transfer?.done(false, r.error);
    _say(r.error);
    if (r.changedOnDisk) {
      _held = null;
      if (save == _gamePath && _source >= 0) unawaited(_loadGame(_source));
    }
  }

  /// Game -> Pokéville.
  Future<void> _take(Held h, int box, int slot) async {
    if (await _boxChanged()) return;
    final g = _saveAt(h.save);
    _play(h.mon, g, toBox: true);
    _busy = true;
    _busyText = '';
    _notify();
    final now = DateTime.now();
    final r = await _run(takeFromGame, (
      save: h.save,
      expected: h.saveBytes!,
      box: h.box,
      slot: h.slot,
      pokeville: folder.dir,
      backups: backups,
      stamp: now.millisecondsSinceEpoch,
      seed: _rnd.nextInt(1 << 30),
    ));
    _busy = false;
    if (!r.ok) {
      _fail(r, h.save);
      _notify();
      return;
    }
    _held = null;
    _gameChanged(h.save, r.save!);
    final err = await _placeInBox(box, slot, r.file, r.mon!);
    _transfer?.done(true);
    if (err != null) {
      _say(
        '${h.mon.shownName} is safe in ${r.file}, but Pokéville '
        "couldn't be saved: $err",
      );
    }
    _owned = _ownedSpecies();
    _notify();
  }

  static const _unreadable =
      "box.json changed on disk (a sync came in) and can't be read, so it "
      'was left as it is';

  /// Puts a new Pokémon into box.json at [box] / [slot], or the first empty
  /// slot when a sync filled that one meanwhile. Null when saved.
  Future<String?> _placeInBox(
    int box,
    int slot,
    String file,
    Map<String, dynamic> mon,
  ) async {
    for (var tries = 0; tries < 4; tries++) {
      final next = PokeBoxStore.copy(_data);
      var at = (box, slot);
      if (!PokeBoxStore.isEmpty(next, box, slot)) {
        at = PokeBoxStore.firstEmpty(next, box) ?? at;
      }
      if (!PokeBoxStore.place(next, at.$1, at.$2, file, mon)) {
        PokeBoxStore.keepSpareBox(next);
        final again = PokeBoxStore.firstEmpty(next, box);
        if (again == null ||
            !PokeBoxStore.place(next, again.$1, again.$2, file, mon)) {
          return 'no room';
        }
      }
      final r = await folder.write(next);
      switch (r.outcome) {
        case WriteOutcome.saved:
          _data = next;
          return null;
        case WriteOutcome.changed:
          _apply(r.read!); // a sync came in: place it in that one
          // One this app can't read is never written over (it would lose
          // every other slot): the player sees it's broken instead.
          if (r.read!.state == BoxState.broken) return _unreadable;
        case WriteOutcome.failed:
          return r.error ?? 'write failed';
      }
    }
    return 'box.json kept changing';
  }

  /// Takes [file] out of box.json (wherever it is now). Null when saved.
  Future<String?> _clearInBox(Held h) async {
    for (var tries = 0; tries < 4; tries++) {
      final next = PokeBoxStore.copy(_data);
      var found = false;
      if ('${PokeBoxStore.slot(next, h.box, h.slot)['file']}' == h.file) {
        PokeBoxStore.clear(next, h.box, h.slot);
        found = true;
      } else {
        for (var b = 0; b < PokeBoxStore.boxCount(next) && !found; b++) {
          for (var i = 0; i < PokeBoxStore.slots; i++) {
            if ('${PokeBoxStore.slot(next, b, i)['file']}' == h.file) {
              PokeBoxStore.clear(next, b, i);
              found = true;
              break;
            }
          }
        }
      }
      if (!found) return null;
      final r = await folder.write(next);
      switch (r.outcome) {
        case WriteOutcome.saved:
          _data = next;
          return null;
        case WriteOutcome.changed:
          _apply(r.read!);
          // One this app can't read is never written over (it would lose
          // every other slot): the player sees it's broken instead.
          if (r.read!.state == BoxState.broken) return _unreadable;
        case WriteOutcome.failed:
          return r.error ?? 'write failed';
      }
    }
    return 'box.json kept changing';
  }

  /// Pokéville -> game.
  Future<void> _put(Held h, GameSave g, int box, int slot) async {
    if (await _boxChanged()) return;
    if ('${PokeBoxStore.slot(_data, h.box, h.slot)['file']}' != h.file) {
      _held = null;
      _say("That Pokémon isn't where it was any more");
      _notify();
      return;
    }
    _play(h.mon, g, toBox: false);
    _busy = true;
    _busyText = '';
    _notify();
    final r = await _run(putIntoGame, (
      save: g.path,
      expected: _gameBytes!,
      box: box,
      slot: slot,
      pokeville: folder.dir,
      file: h.file,
      backups: backups,
    ));
    _busy = false;
    if (!r.ok) {
      _fail(r, g.path);
      _notify();
      return;
    }
    _held = null;
    _gameChanged(g.path, r.save!);
    final err = await _clearInBox(h);
    _transfer?.done(true);
    if (err != null) {
      _say(
        '${h.mon.shownName} went to ${g.game}, but Pokéville '
        "couldn't be saved: $err",
      );
    } else if (r.reason.isNotEmpty) {
      _say('${h.mon.shownName} went to ${g.game} (${r.reason})');
    }
    _owned = _ownedSpecies();
    _notify();
  }

  /// Inside one game.
  Future<void> _moveIn(Held h, GameSave g, int box, int slot) async {
    _busy = true;
    _busyText = 'Moving ${h.mon.shownName}…';
    _notify();
    final r = await _run(moveInGame, (
      save: g.path,
      expected: h.saveBytes!,
      box: h.box,
      slot: h.slot,
      box2: box,
      slot2: slot,
      backups: backups,
    ));
    _busy = false;
    _held = null;
    if (!r.ok) {
      _fail(r, g.path);
    } else {
      _gameChanged(g.path, r.save!);
    }
    _notify();
  }

  /// From one game straight into another.
  Future<void> _send(Held h, GameSave g, int box, int slot) async {
    _play(h.mon, g, toBox: false);
    _busy = true;
    _busyText = '';
    _notify();
    final r = await _run(sendToGame, (
      from: h.save,
      fromExpected: h.saveBytes!,
      box: h.box,
      slot: h.slot,
      to: g.path,
      toExpected: _gameBytes!,
      box2: box,
      slot2: slot,
      backups: backups,
    ));
    _busy = false;
    if (!r.ok) {
      _fail(r, g.path);
      if (r.error.contains('in both now')) _held = null;
      _notify();
      return;
    }
    _held = null;
    _gameChanged(h.save, r.save!);
    _gameChanged(g.path, r.save2!);
    _transfer?.done(true);
    if (r.reason.isNotEmpty) {
      _say('${h.mon.shownName} went to ${g.game} (${r.reason})');
    }
    _notify();
  }

  // ---- editing (Check's A, as the PC's edit menu) ----------------------------------

  void _openEdit() {
    if (_held != null) {
      _say('Put it down first, then change it');
      return;
    }
    final m = hovered;
    if (m == null) {
      _say('Point at a Pokémon first');
      return;
    }
    if (m.egg) {
      _say("Eggs can't be renamed or hold items");
      return;
    }
    if (formatNumber(m.format) == 0) {
      _say(OnThePc.edit(m.format));
      return;
    }
    final i = slotIndex;
    if (onGame) {
      final g = currentGame;
      if (g == null || _game == null) return;
      _target = EditTarget(
        box: gameBoxOf(_page),
        slot: i,
        mon: m,
        save: g.path,
        saveBytes: _gameBytes,
        game: g.game,
      );
    } else {
      final file = '${PokeBoxStore.slot(_data, _page, i)['file']}';
      _target = EditTarget(box: _page, slot: i, mon: m, file: file);
    }
    _edit = EditStep.menu;
    _editI = 0;
  }

  bool _editStep(int dx, int dy) {
    switch (_edit) {
      case EditStep.none:
        return false;
      case EditStep.menu:
        final i = (_editI + dy).clamp(0, editRows.length - 1);
        if (i == _editI) return false;
        _editI = i;
      case EditStep.items:
        final i = (_itemI + dy)
            .clamp(0, math.max(0, _items.length - 1))
            .toInt();
        if (i == _itemI) return false;
        _itemI = i;
      case EditStep.keyboard:
        final rows = kbRows.length + 1;
        if (dy != 0) {
          _kbRow = (_kbRow + dy) % rows;
          if (_kbRow < 0) _kbRow += rows;
          _kbCol = math.min(_kbCol, kbCells(_kbRow) - 1);
        }
        if (dx != 0) {
          final n = kbCells(_kbRow);
          _kbCol = ((_kbCol + dx) % n + n) % n;
        }
    }
    _notify();
    return true;
  }

  /// A tap on the edit menu's row [i].
  Future<void> editTap(int i) async {
    if (_edit != EditStep.menu || !_ready) return;
    if (i < 0 || i >= editRows.length) return;
    _editI = i;
    await _editConfirm();
  }

  /// A tap on the keyboard key at [row] / [col].
  Future<void> kbTap(int row, int col) async {
    if (_edit != EditStep.keyboard || !_ready) return;
    if (row < 0 || row > kbRows.length || col < 0 || col >= kbCells(row)) {
      return;
    }
    _kbRow = row;
    _kbCol = col;
    await _editConfirm();
  }

  /// A tap on the item list's row [i] (the first highlights, the next
  /// gives it).
  Future<void> itemTap(int i) async {
    if (_edit != EditStep.items || !_ready || i < 0 || i >= _items.length) {
      return;
    }
    if (_itemI != i) {
      _itemI = i;
      _notify();
      return;
    }
    await _editConfirm();
  }

  /// Letters typed on a real keyboard (or the device's own, through
  /// "Type"): added to the name; ones the game can't write are refused.
  void typeText(String text) {
    if (_edit != EditStep.keyboard || !_ready) return;
    for (final ch in _letters(text)) {
      if (!_kbAdd(ch)) break;
    }
    _notify();
  }

  /// The device's keyboard gave [text]: it becomes the name, then OK.
  Future<void> typedName(String text) async {
    if (_edit != EditStep.keyboard || !_ready) return;
    final name = text.trim();
    final bad = <String>{
      for (final ch in _letters(name))
        if (ch != ' ' && !kbCanType(ch)) ch,
    };
    if (bad.isNotEmpty) {
      _kbText = [
        for (final ch in _letters(name))
          if (!bad.contains(ch)) ch,
      ].join();
      if (_kbText.length > nicknameMax) {
        _kbText = _kbText.substring(0, nicknameMax);
      }
      _say("$editWhere can't write ${bad.join(' ')}");
      _notify();
      return;
    }
    if (name.length > nicknameMax) {
      _kbText = name.substring(0, nicknameMax);
      _say('$nicknameMax letters at most');
      _notify();
      return;
    }
    _kbText = name;
    await _runEdit(nickname: name);
  }

  /// The keyboard: a letter less (B, Delete).
  void kbBackspace() {
    if (_edit != EditStep.keyboard || _kbText.isEmpty) return;
    final l = _letters(_kbText);
    _kbText = l.take(l.length - 1).join();
    _notify();
  }

  bool _kbAdd(String ch) {
    if (_kbText.length >= nicknameMax) {
      _say('$nicknameMax letters at most');
      return false;
    }
    if (ch != ' ' && !kbCanType(ch)) {
      _say("$editWhere can't write $ch");
      return false;
    }
    _kbText += ch;
    return true;
  }

  Future<void> _editConfirm() async {
    final t = _target;
    if (t == null) return;
    switch (_edit) {
      case EditStep.none:
        return;
      case EditStep.menu:
        switch (_editI) {
          case 0:
            _kbText = t.mon.nickname;
            _kbRow = 0;
            _kbCol = 0;
            _edit = EditStep.keyboard;
          case 1:
            if (t.format <= 1) {
              _say("Gen 1 Pokémon can't hold items");
            } else {
              _items = ps.heldItemChoices(t.format);
              _itemI = math.max(
                0,
                _items.indexWhere((it) => it.name == t.mon.item),
              );
              _edit = EditStep.items;
            }
          default:
            _closeEdit();
        }
      case EditStep.items:
        if (_items.isEmpty) return;
        await _runEdit(item: _items[_itemI].id);
        return;
      case EditStep.keyboard:
        if (_kbRow < kbRows.length) {
          _kbAdd(kbChar(_kbRow, _kbCol));
        } else {
          switch (kbKeys[_kbCol]) {
            case 'Space':
              _kbAdd(' ');
            case 'abc':
              _kbLower = !_kbLower;
            case 'Delete':
              kbBackspace();
            case 'Type':
              _typeId++;
            case 'OK':
              await _runEdit(nickname: _kbText.trim());
              return;
          }
        }
    }
    _notify();
  }

  // B: a letter less on the keyboard, else a step back.
  void _editBack() {
    switch (_edit) {
      case EditStep.keyboard when _kbText.isNotEmpty:
        kbBackspace();
        return;
      case EditStep.menu:
        _closeEdit();
      case EditStep.none:
        return;
      default:
        _edit = EditStep.menu;
    }
    _notify();
  }

  void _closeEdit() {
    _edit = EditStep.none;
    _target = null;
    _items = const [];
  }

  Future<void> _runEdit({String? nickname, int? item}) async {
    final t = _target;
    if (t == null) return;
    if (!t.inGame) return _editBox(t, nickname, item);
    return _guarded([t.save], () => _editGame(t, nickname, item));
  }

  void _edited(EditTarget t, Mon m, {required bool nick}) {
    final name = m.shownName;
    _say(
      nick
          ? (m.nickname.isEmpty
                ? '$name: nickname taken off'
                : '$name: nickname saved')
          : (m.item.isEmpty
                ? '$name holds nothing now'
                : '$name now holds ${m.item}'),
    );
    _target = t.withMon(m);
    _closeEdit();
  }

  Future<void> _editGame(EditTarget t, String? nickname, int? item) async {
    _busy = true;
    _busyText = nickname != null
        ? 'Saving the nickname…'
        : 'Giving it ${_itemName(item)}…';
    _notify();
    final r = await _run(editInGame, (
      save: t.save,
      expected: t.saveBytes!,
      box: t.box,
      slot: t.slot,
      nickname: nickname,
      item: item,
      backups: backups,
    ));
    _busy = false;
    if (!r.ok) {
      _say(r.error);
      if (r.changedOnDisk) {
        _closeEdit();
        if (t.save == _gamePath && _source >= 0) await _loadGame(_source);
      } else {
        _edit = EditStep.menu;
      }
      _notify();
      return;
    }
    _gameChanged(t.save, r.save!);
    _edited(t, Mon(r.mon!), nick: nickname != null);
    _notify();
  }

  Future<void> _editBox(EditTarget t, String? nickname, int? item) async {
    if (await _boxChanged()) {
      _closeEdit();
      _notify();
      return;
    }
    if ('${PokeBoxStore.slot(_data, t.box, t.slot)['file']}' != t.file) {
      _closeEdit();
      _say("That Pokémon isn't where it was any more");
      _notify();
      return;
    }
    _busy = true;
    _busyText = nickname != null
        ? 'Saving the nickname…'
        : 'Giving it ${_itemName(item)}…';
    _notify();
    final r = await _run(editPokevilleFile, (
      pokeville: folder.dir,
      file: t.file,
      nickname: nickname,
      item: item,
    ));
    if (!r.ok) {
      _busy = false;
      _say(r.error);
      _edit = EditStep.menu;
      _notify();
      return;
    }
    final err = await _updateSummary(t, r.mon!);
    _busy = false;
    final m = Mon(r.mon!);
    if (err != null) {
      _say("${m.shownName} was changed, but Pokéville couldn't be saved: $err");
      _target = t.withMon(m);
      _closeEdit();
    } else {
      _edited(t, m, nick: nickname != null);
    }
    _notify();
  }

  /// The slot holding [t]'s file (wherever it is now) takes the new summary
  /// (its keys over the old ones, as the PC does). Null when saved.
  Future<String?> _updateSummary(EditTarget t, Map<String, dynamic> mon) async {
    for (var tries = 0; tries < 4; tries++) {
      final next = PokeBoxStore.copy(_data);
      SlotData? found;
      if ('${PokeBoxStore.slot(next, t.box, t.slot)['file']}' == t.file) {
        found = PokeBoxStore.slot(next, t.box, t.slot);
      } else {
        for (var b = 0; b < PokeBoxStore.boxCount(next) && found == null; b++) {
          for (var i = 0; i < PokeBoxStore.slots; i++) {
            if ('${PokeBoxStore.slot(next, b, i)['file']}' == t.file) {
              found = PokeBoxStore.slot(next, b, i);
              break;
            }
          }
        }
      }
      if (found == null) return 'its slot is gone';
      final old = found['mon'];
      final merged = <String, dynamic>{
        if (old is Map) ...Map<String, dynamic>.from(old),
        ...mon,
      };
      found['mon'] = merged;
      final r = await folder.write(next);
      switch (r.outcome) {
        case WriteOutcome.saved:
          _data = next;
          return null;
        case WriteOutcome.changed:
          _apply(r.read!); // a sync came in: change that one
          // One this app can't read is never written over (it would lose
          // every other slot): the player sees it's broken instead.
          if (r.read!.state == BoxState.broken) return _unreadable;
        case WriteOutcome.failed:
          return r.error ?? 'write failed';
      }
    }
    return 'box.json kept changing';
  }

  /// [s] letter by letter (whole code points).
  static List<String> _letters(String s) => [
    for (final r in s.runes) String.fromCharCode(r),
  ];

  String _itemName(int? id) {
    for (final it in _items) {
      if (it.id == id) return it.name;
    }
    return 'it';
  }

  // ---- Check -------------------------------------------------------------------

  // Left / right: the tabs. Up / down: the previous or next Pokémon in this
  // box.
  bool _checkStep(int dx, int dy) {
    if (dx != 0) {
      final t = (_tab + dx).clamp(0, _tabs - 1);
      if (t == _tab) return false;
      _tab = t;
      _notify();
      return true;
    }
    if (dy == 0 || _held != null) return false;
    final n = slotCount;
    final i = (_row < 0 ? 0 : _row) * cols + _col;
    for (var k = 1; k < n; k++) {
      final j = (i + dy * k) % n;
      if (pageMon(_page, j) != null) {
        _row = j ~/ cols;
        _col = j % cols;
        _dexToShown();
        _notify();
        return true;
      }
    }
    return false;
  }

  void _dexToShown() {
    final m = shown;
    if (m != null && !m.egg && m.species > 0) {
      _dexPage = ((m.species - 1) ~/ dexPer).clamp(0, dexPages - 1);
    }
  }

  // ---- notices -----------------------------------------------------------------

  void _say(String text) {
    _notice = text;
    _noticeId++;
  }

  static String _count(int n) => n == 1 ? '1 Pokémon' : '$n Pokémon';

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
