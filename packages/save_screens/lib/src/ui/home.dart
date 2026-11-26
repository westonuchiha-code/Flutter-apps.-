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
    final old = _c;
    setState(() => _c = c);
    old?.dispose();
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
        onGame: widget.onGame,
        onLeave: widget.onLeave,
      );
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(backgroundColor: const Color(0xFF0B0D3A), body: body),
    );
  }
}
