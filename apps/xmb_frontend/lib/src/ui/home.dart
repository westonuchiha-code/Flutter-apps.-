import 'dart:async';
import 'dart:io';

import 'package:app_shell/app_shell.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../android.dart';
import '../launch.dart';
import '../library/scanner.dart';
import '../library/systems.dart';
import '../state.dart';
import 'xmb.dart';

/// The menu: Settings and Game for now (more categories come with the
/// save sync, comics, save manager, Pokéville and CRT TV).
class HomePage extends StatefulWidget {
  const HomePage({super.key, this.bridge = const AndroidBridge(), this.state});

  final AndroidBridge bridge;

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
    unawaited(_start());
  }

  @override
  void dispose() {
    _life?.dispose();
    _saveTimer?.cancel();
    _s.removeListener(_changed);
    super.dispose();
  }

  Future<void> _start() async {
    if (widget.state == null) {
      _s.load(await Shell.of(context).storage.readJson('menu.json'));
    }
    // Not awaited: the menu must never wait on the system for this.
    unawaited(_applyScreen().catchError((_) {}));
    await _checkDevice();
    _loaded = true;
    if (_s.romsDir != null && _s.games.isEmpty) await _scan();
    _bump();
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
    _s.returned(DateTime.now().millisecondsSinceEpoch);
    final had = _allFiles;
    await _checkDevice();
    if (!had && _allFiles && _s.romsDir != null) await _scan();
    _bump();
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

  Future<void> _scan() async {
    final dir = _s.romsDir;
    if (dir == null || _scanning) return;
    setState(() => _scanning = true);
    try {
      final list = await runInBackground(scanLibraryJson, dir);
      _s.games = [for (final g in list) Game.fromJson(g)];
      _s.scanned = DateTime.now();
      _s.changed();
      _xmb.currentState?.toast(
        'Found ${_s.games.length} game${_s.games.length == 1 ? '' : 's'}',
      );
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
    final err = await _a.launch(launchSpec(g, choice));
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
      out.add(
        XItem(
          title: 'Choose Your ROMs Folder',
          subtitle: 'The folder with one folder per console (NES, SNES, PS1…)',
          icon: Icons.create_new_folder_outlined,
          children: () => _rootsCache ?? _browse(null),
        ),
      );
      return out;
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
  List<XItem> _browse(String? dir) {
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
        onPress: () => _useRoms(dir),
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
            children: () => _browse(d.path),
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

  Future<List<XItem>> _roots() async {
    final roots = await _a.storageRoots();
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

  void _useRoms(String dir) {
    _s.romsDir = dir;
    _s.games = [];
    _s.changed();
    _xmb.currentState?.closeFolders();
    unawaited(_scan());
  }

  List<XItem>? _rootsCache;

  List<XItem> _settingsRow() {
    final raInstalled = [
      for (final pkg in runnerPackages[Runner.retroarch]!)
        if (_installed.contains(pkg)) pkg,
    ];
    return [
      XItem(
        title: 'ROMs Folder',
        subtitle: _s.romsDir ?? 'Not chosen yet',
        icon: Icons.folder_special_outlined,
        children: () => _rootsCache ?? _browse(null),
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
        status: emus.isEmpty ? null : emus.join('  ·  '),
        categories: [
          XCategory('settings', 'Settings', Icons.work_outline, _settingsRow),
          XCategory('game', 'Game', Icons.sports_esports_outlined, _gameRow),
        ],
      ),
    );
  }
}
