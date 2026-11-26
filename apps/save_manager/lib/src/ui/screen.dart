/// The save manager on screen: picks the page (list, opened save, card
/// page, a dialog) and the layout (wide like the PC, or compact), takes
/// the gamepad / keyboard at the root, shows notices and asks for names.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../art/art.dart';
import '../controller.dart';
import '../state.dart';
import '../texts.dart';
import 'dialogs.dart';
import 'kit.dart';
import 'list_page.dart';
import 'pages.dart';
import 'taps.dart';

class SaveManagerScreen extends StatefulWidget {
  const SaveManagerScreen({
    super.key,
    required this.controller,
    this.actions = const [],
    this.showHints,
    this.onGame,
    this.onLeave,
  });

  final SaveManagerController controller;

  /// Small buttons in a corner (Settings, About).
  final List<Widget> actions;

  /// The button hints: null = shown on desktops, and on Android once a
  /// gamepad or keyboard is used.
  final bool? showHints;

  /// A asked to start a game (this app has no game library: null shows a
  /// notice). The hook for a host that can start games.
  final void Function(String gameId)? onGame;

  /// B with nowhere further back (null: Android leaves the app, desktops
  /// stay).
  final VoidCallback? onLeave;

  /// How long X is held to mark every save of that game.
  static const holdX = Duration(milliseconds: 450);

  @override
  State<SaveManagerScreen> createState() => _SaveManagerScreenState();
}

class _SaveManagerScreenState extends State<SaveManagerScreen> {
  final _focus = FocusNode(debugLabel: 'save manager');
  final _pageScroll = ScrollController();
  Timer? _noticeTimer;
  int _noticeSeen = 0;
  Timer? _xTimer;
  bool _xLong = false;
  bool _sawKeys = false;
  bool _naming = false;

  SaveManagerController get c => widget.controller;

  late Taps _taps = Taps(c, onGame: _game);

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    if (!c.isOpen) c.open();
  }

  @override
  void didUpdateWidget(SaveManagerScreen old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _taps = Taps(c, onGame: _game);
      if (!c.isOpen) c.open();
    }
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    _noticeTimer?.cancel();
    _xTimer?.cancel();
    _focus.dispose();
    _pageScroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (c.noticeCount != _noticeSeen) {
      _noticeSeen = c.noticeCount;
      _noticeTimer?.cancel();
      if (c.notice.isNotEmpty) {
        _noticeTimer = Timer(
          Duration(
            milliseconds: (SaveManagerController.noticeSeconds * 1000).round(),
          ),
          c.clearNotice,
        );
      }
    }
    if (c.renaming != null && !_naming) {
      _naming = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _askName());
    }
    if (!c.isOpen) {
      // B with nowhere further back
      c.isOpen = true;
      final leave = widget.onLeave;
      if (leave != null) {
        leave();
      } else if (Platform.isAndroid) {
        SystemNavigator.pop();
      }
    }
  }

  void _game(String gameId) {
    final host = widget.onGame;
    if (host != null) {
      host(gameId);
      return;
    }
    c.showNotice(
      "Games are started from the XMB Frontend: this app manages the saves",
    );
  }

  Future<void> _askName() async {
    final card = c.renaming;
    if (card == null || !mounted) {
      _naming = false;
      return;
    }
    final text = TextEditingController(text: card.name);
    final got = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename card'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('rename-field'),
              controller: text,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Card name'),
              onSubmitted: (v) => Navigator.of(context).pop(v),
            ),
            const SizedBox(height: 8),
            const Text(
              "Only this app shows the name: the file keeps its own, so the "
              'emulator still finds it. Empty = its own name again.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('rename-ok'),
            onPressed: () => Navigator.of(context).pop(text.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    text.dispose();
    _naming = false;
    if (got == null) {
      c.cancelRename();
    } else {
      c.named(got);
    }
    if (mounted) _focus.requestFocus();
  }

  // ---- the gamepad and keyboard --------------------------------------------

  static final _up = {LogicalKeyboardKey.arrowUp};
  static final _down = {LogicalKeyboardKey.arrowDown};
  static final _left = {LogicalKeyboardKey.arrowLeft};
  static final _right = {LogicalKeyboardKey.arrowRight};
  static final _a = {
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.gameButtonA,
    LogicalKeyboardKey.select,
  };
  static final _b = {
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.backspace,
    LogicalKeyboardKey.gameButtonB,
    LogicalKeyboardKey.goBack,
  };
  static final _y = {LogicalKeyboardKey.gameButtonY, LogicalKeyboardKey.keyY};
  static final _x = {LogicalKeyboardKey.gameButtonX, LogicalKeyboardKey.keyX};
  static final _favorite = {
    LogicalKeyboardKey.gameButtonRight2,
    LogicalKeyboardKey.keyF,
  };
  static final _pageBack = {
    LogicalKeyboardKey.gameButtonLeft1,
    LogicalKeyboardKey.pageUp,
  };
  static final _pageOn = {
    LogicalKeyboardKey.gameButtonRight1,
    LogicalKeyboardKey.pageDown,
  };

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    final k = e.logicalKey;
    if (e is KeyUpEvent) {
      if (_x.contains(k)) {
        final waiting = _xTimer?.isActive ?? false;
        _xTimer?.cancel();
        _xTimer = null;
        if (waiting && !_xLong) c.mark();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (!_sawKeys) setState(() => _sawKeys = true);
    final repeat = e is KeyRepeatEvent;
    int dx = 0, dy = 0;
    if (_up.contains(k)) dy = -1;
    if (_down.contains(k)) dy = 1;
    if (_left.contains(k)) dx = -1;
    if (_right.contains(k)) dx = 1;
    if (dx != 0 || dy != 0) {
      _step(dx, dy);
      return KeyEventResult.handled;
    }
    if (_pageBack.contains(k) || _pageOn.contains(k)) {
      c.turnPage(_pageBack.contains(k) ? -1 : 1);
      return KeyEventResult.handled;
    }
    if (repeat) {
      // held buttons don't repeat
      return _a.contains(k) ||
              _b.contains(k) ||
              _x.contains(k) ||
              _y.contains(k) ||
              _favorite.contains(k)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (_a.contains(k)) {
      _taps.confirm();
    } else if (_b.contains(k)) {
      c.cancel();
    } else if (_y.contains(k)) {
      c.toggleOptions();
    } else if (_x.contains(k)) {
      _xLong = false;
      _xTimer?.cancel();
      _xTimer = Timer(SaveManagerScreen.holdX, () {
        _xLong = true;
        c.markGame();
      });
    } else if (_favorite.contains(k)) {
      c.toggleFavorite();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // Compact pages scroll with up / down (the PC's file window is the whole
  // page here).
  void _step(int dx, int dy) {
    final st = c.state;
    final scrolls =
        dy != 0 &&
        !c.flow.isOpen() &&
        c.asking == null &&
        (st.mode == Mode.opened || st.mode == Mode.card) &&
        _compact &&
        _pageScroll.hasClients;
    if (scrolls) {
      final pos = _pageScroll.position;
      _pageScroll.animateTo(
        (pos.pixels + dy * 90).clamp(pos.minScrollExtent, pos.maxScrollExtent),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
      return;
    }
    c.step(dx, dy);
  }

  bool _compact = false;

  bool get _hints =>
      widget.showHints ?? (!(Platform.isAndroid || Platform.isIOS) || _sawKeys);

  // ---- drawing ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) c.cancel();
    },
    child: Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _key,
      child: ListenableBuilder(
        listenable: c,
        builder: (context, _) => LayoutBuilder(
          builder: (context, box) => _page(context, Dims(box.biggest)),
        ),
      ),
    ),
  );

  Widget _page(BuildContext context, Dims d) {
    _compact = d.compact;
    final st = c.state;
    final dialog = c.flow.isOpen() || c.asking != null;
    final Widget page;
    if (dialog) {
      page = FlowDialog(
        c: c,
        taps: _taps,
        d: d,
        stickerFolder: c.config.stickerFolder,
      );
    } else {
      page = switch (st.mode) {
        Mode.opened => OpenedPage(c: c, taps: _taps, d: d, scroll: _pageScroll),
        Mode.card => CardPage(c: c, taps: _taps, d: d, scroll: _pageScroll),
        Mode.list || Mode.options =>
          d.compact
              ? CompactList(
                  c: c,
                  taps: _taps,
                  d: d,
                  actions: _actions(d),
                  touch: !_hints,
                )
              : WideList(
                  c: c,
                  taps: _taps,
                  d: d,
                  actions: _actions(d),
                  touch: !_hints,
                ),
      };
    }
    final hints = _hints
        ? (c.asking != null
              ? Texts.dialogHints(c.flow).isEmpty
                    ? const [
                        (button: 'A', label: 'Select'),
                        (button: 'B', label: 'Back'),
                      ]
                    : Texts.dialogHints(c.flow)
              : Texts.hints(st, c.flow))
        : const <Hint>[];
    final opened = !dialog && st.mode == Mode.opened ? st.current() : null;
    final notice = c.notice;
    if (d.compact) {
      return MemoryBackdrop.forSave(
        opened,
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  Expanded(child: page),
                  if (hints.isNotEmpty)
                    SizedBox(
                      height: 26,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Center(child: HintsBar(hints, size: 12.5)),
                      ),
                    ),
                ],
              ),
              if (notice.isNotEmpty)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: hints.isNotEmpty ? 84 : 62,
                  child: Center(
                    child: NoticeBox(
                      notice,
                      key: const ValueKey('notice'),
                      size: 13,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return MemoryBackdrop.forSave(
      opened,
      child: Stack(
        children: [
          Positioned.fill(child: page),
          if (hints.isNotEmpty)
            d.at(
              0,
              1016,
              1920,
              56,
              Center(child: HintsBar(hints, size: 24 * d.u)),
            ),
          if (notice.isNotEmpty)
            d.at(
              210,
              830,
              1500,
              70,
              Center(
                child: NoticeBox(
                  notice,
                  key: const ValueKey('notice'),
                  size: 24 * d.u,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _actions(Dims d) => [
    for (final a in widget.actions)
      IconTheme(
        data: IconThemeData(color: Look.soft, size: d.compact ? 20 : 28 * d.u),
        child: a,
      ),
  ];
}
