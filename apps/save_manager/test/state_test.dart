// The save manager's cursor (ported from the PC's MemoryCardTests.gd
// _state and CardFlowTests.gd _options_fit / _card_page): every button is
// safe, the grid scrolls by row, the options are all reachable, and nothing
// destructive is ever highlighted first.
import 'package:flutter_test/flutter_test.dart';
import 'package:save_kit/save_kit.dart';
import 'package:save_manager/src/state.dart';
import 'package:save_manager/src/texts.dart';

import 'fixtures.dart';

List<CardSave> fakeSaves(int n, MemoryCard card) {
  final out = <CardSave>[];
  for (var i = 0; i < n; i++) {
    out.add(
      CardSave()
        ..system = i % 3 == 0 ? 'PS1' : 'PS2'
        ..id = 'S${i.toString().padLeft(2, '0')}'
        ..game = 'Game ${(n - i).toString().padLeft(2, '0')}'
        ..kb = i
        ..modified = 1000 - i
        ..card = card,
    );
  }
  card.saves
    ..clear()
    ..addAll(out);
  return out;
}

List<String> verbs(MemoryCardState st) => [
  for (final o in st.flatOptions()) o.verb,
];

/// Every option can be reached from the first with the d-pad.
bool reachesAll(MemoryCardState st) {
  final seen = {0};
  final todo = [0];
  while (todo.isNotEmpty) {
    final from = todo.removeLast();
    for (final d in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      st.option = from;
      st.step(d.$1, d.$2);
      if (seen.add(st.option)) todo.add(st.option);
    }
  }
  st.option = 0;
  return seen.length == st.flatOptions().length;
}

void main() {
  test('no saves: every button is safe', () {
    final st = MemoryCardState();
    expect(st.step(1, 0), isFalse);
    expect(st.confirm(), 'none');
    expect(st.toggleOptions(), isFalse);
    expect(st.cancel(), isFalse);
  });

  test('the grid, the paint buttons, an opened save, tabs and marks', () {
    final card = MemoryCard()..path = 'c';
    final st = MemoryCardState()..setData([card], fakeSaves(23, card));
    for (var i = 0; i < 4; i++) {
      st.step(0, 1);
    }
    expect(st.index, 20, reason: 'five across');
    expect(st.topRow, 1, reason: 'scrolls by row');
    expect(st.visibleSpan(), (5, 23));
    st
      ..step(1, 0)
      ..step(1, 0);
    expect(st.index, 22);
    expect(st.step(1, 0), isFalse, reason: 'stops at the last save');
    expect(st.step(0, 1), isTrue);
    expect(st.button, 2, reason: 'below the last row: the paint buttons');
    expect(st.confirm(), 'back_up', reason: 'a paint button gives its verb');
    expect(st.cancel(), isTrue);
    expect(st.button, -1, reason: 'B leaves the buttons for the grid');
    expect(st.confirm(), '');
    expect(st.mode, Mode.opened, reason: 'A opens a save');
    expect(st.confirm(), 'start', reason: 'START GAME is highlighted first');
    expect(st.toggleOptions(), isTrue);
    expect(
      st.flatOptions()[st.option].verb,
      st.current()!.gameId.isNotEmpty ? 'start' : 'copy',
    );
    expect(st.cancel(), isTrue);
    expect(st.mode, Mode.opened, reason: 'B steps back one level at a time');
    expect(st.cancel(), isTrue);
    final here = MemoryCardState.saveKey(st.current());
    st.cycleSort();
    expect(
      MemoryCardState.saveKey(st.current()),
      here,
      reason: 'sorting keeps the save you are on',
    );
    expect(st.turnPage(1), isTrue);
    expect(st.saves.length, 8, reason: 'PS1 tab');
    expect(st.toggleMark(), isTrue);
    expect(st.chosen().length, 1);
    expect(st.cancel(), isTrue);
    expect(st.marks, isEmpty, reason: 'X marks, B unmarks');
    st.toggleOptions();
    final first = st.mode == Mode.options ? st.flatOptions()[0].verb : '';
    st.cancel();
    for (final buttons in [
      MemoryCardState.listButtons,
      MemoryCardState.openButtons,
    ]) {
      expect(MemoryCardState.destructive, isNot(contains(buttons[0].verb)));
    }
    expect(MemoryCardState.destructive, isNot(contains(first)));
  });

  test('sorts: by game (natural order), biggest first', () {
    final card = MemoryCard()..path = 'c';
    final st = MemoryCardState()..setData([card], fakeSaves(12, card));
    expect(st.cycleSort(), 'By game');
    expect(st.saves.first.game, 'Game 01');
    expect(st.saves.last.game, 'Game 12');
    expect(st.cycleSort(), 'Biggest first');
    expect(st.saves.first.kb, 11);
    expect(st.actionLabel('Sort', 'sort'), 'Sort: newest first');
    expect(naturalNoCaseCompare('Game 2', 'game 10'), lessThan(0));
  });

  test('Y gives the options for what you are on, all reachable', () {
    final cards = fakeCards('DC');
    final st = MemoryCardState()..setData(cards, savesOf(cards));
    st.toggleOptions();
    var v = verbs(st);
    expect(st.optCard, isNull);
    expect(v, contains('copy'));
    for (final no in ['format', 'customize', 'start']) {
      expect(v, isNot(contains(no)), reason: 'no $no on a save here');
    }
    expect(reachesAll(st), isTrue, reason: 'every save option');
    st
      ..cancel()
      ..cardI = 1
      ..toggleOptions();
    v = verbs(st);
    expect(st.optCard, same(cards[1]));
    expect(v, containsAll(['customize', 'reorder', 'slot_in']));
    expect(v, isNot(contains('copy')));
    expect(v, isNot(contains('favorite')));
    expect(MemoryCardState.destructive, isNot(contains(v.first)));
    expect(reachesAll(st), isTrue, reason: 'every card option');
    st.cancel();
    cards[1].inSlot = 'IN THE DREAMCAST, A1';
    st.toggleOptions();
    v = verbs(st);
    expect(v, contains('slot_out'));
    expect(v, isNot(contains('slot_in')));
    st.cancel();
    final n64 = fakeCards('N64');
    st
      ..setData(n64, n64[0].saves)
      ..cardI = 0
      ..toggleOptions();
    v = verbs(st);
    expect(v, isNot(contains('slot_in')));
    expect(v, isNot(contains('slot_out')));
  });

  test('More... and back, on More...', () {
    final cards = fakeCards();
    final st = MemoryCardState()..setData(cards, savesOf(cards));
    st.toggleOptions();
    final more = verbs(st).indexOf('more');
    st.option = more;
    expect(st.confirm(), 'more');
    st.showMore(true);
    expect(st.groups[0].heading, 'MORE FOR THIS SAVE');
    expect(st.cancel(), isTrue);
    expect(st.showingMore, isFalse);
    expect(st.option, more);
  });

  test("A on a card opens its own page", () {
    final cards = fakeCards('DC');
    final st = MemoryCardState()..setData(cards, savesOf(cards));
    st.cardI = 1;
    expect(st.confirm(), '');
    expect(st.mode, Mode.card);
    expect(st.focusedCard(), same(cards[1]));
    expect(
      [for (final b in st.cardButtons(cards[1])) b.verb],
      ['customize', 'rename', 'slot_in', 'options'],
    );
    expect(st.step(-1, 0), isFalse);
    expect(st.step(1, 0), isTrue);
    expect(st.cardButton, 1);
    expect(st.confirm(), 'rename');
    expect(st.optCard, same(cards[1]));
    st.cardButton = 3;
    expect(st.confirm(), '');
    expect(st.mode, Mode.options);
    expect(st.optCard, same(cards[1]));
    expect(st.cancel(), isTrue);
    expect(st.mode, Mode.card, reason: 'B comes back to the page');
    expect(st.toggleOptions(), isTrue);
    expect(st.mode, Mode.options);
    expect(st.cancel(), isTrue);
    expect(st.mode, Mode.card);
    final before = st.cardI;
    expect(st.turnPage(-1), isTrue);
    expect(st.cardI, before - 1);
    expect(st.cardButton, 0);
    expect(st.cancel(), isTrue);
    expect(st.mode, Mode.list);
    expect(st.cardI, before - 1);
    expect(st.optCard, isNull);
    cards[0].inSlot = 'IN THE DREAMCAST, A1';
    expect(st.cardButtons(cards[0])[2].verb, 'slot_out');
    cards[0].unformatted = true;
    expect(st.cardButtons(cards[0])[0].verb, 'format');
    cards[0]
      ..unformatted = false
      ..inSlot = '';
    final rows = Texts.cardRows(cards[1], 0);
    expect(rows.length, 8);
    expect(rows[0].$2, 'Dreamcast');
    expect(rows[3].$2, 'Not in the console');
  });

  test('Select several: A picks, Y works on the selection', () {
    final cards = fakeCards();
    final st = MemoryCardState()..setData(cards, savesOf(cards));
    st.startSelecting();
    st.confirm();
    st.step(1, 0);
    st.confirm();
    expect(st.marks.length, 2);
    st.toggleOptions();
    expect(st.groups[0].heading, 'THE 2 SELECTED');
    expect(st.actionLabel('Copy', 'copy'), 'Copy 2 selected');
    st.cancel();
    expect(st.markGame(), 1, reason: 'each fake save is its own game');
    expect(st.cancel(), isTrue);
    expect(st.selecting(), isFalse);
  });

  test('Move card carries it and keeps the order of every tab', () {
    final cards = [...fakeCards('PS2'), ...fakeCards('PS1')];
    final st = MemoryCardState()..setData(cards, savesOf(cards));
    st
      ..cardI = 0
      ..toggleOptions();
    expect(st.optCard, isNotNull);
    final moved = st.optCard!;
    st.startMoving();
    expect(st.moving, isTrue);
    expect(st.step(0, 1), isTrue);
    expect(st.column()[1], same(moved));
    expect(st.confirm(), 'order_done');
    expect(st.fullColumn()[1], same(moved));
  });

  test('re-reading keeps the save and the card page', () {
    final cards = fakeCards('DC');
    final st = MemoryCardState()..setData(cards, savesOf(cards));
    st
      ..cardI = 1
      ..confirm();
    final again = fakeCards('DC');
    st.setData(again, savesOf(again));
    expect(st.mode, Mode.card);
    expect(st.focusedCard(), same(again[1]));
    st.setData([again[0]], again[0].saves);
    expect(st.mode, Mode.list, reason: 'the card is gone');
  });

  test('touch helpers', () {
    final cards = fakeCards();
    final st = MemoryCardState()..setData(cards, savesOf(cards));
    expect(st.selectIndex(6), isTrue);
    expect(st.index, 6);
    expect(st.selectIndex(99), isFalse);
    expect(st.focusCard(1), isTrue);
    expect(st.focusedCard(), same(st.column()[1]));
    expect(st.selectIndex(2), isTrue);
    expect(st.cardI, -1);
    expect(st.selectListButton(3), isTrue);
    expect(st.confirm(), 'delete');
    expect(st.selectFilter(2), isTrue);
    expect(MemoryCardState.filters[st.filter], 'PS2');
  });

  test('texts', () {
    expect(Texts.dateText(1795355442, 0), contains('2026'));
    expect(Texts.dateText(0, 0), 'Not recorded');
    expect(
      Texts.shortName('Grand Theft Auto - San Andreas'),
      'GTA: San Andreas',
    );
    expect(Texts.lasted(7199), '2 h 0 min');
    expect(Texts.lasted(10), '1 min');
    expect(Texts.bytesText(512), '512 B');
    expect(Texts.bytesText(5000), '5 KB');
    expect(Texts.wrapped('a bb ccc dddd', 6), ['a bb', 'ccc', 'dddd']);
  });
}
