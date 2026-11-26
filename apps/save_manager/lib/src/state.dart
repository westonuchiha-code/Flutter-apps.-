/// Where you are in the save manager (ported 1:1 from the PC's
/// MemoryCardState.gd). Pure logic: no widgets, no files, no drawing. It is
/// gamepad navigation, but the touch UI drives it too (see [selectIndex],
/// [focusCard], [selectOption]).
library;

import 'package:save_kit/save_kit.dart';

/// Which page the save manager shows.
enum Mode {
  /// The grid of saves, the card column and the paint buttons.
  list,

  /// One save opened up.
  opened,

  /// The options (Y) for what you're on.
  options,

  /// A card's own page (A on a card).
  card,
}

/// One option or button: what it says and the verb it runs.
typedef Choice = ({String label, String verb});

/// A heading over a group of options.
typedef ChoiceGroup = ({String heading, List<Choice> items});

/// Godot's clampi: [lo] wins when [hi] < [lo] (Dart's clamp would throw).
int clampi(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

/// Godot's naturalnocasecmp_to: case-insensitive, digit runs by value.
int naturalNoCaseCompare(String a, String b) {
  final x = a.toLowerCase(), y = b.toLowerCase();
  var i = 0, j = 0;
  bool digit(int c) => c >= 48 && c <= 57;
  while (i < x.length && j < y.length) {
    final cx = x.codeUnitAt(i), cy = y.codeUnitAt(j);
    if (digit(cx) && digit(cy)) {
      var ei = i, ej = j;
      while (ei < x.length && digit(x.codeUnitAt(ei))) {
        ei++;
      }
      while (ej < y.length && digit(y.codeUnitAt(ej))) {
        ej++;
      }
      final nx = BigInt.parse(x.substring(i, ei));
      final ny = BigInt.parse(y.substring(j, ej));
      final c = nx.compareTo(ny);
      if (c != 0) return c;
      i = ei;
      j = ej;
      continue;
    }
    if (cx != cy) return cx < cy ? -1 : 1;
    i++;
    j++;
  }
  final left = x.length - i, right = y.length - j;
  return left == right ? 0 : (left < right ? -1 : 1);
}

/// A sort that keeps equal items in their order.
void stableSort<T>(List<T> list, int Function(T a, T b) compare) {
  final order = [for (var i = 0; i < list.length; i++) i];
  final copy = List<T>.of(list);
  order.sort((a, b) {
    final c = compare(copy[a], copy[b]);
    return c != 0 ? c : a.compareTo(b);
  });
  for (var i = 0; i < order.length; i++) {
    list[i] = copy[order[i]];
  }
}

/// The save manager's cursor, pages and selection.
class MemoryCardState {
  /// Saves across the grid.
  static const cols = 5;

  /// Rows of the grid on screen.
  static const rows = 4;

  /// The tabs: ALL, then one per console.
  static const filters = CardSystems.tabs;

  /// The orders the grid can be in.
  static const sorts = ['Newest first', 'By game', 'Biggest first'];

  /// The paint buttons under the grid.
  static const listButtons = <Choice>[
    (label: 'COPY', verb: 'copy'),
    (label: 'MOVE', verb: 'move'),
    (label: 'BACK UP', verb: 'back_up'),
    (label: 'DELETE', verb: 'delete'),
  ];

  /// The buttons along the bottom of an opened save.
  static const openButtons = <Choice>[
    (label: 'START GAME', verb: 'start'),
    (label: 'COPY', verb: 'copy'),
    (label: 'BACK UP', verb: 'back_up'),
    (label: 'DELETE', verb: 'delete'),
  ];

  /// Files of an opened save shown at once.
  static const filesShown = 16;

  // Y gives the options for what you're on, two to a row, each group on rows
  // of its own. Nothing destructive comes first.

  /// The option that opens the second page.
  static const more = (label: 'More...', verb: 'more');

  /// A save's first page of options.
  static const saveOptions = <Choice>[
    (label: 'Start game', verb: 'start'),
    (label: 'Copy', verb: 'copy'),
    (label: 'Move', verb: 'move'),
    (label: 'Back up', verb: 'back_up'),
    (label: 'Restore', verb: 'restore'),
    (label: 'Favorite', verb: 'favorite'),
    (label: 'Delete', verb: 'delete'),
  ];

  /// A save's More... page (Sort is labelled by [actionLabel]).
  static const saveMore = <Choice>[
    (label: 'Export', verb: 'export'),
    (label: 'Select several', verb: 'select'),
    (label: 'Select all of this game', verb: 'mark'),
    (label: 'Sort', verb: 'sort'),
  ];

  /// The options for the marked saves.
  static const selectedOptions = <Choice>[
    (label: 'Copy', verb: 'copy'),
    (label: 'Move', verb: 'move'),
    (label: 'Back up', verb: 'back_up'),
    (label: 'Export', verb: 'export'),
    (label: 'Favorite', verb: 'favorite'),
    (label: 'Delete', verb: 'delete'),
    (label: 'Pick more', verb: 'select'),
    (label: 'Clear selection', verb: 'unselect'),
  ];

  /// A card's menu is about the card itself.
  static const cardOptions = <Choice>[
    (label: 'Customize', verb: 'customize'),
    (label: 'Rename', verb: 'rename'),
    (label: 'Move card', verb: 'reorder'),
  ];

  /// A card's backup, restore and delete.
  static const cardSafe = <Choice>[
    (label: 'Back up card', verb: 'back_up_card'),
    (label: 'Restore card', verb: 'restore_card'),
    (label: 'Delete card', verb: 'delete_card'),
  ];

  /// A card's More... page.
  static const cardMore = <Choice>[
    (label: 'New card', verb: 'new_card'),
    (label: 'Duplicate', verb: 'duplicate'),
    (label: 'Check', verb: 'check'),
    (label: 'Import save', verb: 'import'),
    (label: 'Undelete', verb: 'undelete'),
    (label: 'Back up every card', verb: 'back_up_all'),
    (label: 'Bring back a deleted card', verb: 'deleted_cards'),
  ];

  /// An unformatted card's More... page.
  static const blankMore = <Choice>[
    (label: 'New card', verb: 'new_card'),
    (label: 'Back up every card', verb: 'back_up_all'),
    (label: 'Bring back a deleted card', verb: 'deleted_cards'),
  ];

  /// [button] value of the paint button under the cards, left of the grid.
  static const backUpAll = 4;

  /// Verbs drawn in the danger colour.
  static const destructive = ['delete', 'delete_all', 'format', 'delete_card'];

  /// Every card read.
  List<MemoryCard> cards = [];

  /// Every save read.
  List<CardSave> allSaves = [];

  /// The saves after the tab and the sort.
  List<CardSave> saves = [];

  /// The page shown.
  Mode mode = Mode.list;

  /// The save you're on, in [saves].
  int index = 0;

  /// The grid's first row on screen.
  int topRow = 0;

  /// The tab, in [filters].
  int filter = 0;

  /// The order, in [sorts].
  int sort = 0;

  /// List: the paint button highlighted, -1 = in the grid.
  int button = -1;

  /// The opened save's button highlighted.
  int openButton = 0;

  /// The card page's button highlighted.
  int cardButton = 0;

  /// The option highlighted, in [flatOptions].
  int option = 0;

  /// The opened save's first file row shown.
  int fileTop = 0;

  /// The card column: -1 = not in it.
  int cardI = -1;

  /// Marked saves, by [saveKey].
  Set<String> marks = {};

  /// Select several was chosen.
  bool picking = false;

  /// The options open now.
  List<ChoiceGroup> groups = [];

  /// Card options: the card they're for (null = a save's or the selection's).
  MemoryCard? optCard;

  /// Move card: up and down carry the card through the list.
  bool moving = false;

  /// The options' More... page is open.
  bool showingMore = false;

  Mode _cameFrom = Mode.list;

  /// New data (first read, or re-read after a game): stays on the same save
  /// if it's still there.
  void setData(List<MemoryCard> newCards, List<CardSave> newSaves) {
    final keep = saveKey(current());
    final optKey = optCard?.key() ?? '';
    var pageKey = '';
    if (mode == Mode.card && focusedCard() != null) {
      pageKey = focusedCard()!.key();
    }
    cards = newCards;
    cardI = cardI < column().length - 1 ? cardI : column().length - 1;
    _followCard(optKey, pageKey);
    allSaves = newSaves;
    marks = {
      for (final s in allSaves)
        if (marks.contains(saveKey(s))) saveKey(s),
    };
    _arrange(keep);
    final onCard =
        mode == Mode.card || (mode == Mode.options && optCard != null);
    if (mode != Mode.list &&
        !onCard &&
        (current() == null || saveKey(current()) != keep)) {
      mode = Mode.list;
    }
  }

  // After the cards are read again: a card's options or page stay on that
  // card (a new object now), and go back to the list when it's gone.
  void _followCard(String optKey, String pageKey) {
    if (optKey.isNotEmpty) {
      optCard = _cardByKey(optKey);
      if (optCard == null) {
        if (mode == Mode.options) {
          mode = Mode.list;
          showingMore = false;
        }
        if (_cameFrom == Mode.card) _cameFrom = Mode.list;
      } else if (mode == Mode.options) {
        groups = optionsForCard(optCard!, showingMore);
        final last = flatOptions().length - 1;
        option = option < (last > 0 ? last : 0) ? option : (last > 0 ? last : 0);
      }
    }
    if (pageKey.isNotEmpty) {
      final found = _cardByKey(pageKey);
      final at = found == null ? -1 : column().indexOf(found);
      if (at < 0) {
        if (mode == Mode.card) mode = Mode.list;
      } else {
        cardI = at;
      }
    }
  }

  MemoryCard? _cardByKey(String k) {
    for (final c in cards) {
      if (c.key() == k) return c;
    }
    return null;
  }

  /// One key per save, even when two cards hold the same id.
  static String saveKey(CardSave? s) {
    if (s == null) return '';
    return '${s.card?.key() ?? ''}|${s.id}';
  }

  /// The save you're on (null = none).
  CardSave? current() => index >= 0 && index < saves.length ? saves[index] : null;

  /// The left column: every card of this tab's console, empty ones too,
  /// yours before the downloaded ones, then as you've put them in order.
  List<MemoryCard> column() {
    final inConsole = <MemoryCard>[];
    final yours = <MemoryCard>[];
    final others = <MemoryCard>[];
    for (final c in cards) {
      if (filter == 0 || c.system == filters[filter]) {
        if (c.slotOrder > 0) {
          inConsole.add(c);
        } else if (c.isTest() || MemoryCards.isDownload(c)) {
          others.add(c);
        } else {
          yours.add(c);
        }
      }
    }
    stableSort<MemoryCard>(
      inConsole,
      (a, b) => a.system != b.system
          ? CardSystems.rank(a.system).compareTo(CardSystems.rank(b.system))
          : a.slotOrder.compareTo(b.slotOrder),
    );
    inConsole
      ..addAll(yours)
      ..addAll(others);
    // Cards you've put in order come in that order; a new one goes after.
    final place = <MemoryCard, int>{
      for (var i = 0; i < inConsole.length; i++) inConsole[i]: i,
    };
    int rank(MemoryCard c) =>
        c.orderRank > 0 ? c.orderRank : 1000000 + place[c]!;
    stableSort<MemoryCard>(inConsole, (a, b) => rank(a).compareTo(rank(b)));
    return inConsole;
  }

  /// The card you're on in the column (null = not in it).
  MemoryCard? focusedCard() {
    final list = column();
    return cardI >= 0 && cardI < list.length ? list[cardI] : null;
  }

  /// Saves of one tab ('ALL' = every save).
  int count(String system) {
    if (system == 'ALL') return allSaves.length;
    var n = 0;
    for (final s in allSaves) {
      if (s.system == system) n++;
    }
    return n;
  }

  /// The saves on screen: (first, one past the last).
  (int, int) visibleSpan() {
    final first = topRow * cols;
    final end = first + cols * rows;
    return (first, end < saves.length ? end : saves.length);
  }

  /// There are rows below the ones on screen.
  bool moreBelow() => (topRow + rows) * cols < saves.length;

  // ---- moving --------------------------------------------------------------

  /// The d-pad. True = something changed.
  bool step(int dx, int dy) => switch (mode) {
    Mode.opened => _stepOpened(dx, dy),
    Mode.options => _stepOptions(dx, dy),
    Mode.card => _stepCard(dx, dy),
    Mode.list => _stepList(dx, dy),
  };

  bool _stepList(int dx, int dy) {
    if (cardI >= 0) return _stepColumn(dx, dy);
    if (button == backUpAll && dy < 0) {
      button = -1;
      cardI = column().length - 1;
      return true;
    }
    if (saves.isEmpty) {
      if (button == backUpAll || column().isEmpty || dx >= 0) return false;
      cardI = 0; // no saves in this tab, but it has cards
      return true;
    }
    if (button == backUpAll) {
      if (dx <= 0 && dy >= 0) return false;
      button = -1;
      return true;
    }
    if (button >= 0) {
      if (dy < 0) {
        button = -1;
        return true;
      }
      final b = clampi(button + dx, 0, listButtons.length - 1);
      final changed = b != button;
      button = b;
      return changed;
    }
    final row = index ~/ cols;
    final col = index % cols;
    if (dx < 0 && col == 0) {
      final at = column().indexOf(current()!.card ?? MemoryCard());
      cardI = at > 0 ? at : 0;
      return true;
    }
    if (dx != 0) {
      final c = clampi(col + dx, 0, cols - 1);
      final to = row * cols + c;
      return _select(to < saves.length - 1 ? to : saves.length - 1);
    }
    if (dy < 0 && row > 0) return _select(index - cols);
    if (dy > 0) {
      if (row < (saves.length - 1) ~/ cols) {
        final to = index + cols;
        return _select(to < saves.length - 1 ? to : saves.length - 1);
      }
      // below the last row: the paint buttons
      button = col < listButtons.length - 1 ? col : listButtons.length - 1;
      return true;
    }
    return false;
  }

  bool _stepColumn(int dx, int dy) {
    if (moving) return dy != 0 ? _carry(dy) : false;
    final last = column().length - 1;
    if (dx > 0 && saves.isNotEmpty) {
      cardI = -1;
    } else if (dy > 0 && cardI >= last) {
      cardI = -1;
      button = backUpAll;
    } else if (dy != 0 && cardI + dy >= 0) {
      cardI = cardI + dy < last ? cardI + dy : last;
    } else {
      return false;
    }
    return true;
  }

  bool _stepOpened(int dx, int dy) {
    if (dx != 0) {
      final b = clampi(openButton + dx, 0, openButtons.length - 1);
      final changed = b != openButton;
      openButton = b;
      return changed;
    }
    final s = current();
    final over = (s?.files.length ?? 0) - filesShown;
    final t = clampi(fileTop + dy, 0, over > 0 ? over : 0);
    final scrolled = t != fileTop;
    fileTop = t;
    return scrolled;
  }

  bool _stepOptions(int dx, int dy) {
    final places = optionPlaces();
    if (option >= places.length) return false;
    final at = places[option];
    final want = (x: at.x + dx, y: at.y + dy);
    var next = -1;
    var fallback = -1;
    for (var i = 0; i < places.length; i++) {
      if (places[i] == want) {
        next = i;
      } else if (dy != 0 && places[i].y == want.y && fallback < 0) {
        fallback = i; // a row with one option: up / down lands on it
      }
    }
    if (next < 0) next = fallback;
    if (next < 0 || next == option) return false;
    option = next;
    return true;
  }

  bool _select(int i) {
    if (i == index) return false;
    index = i;
    _scrollToIndex();
    return true;
  }

  void _scrollToIndex() {
    final row = index ~/ cols;
    topRow = clampi(topRow, row - rows + 1 > 0 ? row - rows + 1 : 0, row);
  }

  /// Touch: stand on save [i] of [saves] in the grid (out of the column and
  /// the paint buttons). True = something changed.
  bool selectIndex(int i) {
    if (mode != Mode.list || i < 0 || i >= saves.length) return false;
    final left = cardI >= 0 || button >= 0;
    cardI = -1;
    button = -1;
    return _select(i) || left;
  }

  /// Touch: stand on card [i] of [column] (list mode). True = changed.
  bool focusCard(int i) {
    if (mode != Mode.list || moving || i < 0 || i >= column().length) {
      return false;
    }
    final changed = i != cardI || button >= 0;
    cardI = i;
    button = -1;
    return changed;
  }

  /// Touch: highlight paint button [b] of [listButtons] (or [backUpAll]).
  bool selectListButton(int b) {
    if (mode != Mode.list || moving) return false;
    if (b == backUpAll) {
      final changed = button != b || cardI >= 0;
      cardI = -1;
      button = b;
      return changed;
    }
    if (saves.isEmpty || b < 0 || b >= listButtons.length) return false;
    final changed = button != b || cardI >= 0;
    cardI = -1;
    button = b;
    return changed;
  }

  /// Touch: highlight button [b] of an opened save or a card's page.
  bool selectPageButton(int b) {
    if (mode == Mode.opened && b >= 0 && b < openButtons.length) {
      final changed = b != openButton;
      openButton = b;
      return changed;
    }
    final c = focusedCard();
    if (mode == Mode.card && c != null && b >= 0 && b < cardButtons(c).length) {
      final changed = b != cardButton;
      cardButton = b;
      return changed;
    }
    return false;
  }

  /// Touch: highlight option [i] of [flatOptions].
  bool selectOption(int i) {
    if (mode != Mode.options || i < 0 || i >= flatOptions().length) {
      return false;
    }
    final changed = i != option;
    option = i;
    return changed;
  }

  /// Touch: go to tab [f] of [filters] (list mode).
  bool selectFilter(int f) {
    if (mode != Mode.list || f < 0 || f >= filters.length) return false;
    return turnPage(f - filter);
  }

  /// LB / RB: the tabs in the list, the save before / after when one is
  /// open, the card above / below on a card's page.
  bool turnPage(int dir) {
    if (mode == Mode.list) {
      final f = clampi(filter + dir, 0, filters.length - 1);
      if (f == filter) return false;
      final keep = saveKey(current());
      filter = f;
      button = -1;
      cardI = -1;
      _arrange(keep);
      return true;
    }
    if (mode == Mode.card) {
      final last = column().length - 1;
      final at = clampi(cardI + dir, 0, last > 0 ? last : 0);
      if (at == cardI) return false;
      cardI = at;
      cardButton = 0;
      return true;
    }
    final last = saves.length - 1;
    if (mode == Mode.opened && _select(clampi(index + dir, 0, last > 0 ? last : 0))) {
      fileTop = 0;
      return true;
    }
    return false;
  }

  // ---- buttons -------------------------------------------------------------

  /// A: '' = opened something here, else the verb to run ('none' = nothing
  /// there).
  String confirm() {
    if (moving) {
      moving = false;
      return 'order_done';
    }
    if (mode == Mode.options) {
      final flat = flatOptions();
      return option < flat.length ? flat[option].verb : 'none';
    }
    if (mode == Mode.list && cardI >= 0 && focusedCard() != null) {
      mode = Mode.card; // a card: its own page, like a save's
      cardButton = 0;
      return '';
    }
    if (mode == Mode.card) {
      final c = focusedCard();
      if (c == null) return 'none';
      final verb = cardButtons(c)[cardButton].verb;
      if (verb == 'options') {
        _openOptions(c);
        return '';
      }
      optCard = c; // what the verb works on
      _cameFrom = Mode.card;
      return verb;
    }
    if (current() == null) return 'none';
    if (mode == Mode.opened) return openButtons[openButton].verb;
    if (button == backUpAll) return 'back_up_all';
    if (button >= 0) return listButtons[button].verb;
    if (selecting()) {
      // while choosing, A chooses
      toggleMark();
      return '';
    }
    mode = Mode.opened;
    openButton = 0;
    fileTop = 0;
    return '';
  }

  /// B: false = there's nowhere further back (leave the save manager).
  bool cancel() {
    if (moving) {
      moving = false;
      return true;
    }
    if (mode == Mode.options) {
      if (showingMore) {
        showMore(false); // back to the first page, on More...
        return true;
      }
      mode = _cameFrom;
      return true;
    }
    if (mode == Mode.opened) {
      mode = Mode.list;
      return true;
    }
    if (mode == Mode.card) {
      mode = Mode.list; // back to the column, on the same card
      optCard = null;
      return true;
    }
    if (cardI >= 0) {
      cardI = -1;
      return true;
    }
    if (button >= 0) {
      button = -1;
      return true;
    }
    if (selecting()) {
      clearSelection();
      return true;
    }
    return false;
  }

  /// Y: opens (or closes) the options for what you're on.
  bool toggleOptions() {
    if (mode == Mode.options) return cancel();
    if (moving) return false;
    final onCard = (mode == Mode.list || mode == Mode.card) && cardI >= 0;
    return _openOptions(onCard ? focusedCard() : null);
  }

  /// X: marks or unmarks the save you're on.
  bool toggleMark() {
    if (mode != Mode.list || button >= 0 || cardI >= 0 || current() == null) {
      return false;
    }
    final key = saveKey(current());
    if (!marks.remove(key)) {
      marks.add(key);
      picking = true;
    }
    return true;
  }

  /// Picking saves (Select several, or something is marked).
  bool selecting() => picking || marks.isNotEmpty;

  /// Select several: back to the grid, A now marks.
  void startSelecting() {
    mode = Mode.list;
    button = -1;
    cardI = -1;
    picking = true;
  }

  /// Unmarks everything and stops picking.
  void clearSelection() {
    marks.clear();
    picking = false;
  }

  /// What an option says, naming what it would act on.
  String actionLabel(String label, String verb) {
    const counted = ['copy', 'move', 'back_up', 'export', 'favorite', 'delete'];
    if (counted.contains(verb) &&
        marks.isNotEmpty &&
        _cameFrom != Mode.opened) {
      return '$label ${marks.length} selected';
    }
    if (verb == 'sort') {
      return 'Sort: ${sorts[(sort + 1) % sorts.length].toLowerCase()}';
    }
    return label;
  }

  /// Hold X: marks every save of that game. Returns how many.
  int markGame() {
    final cur = current();
    if (cur == null) return 0;
    var n = 0;
    for (final s in allSaves) {
      if (s.system == cur.system && s.displayName() == cur.displayName()) {
        marks.add(saveKey(s));
        n++;
      }
    }
    return n;
  }

  /// What a verb acts on: the marked saves, else the one you're on (always
  /// that one when it's open).
  List<CardSave> chosen() {
    final out = <CardSave>[];
    if (mode != Mode.opened) {
      for (final s in allSaves) {
        if (marks.contains(saveKey(s))) out.add(s);
      }
    }
    if (out.isEmpty && current() != null) out.add(current()!);
    return out;
  }

  /// Favorite turns them all on, unless they all are already.
  bool favoriteTurnsOn() {
    for (final s in chosen()) {
      if (!s.favorite) return true;
    }
    return false;
  }

  /// The next order; returns its name.
  String cycleSort() {
    final keep = saveKey(current());
    sort = (sort + 1) % sorts.length;
    _arrange(keep);
    return sorts[sort];
  }

  /// Every open option, in order.
  List<Choice> flatOptions() => [for (final g in groups) ...g.items];

  /// Column (x) and row (y) of each option, in flat order: two to a row,
  /// each group starting a row of its own.
  List<({int x, int y})> optionPlaces() {
    final out = <({int x, int y})>[];
    var row = 0;
    for (final g in groups) {
      for (var k = 0; k < g.items.length; k++) {
        out.add((x: k % 2, y: row + k ~/ 2));
      }
      row += (g.items.length + 1) ~/ 2;
    }
    return out;
  }

  // ---- what the options are ------------------------------------------------

  /// A card's page: the big buttons along the bottom.
  List<Choice> cardButtons(MemoryCard c) {
    if (c.unformatted) {
      return const [
        (label: 'FORMAT', verb: 'format'),
        (label: 'OPTIONS', verb: 'options'),
      ];
    }
    final out = <Choice>[
      (label: 'CUSTOMIZE', verb: 'customize'),
      (label: 'RENAME', verb: 'rename'),
    ];
    if (CardSlots.systems.contains(c.system) && !c.isFolder) {
      out.add(
        c.inSlot.isNotEmpty
            ? (label: 'TAKE OUT', verb: 'slot_out')
            : (label: 'PUT IN', verb: 'slot_in'),
      );
    }
    out.add((label: 'OPTIONS', verb: 'options'));
    return out;
  }

  bool _stepCard(int dx, int dy) {
    final c = focusedCard();
    if (dx == 0 || c == null) return false;
    final b = clampi(cardButton + dx, 0, cardButtons(c).length - 1);
    final changed = b != cardButton;
    cardButton = b;
    return changed;
  }

  /// A card's options ([more] = the More... page).
  List<ChoiceGroup> optionsForCard(MemoryCard c, [bool more = false]) {
    if (more) {
      return [
        (
          heading: 'MORE FOR THIS CARD',
          items: c.unformatted ? blankMore : cardMore,
        ),
      ];
    }
    final these = List<Choice>.of(cardOptions);
    if (CardSlots.systems.contains(c.system) && !c.isFolder) {
      these.add(
        c.inSlot.isNotEmpty
            ? (label: 'Take out of console', verb: 'slot_out')
            : (label: 'Put in console', verb: 'slot_in'),
      );
    }
    if (c.unformatted) {
      these.add((label: 'Format', verb: 'format'));
    } else {
      these.addAll(cardSafe.sublist(0, 2));
    }
    these
      ..add(cardSafe[2])
      ..add(MemoryCardState.more);
    return [(heading: 'THIS CARD', items: these)];
  }

  /// A save's options ([opened]: it's open; [more] = the More... page).
  List<ChoiceGroup> optionsForSave(
    CardSave s,
    bool opened, [
    bool more = false,
  ]) {
    if (more) {
      return [
        (
          heading: 'MORE FOR THIS SAVE',
          items: opened ? [saveMore[0]] : saveMore,
        ),
      ];
    }
    final these = <Choice>[
      for (final o in saveOptions)
        if (o.verb != 'start' || s.gameId.isNotEmpty) o,
      MemoryCardState.more,
    ];
    return [(heading: 'THIS SAVE', items: these)];
  }

  /// The marked saves' options.
  List<ChoiceGroup> optionsForSelection() => [
    (heading: 'THE ${marks.length} SELECTED', items: selectedOptions),
  ];

  /// More...: the page of less used options, and back (B) to the first.
  void showMore(bool on) {
    showingMore = on;
    if (optCard != null) {
      groups = optionsForCard(optCard!, on);
    } else if (current() != null) {
      groups = optionsForSave(current()!, _cameFrom == Mode.opened, on);
    }
    option = 0;
    if (!on) {
      final flat = flatOptions();
      for (var i = 0; i < flat.length; i++) {
        if (flat[i].verb == 'more') option = i;
      }
    }
  }

  // Opens the options for what you're on. False = nothing to work on.
  bool _openOptions(MemoryCard? onCard) {
    _cameFrom = mode;
    optCard = null;
    showingMore = false;
    if (onCard != null) {
      optCard = onCard;
      groups = optionsForCard(onCard);
    } else if (marks.isNotEmpty && mode == Mode.list) {
      groups = optionsForSelection();
    } else if (current() != null) {
      groups = optionsForSave(current()!, mode == Mode.opened);
    } else if (column().isNotEmpty) {
      cardI = 0;
      optCard = column()[0];
      groups = optionsForCard(optCard!);
    } else {
      return false;
    }
    mode = Mode.options;
    option = 0;
    return true;
  }

  // ---- moving a card -------------------------------------------------------

  /// Move card: the card stays highlighted and up / down carry it. A or B
  /// puts it down.
  void startMoving() {
    final c = optCard;
    mode = Mode.list;
    button = -1;
    _rankAll();
    final at = c == null ? -1 : column().indexOf(c);
    cardI = at > 0 ? at : 0;
    moving = true;
  }

  // Every card gets a place, in the order shown with every tab, so a move in
  // one tab keeps the rest as they were.
  void _rankAll() {
    final all = fullColumn();
    for (var i = 0; i < all.length; i++) {
      all[i].orderRank = i + 1;
    }
  }

  bool _carry(int dir) {
    final list = column();
    final to = cardI + dir;
    if (cardI < 0 || to < 0 || to >= list.length) return false;
    final r = list[cardI].orderRank;
    list[cardI].orderRank = list[to].orderRank;
    list[to].orderRank = r;
    cardI = to;
    return true;
  }

  /// Every card, top first, as you've put them (for saving the order).
  List<MemoryCard> fullColumn() {
    final keep = filter;
    filter = 0;
    final all = column();
    filter = keep;
    return all;
  }

  void _arrange(String keep) {
    saves = [
      for (final s in allSaves)
        if (filter == 0 || s.system == filters[filter]) s,
    ];
    if (sort == 1) {
      stableSort<CardSave>(saves, (a, b) {
        final byName = naturalNoCaseCompare(a.displayName(), b.displayName());
        return byName != 0 ? byName : b.modified.compareTo(a.modified);
      });
    } else if (sort == 2) {
      stableSort<CardSave>(
        saves,
        (a, b) => a.kb != b.kb
            ? b.kb.compareTo(a.kb)
            : b.modified.compareTo(a.modified),
      );
    }
    index = 0;
    for (var i = 0; i < saves.length; i++) {
      if (saveKey(saves[i]) == keep) {
        index = i;
        break;
      }
    }
    topRow = 0;
    _scrollToIndex();
    if (saves.isEmpty) button = -1;
  }
}
