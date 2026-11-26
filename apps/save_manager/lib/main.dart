import 'dart:async';
import 'dart:io';

import 'package:app_shell/app_shell.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'src/art/art.dart';
import 'src/controller.dart';
import 'src/host.dart';
import 'src/state.dart';
import 'src/ui/access_page.dart';
import 'src/ui/screen.dart';

/// Folders to read besides the emulators' usual ones.
const extraFoldersSetting = TextSetting(
  key: 'extraFolders',
  title: 'Extra save folders',
  subtitle:
      'One per line (or separated by ;). Memory cards in them show up too.',
  section: 'Save folders',
);

/// The order the grid starts in.
final sortSetting = ChoiceSetting(
  key: 'sort',
  title: 'Sort saves',
  defaultValue: '0',
  choices: {for (final (i, s) in MemoryCardState.sorts.indexed) '$i': s},
  section: 'Save folders',
);

final appConfig = AppShellConfig(
  id: 'save_manager',
  name: 'Save Manager',
  version: '0.1.0',
  description:
      'Memory cards of PS1, PS2, Dreamcast, GameCube, N64, Saturn and Neo Geo '
      'emulators, and PS3 saves: copy, move, back up, restore, undelete, '
      'export and import. Every change is backed up first.',
  accent: Look.cyan,
  defaultThemeMode: ThemeMode.dark,
  settings: [extraFoldersSetting, sortSetting],
);

void main() => runShellApp(appConfig, (_) => const HomePage());

/// Builds the controller's config (tests pass their own).
typedef ConfigMaker = Future<SaveManagerConfig> Function(
  List<String> extra,
  EmulatorCheck? check,
);

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.makeConfig, this.runner, this.showHints});

  /// null = this device's folders.
  final ConfigMaker? makeConfig;

  /// How reads and jobs run (null = a background isolate).
  final BackgroundRunner? runner;

  /// See [SaveManagerScreen.showHints].
  final bool? showHints;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  SaveManagerController? _c;
  bool? _access;
  String _extra = '';
  String _sort = '';
  // Android can't see other apps: ask before writing (kept across rebuilds)
  final EmulatorCheck? _check = Platform.isAndroid ? EmulatorCheck() : null;
  SettingsStore? _settings;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_checkAccess());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = Shell.of(context).settings;
    if (s != _settings) {
      _settings?.removeListener(_settingsChanged);
      _settings = s..addListener(_settingsChanged);
      _settingsChanged();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settings?.removeListener(_settingsChanged);
    _c?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_access == false) {
      unawaited(_checkAccess());
    } else {
      _c?.refresh(); // an emulator may have changed the cards meanwhile
    }
  }

  Future<void> _checkAccess() async {
    final ok = widget.makeConfig != null || await hasAllFiles();
    if (!mounted) return;
    final was = _access;
    setState(() => _access = ok);
    if (ok && was != true) unawaited(_build());
  }

  void _settingsChanged() {
    final s = _settings!;
    final extra = s.get(extraFoldersSetting);
    final sort = s.get(sortSetting);
    final changed = extra != _extra;
    _extra = extra;
    if (sort != _sort) {
      _sort = sort;
      final c = _c;
      if (c != null) {
        c.state.sort = int.tryParse(sort) ?? 0;
        c.refresh();
      }
    }
    if (changed && _access == true) unawaited(_build());
  }

  Future<void> _build() async {
    final extra = splitFolders(_extra);
    final make = widget.makeConfig;
    final SaveManagerConfig config;
    if (make != null) {
      config = await make(extra, _check);
    } else {
      final at = await resolvePlaces();
      config = appConfigFor(at, extra: extra, check: _check);
    }
    if (!mounted) return;
    final services = Shell.of(context);
    final c = SaveManagerController(
      config,
      runner: widget.runner,
      check: _check,
      onSound: (cue) {
        if (cue == 'confirm' || cue == 'move') services.tick();
      },
    );
    c.state.sort = int.tryParse(_sort) ?? 0;
    final old = _c;
    setState(() => _c = c);
    old?.dispose();
  }

  List<Widget> _actions(BuildContext context) => [
    for (final (tip, icon, page) in [
      ('Settings', Icons.settings_outlined, const SettingsPage() as Widget),
      ('About', Icons.info_outline, const AboutShellPage() as Widget),
    ])
      IconButton(
        tooltip: tip,
        color: Look.soft,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        icon: Icon(icon),
        onPressed: () =>
            Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => page)),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final c = _c;
    Widget body;
    if (_access == false) {
      body = AccessPage(
        onAllow: () => unawaited(requestAllFiles()),
        onCheck: () => unawaited(_checkAccess()),
      );
    } else if (c == null) {
      body = const MemoryBackdrop();
    } else {
      body = SaveManagerScreen(
        key: ObjectKey(c),
        controller: c,
        showHints: widget.showHints,
        actions: _actions(context),
      );
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(backgroundColor: const Color(0xFF0B0D3A), body: body),
    );
  }
}
