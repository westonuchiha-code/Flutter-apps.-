/// The whole save manager as one widget: Android's all-files access
/// first, then the screen over the cards found. The Save Manager app shows
/// it as its home; the XMB Frontend pushes it from its Memory Card row.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:save_kit/save_kit.dart';

import '../art/art.dart';
import '../controller.dart';
import '../host.dart';
import 'access_page.dart';
import 'screen.dart';

/// Builds the config (tests and hosts with their own folders).
typedef ConfigMaker = Future<SaveManagerConfig> Function(
  List<String> extra,
  EmulatorCheck? check,
);

class SaveManagerHome extends StatefulWidget {
  const SaveManagerHome({
    super.key,
    this.extraFolders = '',
    this.sort = 0,
    this.games = const [],
    this.played = const {},
    this.onGame,
    this.onStartSave,
    this.startSystems = const {},
    this.onLeave,
    this.actions = const [],
    this.onTick,
    this.makeConfig,
    this.runner,
    this.showHints,
  });

  /// More folders to read, one per line or split by `;`.
  final String extraFolders;

  /// [MemoryCardState.sorts] index.
  final int sort;

  /// The host's game library (names saves, Start game, play time).
  final List<LibraryGame> games;
  final Map<String, PlayStats> played;

  /// Start game: the host starts it (null: a notice says it can't here).
  final void Function(String gameId)? onGame;

  /// Start game for a host with no library (the Save Manager app hands it
  /// to the XMB Frontend): every save of [startSystems] (empty: any) that
  /// the library didn't match offers Start game, and this hears the save.
  /// What it returns, if anything, shows as a notice.
  final Future<String?> Function(CardSave save)? onStartSave;
  final Set<String> startSystems;

  /// B with nowhere further back.
  final VoidCallback? onLeave;

  /// Buttons in the corner (settings, about...).
  final List<Widget> actions;

  /// A confirm or move happened (haptics).
  final VoidCallback? onTick;

  final ConfigMaker? makeConfig;
  final BackgroundRunner? runner;
  final bool? showHints;

  @override
  State<SaveManagerHome> createState() => _SaveManagerHomeState();
}

class _SaveManagerHomeState extends State<SaveManagerHome>
    with WidgetsBindingObserver {
  SaveManagerController? _c;
  bool? _access;
  final EmulatorCheck? _check = Platform.isAndroid ? EmulatorCheck() : null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_checkAccess());
  }

  @override
  void didUpdateWidget(SaveManagerHome old) {
    super.didUpdateWidget(old);
    if (old.sort != widget.sort) {
      final c = _c;
      if (c != null) {
        c.state.sort = widget.sort;
        c.refresh();
      }
    }
    if (old.extraFolders != widget.extraFolders && _access == true) {
      unawaited(_build());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  Future<void> _build() async {
    final extra = splitFolders(widget.extraFolders);
    final make = widget.makeConfig;
    final SaveManagerConfig config;
    if (make != null) {
      config = await make(extra, _check);
    } else {
      final at = await resolvePlaces();
      config = appConfigFor(
        at,
        extra: extra,
        check: _check,
        games: widget.games,
        played: widget.played,
      );
    }
    if (!mounted) return;
    final c = SaveManagerController(
      config,
      runner: widget.runner,
      check: _check,
      onSound: (cue) {
        if (cue == 'confirm' || cue == 'move') widget.onTick?.call();
      },
    );
    c.state.sort = widget.sort;
    if (widget.onStartSave != null) c.addListener(() => _markStartable(c));
    final old = _c;
    setState(() => _c = c);
    old?.dispose();
  }

  /// Saves Start game hands to [SaveManagerHome.onStartSave], by the
  /// stand-in game id they're given.
  final _startable = <String, CardSave>{};
  static const _startTag = 'start-save:';

  /// The saves on show get a stand-in game id, so their options offer
  /// Start game and A hands it to [_game].
  void _markStartable(SaveManagerController c) {
    final only = widget.startSystems;
    _startable.clear();
    for (final s in c.state.saves) {
      if (s.gameId.isEmpty && (only.isEmpty || only.contains(s.system))) {
        s.gameId = '$_startTag${identityHashCode(s)}';
      }
      if (s.gameId.startsWith(_startTag)) _startable[s.gameId] = s;
    }
  }

  void _game(String gameId) {
    final save = _startable[gameId];
    final start = widget.onStartSave;
    if (save == null || start == null) {
      widget.onGame?.call(gameId);
      return;
    }
    unawaited(
      start(save).then((notice) {
        if (mounted && notice != null && notice.isNotEmpty) {
          _c?.showNotice(notice);
        }
      }),
    );
  }

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
        actions: widget.actions,
        onGame: widget.onStartSave != null ? _game : widget.onGame,
        onLeave: widget.onLeave,
      );
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(backgroundColor: const Color(0xFF0B0D3A), body: body),
    );
  }
}
