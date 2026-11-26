// Pokéville's screen logic, ported from the PC's PokeBoxScreen.gd (the Box
// side; games come in part B): the cursor, LB / RB boxes, holding a Pokémon
// (pick up, put down, swap), Check (status, moves) with the Box Dex, and the
// X menu. Pure Dart: the widgets only draw it and feed it buttons.
//
// Every change is written to box.json at once (atomically). If box.json
// changed on disk since it was read (a sync came in), the new one is read and
// the move is refused with a notice, rather than overwriting it.
import 'package:flutter/foundation.dart';

import 'folder.dart';
import 'store.dart';

enum PokeView { box, check }

/// A Pokémon being carried (picked up from [box], [slot]).
class Held {
  const Held(this.box, this.slot, this.file, this.mon);

  final int box;
  final int slot;
  final String file;
  final Mon mon;
}

/// A row of the X menu.
class MenuRow {
  const MenuRow(this.title, this.detail, {this.box, this.enabled = true});

  final String title;
  final String detail;

  /// The box it goes to (null: a row that isn't a box).
  final int? box;
  final bool enabled;
}

/// Things the PC does with its helper (PKHeX), which this side leaves out.
abstract final class OnThePc {
  static const games =
      'Moving Pokémon in and out of your games happens on the PC (it needs PKHeX)';
  static const edit =
      'Nicknames and held items are changed on the PC (they need PKHeX)';
}

class PokevilleController extends ChangeNotifier {
  PokevilleController(this.folder);

  static const dexAll = 1025;
  static const dexPer = 60; // 10 x 6 (6 x 10 on a phone)

  final PokevilleFolder folder;

  BoxState? _state; // null: still reading
  String? _error;
  BoxData _data = PokeBoxStore.blank();
  int _page = 0;
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
  bool _disposed = false;

  // ---- what there is to draw ------------------------------------------------

  /// null while reading, then missing / broken / ready.
  BoxState? get state => _state;
  String? get error => _error;
  BoxData get data => _data;
  int get page => _page;
  int get row => _row;
  int get col => _col;
  int get cols => PokeBoxStore.cols;
  int get rows => PokeBoxStore.rows;
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

  /// A write is under way: buttons wait.
  bool get busy => _busy;
  int get pageCount => PokeBoxStore.boxCount(_data);
  int get total => PokeBoxStore.total(_data);
  int get slotIndex => _row < 0 ? -1 : _row * cols + _col;

  String pageTitle(int page) => PokeBoxStore.boxName(_data, page);

  Mon? pageMon(int page, int slot) =>
      Mon.of(PokeBoxStore.slot(_data, page, slot));

  /// The Pokémon under the cursor.
  Mon? get hovered => _row < 0 ? null : pageMon(_page, slotIndex);

  /// What the data panel and Check show: the carried one, else the hovered.
  Mon? get shown => _held?.mon ?? hovered;

  /// Is slot [i] of the shown box the carried one's own (drawn lifted out)?
  bool heldIsHere(int i) =>
      _held != null && _held!.box == _page && _held!.slot == i;

  /// Where the carried one came from ("Box 2").
  String get heldWhere =>
      _held == null ? '' : PokeBoxStore.boxName(_data, _held!.box);

  /// "Box 1 · slot 3" for the hovered slot.
  String get whereText => '${pageTitle(_page)} · slot ${slotIndex + 1}';

  /// The Check view has 2 tabs beside the Box Dex on wide screens, 3 when
  /// the Dex is a tab of its own (set by the layout).
  set tabCount(int n) {
    _tabs = n;
    if (_tab >= n) _tab = n - 1;
  }

  // ---- reading ----------------------------------------------------------------

  /// Reads box.json (call once; the screen does).
  Future<void> open() async {
    await _readNow();
    _fixPage();
    _notify();
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

  /// When box.json changed on disk (a sync came in), reads it again.
  Future<bool> refreshIfChanged() async {
    if (_busy) return false;
    if (!await folder.changedOnDisk()) return false;
    await reload(notice: 'Pokéville was updated (a sync came in)');
    return true;
  }

  Future<void> _readNow() async {
    final r = await folder.read();
    _apply(r);
  }

  void _apply(BoxRead r) {
    _state = r.state;
    _error = r.error;
    _data = r.data ?? PokeBoxStore.blank();
    _owned = PokeBoxStore.species(_data);
  }

  void _fixPage() {
    _page = _page.clamp(0, (pageCount - 1).clamp(0, 1 << 20));
    _col = _col.clamp(0, cols - 1);
    _row = _row.clamp(-1, rows - 1);
  }

  bool get _ready => _state == BoxState.ready && !_busy;

  // ---- buttons ----------------------------------------------------------------

  /// The d-pad / arrows.
  bool step(int dx, int dy) {
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

  /// LB / RB: the boxes (wrapping). In Check: the Box Dex's pages.
  bool turnPage(int dir) {
    if (!_ready || _menuOpen) return false;
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

  /// Shows box [p] (the strip, the menu, a tap).
  void goToPage(int p) {
    if (!_ready || p < 0 || p >= pageCount || _view != PokeView.box) return;
    _page = p;
    _notify();
  }

  /// Puts the cursor on slot [i] (a tap).
  void select(int i) {
    if (!_ready || _menuOpen || i < 0 || i >= PokeBoxStore.slots) return;
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
    if (_menuOpen || !_ready) return false;
    if (_view == PokeView.check) {
      _view = PokeView.box;
    } else {
      _view = PokeView.check;
      _owned = PokeBoxStore.species(_data);
      _dexToShown();
    }
    _notify();
    return true;
  }

  /// X: the menu (X again closes it). Not in Check.
  bool menu() {
    if (!_ready || _view == PokeView.check) return false;
    if (_menuOpen) {
      _menuOpen = false;
      _notify();
      return true;
    }
    _menu = [
      for (var b = 0; b < pageCount; b++)
        MenuRow(
          pageTitle(b),
          _count(PokeBoxStore.countInBox(_data, b)),
          box: b,
        ),
      const MenuRow('Your games', 'on the PC', enabled: false),
    ];
    _menuI = _page;
    _menuOpen = true;
    _notify();
    return true;
  }

  /// Puts the menu's highlight on row [i] (a tap).
  void menuSelect(int i) {
    if (!_menuOpen || i < 0 || i >= _menu.length) return;
    _menuI = i;
    _notify();
  }

  /// A: pick up / put down; in the menu, open the row.
  Future<void> confirm() async {
    if (_menuOpen) {
      final r = _menu[_menuI];
      if (r.box != null) {
        _menuOpen = false;
        _page = r.box!;
        _fixPage();
      } else {
        _say(OnThePc.games);
      }
      _notify();
      return;
    }
    if (!_ready) return;
    if (_view == PokeView.check) {
      if (shown != null) _say(OnThePc.edit);
      return;
    }
    if (_row < 0) return;
    if (_held == null) {
      _pickUp(slotIndex);
    } else {
      await _putDown(slotIndex);
    }
  }

  /// B: closes the menu, leaves Check, lets go of a carried Pokémon. False
  /// when there's nothing left to back out of (the host leaves Pokéville).
  bool cancel() {
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

  // ---- picking up and putting down -------------------------------------------

  void _pickUp(int slot) {
    final s = PokeBoxStore.slot(_data, _page, slot);
    final m = Mon.of(s);
    if (m == null) return;
    _held = Held(_page, slot, '${s['file']}', m);
    _notify();
  }

  Future<void> _putDown(int slot) async {
    final h = _held!;
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
    _owned = PokeBoxStore.species(_data);
    _notify();
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
    final n = cols * rows;
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
