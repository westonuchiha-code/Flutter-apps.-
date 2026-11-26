/// Touch and mouse, the PC's buttons made tappable: tapping something not
/// highlighted highlights it, tapping it again is A. Long press (or a
/// right click) is Y.
library;

import '../controller.dart';
import '../state.dart';

class Taps {
  /// Taps for [c]; [onGame] hears a game id A asked to start.
  const Taps(this.c, {this.onGame});

  final SaveManagerController c;

  /// A asked to start this game (this app has no games: a hook).
  final void Function(String gameId)? onGame;

  MemoryCardState get _st => c.state;

  /// A, with the start-game hook.
  void confirm() {
    final game = c.confirm();
    if (game.isNotEmpty) onGame?.call(game);
  }

  /// Outside the options while they're open: B.
  bool _backOut() {
    if (_st.mode == Mode.list) return false;
    c.cancel();
    return true;
  }

  // ---- the list ------------------------------------------------------------

  void save(int i) {
    if (_backOut()) return;
    if (_st.selecting()) {
      // choosing several: one tap stands on it and picks it
      c.selectSave(i);
      confirm();
      return;
    }
    if (!c.selectSave(i)) confirm();
  }

  void saveOptions(int i) {
    if (_st.mode != Mode.list) return;
    c.selectSave(i);
    c.toggleOptions();
  }

  void card(int i) {
    if (_backOut() || _st.moving) return;
    if (!c.selectCard(i)) confirm();
  }

  void cardOptions(int i) {
    if (_st.mode != Mode.list || _st.moving) return;
    c.selectCard(i);
    c.toggleOptions();
  }

  void button(int b) {
    if (_backOut()) return;
    if (!c.selectListButton(b)) confirm();
  }

  void tab(int f) {
    if (_backOut()) return;
    c.selectFilter(f);
  }

  void option(int i) {
    if (!c.selectOption(i)) confirm();
  }

  void sort() {
    if (_backOut()) return;
    final name = _st.cycleSort();
    c.showNotice('Sorted: ${name.toLowerCase()}');
  }

  // ---- an opened save, a card's page -----------------------------------------

  void pageButton(int b) {
    if (!c.selectPageButton(b)) confirm();
  }

  // ---- the dialogs ---------------------------------------------------------

  /// A picker's row or a question's button.
  void item(int i) {
    if (!c.selectFlowItem(i)) confirm();
  }

  /// A save on the copy screen: stands on it and marks / unmarks it.
  void copyCell(int i) {
    c.selectCopyCell(i);
    c.mark();
  }

  void copyButton(int b) {
    if (!c.selectCopyButton(b)) confirm();
  }

  void copyTarget(int i) => c.selectCopyTarget(i);

  /// Customize's row [r] (A on it when it's already highlighted).
  void lookRow(int r) {
    if (!c.selectLookRow(r)) confirm();
  }

  /// Customize's < > on row [r].
  void lookChange(int r, int dx) {
    c.selectLookRow(r);
    c.step(dx, 0);
  }

  /// The emulators-closed question's answer [i].
  void closedAnswer(int i) {
    if (!c.selectClosedAnswer(i)) confirm();
  }
}
