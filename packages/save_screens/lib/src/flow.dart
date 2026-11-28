/// What happens between pressing a verb and its result: pickers, questions,
/// the copy screen, customize (ported 1:1 from the PC's MemoryCardFlow.gd).
/// Pure logic: no widgets. Anything that touches a card becomes a [FlowJob]
/// (plain data) that the host runs off the UI thread with [performJob];
/// [MemoryCardFlow.finish] takes what came back. The safe answer is always
/// highlighted first.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:save_kit/save_kit.dart';

import 'state.dart';
import 'texts.dart';

/// What the flow shows.
enum FlowKind {
  /// Nothing: the state's pages show.
  none,

  /// A list to pick from ([MemoryCardFlow.items], labels and details).
  pick,

  /// A question ([MemoryCardFlow.lines]) with buttons ([MemoryCardFlow.items]).
  ask,

  /// The copy screen: saves on the left, the target card on the right.
  copy,

  /// A job is running ([MemoryCardFlow.title] says what).
  working,

  /// Customize: one card's colour, sticker and name.
  look,
}

/// Saves of one card, by id.
typedef SaveGroup = ({MemoryCard card, List<String> ids});

/// A save file that Import could take in.
typedef ImportFile = ({String file, int time});

/// A sticker a card could wear: key ('' = none) and what it's called.
typedef StickerChoice = ({String key, String label});

/// One job: [verb] says what (the GDScript's "do"), the rest is its data.
/// Plain data only, so it can go to a background isolate.
class FlowJob {
  /// A job doing [verb] with the given data.
  const FlowJob(
    this.verb, {
    this.card,
    this.cards = const [],
    this.groups = const [],
    this.id = '',
    this.entry,
    this.replace = false,
    this.move = false,
    this.to,
    this.file = '',
    this.folders = const [],
    this.slot = '',
    this.where = '',
    this.after = '',
    this.color = '',
    this.sticker = '',
    this.rename = false,
  });

  /// What to do: back_up, export, delete, copy, back_up_cards, save_history,
  /// card_history, lost, restore_save, restore_card, undelete, import_list,
  /// import, format, new_card, duplicate, check, slot_list, slot_in,
  /// delete_card, deleted_cards, bring_back, slot_out_card, slot_out;
  /// handled by the host itself: rename, save_look.
  final String verb;

  /// The card it works on (null for some).
  final MemoryCard? card;

  /// back_up_cards: the cards.
  final List<MemoryCard> cards;

  /// back_up / export / delete / copy: the saves, one group per card.
  final List<SaveGroup> groups;

  /// save_history: the save's id.
  final String id;

  /// restore_save / restore_card / bring_back: a [Backup]; undelete: a
  /// [LostSave].
  final Object? entry;

  /// Copy / import / restore: replace what's there (asked first).
  final bool replace;

  /// Copy: delete the originals once copied.
  final bool move;

  /// Copy: the target card.
  final MemoryCard? to;

  /// import: the save file.
  final String file;

  /// import_list: the folders to look in (the host fills them in).
  final List<String> folders;

  /// slot_in / slot_out: the slot's id.
  final String slot;

  /// slot_in / slot_out / slot_out_card: the slot's name, for the message.
  final String where;

  /// slot_out: what the console does with that slot now.
  final String after;

  /// save_look: the palette value ('' = the console's own).
  final String color;

  /// save_look: the sticker key ('' = none).
  final String sticker;

  /// save_look: the name row was chosen, so ask for a name after.
  final bool rename;

  /// The same job with some fields changed.
  FlowJob copyWith({bool? replace, List<String>? folders}) => FlowJob(
    verb,
    card: card,
    cards: cards,
    groups: groups,
    id: id,
    entry: entry,
    replace: replace ?? this.replace,
    move: move,
    to: to,
    file: file,
    folders: folders ?? this.folders,
    slot: slot,
    where: where,
    after: after,
    color: color,
    sticker: sticker,
    rename: rename,
  );
}

/// One row of a picker, or one button of a question.
class FlowItem {
  /// A row / button.
  FlowItem(
    this.label, {
    this.detail = '',
    this.verb = '',
    this.card,
    this.job,
    this.again = '',
    this.againYes = 'DELETE ALL',
  });

  /// What it says.
  final String label;

  /// Picker: the smaller text on the right.
  final String detail;

  /// Picker: what choosing it does ('entry' = run [job]).
  final String verb;

  /// The card it's about.
  final MemoryCard? card;

  /// What choosing it runs (null = it just closes).
  final FlowJob? job;

  /// Question: ask again with this title before running [job] ('' = don't).
  String again;

  /// The second question's yes button.
  String againYes;
}

/// The emulator folders for console slots ('' = none for that console).
class SlotsConfig {
  /// Plain values for [CardSlots].
  const SlotsConfig({
    required this.recordFile,
    this.raRoot = '',
    this.pcsx2Dir = '',
    this.duckDir = '',
    this.dolphinDir = '',
    this.dolphinUser = '',
    this.windowsPaths,
  });

  /// The slot record (JSON).
  final String recordFile;

  /// RetroArch's folder (Dreamcast).
  final String raRoot;

  /// PCSX2's data folder (PS2).
  final String pcsx2Dir;

  /// DuckStation's folder (PS1).
  final String duckDir;

  /// Dolphin's folder (GameCube).
  final String dolphinDir;

  /// Dolphin's user folder when it isn't portable.
  final String dolphinUser;

  /// Settings paths use '\' (null = on Windows).
  final bool? windowsPaths;

  /// The slots, writing through [store] (null = read only).
  CardSlots build(CardStore? store) => CardSlots(
    store: store,
    recordFile: recordFile,
    formats: standardSlotFormats,
    raRoot: raRoot,
    pcsx2Dir: pcsx2Dir,
    duckDir: duckDir,
    dolphinDir: dolphinDir,
    dolphinUser: dolphinUser,
    windowsPaths: windowsPaths,
  );
}

int _vmuSaves(Uint8List b) => VmuWriter.saves(b).length;
int _ps1Saves(Uint8List b) => Ps1Writer.saves(b).length;
int _ps2Saves(Uint8List b) => Ps2Writer.saveNames(b).length;
int _gcSaves(Uint8List b) => GcWriter.saves(b).length;

/// The card formats [CardSlots] needs, wired to save_kit's writers.
final standardSlotFormats = SlotFormats(
  vmuBlank: VmuWriter.blank,
  vmuCheck: VmuWriter.check,
  vmuSaves: _vmuSaves,
  ps1Saves: _ps1Saves,
  ps2Check: Ps2Writer.check,
  ps2Saves: _ps2Saves,
  gcCheck: GcWriter.check,
  gcSaves: _gcSaves,
);

/// [CardOps]'s constructor values, plain, so a background isolate can
/// build its own.
class CardOpsConfig {
  /// Plain values for [CardOps].
  const CardOpsConfig({
    required this.isApp,
    required this.backupRoot,
    required this.exportDir,
    this.testRoots = const [],
    this.readOnlyDirs = const [],
    this.favoritesFile = '',
    this.looseDir = '',
    this.slots,
    this.askSystem = true,
    this.running,
  });

  /// It's the app: it may change real cards.
  final bool isApp;

  /// Folders a test may write in.
  final List<String> testRoots;

  /// Folders of copies that are never changed ([CardSafety.readOnly]).
  final List<String> readOnlyDirs;

  /// Where backups go.
  final String backupRoot;

  /// Where Export puts save files.
  final String exportDir;

  /// The favorites list ('' = in [backupRoot]).
  final String favoritesFile;

  /// The downloaded saves' folder.
  final String looseDir;

  /// The console slots (null = none).
  final SlotsConfig? slots;

  /// Ask the system which emulators run (not possible on Android).
  final bool askSystem;

  /// When not [askSystem]: the emulators running when the job started
  /// (null = can't tell).
  final List<String>? running;

  /// The write gate.
  CardSafety safety() =>
      CardSafety(isApp: isApp, testRoots: testRoots, readOnly: readOnlyDirs);

  /// A [CardOps] (with its slots) from these values.
  CardOps build() {
    final names = running;
    final ops = CardOps(
      safety: safety(),
      backupRoot: backupRoot,
      exportDir: exportDir,
      favoritesFile: favoritesFile,
      looseDir: looseDir,
      running: askSystem ? null : () => names,
    );
    ops.slots = slots?.build(ops.store);
    return ops;
  }
}

/// Runs [job] with a [CardOps] built from the config: the top-level entry
/// for `runInBackground(performJob, (config, job))`.
Object? performJob((CardOpsConfig, FlowJob) arg) =>
    MemoryCardFlow.perform(arg.$1.build(), arg.$2);

/// The flow between a verb and its result.
class MemoryCardFlow {
  /// Copy screen: saves across.
  static const copyCols = 3;

  /// Copy screen: rows on screen.
  static const copyRows = 4;

  /// Picker: rows on screen.
  static const pickRows = 9;

  /// The copy screen's buttons.
  static const copyButtons = <Choice>[
    (label: 'COPY', verb: 'copy'),
    (label: 'COPY ALL', verb: 'all'),
    (label: 'MOVE', verb: 'move'),
    (label: 'BACK UP', verb: 'back_up'),
  ];

  /// Card verbs that ask which card first, and how.
  static const cardVerbs = {
    'back_up_card': 'Back up which card?',
    'restore_card': 'Restore which card?',
    'duplicate': 'Duplicate which card?',
    'import': 'Import onto which card?',
    'undelete': 'Undelete on which card?',
    'rename': 'Rename which card?',
    'new_card': 'A new card like which one?',
    'check': 'Check which card?',
    'format': 'Format which card?',
    'slot_in': 'Put which card in the console?',
  };

  /// What each console does with a slot a card was taken out of.
  static const afterOut = {
    'DC': 'An empty card is in it now',
    'PS2': 'PCSX2 starts with that slot empty',
    'PS1': 'DuckStation starts with no card in that slot',
    'GC': 'Dolphin starts with no card in that slot',
  };

  /// The slot pickers' note.
  static const slotNote =
      'The console reads its cards when a game starts, so close the game first.';

  /// What a backup was made for.
  static const what = {
    'backup': 'Backed up',
    'delete': 'Before a delete',
    'move': 'Before a move',
    'copy': 'Before a copy',
    'import': 'Before an import',
    'format': 'Before a format',
    'replaced': 'Before being replaced',
    'restore': 'Before a restore',
    'before restore': 'Before a restore',
    'undelete': 'Before an undelete',
  };

  /// The last line of every question that changes a card.
  static const stateNote =
      'Loading an older save state brings the old card back with it.';

  /// How many favorites a delete leaves (use with [staying]).
  static String staying(int n) =>
      "Favorites can't be deleted: $n of them will stay.";

  /// A copy-protected save's warning.
  static const protectedNote =
      "It's copy-protected, so the console would refuse. Press again to do it anyway.";

  /// Customize's rows.
  static const lookRows = ['COLOUR', 'STICKER', 'NAME', 'DONE'];

  /// What shows.
  FlowKind kind = FlowKind.none;

  /// The heading (or, while working, what's being done).
  String title = '';

  /// Question / picker text.
  List<String> lines = [];

  /// Picker rows, or a question's buttons.
  List<FlowItem> items = [];

  /// The row / button highlighted.
  int index = 0;

  /// Picker: the first row on screen.
  int top = 0;

  /// Question: the save shown big (null = none).
  CardSave? subject;

  // The copy screen

  /// Where the saves come from (null = the selection is from several cards).
  MemoryCard? source;

  /// Their console.
  String fromSystem = '';

  /// Cards they could go to.
  List<MemoryCard> targets = [];

  /// The target, in [targets].
  int targetI = 0;

  /// The saves shown on the left.
  List<CardSave> list = [];

  /// Marked saves, by [markKey].
  Set<String> marked = {};

  /// The cursor is on the buttons (else on the saves).
  bool inButtons = true;

  /// The button highlighted, in [copyButtons].
  int button = 0;

  /// The save highlighted, in [list].
  int cell = 0;

  /// The first row of saves on screen.
  int copyTop = 0;

  /// A warning or hint on the copy screen ('' = none).
  String message = '';

  // Customize

  /// The card being customized (its look changes as you go).
  MemoryCard? lookCard;

  /// The row highlighted, in [lookRows].
  int lookRow = 0;

  /// The colour, in [CardLooks.palette].
  int colorI = 0;

  /// What it could wear, "No sticker" first.
  List<StickerChoice> stickers = [];

  /// The sticker, in [stickers].
  int stickerI = 0;

  /// Loads a sticker's picture (the host sets it; null = none shown).
  Pixels? Function(String key, MemoryCard card)? resolve;

  int _wasColor = 0;
  String _wasFinish = '';
  String _wasSticker = '';
  Pixels? _wasImage;

  List<MemoryCard> _cards = [];
  List<MemoryCard> _blanks = []; // unformatted: only Format lists them
  FlowJob? _job; // the one at work
  String _armed = ''; // a copy-protected save's second press

  /// The job at work (null = none).
  FlowJob? get workingJob => _job;

  /// Something shows.
  bool isOpen() => kind != FlowKind.none;

  /// Shows nothing.
  void close() {
    kind = FlowKind.none;
    lookCard = null;
    stickers = [];
    title = '';
    lines = [];
    items = [];
    index = 0;
    top = 0;
    subject = null;
    source = null;
    targets = [];
    list = [];
    marked = {};
    message = '';
    _armed = '';
  }

  /// A verb from the buttons or the options. Returns a job to run, or null.
  FlowJob? begin(
    String verb,
    List<MemoryCard> cards,
    List<CardSave> chosen,
    CardSave? current, [
    MemoryCard? onCard,
  ]) {
    close();
    _cards = [
      for (final c in cards)
        if (c.error.isEmpty) c,
    ];
    _blanks = [
      for (final c in cards)
        if (c.unformatted) c,
    ];
    if (verb == 'back_up_all') {
      return _working(
        FlowJob('back_up_cards', cards: List.of(_cards)),
        'Backing up every card...',
      );
    }
    if (verb == 'slot_out') {
      if (onCard != null && onCard.inSlot.isNotEmpty) {
        return _working(
          FlowJob(
            'slot_out_card',
            card: onCard,
            where: _capitalize(onCard.inSlot),
          ),
          'Taking it out...',
        );
      }
      return _working(const FlowJob('slot_list'), 'Looking in the consoles...');
    }
    if (onCard != null && cardVerbs.containsKey(verb)) {
      // from that card's own options: no need to ask which card
      return _chosen(FlowItem('', verb: verb, card: onCard));
    }
    if (onCard != null && verb == 'copy_all') {
      if (onCard.saves.isEmpty) return null;
      _openCopy(onCard.saves, false);
      return null;
    }
    if (onCard != null && verb == 'delete_all') {
      _askDeleteAll(onCard);
      return null;
    }
    if (onCard != null && verb == 'delete_card') {
      _askDeleteCard(onCard);
      return null;
    }
    if (verb == 'deleted_cards') {
      return _working(
        const FlowJob('deleted_cards'),
        'Looking for deleted cards...',
      );
    }
    if (cardVerbs.containsKey(verb)) {
      _pickCard(verb, onCard ?? current?.card);
      return null;
    }
    if (current == null) return null;
    switch (verb) {
      case 'copy':
      case 'move':
        _openCopy(chosen, verb == 'move');
      case 'copy_all':
        _openCopy(current.card?.saves ?? [], false);
      case 'back_up':
        return _working(
          FlowJob('back_up', groups: groups(chosen)),
          'Backing up...',
        );
      case 'export':
        return _working(
          FlowJob('export', groups: groups(chosen)),
          'Exporting...',
        );
      case 'delete':
        _askDelete(chosen);
      case 'delete_all':
        _askDeleteAll(current.card);
      case 'history':
      case 'restore':
        return _working(
          FlowJob('save_history', card: current.card, id: current.id),
          'Looking for backups...',
        );
    }
    return null;
  }

  /// The saves, one group per card (saves with no card are left out).
  static List<SaveGroup> groups(List<CardSave> saves) {
    final out = <SaveGroup>[];
    final at = <String, int>{};
    for (final s in saves) {
      final c = s.card;
      if (c == null) continue;
      if (!at.containsKey(c.key())) {
        at[c.key()] = out.length;
        out.add((card: c, ids: <String>[]));
      }
      out[at[c.key()]!].ids.add(s.id);
    }
    return out;
  }

  // ---- the buttons ---------------------------------------------------------

  /// The d-pad. True = something changed.
  bool step(int dx, int dy) {
    switch (kind) {
      case FlowKind.pick:
        return _stepPick(dy);
      case FlowKind.ask:
        final to = clampi(index + dx, 0, items.length - 1);
        if (to == index) return false;
        index = to;
        return true;
      case FlowKind.copy:
        return _stepCopy(dx, dy);
      case FlowKind.look:
        return _stepLook(dx, dy);
      case FlowKind.none:
      case FlowKind.working:
        return false;
    }
  }

  /// LB / RB: which card it's going to; a page of a picker; customize's
  /// left / right.
  bool turnPage(int dir) {
    if (kind == FlowKind.look) return _stepLook(dir, 0);
    if (kind == FlowKind.pick) return _stepPick(dir * pickRows);
    if (kind != FlowKind.copy || targets.length < 2) return false;
    targetI = (targetI + dir) % targets.length;
    _disarm();
    return true;
  }

  /// X on the copy screen: marks or unmarks the save highlighted.
  bool mark() {
    if (kind != FlowKind.copy || inButtons || cell >= list.length) return false;
    final id = markKey(list[cell]);
    if (!marked.remove(id)) marked.add(id);
    _disarm();
    return true;
  }

  /// A. Returns a job to run, or null.
  FlowJob? confirm() {
    switch (kind) {
      case FlowKind.pick:
        if (index < items.length) return _chosen(items[index]);
      case FlowKind.ask:
        if (index < items.length) return _answer(items[index]);
      case FlowKind.copy:
        if (inButtons) return _copyButton();
        mark();
      case FlowKind.look:
        if (lookRow < 2) {
          lookRow += 1; // A on a choice moves on to the next one
          return null;
        }
        final job = FlowJob(
          'save_look',
          card: lookCard,
          color: CardLooks.palette[colorI].$2,
          sticker: stickerI < stickers.length ? stickers[stickerI].key : '',
          rename: lookRow == 2,
        );
        lookCard = null; // keeps what it shows: it's being saved
        close();
        return job;
      case FlowKind.none:
      case FlowKind.working:
        break;
    }
    return null;
  }

  /// B. False = nothing to back out of (a job that has started can't be
  /// walked away from).
  bool cancel() {
    if (kind == FlowKind.none || kind == FlowKind.working) return false;
    final card = lookCard;
    if (kind == FlowKind.look && card != null) {
      // back as it was
      card
        ..color = _wasColor
        ..finish = _wasFinish
        ..sticker = _wasSticker
        ..stickerImage = _wasImage;
    }
    close();
    return true;
  }

  // ---- touch ---------------------------------------------------------------

  /// Touch: highlight row / button [i] of [items] (picker or question).
  bool selectItem(int i) {
    if ((kind != FlowKind.pick && kind != FlowKind.ask) ||
        i < 0 ||
        i >= items.length ||
        i == index) {
      return false;
    }
    if (kind == FlowKind.pick) return _stepPick(i - index);
    index = i;
    return true;
  }

  /// Touch: highlight save [i] of [list] on the copy screen.
  bool selectCell(int i) {
    if (kind != FlowKind.copy || i < 0 || i >= list.length) return false;
    final changed = inButtons || i != cell;
    inButtons = false;
    cell = i;
    copyTop = clampi(
      copyTop,
      cell ~/ copyCols - copyRows + 1 > 0 ? cell ~/ copyCols - copyRows + 1 : 0,
      cell ~/ copyCols,
    );
    return changed;
  }

  /// Touch: highlight button [b] of [copyButtons].
  bool selectCopyButton(int b) {
    if (kind != FlowKind.copy || b < 0 || b >= copyButtons.length) return false;
    final changed = !inButtons || b != button;
    inButtons = true;
    if (b != button) _disarm();
    button = b;
    return changed;
  }

  /// Touch: send to target [i] of [targets].
  bool selectTarget(int i) {
    if (kind != FlowKind.copy || i < 0 || i >= targets.length || i == targetI) {
      return false;
    }
    targetI = i;
    _disarm();
    return true;
  }

  /// Touch: highlight row [r] of [lookRows].
  bool selectLookRow(int r) {
    if (kind != FlowKind.look ||
        r < 0 ||
        r >= lookRows.length ||
        r == lookRow) {
      return false;
    }
    lookRow = r;
    return true;
  }

  // ---- customize -----------------------------------------------------------

  /// Opens Customize for [card], with these sticker [choices].
  void openLook(MemoryCard card, List<StickerChoice> choices) {
    close();
    kind = FlowKind.look;
    title = 'CUSTOMIZE';
    lookCard = card;
    _wasColor = card.color;
    _wasFinish = card.finish;
    _wasSticker = card.sticker;
    _wasImage = card.stickerImage;
    stickers = choices;
    colorI = CardLooks.paletteIndex(card.color, card.finish);
    stickerI = 0;
    for (var i = 0; i < stickers.length; i++) {
      if (stickers[i].key == card.sticker) stickerI = i;
    }
    lookRow = 0;
  }

  /// The colour's name.
  String colorName() => CardLooks.palette[colorI].$1;

  /// The sticker's name.
  String stickerName() =>
      stickerI < stickers.length ? stickers[stickerI].label : 'No sticker';

  bool _stepLook(int dx, int dy) {
    if (dy != 0) {
      final r = clampi(lookRow + dy, 0, lookRows.length - 1);
      if (r == lookRow) return false;
      lookRow = r;
      return true;
    }
    final card = lookCard;
    if (dx == 0 || card == null) return false;
    switch (lookRow) {
      case 0:
        colorI = (colorI + dx) % CardLooks.palette.length;
        CardLooks.wear(card, CardLooks.palette[colorI].$2);
        return true;
      case 1:
        if (stickers.length < 2) return false;
        stickerI = (stickerI + dx) % stickers.length;
        card.sticker = stickers[stickerI].key;
        card.stickerImage = resolve?.call(card.sticker, card);
        return true;
    }
    return false;
  }

  // ---- jobs ----------------------------------------------------------------

  /// Runs on a worker. Gives an [OpResult], or a list for the pickers
  /// (List of [Backup], [LostSave], [ImportFile] or [SlotDescription]).
  static Object? perform(CardOps ops, FlowJob job) {
    final card = job.card;
    switch (job.verb) {
      case 'back_up':
      case 'export':
      case 'delete':
        OpResult? last;
        var done = 0;
        for (final g in job.groups) {
          last = switch (job.verb) {
            'back_up' => ops.backUpSaves(g.card, g.ids),
            'export' => ops.exportSaves(g.card, g.ids),
            _ => ops.deleteSaves(g.card, g.ids),
          };
          if (!last.ok) {
            if (done > 0) {
              return OpResult(false, 'Did $done first, then: ${last.text}')
                ..conflicts = last.conflicts;
            }
            return last;
          }
          done += g.ids.length;
        }
        if (last != null && job.groups.length > 1) {
          const did = {
            'back_up': 'Backed up',
            'export': 'Exported',
            'delete': 'Deleted',
          };
          return OpResult(
            last.ok,
            '${did[job.verb]} $done saves from ${job.groups.length} cards',
          )..conflicts = last.conflicts;
        }
        return last;
      case 'copy':
        final to = job.to;
        if (to == null) return OpResult(false, 'No card was chosen');
        return ops.copyMany(
          job.groups,
          to,
          replace: job.replace,
          move: job.move,
        );
      case 'back_up_cards':
        return ops.backUpCards(job.cards);
      case 'save_history':
        return ops.saveHistory(card!, job.id);
      case 'card_history':
        return ops.cardHistory(card!);
      case 'lost':
        return ops.lostSaves(card!);
      case 'restore_save':
        return ops.restoreSave(
          card!,
          job.entry! as Backup,
          replace: job.replace,
        );
      case 'restore_card':
        return ops.restoreCard(card!, job.entry! as Backup);
      case 'undelete':
        return ops.undelete(card!, job.entry! as LostSave);
      case 'import_list':
        return importList(card!.system, job.folders);
      case 'import':
        return ops.importFile(card!, job.file, replace: job.replace);
      case 'format':
        return ops.formatCard(card!);
      case 'new_card':
        return ops.newCard(card!);
      case 'duplicate':
        return ops.duplicateCard(card!);
      case 'check':
        return ops.checkCard(card!);
      case 'slot_list':
        return slotList(ops.slots, card);
      case 'slot_in':
        final no =
            ops.slots?.putIn(job.slot, card) ??
            'Nothing can be moved from here';
        return no.isNotEmpty
            ? OpResult(false, no)
            : OpResult(
                true,
                "${card?.name} is in ${job.where}. Start a game and it's there",
              );
      case 'delete_card':
        return ops.deleteCard(card!);
      case 'deleted_cards':
        return ops.deletedCards();
      case 'bring_back':
        return ops.bringBack(job.entry! as Backup);
      case 'slot_out_card':
        final slot = ops.slots?.slotOf(card!.path);
        if (slot == null) {
          return OpResult(false, "That card isn't in a console slot any more");
        }
        final gone = ops.slots!.takeOut(slot.id);
        return gone.isNotEmpty
            ? OpResult(false, gone)
            : OpResult(
                true,
                'Taken out of ${CardSystems.info[slot.system]!['name']} ${slot.label}',
              );
      case 'slot_out':
        final out =
            ops.slots?.takeOut(job.slot) ?? 'Nothing can be moved from here';
        return out.isNotEmpty
            ? OpResult(false, out)
            : OpResult(true, 'Taken out of ${job.where}. ${job.after}');
    }
    return null;
  }

  /// The slots a card could go in (card = null: every slot, to take one
  /// out). An [OpResult] when there are none.
  static Object slotList(CardSlots? slots, MemoryCard? card) {
    if (slots == null) return OpResult(false, 'Nothing can be moved from here');
    final out = <SlotDescription>[];
    final systems = card != null ? [card.system] : CardSlots.systems;
    var why = '';
    for (final system in systems) {
      why = slots.whyNot(system);
      if (why.isEmpty) out.addAll(slots.describe(system));
    }
    if (out.isEmpty) {
      return OpResult(
        false,
        why.isNotEmpty ? why : 'No console slots were found',
      );
    }
    return out;
  }

  /// Save files for that console lying in these folders, newest first.
  static List<ImportFile> importList(String system, List<String> folders) {
    final out = <ImportFile>[];
    final exts = [CardOps.saveExt[system] ?? ''];
    if (system == 'DC') exts.add('vmi');
    for (final dir in folders) {
      final d = Directory(dir);
      if (!d.existsSync()) continue;
      for (final f in d.listSync().whereType<File>()) {
        final ext = p.extension(f.path).replaceFirst('.', '').toLowerCase();
        if (exts.contains(ext)) {
          out.add((
            file: p.join(dir, p.basename(f.path)),
            time: f.lastModifiedSync().millisecondsSinceEpoch ~/ 1000,
          ));
        }
      }
    }
    stableSort<ImportFile>(out, (a, b) => b.time.compareTo(a.time));
    return out;
  }

  /// Takes what a job gave back. Returns what to tell the player, '' when
  /// a picker or a question opened instead.
  String finish(Object? got, int utcOffset) {
    final job = _job ?? const FlowJob('');
    _job = null;
    close();
    if (got is List) return _showList(job, got, utcOffset);
    if (got is! OpResult) {
      return "That didn't work, so nothing was reported back";
    }
    if (got.conflicts.isEmpty) return got.text;
    final again = job.copyWith(replace: true);
    kind = FlowKind.ask;
    title = "REPLACE WHAT'S THERE?";
    lines = [got.text, ...got.conflicts.take(5)];
    lines.add("The one being replaced is backed up first.");
    items = [FlowItem('KEEP IT'), FlowItem('REPLACE', job: again)];
    return '';
  }

  // ---- inside --------------------------------------------------------------

  FlowJob _working(FlowJob job, String doing) {
    _job = job;
    kind = FlowKind.working;
    title = doing;
    lines = [];
    items = [];
    return job;
  }

  bool _stepPick(int by) {
    if (by == 0 || items.isEmpty) return false;
    final to = clampi(index + by, 0, items.length - 1);
    if (to == index) return false;
    index = to;
    top = clampi(
      top,
      index - pickRows + 1 > 0 ? index - pickRows + 1 : 0,
      index,
    );
    return true;
  }

  void _pickCard(String verb, MemoryCard? preferred) {
    kind = FlowKind.pick;
    title = cardVerbs[verb]!;
    var offered = verb == 'format' || verb == 'slot_in'
        ? [..._cards, ..._blanks]
        : _cards;
    if (verb == 'slot_in') {
      // only the consoles with shared slots; one already in goes from Take out
      offered = [
        for (final c in offered)
          if (CardSlots.systems.contains(c.system) && !c.isFolder) c,
      ];
    }
    for (final c in offered) {
      if (preferred != null && c.key() == preferred.key()) index = items.length;
      items.add(
        FlowItem(
          '${c.name} (${MemoryCards.place(c)})',
          detail: '${CardSystems.info[c.system]?['name']}, ${c.freeText()}',
          verb: verb,
          card: c,
        ),
      );
    }
    top = index - pickRows + 1 > 0 ? index - pickRows + 1 : 0;
    if (items.isEmpty) {
      lines = [
        verb == 'slot_in'
            ? 'No Dreamcast or PS2 cards were found.'
            : 'No memory cards were found.',
      ];
    }
  }

  FlowJob? _chosen(FlowItem it) {
    final card = it.card;
    switch (it.verb) {
      case 'back_up_card':
        return _working(
          FlowJob('back_up_cards', cards: [card!]),
          'Backing up ${card.name}...',
        );
      case 'duplicate':
        return _working(FlowJob('duplicate', card: card), 'Duplicating...');
      case 'new_card':
        return _working(
          FlowJob('new_card', card: card),
          'Making a new card...',
        );
      case 'check':
        return _working(
          FlowJob('check', card: card),
          'Checking ${card?.name}...',
        );
      case 'restore_card':
        return _working(
          FlowJob('card_history', card: card),
          'Looking for backups...',
        );
      case 'undelete':
        return _working(
          FlowJob('lost', card: card),
          'Looking for deleted saves...',
        );
      case 'import':
        return _working(
          FlowJob('import_list', card: card),
          'Looking for save files...',
        );
      case 'slot_in':
        return _working(
          FlowJob('slot_list', card: card),
          'Looking in the console...',
        );
      case 'rename':
        close();
        return FlowJob('rename', card: card); // the host asks for the name
      case 'format':
        final c = card!;
        final starred = [
          for (final s in c.saves)
            if (s.favorite) s,
        ];
        if (starred.isNotEmpty) {
          _keptSafe(starred);
          return null;
        }
        _ask(
          'FORMAT THIS CARD?',
          [
            '${c.name} (${MemoryCards.place(c)})',
            c.freeText(),
            'Every save on it will be erased.',
            'It gets backed up first. Restore card undoes it.',
          ],
          'FORMAT',
          FlowJob('format', card: c),
          c.system,
        );
        return null;
      case 'entry':
        final job = it.job!;
        if (job.verb == 'restore_card' || job.verb == 'restore_save') {
          _ask(
            'RESTORE THIS BACKUP?',
            [it.label, "What's there now is backed up first."],
            'RESTORE',
            job,
            card?.system ?? '',
          );
          return null;
        }
        return _working(job, 'Working...');
    }
    return null;
  }

  // [system] is kept from the PC version (unused there too).
  void _ask(
    String head,
    List<String> body,
    String yes,
    FlowJob job,
    String system,
  ) {
    kind = FlowKind.ask;
    title = head;
    lines = [...body, stateNote];
    items = [FlowItem('KEEP IT'), FlowItem(yes, job: job)];
    index = 0;
  }

  FlowJob? _answer(FlowItem it) {
    if (it.again.isNotEmpty) {
      // Delete all and the like ask a second time
      title = it.again;
      items = [FlowItem('KEEP THEM'), FlowItem(it.againYes, job: it.job)];
      index = 0;
      return null;
    }
    final job = it.job;
    if (job == null) {
      close();
      return null;
    }
    subject = null;
    return _working(job, 'Working...');
  }

  void _askDelete(List<CardSave> chosen) {
    if (chosen.isEmpty) return;
    final saves = _notFavorites(chosen);
    if (saves.isEmpty) {
      _keptSafe(chosen);
      return;
    }
    final job = FlowJob('delete', groups: groups(saves));
    var system = saves[0].system;
    if (saves.length == 1 && chosen.length == 1) {
      _ask(
        'DELETE THIS SAVE?',
        [
          saves[0].displayName(),
          ...saves[0].titleLines,
          'It gets backed up first, so you can restore it later.',
        ],
        'DELETE',
        job,
        system,
      );
      subject = saves[0];
      return;
    }
    for (final s in saves) {
      if (s.system == 'NEO GEO') system = s.system;
    }
    final body = ['They get backed up first, so you can restore them later.'];
    final stay = chosen.length - saves.length;
    if (stay > 0) body.add(staying(stay));
    _ask(
      'DELETE ${saves.length} SAVE${saves.length == 1 ? '' : 'S'}?',
      body,
      'DELETE',
      job,
      system,
    );
    items[1].again = 'REALLY DELETE ALL ${saves.length}?';
  }

  void _askDeleteCard(MemoryCard card) {
    final starred = [
      for (final s in card.saves)
        if (s.favorite) s,
    ];
    if (starred.isNotEmpty) {
      _keptSafe(starred);
      return;
    }
    final n = card.saves.length;
    final body = [
      '${card.name} (${MemoryCards.place(card)})',
      if (n == 0)
        "It's empty."
      else
        'Its $n save${n == 1 ? '' : 's'} go with it.',
      "It's backed up first: More > Bring back a deleted card undoes it.",
    ];
    _ask(
      'DELETE THIS CARD?',
      body,
      'DELETE CARD',
      FlowJob('delete_card', card: card),
      card.system,
    );
    if (n > 0) {
      items[1]
        ..again = 'REALLY DELETE IT AND ITS SAVES?'
        ..againYes = 'DELETE CARD';
    }
  }

  void _askDeleteAll(MemoryCard? card) {
    if (card == null || card.saves.isEmpty) return;
    final going = _notFavorites(card.saves);
    if (going.isEmpty) {
      _keptSafe(card.saves);
      return;
    }
    final body = [
      '${card.name}: ${going.length} saves',
      'They get backed up first, so you can restore them later.',
    ];
    var head = 'DELETE EVERY SAVE ON THIS CARD?';
    if (going.length < card.saves.length) {
      body.add(staying(card.saves.length - going.length));
      head = 'DELETE ALL BUT THE FAVORITES?';
    }
    _ask(
      head,
      body,
      'DELETE ALL',
      FlowJob('delete', groups: groups(going)),
      card.system,
    );
    items[1].again = 'REALLY DELETE ALL ${going.length}?';
  }

  static List<CardSave> _notFavorites(List<CardSave> saves) => [
    for (final s in saves)
      if (!s.favorite) s,
  ];

  void _keptSafe(List<CardSave> saves) {
    kind = FlowKind.ask;
    final one = saves.length == 1;
    title = one ? "THAT'S A FAVORITE" : 'THOSE ARE FAVORITES';
    final who = one ? saves[0].displayName() : '${saves.length} favorites';
    lines = [
      who,
      "Favorites can't be deleted or formatted away.",
      'They can still be backed up and moved. RT takes the star off.',
    ];
    items = [FlowItem('OK')];
    index = 0;
    subject = null;
  }

  void _openCopy(List<CardSave> chosen, bool move) {
    if (chosen.isEmpty) return;
    final system = chosen[0].system;
    final homes = <String>{};
    for (final s in chosen) {
      if (s.system != system) {
        kind = FlowKind.ask;
        title = 'ONE CONSOLE AT A TIME';
        lines = [
          'The selected saves are for different consoles.',
          "A save only works on its own console's cards. Use the tabs to pick from one.",
        ];
        items = [FlowItem('OK')];
        return;
      }
      homes.add(s.card?.key() ?? '');
    }
    final from = homes.length == 1 ? chosen[0].card : null;
    for (final c in _cards) {
      if (c.system != system || (from != null && c.key() == from.key())) {
        continue;
      }
      // a PC copy is kept as it is: nothing lands on it
      if (c.readOnly) continue;
      if (c.system != 'PS2' || !c.isFolder) targets.add(c);
    }
    if (targets.isEmpty) {
      kind = FlowKind.ask;
      title = 'NOWHERE TO COPY IT';
      lines = [
        "There's no other $system card yet.",
        'A new, empty one can be made beside this one.',
      ];
      var make = 'NEW CARD';
      if (system == 'PS3') {
        // like the real console: saves get copied to a USB stick
        lines = [
          "There's nowhere else for PS3 saves yet.",
          "Make RPCS3's USB stick and copy them there.",
        ];
        make = 'MAKE USB';
      }
      items = [
        FlowItem('BACK'),
        FlowItem(make, job: FlowJob('new_card', card: chosen[0].card)),
      ];
      return;
    }
    kind = FlowKind.copy;
    source = from;
    fromSystem = system;
    list = List.of(from != null ? from.saves : chosen);
    targetI = 0;
    var best = 2;
    for (var i = 0; i < targets.length; i++) {
      // a card they all fit on, better one none of them is already on
      var need = 0;
      for (final s in chosen) {
        if (s.card?.key() != targets[i].key()) {
          need += system == 'PS2' ? s.kb : s.blocks;
        }
      }
      final rank = homes.contains(targets[i].key()) ? 1 : 0;
      if (targets[i].free >= need && need > 0 && rank < best) {
        targetI = i;
        best = rank;
      }
    }
    for (final s in chosen) {
      marked.add(markKey(s));
    }
    for (var i = 0; i < list.length; i++) {
      if (markKey(list[i]) == markKey(chosen[0])) cell = i;
    }
    final firstRow = cell ~/ copyCols - copyRows + 1;
    copyTop = firstRow > 0 ? firstRow : 0;
    inButtons = true;
    button = move ? 2 : 0;
  }

  bool _stepCopy(int dx, int dy) {
    if (inButtons) {
      if (dx < 0 && list.isNotEmpty) {
        inButtons = false;
        return true;
      }
      if (dy == 0) return false;
      final b = clampi(button + dy, 0, copyButtons.length - 1);
      if (b == button) return false;
      button = b;
      _disarm();
      return true;
    }
    var to = cell;
    if (dx > 0) {
      if (cell % copyCols == copyCols - 1 || cell + 1 >= list.length) {
        inButtons = true;
        return true;
      }
      to = cell + 1;
    } else if (dx < 0 && cell % copyCols > 0) {
      to = cell - 1;
    } else if (dy < 0 && cell >= copyCols) {
      to = cell - copyCols;
    } else if (dy > 0 && cell ~/ copyCols < (list.length - 1) ~/ copyCols) {
      to = cell + copyCols < list.length - 1
          ? cell + copyCols
          : list.length - 1;
    }
    if (to == cell) return false;
    cell = to;
    final row = cell ~/ copyCols;
    copyTop = clampi(
      copyTop,
      row - copyRows + 1 > 0 ? row - copyRows + 1 : 0,
      row,
    );
    return true;
  }

  /// Two cards can hold saves with the same id.
  static String markKey(CardSave s) => MemoryCardState.saveKey(s);

  /// What would really travel: what's on the target already stays put.
  List<CardSave> arriving() {
    final to = target();
    return [
      for (final s in markedSaves())
        if (to == null || s.card?.key() != to.key()) s,
    ];
  }

  /// The card they're going to (null = none).
  MemoryCard? target() => targetI < targets.length ? targets[targetI] : null;

  /// The marked saves, in [list] order.
  List<CardSave> markedSaves() => [
    for (final s in list)
      if (marked.contains(markKey(s))) s,
  ];

  FlowJob? _copyButton() {
    final verb = copyButtons[button].verb;
    if (verb == 'all') {
      for (final s in list) {
        marked.add(markKey(s));
      }
      button = 0;
      _disarm();
      return null;
    }
    final picked = markedSaves();
    if (picked.isEmpty) {
      message = 'Nothing is marked: A marks a save';
      return null;
    }
    if (verb == 'back_up') {
      return _working(
        FlowJob('back_up', groups: groups(picked)),
        'Backing up...',
      );
    }
    var guarded = false;
    for (final s in picked) {
      guarded = guarded || s.copyProtected;
    }
    final warn = <String>[if (guarded) protectedNote];
    if (warn.isNotEmpty && _armed != verb) {
      _armed = verb;
      message = warn.join(' ');
      return null;
    }
    final job = FlowJob(
      'copy',
      groups: groups(picked),
      to: target(),
      move: verb == 'move',
    );
    return _working(job, verb == 'move' ? 'Moving...' : 'Copying...');
  }

  void _disarm() {
    _armed = '';
    message = '';
  }

  // card = the one going in; null = taking one out.
  void _showSlots(MemoryCard? card, List<SlotDescription> got) {
    kind = FlowKind.pick;
    title = card != null
        ? 'Put ${card.name} in which slot?'
        : 'Take the card out of which slot?';
    lines = [slotNote];
    for (final e in got) {
      final slot = e.slot;
      final where = card == null
          ? '${slot.label} (${CardSystems.info[slot.system]?['name']})'
          : slot.label;
      final job = FlowJob(
        card != null ? 'slot_in' : 'slot_out',
        slot: slot.id,
        card: card,
        where: where,
        after: afterOut[slot.system] ?? '',
      );
      items.add(
        FlowItem(
          card == null ? where : e.label,
          detail: e.detail,
          verb: 'entry',
          card: card,
          job: job,
        ),
      );
    }
    index = 0;
    top = 0;
  }

  String _showList(FlowJob job, List<Object?> got, int utcOffset) {
    final card = job.card;
    final from = job.verb;
    if (from == 'deleted_cards') {
      if (got.isEmpty) return 'No deleted cards to bring back';
      kind = FlowKind.pick;
      title = 'Bring back which card?';
      for (final e in got.whereType<Backup>()) {
        items.add(
          FlowItem(
            MemoryCards.cardName(p.basenameWithoutExtension(e.path)),
            detail: 'Deleted ${Texts.dateText(e.time, utcOffset)}',
            verb: 'entry',
            job: FlowJob('bring_back', entry: e),
          ),
        );
      }
      return '';
    }
    if (from == 'slot_list') {
      _showSlots(card, got.whereType<SlotDescription>().toList());
      return '';
    }
    if (got.isEmpty) {
      switch (from) {
        case 'import_list':
          return 'No ${card?.system} save files in Memory Card Exports or Downloads';
        case 'lost':
          return 'Nothing to bring back on ${card?.name}';
      }
      return 'There are no backups of that yet';
    }
    kind = FlowKind.pick;
    const heads = {
      'import_list': 'Import which save file?',
      'lost': 'Bring back which save?',
      'save_history': "This save's history",
      'card_history': "This card's history",
    };
    title = heads[from] ?? '';
    for (final e in got) {
      var label = '';
      var detail = '';
      FlowJob next;
      if (from == 'import_list' && e is ImportFile) {
        detail = Texts.dateText(e.time, utcOffset);
        next = FlowJob('import', card: card, file: e.file);
        label = p.basename(e.file);
      } else if (from == 'lost' && e is LostSave) {
        detail = Texts.dateText(e.time, utcOffset);
        next = FlowJob('undelete', card: card, entry: e);
        label = e.id;
        if (e.slot > 0) detail = 'Still on the card';
      } else if (e is Backup) {
        next = FlowJob(
          from == 'save_history' ? 'restore_save' : 'restore_card',
          card: card,
          entry: e,
        );
        label = Texts.dateText(e.time, utcOffset);
        detail = what[e.what] ?? 'Backed up';
      } else {
        continue;
      }
      items.add(
        FlowItem(label, detail: detail, verb: 'entry', card: card, job: next),
      );
    }
    return '';
  }

  // Godot's String.capitalize, enough for slot tags ("IN PCSX2 SLOT 2").
  static String _capitalize(String s) => s
      .toLowerCase()
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}
