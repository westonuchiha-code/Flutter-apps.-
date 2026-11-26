import 'dart:async';
import 'dart:io';

import 'package:app_shell/app_shell.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:save_screens/save_screens.dart' as saves;

import '../android.dart';
import '../launch.dart';
import '../library/scanner.dart';
import '../library/systems.dart';
import '../state.dart';
import '../sync/controller.dart';
import '../sync/cross_save.dart';
import '../sync/setup.dart';
import '../comics/library.dart';
import '../comics/pdf_book.dart';
import 'comic_reader.dart';
import 'xmb.dart';

/// The menu: Settings and Game for now (more categories come with the
/// save sync, comics, save manager, Pokéville and CRT TV).
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.bridge = const AndroidBridge(),
    this.state,
    this.crossSave,
  });

  final AndroidBridge bridge;

  /// For tests: a ready cross-save controller.
  final CrossSaveController? crossSave;

  /// For tests: a ready state (otherwise loaded from storage).
  final MenuState? state;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final MenuState _s = widget.state ?? MenuState();
  final _xmb = GlobalKey<XmbViewState>();
  Set<String> _installed = {};
  bool _allFiles = true, _scanning = false, _loaded = false;
  int _revision = 0;
  Timer? _saveTimer;
  AppLifecycleListener? _life;

  AndroidBridge get _a => widget.bridge;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _life = AppLifecycleListener(onResume: _resumed);
    _s.addListener(_changed);
    // After the first frame: start-up reads inherited services (storage).
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_start()));
  }

  CrossSaveController? _cs;

  @override
  void dispose() {
    _life?.dispose();
    _saveTimer?.cancel();
    _s.removeListener(_changed);
    super.dispose();
  }

  Future<void> _start() async {
    final storage = Shell.of(context).storage;
    if (widget.state == null) {
      _s.load(await storage.readJson('menu.json'));
    }
    final cs = widget.crossSave ?? CrossSaveController(storage);
    if (widget.crossSave == null) await cs.load();
    cs.addListener(_bump);
    _cs = cs;
    // Not awaited: the menu must never wait on the system for this.
    unawaited(_applyScreen().catchError((_) {}));
    await _checkDevice();
    try {
      cs.model = await _a.deviceModel();
    } catch (_) {}
    _loaded = true;
    _bump();
    await _setupFolders();
    if (_s.romsDir != null) {
      // The cached list shows at once; look for new games behind it.
      await _scan(quiet: _s.games.isNotEmpty);
    }
    _bump();
    unawaited(_sync(quiet: true));
  }

  /// Makes the menu's `XMB Frontend` folder (ROMs with a folder per
  /// console, BIOS, saves for each emulator) and RetroArch's settings file.
  /// Needs storage access; tried again when it is allowed.
  Future<void> _setupFolders() async {
    if (!_allFiles || !_a.available) return;
    try {
      final roots = await _a.storageRoots();
      final f = XmbFolders(p.join(roots.first, 'XMB Frontend'))..create();
      writeRetroArchConfig(f);
      _cs?.folders = f;
      if (_s.comicsDir == null) {
        _s.comicsDir = f.comics;
        _writeComicsGuide(f.comics);
        _s.changed();
      }
      if (_s.romsDir == null) {
        prepareRomsFolder(f.roms);
        _s.romsDir = f.roms;
        _s.changed();
        await _scan(quiet: true);
      }
    } catch (e) {
      _xmb.currentState?.toast('Could not set up the XMB Frontend folder: $e');
    }
  }

  /// A cross save now (if set up); says what moved.
  Future<void> _sync({bool quiet = false}) async {
    final cs = _cs;
    if (cs == null || !cs.ready) return;
    final rep = await cs.sync();
    if (rep == null) return;
    if (rep.took.isNotEmpty) await _scan(quiet: true);
    final line = rep.summary;
    if (line.isNotEmpty) {
      _xmb.currentState?.toast(line);
    } else if (!quiet) {
      _xmb.currentState?.toast('Cross save: everything is up to date');
    }
  }

  /// Applies the Screen setting ('auto' locks nothing).
  Future<void> _applyScreen() =>
      SystemChrome.setPreferredOrientations(switch (_s.screen) {
        'wide' => [DeviceOrientation.landscapeLeft],
        'wideFlipped' => [DeviceOrientation.landscapeRight],
        'tall' => [DeviceOrientation.portraitUp],
        'tallFlipped' => [DeviceOrientation.portraitDown],
        _ => <DeviceOrientation>[],
      });

  Future<void> _checkDevice() async {
    try {
      _installed = await _a.installed(allRunnerPackages);
      _allFiles = await _a.hasAllFiles();
    } catch (_) {}
  }

  Future<void> _resumed() async {
    final fromGame = _s.running != null;
    _s.returned(DateTime.now().millisecondsSinceEpoch);
    await _checkDevice();
    if (_cs?.folders == null || _s.romsDir == null || _s.comicsDir == null) {
      await _setupFolders();
    } else if (_allFiles) {
      // Games may have been copied in while the menu was away.
      await _scan(quiet: true);
    }
    _bump();
    // Back from a game: send what it saved. Otherwise now and then.
    final last = _cs?.last;
    if (fromGame ||
        last == null ||
        DateTime.now().difference(last) > const Duration(minutes: 10)) {
      await _sync(quiet: true);
    }
  }

  void _changed() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted && widget.state == null) {
        unawaited(
          Shell.of(context).storage.writeJson('menu.json', _s.toJson()),
        );
      }
    });
    _bump();
  }

  void _bump() {
    if (mounted) setState(() => _revision++);
  }

  /// Reads the ROMs folder. [quiet]: only say something when the number of
  /// games changed.
  Future<void> _scan({bool quiet = false}) async {
    final dir = _s.romsDir;
    if (dir == null || _scanning) return;
    setState(() => _scanning = true);
    try {
      final before = _s.games.length;
      final list = await runInBackground(scanLibraryJson, dir);
      _s.games = [for (final g in list) Game.fromJson(g)];
      _s.scanned = DateTime.now();
      _s.changed();
      final n = _s.games.length;
      if (!quiet || n != before) {
        _xmb.currentState?.toast('$n game${n == 1 ? '' : 's'} in the library');
      }
    } catch (e) {
      _xmb.currentState?.toast('Could not read the ROMs folder: $e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  // ---- Playing ----

  LaunchChoice? _choiceFor(GameSystem s) {
    final installed = {..._installed};
    final ra = _s.retroArchPackage;
    if (ra != null && installed.contains(ra)) {
      // The chosen RetroArch build first.
      installed.removeAll(runnerPackages[Runner.retroarch]!);
      installed.add(ra);
    }
    return chooseRunner(
      s,
      installed,
      core: _s.cores[s.id],
      preferRetroArch: _s.preferRetroArch.contains(s.id),
    );
  }

  Future<void> _play(Game g) async {
    final s = systemById(g.system)!;
    final choice = _choiceFor(s);
    if (choice == null) {
      _xmb.currentState?.showPanel(
        XPanel(
          title: 'No emulator for ${s.title}',
          lines: [
            'Install ${s.runners.map((r) => r.label).join(' or ')} on this '
                'device, then come back.',
          ],
        ),
      );
      return;
    }
    // Pull first, so the game loads the newest save (give up after 12 s).
    final cs = _cs;
    if (cs != null && cs.ready) {
      _xmb.currentState?.toast('Getting your newest saves…');
      try {
        await _sync(quiet: true).timeout(const Duration(seconds: 12));
      } catch (_) {}
    }
    final err = await _a.launch(
      launchSpec(
        g,
        choice,
        raConfig: _s.raOwnConfig ? null : cs?.folders?.raConfig,
      ),
    );
    if (err != null) {
      _xmb.currentState?.showPanel(
        XPanel(
          title: 'Could not start ${g.title}',
          lines: [err, 'With: ${choice.label} (${choice.package})'],
        ),
      );
      return;
    }
    _s.started(g.id, DateTime.now().millisecondsSinceEpoch);
  }

  // ---- Items ----

  String _gameLine(Game g, {bool pinned = false}) {
    final s = systemById(g.system);
    final pl = _s.played[g.id];
    return [
      if (pinned) 'Pinned',
      s?.title ?? g.system,
      if (pl != null && pl.last > 0) playedAgo(pl.last, DateTime.now()),
      if (pl != null && pl.seconds >= 60) formatPlayTime(pl.seconds),
      if (g.size > 0) formatSize(g.size),
      if (_s.hidden.contains(g.id)) 'Hidden',
    ].join('  ·  ');
  }

  XItem _gameItem(Game g, {bool showPinned = false}) => XItem(
    title: g.title,
    subtitle: _gameLine(g, pinned: showPinned && _s.pins.contains(g.id)),
    icon: Icons.sports_esports_outlined,
    art: g.art,
    dim: _s.hidden.contains(g.id),
    boxed: true,
    onPress: () => _play(g),
    options: () => _gameOptions(g),
  );

  List<XOption> _gameOptions(Game g) {
    final pinned = _s.pins.contains(g.id);
    final i = _s.pins.indexOf(g.id);
    return [
      XOption(pinned ? 'Unpin from Front' : 'Pin to Front', () {
        _s.togglePin(g.id);
      }),
      if (pinned && i > 0) XOption('Move Pin Up', () => _s.movePin(g.id, -1)),
      if (pinned && i < _s.pins.length - 1)
        XOption('Move Pin Down', () => _s.movePin(g.id, 1)),
      XOption('Information', () => _info(g)),
      XOption('Sort Games By…', _sortMenu),
      XOption(
        _s.hidden.contains(g.id) ? 'Show in Library' : 'Hide from Library',
        () => _s.toggleHidden(g.id),
      ),
    ];
  }

  void _sortMenu() => _xmb.currentState?.showPanel(
    XPanel(
      title: 'Sort Games By',
      options: [
        for (final (v, l) in [
          (SortBy.title, 'Title'),
          (SortBy.recent, 'Last Played'),
          (SortBy.system, 'Console'),
        ])
          XOption('${_s.sortBy == v ? '● ' : ''}$l', () {
            _s.sortBy = v;
            _s.changed();
          }),
      ],
    ),
  );

  void _info(Game g) {
    final s = systemById(g.system)!;
    final pl = _s.played[g.id];
    final choice = _choiceFor(s);
    _xmb.currentState?.showPanel(
      XPanel(
        title: g.title,
        lines: [
          s.title,
          'Plays with: ${choice?.label ?? 'nothing installed yet'}',
          if (pl != null && pl.last > 0) playedAgo(pl.last, DateTime.now()),
          if (pl != null && pl.seconds > 0)
            'Play time: ${formatPlayTime(pl.seconds)} '
                '(${pl.sessions} session${pl.sessions == 1 ? '' : 's'})',
          'Size: ${formatSize(g.size)}',
          'File: ${p.basename(g.path)}',
          if (_s.romsDir != null)
            'Folder: ${p.relative(p.dirname(g.path), from: _s.romsDir)}',
          'Saves are named: ${g.saveName}',
        ],
      ),
    );
  }

  List<XItem> _gameRow() {
    final out = <XItem>[];
    if (!_allFiles) {
      out.add(
        XItem(
          title: 'Allow Storage Access',
          subtitle: 'Needed to find your games and start them in emulators',
          icon: Icons.lock_open_outlined,
          onPress: () => _a.requestAllFiles(),
        ),
      );
    }
    if (_s.romsDir == null) {
      if (_allFiles) {
        out.add(
          XItem(
            title: 'Setting Up the ROMs Folder…',
            icon: Icons.hourglass_empty,
            onPress: _setupFolders,
          ),
        );
      }
      return out;
    }
    if (_s.games.isEmpty) {
      out.add(
        XItem(
          title: 'How to Add Games',
          subtitle: 'Copy them into ${_shortPath(_s.romsDir!)}/<console>',
          icon: Icons.lightbulb_outline,
          onPress: _howToAdd,
        ),
      );
    }
    for (final g in _s.front()) {
      out.add(_gameItem(g, showPinned: true));
    }
    final games = _s.visibleGames;
    out.add(
      XItem(
        title: 'All Games',
        subtitle: '${games.length} game${games.length == 1 ? '' : 's'}',
        icon: Icons.folder_outlined,
        children: () => [
          for (final g in _s.sorted(_s.visibleGames.where((g) => !g.demo)))
            _gameItem(g),
        ],
      ),
    );
    for (final s in systems) {
      final list = [
        for (final g in games)
          if (g.system == s.id && !g.demo) g,
      ];
      if (list.isEmpty) continue;
      out.add(
        XItem(
          title: s.title,
          subtitle:
              '${list.length} game${list.length == 1 ? '' : 's'}  ·  '
              '${_choiceFor(s)?.label ?? 'no emulator installed'}',
          icon: Icons.folder_outlined,
          children: () => [
            for (final g in _s.sorted(
              _s.visibleGames.where((g) => g.system == s.id && !g.demo),
            ))
              _gameItem(g),
          ],
        ),
      );
    }
    final demos = [
      for (final g in games)
        if (g.demo) g,
    ];
    if (demos.isNotEmpty) {
      out.add(
        XItem(
          title: 'Demo Discs',
          subtitle: '${demos.length} disc${demos.length == 1 ? '' : 's'}',
          icon: Icons.album_outlined,
          children: () => [
            for (final g in _s.sorted(_s.visibleGames.where((g) => g.demo)))
              _gameItem(g),
          ],
        ),
      );
    }
    final history = [
      for (final g in _s.games)
        if ((_s.played[g.id]?.last ?? 0) > 0) g,
    ];
    if (history.isNotEmpty) {
      out.add(
        XItem(
          title: 'Play History',
          subtitle: '${history.length} played',
          icon: Icons.history,
          children: () {
            final l =
                [
                  for (final g in _s.games)
                    if ((_s.played[g.id]?.last ?? 0) > 0) g,
                ]..sort(
                  (a, b) =>
                      _s.played[b.id]!.last.compareTo(_s.played[a.id]!.last),
                );
            return [for (final g in l) _gameItem(g)];
          },
        ),
      );
    }
    final hidden = _s.games.where((g) => _s.hidden.contains(g.id)).length;
    out.add(
      XItem(
        title: _scanning ? 'Looking for Games…' : 'Refresh Game Library',
        subtitle: [
          if (_s.scanned != null)
            'Last checked ${playedAgo(_s.scanned!.millisecondsSinceEpoch, DateTime.now()).replaceFirst('Played ', '')}',
          if (hidden > 0)
            '$hidden hidden (Y > ${_s.showHidden ? 'Hide' : 'Show'} Hidden Games)',
        ].join('  ·  '),
        icon: Icons.refresh,
        onPress: _scan,
        options: () => [
          XOption(
            _s.showHidden ? 'Hide Hidden Games' : 'Show Hidden Games',
            () {
              _s.showHidden = !_s.showHidden;
              _s.changed();
            },
          ),
        ],
      ),
    );
    return out;
  }

  /// A folder picker as XMB folders. [dir] null: the storage roots.
  List<XItem> _browse(String? dir, [void Function(String dir)? use]) {
    if (dir == null) {
      return [
        XItem(
          title: 'Looking for storage…',
          icon: Icons.sd_storage_outlined,
          children: () => [],
        ),
      ];
    }
    final out = <XItem>[
      XItem(
        title: 'Use This Folder',
        subtitle: dir,
        icon: Icons.check_circle_outline,
        onPress: () => (use ?? _useRoms)(dir),
      ),
    ];
    try {
      final dirs =
          Directory(dir)
              .listSync(followLinks: false)
              .whereType<Directory>()
              .where((d) => !p.basename(d.path).startsWith('.'))
              .toList()
            ..sort(
              (a, b) => p
                  .basename(a.path)
                  .toLowerCase()
                  .compareTo(p.basename(b.path).toLowerCase()),
            );
      for (final d in dirs) {
        final console = systems.any((s) => s.folder == p.basename(d.path));
        out.add(
          XItem(
            title: p.basename(d.path),
            subtitle: console ? 'A console folder' : null,
            icon: Icons.folder_outlined,
            children: () => _browse(d.path, use),
          ),
        );
      }
    } catch (e) {
      out.add(
        XItem(
          title: 'Cannot open this folder',
          subtitle: _allFiles ? '$e' : 'Allow storage access first',
          icon: Icons.block,
        ),
      );
    }
    return out;
  }

  List<String> _rootPaths = const [];

  /// Storage roots to choose a folder from, each opening onto [use].
  List<XItem> _rootsFor(void Function(String dir) use) => [
    for (final (i, r) in _rootPaths.indexed)
      XItem(
        title: i == 0
            ? 'Internal Storage'
            : 'SD Card ${_rootPaths.length > 2 ? i : ''}'.trim(),
        subtitle: r,
        icon: i == 0 ? Icons.phone_android : Icons.sd_card_outlined,
        children: () => _browse(r, use),
      ),
  ];

  Future<List<XItem>> _roots() async {
    final roots = await _a.storageRoots();
    _rootPaths = roots;
    return [
      for (final (i, r) in roots.indexed)
        XItem(
          title: i == 0
              ? 'Internal Storage'
              : 'SD Card ${roots.length > 2 ? i : ''}'.trim(),
          subtitle: r,
          icon: i == 0 ? Icons.phone_android : Icons.sd_card_outlined,
          children: () => _browse(r),
        ),
    ];
  }

  /// "XMB Frontend/ROMs" for the built-in folder, else the full path.
  String _shortPath(String dir) {
    final i = dir.indexOf('XMB Frontend');
    return i >= 0 ? dir.substring(i) : dir;
  }

  void _howToAdd() => _xmb.currentState?.showPanel(
    XPanel(
      title: 'How to Add Games',
      lines: [
        'Copy each game into its console\'s folder in',
        _s.romsDir ?? '',
        'with a file manager, or over USB from a PC. The menu finds them '
            'when you come back to it.',
        '',
        for (final s in systems) '${s.folder}:  .${s.exts.join('  .')}',
        '',
        'Use the same ROM file names as on the PC: saves are matched by name.',
      ],
    ),
  );

  void _useRoms(String dir) {
    _s.romsDir = dir;
    _s.games = [];
    _s.changed();
    _xmb.currentState?.closeFolders();
    unawaited(_scan());
  }

  List<XItem>? _rootsCache;

  // ---- Memory Card (the PC's row between Game and the rest) ----

  /// The save manager's own consoles, by this library's system ids.
  static const _saveSystems = {
    'ps1': 'PS1',
    'n64': 'N64',
    'saturn': 'SATURN',
    'dreamcast': 'DC',
    'gamecube': 'GC',
  };

  List<XItem> _memoryRow() => [
    XItem(
      title: 'Save Manager',
      icon: Icons.sd_card_outlined,
      onPress: () => unawaited(_openSaves()),
    ),
  ];

  Future<void> _openSaves() async {
    saves.androidChannel = const MethodChannel('xmb/android');
    final games = [
      for (final g in _s.games)
        if (_saveSystems[g.system] case final sys?)
          (id: g.id, title: g.title, system: sys, serial: ''),
    ];
    final played = {
      for (final e in _s.played.entries)
        e.key: (
          seconds: e.value.seconds,
          sessions: e.value.sessions,
          last: e.value.last,
        ),
    };
    final nav = Navigator.of(context);
    await nav.push(
      MaterialPageRoute<void>(
        builder: (context) => saves.SaveManagerHome(
          games: games,
          played: played,
          onTick: Shell.of(context).tick,
          onLeave: () => nav.maybePop(),
          onGame: (id) {
            final g = _s.games.where((g) => g.id == id).firstOrNull;
            if (g == null) return;
            nav.pop();
            unawaited(_play(g));
          },
        ),
      ),
    );
    if (mounted) setState(() => _revision++);
  }

  // ---- Comics ----

  ComicProgress _comicProgress = ComicProgress();
  ComicShelf? _shelf;
  bool _comicsLoaded = false;

  static const _comicsGuide = 'HOW TO ADD COMICS.txt';

  void _writeComicsGuide(String dir) {
    final f = File(p.join(dir, _comicsGuide));
    if (f.existsSync()) return;
    f.writeAsStringSync(
      'Put comics here: .cbz .cbr .cb7 .zip .epub .cbt .pdf, or a folder\n'
      'of page pictures (one book). Make a folder per series to group them.\n'
      'Manga reads right to left by itself when the book says so\n'
      '(ComicInfo.xml), or its folder/name says manga; switch it with\n'
      'Start while reading.\n',
    );
  }

  void _useComics(String dir) {
    _s.comicsDir = dir;
    _shelf = null;
    _s.changed();
    _xmb.currentState?.closeFolders();
    setState(() => _revision++);
  }

  Future<void> _loadComicProgress() async {
    if (_comicsLoaded) return;
    _comicsLoaded = true;
    final j = await Shell.of(context).storage.readJson('comics.json');
    _comicProgress = ComicProgress(j is Map<String, Object?> ? j : null);
    if (mounted) setState(() => _revision++);
  }

  void _saveComicProgress() => unawaited(
    Shell.of(context).storage.writeJson('comics.json', _comicProgress.toJson()),
  );

  List<XItem> _comicsRow() {
    final dir = _s.comicsDir;
    if (!_comicsLoaded) unawaited(_loadComicProgress());
    if (dir == null) {
      return [
        XItem(
          title: 'Comics',
          subtitle: _allFiles
              ? 'Setting up the Comics folder…'
              : 'Allow storage access in Settings first',
          icon: Icons.menu_book_outlined,
          onPress: () => _a.requestAllFiles(),
        ),
      ];
    }
    final shelf = _shelf ??= () {
      try {
        return scanComics(dir);
      } catch (_) {
        return const ComicShelf([], {});
      }
    }();
    XItem book(String b) => XItem(
      title: FileSystemEntity.isDirectorySync(b)
          ? p.basename(b)
          : p.basenameWithoutExtension(b),
      subtitle: [
        _comicProgress.status(dir, b),
        if (_comicProgress.guessRtl(dir, b)) 'Manga (right to left)',
      ].join('  ·  '),
      icon: Icons.auto_stories_outlined,
      onPress: () => unawaited(_openComic(b)),
    );
    return [
      for (final b in shelf.books) book(b),
      for (final e in shelf.series.entries)
        XItem(
          title: e.key,
          subtitle: '${e.value.length} book${e.value.length == 1 ? '' : 's'}',
          icon: Icons.collections_bookmark_outlined,
          children: () => [for (final b in e.value) book(b)],
        ),
      if (shelf.books.isEmpty && shelf.series.isEmpty)
        XItem(
          title: 'No comics yet',
          subtitle:
              'Put .cbz / .cbr / .pdf files (or folders of pages) in ${_shortPath(dir)}',
          icon: Icons.lightbulb_outline,
          onPress: () {},
        ),
      XItem(
        title: 'Refresh Comic Library',
        subtitle: 'Looks in: ${_shortPath(dir)}',
        icon: Icons.refresh,
        onPress: () => setState(() {
          _shelf = null;
          _revision++;
        }),
      ),
    ];
  }

  Future<void> _openComic(String path) async {
    final root = _s.comicsDir!;
    final err = <String>[];
    final book = await openComic(path, err);
    if (!mounted) return;
    if (book == null) {
      _xmb.currentState?.toast(err.isEmpty ? 'Could not open it' : err.first);
      return;
    }
    final key = ComicProgress.key(root, path);
    final place = _comicProgress.pages[key];
    var start = place?.page ?? 0;
    // A finished book starts again.
    if (place != null && start >= book.pageCount - 1) start = 0;
    final rtl = book.manga >= 0
        ? book.manga == 1
        : _comicProgress.guessRtl(root, path);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ComicReader(
          book: book,
          startPage: start,
          rtl: rtl,
          swapAB: _s.swapAB,
          onPlace: (pg, of) {
            _comicProgress.pages[key] = (page: pg, of: of);
            _saveComicProgress();
          },
          onDirection: (r) {
            _comicProgress.rtl[ComicProgress.seriesKey(root, path)] = r;
            _saveComicProgress();
          },
        ),
      ),
    );
    book.close();
    if (mounted) setState(() => _revision++);
  }

  List<XItem> _settingsRow() {
    final raInstalled = [
      for (final pkg in runnerPackages[Runner.retroarch]!)
        if (_installed.contains(pkg)) pkg,
    ];
    return [
      XItem(
        title: 'ROMs Folder',
        subtitle: _s.romsDir == null
            ? 'Made when storage access is allowed'
            : _s.romsDir!.contains('XMB Frontend')
            ? '${_shortPath(_s.romsDir!)} (built in)'
            : _s.romsDir!,
        icon: Icons.folder_special_outlined,
        children: () => [
          XItem(
            title: 'How to Add Games',
            subtitle: 'Which folder takes which files',
            icon: Icons.lightbulb_outline,
            onPress: _howToAdd,
          ),
          XItem(
            title: 'Use the Built-in Folder',
            subtitle: 'XMB Frontend/ROMs, set up with a folder per console',
            icon: Icons.folder_special_outlined,
            onPress: () async {
              final roots = await _a.storageRoots();
              final dir = defaultRomsDir(roots.first);
              try {
                prepareRomsFolder(dir);
              } catch (_) {}
              _useRoms(dir);
            },
          ),
          XItem(
            title: 'Choose Another Folder',
            subtitle: 'An existing ROMs folder, on this device or an SD card',
            icon: Icons.drive_folder_upload_outlined,
            children: () => _rootsCache ?? _browse(null),
          ),
        ],
      ),
      XItem(
        title: 'Comics Folder',
        subtitle: _s.comicsDir == null
            ? 'Made when storage access is allowed'
            : _s.comicsDir!.contains('XMB Frontend')
            ? '${_shortPath(_s.comicsDir!)} (built in)'
            : _s.comicsDir!,
        icon: Icons.menu_book_outlined,
        children: () => [
          XItem(
            title: 'Use the Built-in Folder',
            subtitle: 'XMB Frontend/Comics',
            icon: Icons.folder_special_outlined,
            onPress: () async {
              final roots = await _a.storageRoots();
              final dir = p.join(roots.first, 'XMB Frontend', 'Comics');
              try {
                Directory(dir).createSync(recursive: true);
                _writeComicsGuide(dir);
              } catch (_) {}
              _useComics(dir);
            },
          ),
          XItem(
            title: 'Choose Another Folder',
            subtitle:
                'For example Documents/Comics, on this device or an SD card',
            icon: Icons.drive_folder_upload_outlined,
            children: () =>
                _rootPaths.isEmpty ? _browse(null) : _rootsFor(_useComics),
          ),
        ],
      ),
      if (_s.romsDir != null)
        XItem(
          title: 'Make Console Folders',
          subtitle: 'Empty NES, SNES, PS1… folders in the ROMs folder, named as on the PC',
          icon: Icons.create_new_folder_outlined,
          onPress: () {
            try {
              makeConsoleFolders(_s.romsDir!);
              _xmb.currentState?.toast('Console folders are ready');
            } catch (e) {
              _xmb.currentState?.toast('Could not make them: $e');
            }
          },
        ),
      XItem(
        title: 'Storage Access',
        subtitle: _allFiles
            ? 'Allowed'
            : 'Not allowed yet (needed to start games)',
        icon: _allFiles ? Icons.lock_open_outlined : Icons.lock_outline,
        onPress: () => _a.requestAllFiles(),
      ),
      XItem(
        title: 'Emulators',
        subtitle: _installed.isEmpty
            ? 'None found yet'
            : [
                for (final r in Runner.values)
                  if (runnerPackages[r]!.any(_installed.contains)) r.label,
              ].join(' · '),
        icon: Icons.videogame_asset_outlined,
        children: _emulatorsList,
      ),
      if (raInstalled.length > 1)
        XItem(
          title: 'RetroArch Build',
          subtitle: _s.retroArchPackage ?? 'Automatic (${raInstalled.first})',
          icon: Icons.memory,
          onPress: () => _xmb.currentState?.showPanel(
            XPanel(
              title: 'RetroArch Build',
              options: [
                XOption('Automatic', () {
                  _s.retroArchPackage = null;
                  _s.changed();
                }),
                for (final pkg in raInstalled)
                  XOption(pkg, () {
                    _s.retroArchPackage = pkg;
                    _s.changed();
                  }),
              ],
            ),
          ),
        ),
      XItem(
        title: 'Screen',
        subtitle: _s.screen == 'auto'
            ? 'Follow the Device (right for the Retroid Pocket Classic)'
            : screenChoices[_s.screen],
        icon: Icons.screen_rotation_outlined,
        onPress: () => _xmb.currentState?.showPanel(
          XPanel(
            title: 'Screen',
            lines: const [
              'Follow the Device is right for the Retroid Pocket Classic and '
                  'phones. Only change it if the menu shows up sideways.',
            ],
            options: [
              for (final e in screenChoices.entries)
                XOption('${_s.screen == e.key ? '● ' : ''}${e.value}', () {
                  _s.screen = e.key;
                  _s.changed();
                  unawaited(_applyScreen());
                }),
            ],
          ),
        ),
      ),
      XItem(
        title: 'Swap A and B',
        subtitle: _s.swapAB
            ? 'On: the right button confirms (Nintendo style)'
            : 'Off: the bottom button confirms (Xbox / PlayStation style)',
        icon: Icons.swap_horiz,
        onPress: () {
          _s.swapAB = !_s.swapAB;
          _s.changed();
        },
      ),
      _crossSaveItem(),
      XItem(
        title: 'About',
        subtitle:
            'XMB Frontend for Android ${Shell.of(context).config.version}',
        icon: Icons.info_outline,
        onPress: () => _xmb.currentState?.showPanel(
          XPanel(
            title: 'XMB Frontend',
            lines: const [
              'The Android companion to the XMB Frontend on the PC.',
              'Games start in RetroArch, PPSSPP, DuckStation or Dolphin.',
              'Same ROM folders and file names as the PC, so saves can cross over.',
            ],
          ),
        ),
      ),
    ];
  }

  /// One line under the clock about cross saves (null: not set up).
  String? _crossLine() {
    final cs = _cs;
    if (cs == null || cs.token.isEmpty) return null;
    if (cs.busy) return 'Syncing saves…';
    if (cs.conflicts.isNotEmpty) {
      return '${cs.conflicts.length} save${cs.conflicts.length == 1 ? '' : 's'} changed on both sides';
    }
    final l = cs.last;
    if (l == null) return null;
    if (cs.lastError != null) return 'Cross save: not synced';
    return 'Saves synced ${playedAgo(l.millisecondsSinceEpoch, DateTime.now()).replaceFirst('Played ', '')}';
  }

  XItem _crossSaveItem() {
    final cs = _cs;
    return XItem(
      title: 'Cross Save',
      subtitle: cs == null || cs.token.isEmpty
          ? 'Share saves with the PC through your Cross-Save repo'
          : _crossLine() ?? 'Ready',
      icon: Icons.sync,
      children: _crossSaveList,
    );
  }

  List<XItem> _crossSaveList() {
    final cs = _cs!;
    final f = cs.folders;
    return [
      XItem(
        title: 'GitHub Token',
        subtitle: cs.token.isEmpty
            ? 'Not set: needed to reach the Cross-Save repo'
            : 'Set (Contents: read and write on Cross-Save)',
        icon: Icons.key_outlined,
        onPress: _askToken,
        options: () => [
          XOption('How to Make One', _tokenHelp),
          if (cs.token.isNotEmpty)
            XOption('Forget the Token', cs.forgetToken, danger: true),
        ],
      ),
      if (cs.token.isNotEmpty)
        XItem(
          title: cs.busy ? 'Syncing…' : 'Sync Now',
          subtitle: [
            if (cs.last != null)
              'Last: ${playedAgo(cs.last!.millisecondsSinceEpoch, DateTime.now()).replaceFirst('Played ', '')}',
            if (cs.lastSummary.isNotEmpty) cs.lastSummary,
          ].join('  ·  '),
          icon: Icons.sync,
          onPress: () => _sync(),
        ),
      if (cs.conflicts.isNotEmpty)
        XItem(
          title: 'Changed on Both Sides',
          subtitle:
              '${cs.conflicts.length} save${cs.conflicts.length == 1 ? '' : 's'}: pick which to keep',
          icon: Icons.call_split,
          children: () => [for (final c in _cs!.conflicts) _conflictItem(c)],
        ),
      XItem(
        title: 'This Device',
        subtitle:
            '"${cs.device}"${cs.deviceOverride == null ? ' (from ${cs.model.isEmpty ? 'the model' : cs.model})' : ''}: names its commits',
        icon: Icons.devices_other,
        onPress: () => _xmb.currentState?.showPanel(
          XPanel(
            title: 'This Device',
            lines: const ['Commits say which device sent a save.'],
            options: [
              for (final (v, l) in [
                (null, 'Automatic'),
                ('phone', 'Phone'),
                ('retroid', 'Retroid'),
              ])
                XOption('${cs.deviceOverride == v ? '● ' : ''}$l', () {
                  cs.deviceOverride = v;
                  unawaited(cs.save());
                  _bump();
                }),
            ],
          ),
        ),
      ),
      XItem(
        title: 'Save Folders',
        subtitle: 'Where each emulator must save (set once)',
        icon: Icons.folder_copy_outlined,
        onPress: () => _xmb.currentState?.showPanel(
          XPanel(
            title: 'Save Folders',
            lines: f == null
                ? const ['Allow storage access first.']
                : [
                    'RetroArch: automatic (the menu starts it with its own '
                        'settings: saves sorted by core, as on the PC).',
                    '   ${_shortPath(f.raSaves)}',
                    'PPSSPP: in PPSSPP, Settings > System > Memory Stick '
                        'folder: choose',
                    '   ${_shortPath(f.ppssppStick)}',
                    'DuckStation: set its memory card folder to',
                    '   ${_shortPath(f.duckCards)}',
                    '   (memory card type: separate card per game title)',
                    'BIOS files for RetroArch: ${_shortPath(f.bios)}',
                    'Backups before anything is replaced: ${_shortPath(f.backups)}',
                  ],
          ),
        ),
      ),
      XItem(
        title: 'RetroArch Settings',
        subtitle: _s.raOwnConfig
            ? "RetroArch's own (set its save folder yourself)"
            : "The menu's (saves go where cross saves look)",
        icon: Icons.tune,
        onPress: () {
          _s.raOwnConfig = !_s.raOwnConfig;
          _s.changed();
        },
      ),
    ];
  }

  XItem _conflictItem(Conflict c) {
    String when(String path) {
      try {
        final t = File(path).lastModifiedSync();
        return '${t.month}/${t.day} ${t.hour}:${t.minute.toString().padLeft(2, '0')}';
      } catch (_) {
        return '?';
      }
    }

    final name = p.basenameWithoutExtension(c.key);
    return XItem(
      title: name,
      subtitle:
          'This device: ${when(c.local)}  ·  other copy arrived ${when(c.copy)}',
      icon: Icons.call_split,
      onPress: () => _xmb.currentState?.showPanel(
        XPanel(
          title: name,
          lines: [
            'This save changed here and on another device before they synced.',
            'This device saved it ${when(c.local)}.',
            'The other copy (from the repo) is beside it: ${p.basename(c.copy)}.',
            'Whichever you pick, the other one is backed up first.',
          ],
          options: [
            XOption(
              "Keep This Device's",
              () => _cs!.resolve(c, keepThisDevice: true),
            ),
            XOption(
              'Use the Other One',
              () => _cs!.resolve(c, keepThisDevice: false),
            ),
            XOption('Decide Later', () {}),
          ],
        ),
      ),
    );
  }

  void _tokenHelp() => _xmb.currentState?.showPanel(
    XPanel(
      title: 'Making the GitHub Token',
      lines: const [
        '1. On github.com: Settings > Developer settings > Personal access '
            'tokens > Fine-grained tokens > Generate new token.',
        '2. Repository access: Only select repositories > Cross-Save.',
        '3. Permissions > Repository permissions > Contents: Read and write.',
        '4. Generate, copy it, and paste it here (Cross Save > GitHub Token).',
        'It stays in this app on this device only.',
      ],
    ),
  );

  Future<void> _askToken() async {
    final cs = _cs!;
    final field = TextEditingController();
    final t = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('GitHub token'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste the fine-grained token that can read and write the '
              'Cross-Save repo.',
            ),
            TextField(
              controller: field,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(hintText: 'github_pat_…'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (t == null || t.trim().isEmpty) return;
    final err = await cs.setToken(t);
    if (err != null) {
      _xmb.currentState?.showPanel(
        XPanel(title: 'That token did not work', lines: [err]),
      );
      return;
    }
    _xmb.currentState?.toast('Connected to Cross-Save. Syncing…');
    await _sync();
  }

  List<XItem> _emulatorsList() => [
    for (final s in systems)
      XItem(
        title: s.title,
        subtitle: () {
          final c = _choiceFor(s);
          return c == null
              ? 'Needs ${s.runners.map((r) => r.label).join(' or ')}'
              : 'Plays with ${c.label}';
        }(),
        icon: Icons.videogame_asset_outlined,
        onPress: () => _testLaunch(s),
        options: () => [
          XOption('Test Launch', () => _testLaunch(s)),
          if (s.runners.contains(Runner.retroarch))
            for (final c in s.cores)
              XOption(
                '${(_s.cores[s.id] ?? s.cores.first) == c ? '● ' : ''}RetroArch core: $c',
                () {
                  _s.cores[s.id] = c;
                  _s.changed();
                },
              ),
          if (s.runners.length > 1 && s.runners.contains(Runner.retroarch))
            XOption(
              _s.preferRetroArch.contains(s.id)
                  ? 'Use ${s.runners.first.label} again'
                  : 'Use RetroArch instead',
              () {
                if (!_s.preferRetroArch.remove(s.id)) {
                  _s.preferRetroArch.add(s.id);
                }
                _s.changed();
              },
            ),
          if (s.note != null) XOption(s.note!, () {}),
        ],
      ),
  ];

  void _testLaunch(GameSystem s) {
    final g = _s.games.where((g) => g.system == s.id).firstOrNull;
    if (g == null) {
      _xmb.currentState?.toast('No ${s.title} games found to test with');
      return;
    }
    _xmb.currentState?.showPanel(
      XPanel(
        title: 'Test Launch',
        lines: [
          'Starts "${g.title}" with ${_choiceFor(s)?.label ?? 'nothing'}.',
          'If the emulator opens without the game, tell Claude what you see.',
        ],
        options: [
          XOption('Start It', () => _play(g)),
          XOption('Cancel', () {}),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const ColoredBox(color: Color(0xFF0E2A63));
    }
    // Storage roots come from Android; fetched once for the folder picker.
    if (_rootsCache == null) {
      unawaited(
        _roots().then((r) {
          if (mounted) setState(() => _rootsCache = r);
        }),
      );
    }
    final emus = [
      for (final r in Runner.values)
        if (runnerPackages[r]!.any(_installed.contains)) r.label,
    ];
    return Scaffold(
      backgroundColor: const Color(0xFF0E2A63),
      body: XmbView(
        key: _xmb,
        revision: _revision,
        swapAB: _s.swapAB,
        initialCategory: 1,
        status: [
          if (emus.isNotEmpty) emus.join('  ·  '),
          if (_crossLine() != null) _crossLine()!,
        ].join('\n'),
        categories: [
          XCategory('settings', 'Settings', Icons.work_outline, _settingsRow),
          XCategory('game', 'Game', Icons.sports_esports_outlined, _gameRow),
          XCategory(
            'memory',
            'Memory Card',
            Icons.sd_card_outlined,
            _memoryRow,
          ),
          XCategory('comics', 'Comics', Icons.menu_book_outlined, _comicsRow),
        ],
      ),
    );
  }
}
