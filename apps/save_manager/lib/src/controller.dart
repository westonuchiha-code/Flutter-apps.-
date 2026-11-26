/// The save manager's controller (ported from the PC's MemoryCardScreen.gd,
/// without the drawing): it reads the cards and runs every change off the
/// UI thread, and turns the buttons into [MemoryCardState] and
/// [MemoryCardFlow] calls. The UI listens to it and draws [state] / [flow].
library;

import 'dart:async';
import 'dart:io';

import 'package:app_shell/app_shell.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:save_kit/save_kit.dart';

import 'flow.dart';
import 'state.dart';
import 'texts.dart';

/// Runs `work(arg)` somewhere (default: [runInBackground], a background
/// isolate). [work] must be a top-level function; [arg] plain data.
typedef BackgroundRunner = Future<R> Function<A, R>(R Function(A) work, A arg);

/// Every card and save, as read.
typedef CardsRead = ({List<MemoryCard> cards, List<CardSave> saves});

/// A library game for stickers: its art file and screenshots, newest first.
typedef StickerGame = ({
  String id,
  String title,
  String art,
  List<String> shots,
});

/// What reading the cards needs, as plain data.
class ReadConfig {
  /// Plain values for [readCardsJob].
  const ReadConfig({
    required this.dirs,
    required this.namesFile,
    required this.favoritesFile,
    required this.looksFile,
    required this.isApp,
    this.testRoots = const [],
    this.games = const [],
    this.played = const {},
    this.indexNames = const {},
    this.slots,
  });

  /// The folders to look in.
  final List<String> dirs;

  /// This app's card names, looks and favorites files.
  final String namesFile, favoritesFile, looksFile;

  /// It's the app (real cards).
  final bool isApp;

  /// Folders a test may write in.
  final List<String> testRoots;

  /// The library's games, for naming saves.
  final List<LibraryGame> games;

  /// Play history per game id.
  final Map<String, PlayStats> played;

  /// Serial -> game name (PCSX2's GameIndex).
  final Map<String, String> indexNames;

  /// The console slots (null = none).
  final SlotsConfig? slots;
}

/// Reads every card: named, starred, tagged with its slot, wearing its
/// look. Top-level, for `runInBackground(readCardsJob, config)`.
CardsRead readCardsJob(ReadConfig c) {
  final got = MemoryCards.readAll(
    c.dirs,
    games: c.games,
    played: c.played,
    names: c.indexNames,
  );
  // after matching, which goes by the cards' own names
  CardNames.apply(got.cards, c.namesFile);
  final safety = CardSafety(isApp: c.isApp, testRoots: c.testRoots);
  CardFavorites(c.favoritesFile, safety).mark(got.cards);
  // the cards in a console's slots come first, tagged
  c.slots?.build(null).dress(got.cards, got.saves);
  // after dress: a card in a slot keeps its own look
  CardLooks.apply(got.cards, c.looksFile);
  return got;
}

/// What the save manager needs from its host.
class SaveManagerConfig {
  /// The host's folders and files.
  const SaveManagerConfig({
    required this.cardDirs,
    required this.backupRoot,
    required this.exportDir,
    required this.namesFile,
    required this.looksFile,
    this.favoritesFile = '',
    this.isApp = false,
    this.testRoots = const [],
    this.looseDir = '',
    this.importFolders = const [],
    this.stickerFolder = '',
    this.slots,
    this.running,
    this.games = const [],
    this.played = const {},
    this.indexNames = const {},
    this.stickerGames = const [],
    this.utcOffset,
  });

  /// The card folders to read.
  final List<String> cardDirs;

  /// Where backups go.
  final String backupRoot;

  /// Where Export puts save files.
  final String exportDir;

  /// This app's card names file.
  final String namesFile;

  /// This app's card looks (colour, sticker, order) file.
  final String looksFile;

  /// The favorites list ('' = favorites.json in [backupRoot]).
  final String favoritesFile;

  /// It's the installed app: it may change real cards.
  final bool isApp;

  /// Folders a test may write in (anything when [isApp]).
  final List<String> testRoots;

  /// The downloaded saves' folder (no emulator holds those open).
  final String looseDir;

  /// Where Import looks for save files.
  final List<String> importFolders;

  /// Where your own sticker pictures go ('' = none).
  final String stickerFolder;

  /// The console slots (null = none).
  final SlotsConfig? slots;

  /// The emulators running now (null result = can't tell). Null callback:
  /// ask the system (not possible on Android).
  final List<String>? Function()? running;

  /// The library's games, for naming saves.
  final List<LibraryGame> games;

  /// Play history per game id.
  final Map<String, PlayStats> played;

  /// Serial -> game name.
  final Map<String, String> indexNames;

  /// Games with art and screenshots, for Customize's stickers.
  final List<StickerGame> stickerGames;

  /// Seconds east of UTC for dates (null = this device's).
  final int? utcOffset;

  /// The favorites file actually used.
  String get favoritesPath => favoritesFile.isNotEmpty
      ? favoritesFile
      : p.join(backupRoot, 'favorites.json');

  /// The write gate.
  CardSafety safety() => CardSafety(isApp: isApp, testRoots: testRoots);
}

/// Android can't see other apps, so it can't tell whether an emulator has
/// a card open. Before a job that changes a card the player is asked to
/// close them; a yes is remembered for [remember]. Its [running] goes in
/// [SaveManagerConfig.running].
class EmulatorCheck {
  /// A check; [now] is the clock (tests).
  EmulatorCheck({
    this.remember = const Duration(minutes: 2),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// How long a yes counts.
  final Duration remember;

  final DateTime Function() _now;
  DateTime? _yesAt;

  /// What [running] says after a yes: a list with no emulator in it. (An
  /// empty list would mean "can't tell" to CardOwners.reason.)
  static const confirmed = ['user-confirmed-closed'];

  /// The emulators an Android card's folder belongs to, by its path.
  static const androidEmulators = [
    ('retroarch', 'RetroArch'),
    ('duckstation', 'DuckStation'),
    ('aethersx2', 'NetherSX2'),
    ('nethersx2', 'NetherSX2'),
    ('dolphin', 'Dolphin'),
    ('flycast', 'Flycast'),
    ('yabasanshiro', 'YabaSanshiro'),
  ];

  /// The player said yes, and it still counts.
  bool get fresh {
    final at = _yesAt;
    return at != null && _now().difference(at) < remember;
  }

  /// The player said the emulators are closed.
  void yes() => _yesAt = _now();

  /// Forget the yes.
  void reset() => _yesAt = null;

  /// For [SaveManagerConfig.running]: [confirmed] after a fresh yes, else
  /// null (can't tell: nothing is changed).
  List<String>? running() => fresh ? confirmed : null;

  /// The emulators the cards at [paths] belong to ("RetroArch and
  /// DuckStation"; "your emulators" when the folders don't say).
  static String namesFor(Iterable<String> paths) {
    final names = <String>[];
    for (final path in paths) {
      final low = path.toLowerCase();
      for (final (key, name) in androidEmulators) {
        if (low.contains(key) && !names.contains(name)) names.add(name);
      }
    }
    if (names.isEmpty) return 'your emulators';
    if (names.length == 1) return names[0];
    return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
  }

  /// The question.
  static String question(String names) =>
      'Close $names fully first (not just Home). Are they closed?';
}

/// The question asked before a job that changes a card (Android).
class ClosedQuestion {
  /// Asking about [job]; [names] = its emulators.
  ClosedQuestion(this.job, this.names);

  /// The job waiting for the answer.
  final FlowJob job;

  /// "RetroArch and DuckStation".
  final String names;

  /// The answers, the safe one first.
  static const answers = ['NOT YET', "YES, THEY'RE CLOSED"];

  /// The answer highlighted.
  int index = 0;

  /// The heading.
  static const title = 'ARE THE EMULATORS CLOSED?';

  /// What it says.
  List<String> get lines => [
    EmulatorCheck.question(names),
    "An emulator that's still open writes its own copy of the card back "
        'over the change.',
  ];
}

Future<R> _defaultRunner<A, R>(R Function(A) work, A arg) =>
    runInBackground<A, R>(work, arg);

/// Holds the [state] and the [flow] and runs what they ask for.
class SaveManagerController extends ChangeNotifier {
  /// A controller for [config]; [runner] runs the reads and jobs (default
  /// a background isolate; tests can pass a synchronous one); [onSound]
  /// hears the PC's sound cues (confirm, error, back, panel_open, move).
  /// [check] (Android) asks whether the emulators are closed before a job
  /// that changes a card.
  SaveManagerController(
    this.config, {
    BackgroundRunner? runner,
    this.onSound,
    this.check,
  }) : _runner = runner ?? _defaultRunner,
       utcOffset = config.utcOffset ?? Texts.localOffset();

  /// How long a notice stays up, for the UI.
  static const noticeSeconds = 4.0;

  /// The host's folders and files.
  final SaveManagerConfig config;

  /// The sound cues.
  final void Function(String cue)? onSound;

  /// Android: asks whether the emulators are closed (null = the system is
  /// asked instead).
  final EmulatorCheck? check;

  /// The emulators-closed question showing now (null = none).
  ClosedQuestion? asking;

  /// Jobs that change a card (the others only read, or write files of
  /// this app's own).
  static const writes = {
    'delete',
    'copy',
    'restore_save',
    'restore_card',
    'undelete',
    'import',
    'format',
    'delete_card',
    'bring_back',
    'slot_in',
    'slot_out',
    'slot_out_card',
  };

  final BackgroundRunner _runner;

  /// Seconds east of UTC, for dates.
  final int utcOffset;

  /// The cursor, pages and selection.
  final state = MemoryCardState();

  /// Pickers, questions, the copy screen, customize.
  final flow = MemoryCardFlow();

  /// The save manager is open.
  bool isOpen = false;

  /// The cards have been read once.
  bool loaded = false;

  /// A line to show ('' = none); the UI clears it after [noticeSeconds].
  String notice = '';

  /// Counts notices, so the UI can restart its timer for a repeated one.
  int noticeCount = 0;

  /// Rename: the card waiting for a name (the UI asks, then calls [named]).
  MemoryCard? renaming;

  Future<void>? _reading;
  bool _readAgain = false;
  Future<void>? _working;

  /// Reading the cards.
  bool get isLoading => _reading != null;

  /// A job is running (or waiting for the emulators-closed answer).
  bool get isJobRunning => _working != null || asking != null;

  /// Reading or working.
  bool get isBusy => isLoading || isJobRunning;

  /// [CardOps]'s values for a job (the running emulators asked now).
  CardOpsConfig opsConfig() => CardOpsConfig(
    isApp: config.isApp,
    testRoots: config.testRoots,
    backupRoot: config.backupRoot,
    exportDir: config.exportDir,
    favoritesFile: config.favoritesPath,
    looseDir: config.looseDir,
    slots: config.slots,
    askSystem: config.running == null,
    running: config.running?.call(),
  );

  /// The values for reading the cards.
  ReadConfig readConfig() => ReadConfig(
    dirs: config.cardDirs,
    namesFile: config.namesFile,
    favoritesFile: config.favoritesPath,
    looksFile: config.looksFile,
    isApp: config.isApp,
    testRoots: config.testRoots,
    games: config.games,
    played: config.played,
    indexNames: config.indexNames,
    slots: config.slots,
  );

  /// Opens the save manager on the list and reads the cards.
  void open() {
    isOpen = true;
    state
      ..mode = Mode.list
      ..button = -1
      ..cardI = -1
      ..clearSelection();
    if (!isJobRunning) flow.close();
    notice = '';
    refresh();
    notifyListeners();
  }

  /// Marks it closed (B with nowhere further back).
  void close() {
    isOpen = false;
    notifyListeners();
  }

  /// Reads the cards again (opening it, or after something changed them).
  void refresh() {
    if (_reading != null) {
      _readAgain = true;
      return;
    }
    _reading = _read();
    notifyListeners();
  }

  Future<void> _read() async {
    CardsRead? got;
    try {
      got = await _runner<ReadConfig, CardsRead>(readCardsJob, readConfig());
    } catch (e) {
      _say("Couldn't read the memory cards: $e");
    }
    _reading = null;
    if (got != null) {
      state.setData(got.cards, got.saves);
      loaded = true;
    }
    notifyListeners();
    if (_readAgain) {
      _readAgain = false;
      refresh();
    }
  }

  /// Completes when no read or job is running (for tests and the UI).
  Future<void> settled() async {
    while (_reading != null || _working != null) {
      await (_reading ?? _working);
    }
  }

  // ---- buttons -------------------------------------------------------------

  /// The d-pad. True = something changed.
  bool step(int dx, int dy) {
    final q = asking;
    if (q != null) {
      final to = clampi(q.index + dx, 0, ClosedQuestion.answers.length - 1);
      if (to == q.index || dx == 0) return false;
      q.index = to;
      notifyListeners();
      return true;
    }
    final moved = flow.isOpen() ? flow.step(dx, dy) : state.step(dx, dy);
    if (moved) notifyListeners();
    return moved;
  }

  /// LB / RB. True = something changed.
  bool turnPage(int dir) {
    if (asking != null) return false;
    final moved = flow.isOpen() ? flow.turnPage(dir) : state.turnPage(dir);
    if (moved) notifyListeners();
    return moved;
  }

  /// A. Returns the game id to start, '' = it was handled here.
  String confirm() {
    final q = asking;
    if (q != null) {
      answerClosed(q.index == 1);
      return '';
    }
    if (state.moving) {
      _putCardDown();
      return '';
    }
    if (flow.isOpen()) {
      if (flow.kind != FlowKind.working) {
        _sound('confirm');
        _run(flow.confirm());
      }
      notifyListeners();
      return '';
    }
    final verb = state.confirm();
    var out = '';
    switch (verb) {
      case '':
        _sound('confirm');
      case 'none':
        _sound('error');
        _say(
          loaded ? 'No saves here yet' : 'Still reading your memory cards...',
        );
      case 'start':
        final s = state.current();
        if (s != null && s.gameId.isNotEmpty) {
          out = s.gameId;
        } else {
          _sound('error');
          _say(
            "That game isn't in your ROMs folder, so it can't be started from here",
          );
        }
      case 'sort':
        _sound('confirm');
        _say('Sorted: ${state.cycleSort().toLowerCase()}');
      case 'favorite':
        toggleFavorite();
        if (state.mode == Mode.options) state.cancel();
      case 'select':
        state.startSelecting();
        _sound('confirm');
        _say(
          'Press A on each save you want, then Y to copy, move or delete them',
        );
      case 'more':
        state.showMore(true);
        _sound('panel_open');
      case 'unselect':
        state
          ..clearSelection()
          ..cancel();
        _sound('back');
        _say('Selection cleared');
      case 'reorder':
        state.startMoving();
        _sound('confirm');
        _say('Up and down move the card. A or B puts it down');
      case 'customize':
        _customize(state.optCard);
      case 'mark':
        final n = state.markGame();
        state.cancel();
        _sound('confirm');
        _say('$n marked from that game');
      default:
        final job = flow.begin(
          verb,
          state.cards,
          state.chosen(),
          state.current(),
          state.optCard,
        );
        if (flow.isOpen()) {
          _sound('panel_open');
          _run(job);
        } else if (job != null) {
          // straight to the job (Rename asks for the name itself)
          _sound('confirm');
          _run(job);
        } else {
          _sound('error');
          _say("There's nothing to do that to");
        }
    }
    notifyListeners();
    return out;
  }

  /// B. False = there's nowhere further back: the save manager closes.
  bool cancel() {
    if (asking != null) {
      answerClosed(false);
      return true;
    }
    if (state.moving) {
      _putCardDown();
      return true;
    }
    if (flow.isOpen()) {
      if (flow.cancel()) {
        _sound('back');
        notifyListeners();
      }
      return true;
    }
    final stays = state.cancel();
    _sound('back');
    if (stays) {
      notifyListeners();
    } else {
      close();
    }
    return stays;
  }

  /// Y: the options for what you're on.
  void toggleOptions() {
    if (asking != null) return;
    if (state.moving) {
      _putCardDown();
      return;
    }
    if (flow.isOpen()) return;
    if (state.toggleOptions()) {
      _sound(state.mode == Mode.options ? 'panel_open' : 'back');
      notifyListeners();
    } else {
      _sound('error');
    }
  }

  /// X: marks one save (or, on the copy screen, one save to copy).
  void mark() {
    if (asking != null) return;
    final did = flow.isOpen() ? flow.mark() : state.toggleMark();
    if (did) {
      _sound('move');
      notifyListeners();
    }
  }

  /// Hold X: marks every save of that game.
  void markGame() {
    if (flow.isOpen() || asking != null) return;
    _say('${state.markGame()} marked from that game');
    notifyListeners();
  }

  /// RT, or Favorite in the options: stars (or unstars) what's chosen.
  void toggleFavorite() {
    if (flow.isOpen() || isJobRunning) return;
    final onCardColumn = state.cardI >= 0 && state.mode == Mode.list;
    if (onCardColumn || state.current() == null) {
      // say why, never just nothing
      _sound('error');
      _say('Favorites are saves: pick a save first');
      notifyListeners();
      return;
    }
    final saves = state.chosen();
    final on = state.favoriteTurnsOn();
    final no = CardFavorites(
      config.favoritesPath,
      config.safety(),
    ).setFor(saves, on);
    _sound(no.isEmpty ? 'confirm' : 'error');
    if (no.isNotEmpty) {
      _say(no);
      notifyListeners();
      return;
    }
    for (final s in saves) {
      s.favorite = on;
    }
    final who = saves.length == 1
        ? saves[0].displayName()
        : '${saves.length} saves';
    _say(
      on ? "Favorite: $who. It can't be deleted now" : 'Star taken off $who',
    );
    notifyListeners();
  }

  /// The name typed for [renaming] ('' = back to the file's own).
  void named(String text) {
    final card = renaming;
    if (card == null) return;
    final no = CardNames.setNameFor(
      card,
      text,
      config.namesFile,
      config.safety(),
    );
    _say(
      no.isNotEmpty ? no : 'Renamed here. The file keeps its name, so the emulator still finds it',
    );
    renaming = null;
    refresh();
    notifyListeners();
  }

  /// Rename was backed out of.
  void cancelRename() {
    renaming = null;
    notifyListeners();
  }

  /// Shows [message] as the notice.
  void showNotice(String message) {
    _say(message);
    notifyListeners();
  }

  /// Takes the notice down.
  void clearNotice() {
    if (notice.isEmpty) return;
    notice = '';
    notifyListeners();
  }

  // ---- touch ---------------------------------------------------------------

  /// Touch: stand on save [i] of `state.saves`.
  bool selectSave(int i) => _touched(!flow.isOpen() && state.selectIndex(i));

  /// Touch: stand on card [i] of `state.column()`.
  bool selectCard(int i) => _touched(!flow.isOpen() && state.focusCard(i));

  /// Touch: highlight option [i] of `state.flatOptions()`.
  bool selectOption(int i) => _touched(!flow.isOpen() && state.selectOption(i));

  /// Touch: go to tab [f] of [MemoryCardState.filters].
  bool selectFilter(int f) => _touched(!flow.isOpen() && state.selectFilter(f));

  /// Touch: highlight a paint button (or [MemoryCardState.backUpAll]).
  bool selectListButton(int b) =>
      _touched(!flow.isOpen() && state.selectListButton(b));

  /// Touch: highlight a button of an opened save or a card's page.
  bool selectPageButton(int b) =>
      _touched(!flow.isOpen() && state.selectPageButton(b));

  /// Touch: highlight row / button [i] of a picker or a question.
  bool selectFlowItem(int i) => _touched(flow.selectItem(i));

  /// Touch: highlight save [i] on the copy screen.
  bool selectCopyCell(int i) => _touched(flow.selectCell(i));

  /// Touch: highlight button [b] on the copy screen.
  bool selectCopyButton(int b) => _touched(flow.selectCopyButton(b));

  /// Touch: copy to target [i].
  bool selectCopyTarget(int i) => _touched(flow.selectTarget(i));

  /// Touch: highlight Customize's row [r].
  bool selectLookRow(int r) => _touched(flow.selectLookRow(r));

  /// Touch: highlight answer [i] of the emulators-closed question.
  bool selectClosedAnswer(int i) {
    final q = asking;
    if (q == null || i < 0 || i >= ClosedQuestion.answers.length) {
      return false;
    }
    final changed = q.index != i;
    q.index = i;
    return _touched(changed);
  }

  /// The emulators-closed question's answer: yes runs the job (and counts
  /// for a while), no leaves everything as it was.
  void answerClosed(bool closed) {
    final q = asking;
    if (q == null) return;
    asking = null;
    if (closed) {
      check?.yes();
      _sound('confirm');
      _working = _work(q.job);
    } else {
      flow.close();
      _sound('back');
      _say('Nothing was changed. Close the emulators, then try again');
    }
    notifyListeners();
  }

  /// The job changes a card that an emulator could have open (not one
  /// in the downloaded saves or the exports).
  bool changesCards(FlowJob job) {
    if (!writes.contains(job.verb)) return false;
    final paths = _paths(job);
    if (paths.isEmpty) return true;
    return paths.any((path) => !_loose(path));
  }

  static List<String> _paths(FlowJob job) => [
    if (job.card != null) job.card!.path,
    if (job.to != null) job.to!.path,
    for (final c in job.cards) c.path,
    for (final g in job.groups) g.card.path,
  ].where((path) => path.isNotEmpty).toList();

  bool _loose(String path) {
    bool under(String dir) =>
        dir.isNotEmpty &&
        p.isWithin(p.normalize(dir).toLowerCase(), path.toLowerCase());
    return under(config.looseDir) || under(config.exportDir);
  }

  bool _touched(bool changed) {
    if (changed) notifyListeners();
    return changed;
  }

  // ---- inside --------------------------------------------------------------

  void _run(FlowJob? job) {
    if (job == null || _working != null || asking != null) return;
    if (job.verb == 'rename') {
      renaming = job.card;
      return;
    }
    if (job.verb == 'save_look') {
      // a small file of this menu's own: no worker needed
      final card = job.card!;
      final no = CardLooks.setLook(
        card,
        job.color,
        job.sticker,
        config.looksFile,
        config.safety(),
      );
      _sound(no.isEmpty ? 'confirm' : 'error');
      if (no.isNotEmpty) {
        _say(no);
        refresh();
      } else if (job.rename) {
        renaming = card;
      } else {
        final colour = CardLooks
            .palette[CardLooks.paletteIndex(card.color, card.finish)]
            .$1;
        _say(
          '${card.name}: $colour, '
          '${card.sticker.isNotEmpty ? 'with a sticker' : 'no sticker'}',
        );
      }
      return;
    }
    final given = job.verb == 'import_list'
        ? job.copyWith(folders: config.importFolders)
        : job;
    final ask = check;
    if (ask != null && !ask.fresh && changesCards(given)) {
      // Android can't see the emulators: ask first (the flow stays on
      // "working" behind the question)
      asking = ClosedQuestion(
        given,
        EmulatorCheck.namesFor(_paths(given).where((path) => !_loose(path))),
      );
      _sound('panel_open');
      return;
    }
    _working = _work(given);
  }

  Future<void> _work(FlowJob job) async {
    Object? result;
    try {
      result = await _runner<(CardOpsConfig, FlowJob), Object?>(performJob, (
        opsConfig(),
        job,
      ));
    } catch (e) {
      result = OpResult(false, 'That stopped halfway: $e');
    }
    _working = null;
    final said = flow.finish(result, utcOffset);
    if (said.isNotEmpty) _say(said);
    if (result is OpResult) {
      if (result.ok) state.clearSelection();
      if (isOpen) _sound(result.ok ? 'confirm' : 'error');
      refresh(); // what's on the cards may be different now
    }
    notifyListeners();
  }

  // Move card ends: the new order is kept.
  void _putCardDown() {
    state.moving = false;
    final no = CardLooks.setOrder(
      state.fullColumn(),
      config.looksFile,
      config.safety(),
    );
    _sound(no.isEmpty ? 'confirm' : 'error');
    _say(no.isNotEmpty ? no : 'Card order saved');
    notifyListeners();
  }

  void _customize(MemoryCard? card) {
    if (card == null) {
      _sound('error');
      _say('Pick a card first');
      return;
    }
    final folder = config.stickerFolder;
    // so you can find where your own pictures go
    if (folder.isNotEmpty && config.safety().refusal(folder).isEmpty) {
      try {
        Directory(folder).createSync(recursive: true);
      } catch (_) {}
    }
    flow
      ..resolve = CardLooks.stickerImage
      ..openLook(
        card,
        CardLooks.stickerChoices(card, config.stickerGames, folder),
      );
    _sound('panel_open');
  }

  void _say(String message) {
    notice = message;
    noticeCount++;
  }

  void _sound(String cue) => onSound?.call(cue);
}
