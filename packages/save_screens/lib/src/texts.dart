/// The save manager's words: names, dates, sizes, the rows of a save's and
/// a card's sheets, the button hints and the dialogs' text (ported from the
/// PC's MemoryCardPages.gd and MemoryCardDialogs.gd, without the drawing).
library;

import 'package:save_kit/save_kit.dart';

import 'flow.dart';
import 'state.dart';

/// A label and its value, for a sheet row.
typedef Row2 = (String, String);

/// A button hint: which [button] does what ([label]).
typedef Hint = ({String button, String label});

/// Text helpers. All static, all pure.
abstract final class Texts {
  /// Names too long for a cell that "..." would ruin.
  static const nicknames = {
    'Saru! Get You! Million Monkeys': 'Million Monkeys',
    'Saru Get You - Million Monkeys': 'Million Monkeys',
    'Ys V Lost Kefin Kingdom of Sand': 'Ys V',
    'Ys V - Lost Kefin, Kingdom of Sand': 'Ys V',
  };

  /// Month names for [dateText].
  static const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// While a job runs, under its title.
  static const workingNote = "Don't switch off while a card is being written";

  /// "Grand Theft Auto - San Andreas" -> "GTA: San Andreas".
  static String shortName(String title) =>
      nicknames[title] ??
      title
          .replaceAll('Grand Theft Auto - ', 'GTA: ')
          .replaceAll('Grand Theft Auto ', 'GTA ');

  /// Play time: "12 min", "2 h 0 min".
  static String lasted(int seconds) {
    if (seconds < 3600) {
      final m = (seconds / 60).round();
      return '${m > 1 ? m : 1} min';
    }
    final minutes = (seconds / 60).round();
    return '${minutes ~/ 60} h ${minutes % 60} min';
  }

  /// Unix seconds as "Nov 22, 2026, 1:50 PM" ([offset] = seconds east of
  /// UTC); 0 = "Not recorded".
  static String dateText(int unix, int offset) {
    if (unix <= 0) return 'Not recorded';
    final d = DateTime.fromMillisecondsSinceEpoch(
      (unix + offset) * 1000,
      isUtc: true,
    );
    final twelve = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final minute = d.minute.toString().padLeft(2, '0');
    return '${months[d.month - 1]} ${d.day}, ${d.year}, $twelve:$minute '
        '${d.hour < 12 ? 'AM' : 'PM'}';
  }

  /// 512 -> "512 B", 5000 -> "5 KB".
  static String bytesText(int n) =>
      n < 1024 ? '$n B' : '${MemoryCard.thousands((n / 1024).ceil())} KB';

  /// The local time zone's offset, in seconds.
  static int localOffset() => DateTime.now().timeZoneOffset.inSeconds;

  /// A save's own rows ([opened]: the save is open, so its card's place is
  /// named too).
  static List<Row2> saveRows(CardSave s, int utcOffset, {bool opened = false}) {
    var where = '';
    final c = s.card;
    if (c != null) {
      where = opened ? '${c.name} (${MemoryCards.place(c)})' : c.name;
      if (s.system == 'PS1' && s.held.isNotEmpty) {
        where += s.held.length == 1
            ? ', block ${s.held[0]}'
            : ', blocks ${s.held.first}-${s.held.last}';
      }
    }
    return [
      ('Saved', dateText(s.modified, utcOffset)),
      ('Created', dateText(s.created, utcOffset)),
      ('Size', s.sizeText()),
      ('Card', where),
      ('Copy protected', s.copyProtected ? 'Yes' : 'No'),
      ('Save ID', s.id),
    ];
  }

  /// A save's game rows.
  static List<Row2> gameRows(CardSave s, int utcOffset) {
    final played = s.sessions > 0;
    final code = s.serial.isEmpty
        ? 'Unknown'
        : (s.system == 'PS3' ? Ps3Card.serialText(s.serial) : s.serial);
    return [
      ('Game', s.displayName()),
      ('Region', s.region.isNotEmpty ? s.region : 'Unknown'),
      ('Product code', code),
      ('Time played', played ? lasted(s.playedS) : 'Not recorded'),
      ('Sessions', played ? '${s.sessions}' : '-'),
      ('Last played', played ? dateText(s.lastPlayed, utcOffset) : '-'),
    ];
  }

  /// The list's side panel: the first four save rows, then the game's
  /// (without its name).
  static List<Row2> sideRows(CardSave s, int utcOffset) => [
    ...saveRows(s, utcOffset).take(4),
    ...gameRows(s, utcOffset).skip(1),
  ];

  /// What a card's page says about it.
  static List<Row2> cardRows(MemoryCard c, int utcOffset) {
    final info = CardSystems.info[c.system] ?? const {};
    var where = 'Not in the console';
    if (c.inSlot.isNotEmpty) {
      where = 'Yes, slot ${c.inSlot.split(' ').last}'; // A1 / 2
    } else if (!CardSlots.systems.contains(c.system) || c.isFolder) {
      where = 'Its emulator picks it per game';
    }
    final at = CardLooks.paletteIndex(c.color, c.finish);
    var colour = c.color != 0 ? CardLooks.palette[at].$1 : "Console's own";
    if (c.color != 0 && at == 0) {
      colour = c.finish.isNotEmpty
          ? c.finish[0].toUpperCase() + c.finish.substring(1)
          : 'Custom';
    }
    return [
      ('Console', info['name'] ?? c.system),
      ('Space', c.freeText()),
      ('Saves', '${c.saves.length}'),
      ('In the console', where),
      ('Colour', colour),
      ('Sticker', c.sticker.isNotEmpty ? 'Yes' : 'None'),
      ('Changed', dateText(c.modified, utcOffset)),
      ('Kept in', MemoryCards.place(c)),
    ];
  }

  /// Under a card's name on its page: "Dreamcast memory card - IN ...".
  static String cardTag(MemoryCard c) {
    var tag = '${CardSystems.info[c.system]?['name'] ?? c.system} memory card';
    if (c.inSlot.isNotEmpty) tag += '  -  ${c.inSlot}';
    return tag;
  }

  /// A card page's saves heading: "SAVES (24)  first 19".
  static String cardSavesHeading(MemoryCard c, {int shown = 19}) {
    var head = 'SAVES (${c.saves.length})';
    if (c.saves.length > shown) head += '  first $shown';
    return head;
  }

  /// The list's top right: the order, or how many are selected.
  static String listCorner(MemoryCardState st) => st.marks.isEmpty
      ? MemoryCardState.sorts[st.sort]
      : '${st.marks.length} selected';

  /// The grid when there's no save to show.
  static String emptyGrid(bool loading) =>
      loading ? 'Reading your memory cards...' : 'No saves here yet';

  /// The options panel's heading.
  static String optionsHeading(MemoryCardState st) {
    final s = st.current();
    var head = s != null ? shortName(s.displayName()) : 'Memory cards';
    if (st.optCard != null) {
      head = st.optCard!.name;
    } else if (st.marks.isNotEmpty &&
        st.groups.isNotEmpty &&
        st.groups[0].heading.startsWith('THE ')) {
      head = '${st.marks.length} selected';
    }
    return head;
  }

  /// What an option says now ("Unfavorite", "Copy 3 selected"...).
  static String optionLabel(MemoryCardState st, Choice o) {
    var label = o.label;
    if (o.verb == 'favorite' && st.current() != null && !st.favoriteTurnsOn()) {
      label = 'Unfavorite';
    }
    return st.actionLabel(label, o.verb);
  }

  /// The button hints for what shows now.
  static List<Hint> hints(MemoryCardState st, MemoryCardFlow flow) {
    Hint h(String button, String label) => (button: button, label: label);
    if (flow.isOpen()) return dialogHints(flow);
    if (st.moving) {
      return [
        h('Up / Down', 'Move the card'),
        h('A', 'Put it here'),
        h('B', 'Done'),
      ];
    }
    switch (st.mode) {
      case Mode.opened:
        return [
          h('A', 'Select'),
          h('B', 'Back to all saves'),
          h('LB / RB', 'Other saves'),
          h('RT', 'Favorite'),
          h('Y', "This save's options"),
        ];
      case Mode.options:
        return [h('A', 'Select'), h('B', 'Back')];
      case Mode.card:
        return [
          h('A', 'Select'),
          h('B', 'Back to the cards'),
          h('LB / RB', 'Other cards'),
          h('Y', 'All card options'),
        ];
      case Mode.list:
        break;
    }
    if (st.saves.isEmpty) {
      return [h('B', 'Back'), h('LB / RB', 'Console'), h('Y', 'Options')];
    }
    if (st.cardI >= 0) {
      return [
        h('A', 'Open card'),
        h('Y', 'Card options'),
        h('B', 'Back to saves'),
        h('LB / RB', 'Console'),
      ];
    }
    if (st.selecting() && st.button < 0) {
      final onIt = st.marks.contains(MemoryCardState.saveKey(st.current()));
      return [
        h('A', onIt ? 'Unselect' : 'Select'),
        if (st.marks.isNotEmpty)
          h('Y', 'Copy, move or delete ${st.marks.length}'),
        h('B', 'Cancel'),
        h('LB / RB', 'Console'),
      ];
    }
    return [
      h('A', st.button >= 0 ? 'Select' : 'Open'),
      h('B', st.marks.isEmpty ? 'Back' : 'Unmark all'),
      h('X', 'Select'),
      h('RT', 'Favorite'),
      h('LB / RB', 'Console'),
      h('Y', "This save's options"),
    ];
  }

  /// The dialogs' button hints.
  static List<Hint> dialogHints(MemoryCardFlow flow) {
    Hint h(String button, String label) => (button: button, label: label);
    switch (flow.kind) {
      case FlowKind.pick:
      case FlowKind.ask:
        return [h('A', 'Select'), h('B', 'Back')];
      case FlowKind.copy:
        return [
          h('A', flow.inButtons ? 'Select' : 'Mark'),
          h('B', 'Back'),
          if (flow.targets.length > 1) h('LB / RB', 'Other card'),
        ];
      case FlowKind.look:
        return [
          h('Left / Right', 'Change'),
          h('A', flow.lookRow < 2 ? 'Next' : 'Select'),
          h('B', 'Cancel'),
        ];
      case FlowKind.none:
      case FlowKind.working:
        return [];
    }
  }

  /// A picker's "3 of 12" (when it has more rows than fit; '' otherwise).
  static String pickCounter(MemoryCardFlow flow) =>
      flow.items.length > MemoryCardFlow.pickRows
      ? '${flow.index + 1} of ${flow.items.length}'
      : '';

  /// Customize's value per row of [MemoryCardFlow.lookRows].
  static List<String> lookValues(MemoryCardFlow flow) {
    final card = flow.lookCard;
    return [
      '<  ${flow.colorName()}  >',
      '<  ${flow.stickerName()}  >',
      card != null ? '${card.name}   (A to type a new one)' : '',
      'Keep this look',
    ];
  }

  /// Customize's help lines ([stickerFolder] = where your pictures go).
  static List<String> lookHelp(String stickerFolder) => [
    'Stickers: game art, screenshots and save icons from this card.',
    'Put pictures in $stickerFolder and they show up here.',
    'Only this menu shows the look. The card file stays exactly as it is.',
  ];

  /// Copy screen, the source pane when the saves come from several cards:
  /// "From 3 different cards".
  static String copyFromText(MemoryCardFlow flow) {
    final homes = {for (final s in flow.list) s.card?.key() ?? ''};
    return 'From ${homes.length} different cards';
  }

  /// Copy screen, the target's free space after the copy ('' = no target;
  /// "Not enough room" when it won't fit).
  static String copyTargetText(MemoryCardFlow flow) {
    final to = flow.target();
    if (to == null) return '';
    final after = to.free - copyAmount(flow);
    return after < 0
        ? 'Not enough room'
        : '${MemoryCard.thousands(after)} ${CardSystems.unit(to.system, after)} free afterwards';
  }

  /// Copy screen: the space the arriving saves need, in the card's unit.
  static int copyAmount(MemoryCardFlow flow) {
    var amount = 0;
    for (final s in flow.arriving()) {
      amount += s.system == 'PS2' ? s.kb : s.blocks;
    }
    return amount;
  }

  /// Copy screen's summary: "3 saves, 1,024 KB".
  static String copySummary(MemoryCardFlow flow) {
    final coming = flow.arriving();
    var kb = 0;
    for (final s in coming) {
      kb += s.kb;
    }
    return '${coming.length} save${coming.length == 1 ? '' : 's'}, '
        '${MemoryCard.thousands(kb)} KB';
  }

  /// Copy screen: "and 4 more" under a full target pane ('' = all shown).
  static String copyMore(MemoryCardFlow flow) {
    const perPage = MemoryCardFlow.copyCols * MemoryCardFlow.copyRows;
    final n = flow.arriving().length;
    return n > perPage ? 'and ${n - perPage} more' : '';
  }

  /// A question line that is the save-state warning (drawn as a warning).
  static bool isWarning(String line) => line == MemoryCardFlow.stateNote;

  /// Words to lines of at most [width] characters.
  static List<String> wrapped(String text, int width) {
    final out = <String>[];
    var line = '';
    for (final word in text.split(' ').where((w) => w.isNotEmpty)) {
      if (line.isNotEmpty && line.length + 1 + word.length > width) {
        out.add(line);
        line = word;
      } else {
        line = line.isEmpty ? word : '$line $word';
      }
    }
    if (line.isNotEmpty) out.add(line);
    return out;
  }
}
