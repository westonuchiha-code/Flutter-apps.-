// The Pokéville widgets: PokevilleScreen (the Box) and PokevilleHome (the
// Box, or a friendly page while the folder has no box.json yet).
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'controller.dart';
import 'folder.dart';
import 'guard.dart';
import 'look.dart';
import 'painter.dart';
import 'sprites.dart';
import 'store.dart';

/// The pad / keyboard buttons Pokéville uses.
enum PokeButton { up, down, left, right, a, b, x, y, lb, rb }

/// Which button a key is (null: not one of ours). Arrows / d-pad, A / Enter /
/// Space, B / Esc / Backspace, X, Y, LB / RB / PageUp / PageDown.
PokeButton? pokeButtonFor(LogicalKeyboardKey k) => switch (k) {
  LogicalKeyboardKey.arrowUp => PokeButton.up,
  LogicalKeyboardKey.arrowDown => PokeButton.down,
  LogicalKeyboardKey.arrowLeft => PokeButton.left,
  LogicalKeyboardKey.arrowRight => PokeButton.right,
  LogicalKeyboardKey.gameButtonA ||
  LogicalKeyboardKey.enter ||
  LogicalKeyboardKey.numpadEnter ||
  LogicalKeyboardKey.select ||
  LogicalKeyboardKey.space => PokeButton.a,
  LogicalKeyboardKey.gameButtonB ||
  LogicalKeyboardKey.escape ||
  LogicalKeyboardKey.backspace ||
  LogicalKeyboardKey.goBack => PokeButton.b,
  LogicalKeyboardKey.gameButtonX || LogicalKeyboardKey.keyX => PokeButton.x,
  LogicalKeyboardKey.gameButtonY ||
  LogicalKeyboardKey.keyY ||
  LogicalKeyboardKey.contextMenu => PokeButton.y,
  LogicalKeyboardKey.gameButtonLeft1 ||
  LogicalKeyboardKey.pageUp ||
  LogicalKeyboardKey.keyQ => PokeButton.lb,
  LogicalKeyboardKey.gameButtonRight1 ||
  LogicalKeyboardKey.pageDown ||
  LogicalKeyboardKey.keyE => PokeButton.rb,
  _ => null,
};

/// Pokéville: view and arrange the Box in [folder] (the synced Pokéville
/// folder holding box.json). Sprites are cached in [cacheDir].
///
/// Pad / keyboard: arrows move, A picks up / puts down, B backs out (lets go,
/// leaves Check, then [onLeave]), Y checks, X opens the menu, LB / RB (or
/// PageUp / PageDown) change box. Touch: tap a slot to select it, tap again
/// to pick up / put down; long-press and drag to carry one; swipe or tap the
/// arrows / strip to change box; the buttons along the bottom.
class PokevilleScreen extends StatefulWidget {
  const PokevilleScreen(
    this.folder,
    this.cacheDir, {
    super.key,
    this.onLeave,
    this.swapAB = false,
    this.autofocus = true,
    this.controller,
    this.sprites,
    this.fetcher,
    this.games,
    this.guard,
  });

  /// The Pokéville folder (box.json, mons/).
  final String folder;

  /// Where downloaded sprites are kept.
  final String cacheDir;

  /// B with nothing left to back out of (or Android's back). Null: pops the
  /// route.
  final VoidCallback? onLeave;

  /// Nintendo-style pads: the pad's A and B swapped (keyboard keys never).
  final bool swapAB;
  final bool autofocus;

  /// A controller to use (tests, or a host that keeps one); else made here.
  final PokevilleController? controller;

  /// Sprites to use; else made here with [fetcher] (default: the internet).
  final PokeSprites? sprites;
  final SpriteFetcher? fetcher;

  /// The host's Pokémon game saves (null: none here, "on the PC").
  final PokeGames? games;

  /// Emulator safety (null: the platform's, see [SaveGuard.forPlatform]).
  final SaveGuard? guard;

  @override
  State<PokevilleScreen> createState() => _PokevilleScreenState();
}

class _PokevilleScreenState extends State<PokevilleScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late PokevilleController c;
  late PokeSprites sprites;
  late bool _ownController;
  late bool _ownSprites;
  final _hits = Hits();
  final _focus = FocusNode(debugLabel: 'pokeville');
  late final AnimationController _sway;
  late final Ticker _clock = createTicker(_tick);
  Duration _last = Duration.zero;
  Timer? _noticeTimer;
  int _noticeSeen = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownController = widget.controller == null;
    c = widget.controller ?? _make();
    _ownSprites = widget.sprites == null;
    sprites =
        widget.sprites ?? PokeSprites(widget.cacheDir, fetcher: widget.fetcher);
    _sway = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    c.addListener(_changed);
    _changed();
  }

  @override
  void didUpdateWidget(PokevilleScreen old) {
    super.didUpdateWidget(old);
    final folderMoved = old.folder != widget.folder;
    if (widget.controller != old.controller ||
        (folderMoved && widget.controller == null)) {
      c.removeListener(_changed);
      if (_ownController) c.dispose();
      _ownController = widget.controller == null;
      c = widget.controller ?? _make();
      c.addListener(_changed);
      _changed();
    }
    if (widget.sprites != old.sprites || old.cacheDir != widget.cacheDir) {
      if (_ownSprites) sprites.dispose();
      _ownSprites = widget.sprites == null;
      sprites =
          widget.sprites ??
          PokeSprites(widget.cacheDir, fetcher: widget.fetcher);
    }
  }

  PokevilleController _make() => PokevilleController(
    PokevilleFolder(widget.folder),
    games: widget.games,
    guard: widget.guard,
  )..open();

  void _changed() {
    if (c.noticeId != _noticeSeen) {
      _noticeSeen = c.noticeId;
      _noticeTimer?.cancel();
      _noticeTimer = Timer(const Duration(seconds: 5), c.clearNotice);
    }
    if (c.transfer != null && !_clock.isActive) {
      _last = Duration.zero;
      _clock.start();
    } else if (c.transfer == null && _clock.isActive) {
      _clock.stop();
    }
    if (c.holding && !_sway.isAnimating) {
      _sway.repeat();
    } else if (!c.holding && _sway.isAnimating) {
      _sway.stop();
    }
  }

  void _tick(Duration at) {
    final dt = (at - _last).inMicroseconds / 1e6;
    _last = at;
    c.advanceTransfer(dt.clamp(0, 0.1));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // a sync may have come in while away
    if (state == AppLifecycleState.resumed) unawaited(c.refreshIfChanged());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _noticeTimer?.cancel();
    c.removeListener(_changed);
    if (_ownController) c.dispose();
    if (_ownSprites) sprites.dispose();
    _sway.dispose();
    _clock.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _leave() {
    if (widget.onLeave != null) {
      widget.onLeave!();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _back() {
    if (!c.cancel()) _leave();
  }

  void press(PokeButton b) {
    switch (b) {
      case PokeButton.up:
        c.step(0, -1);
      case PokeButton.down:
        c.step(0, 1);
      case PokeButton.left:
        c.step(-1, 0);
      case PokeButton.right:
        c.step(1, 0);
      case PokeButton.a:
        unawaited(c.confirm());
      case PokeButton.b:
        _back();
      case PokeButton.x:
        c.menu();
      case PokeButton.y:
        c.check();
      case PokeButton.lb:
        c.turnPage(-1);
      case PokeButton.rb:
        c.turnPage(1);
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    var b = pokeButtonFor(k);
    if (b == null) return KeyEventResult.ignored;
    if (widget.swapAB && k == LogicalKeyboardKey.gameButtonA) b = PokeButton.b;
    if (widget.swapAB && k == LogicalKeyboardKey.gameButtonB) b = PokeButton.a;
    const moves = {
      PokeButton.up,
      PokeButton.down,
      PokeButton.left,
      PokeButton.right,
      PokeButton.lb,
      PokeButton.rb,
    };
    if (e is KeyRepeatEvent && !moves.contains(b)) {
      return KeyEventResult.handled; // held buttons don't repeat
    }
    press(b);
    return KeyEventResult.handled;
  }

  // ---- touch ----------------------------------------------------------------

  void _tap(Offset at) {
    _focus.requestFocus();
    final h = _hits.at(at);
    if (h == null) return;
    switch (h.kind) {
      case HitKind.slot:
        unawaited(c.tap(h.index));
      case HitKind.pagePrev:
        c.turnPage(-1);
      case HitKind.pageNext:
        c.turnPage(1);
      case HitKind.strip:
        c.goToPage(h.index);
      case HitKind.button:
        press(
          const [
            PokeButton.a,
            PokeButton.y,
            PokeButton.x,
            PokeButton.b,
          ][h.index],
        );
      case HitKind.data:
        if (c.shown != null) c.check();
      case HitKind.tab:
        c.setTab(h.index);
      case HitKind.dexPrev:
        c.turnPage(-1);
      case HitKind.dexNext:
        c.turnPage(1);
      case HitKind.checkPrev:
        c.step(0, -1);
      case HitKind.checkNext:
        c.step(0, 1);
      case HitKind.menuRow:
        if (h.index >= 0) {
          c.menuSelect(h.index);
          unawaited(c.confirm());
        }
      case HitKind.menuOutside:
        c.cancel();
      case HitKind.answer:
        c.answerSelect(h.index);
        unawaited(c.answer(h.index));
      case HitKind.transfer:
        c.skipTransfer();
    }
  }

  void _dragStart(Offset at) {
    if (c.view != PokeView.box || c.menuOpen) return;
    final i = _hits.slotAt(at);
    if (i == null) return;
    c.select(i);
    if (!c.holding && c.pageMon(c.page, i) != null) {
      unawaited(c.confirm()); // picks it up
    }
    _dragging = c.holding;
  }

  void _dragMove(Offset at) {
    if (!_dragging) return;
    final i = _hits.slotAt(at);
    if (i != null && i != c.slotIndex) c.select(i);
  }

  void _dragEnd() {
    if (!_dragging) return;
    _dragging = false;
    if (c.holding) unawaited(c.confirm()); // puts it down
  }

  void _swipe(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v.abs() < 250 || c.menuOpen) return;
    c.turnPage(v < 0 ? 1 : -1);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Focus(
        focusNode: _focus,
        autofocus: widget.autofocus,
        onKeyEvent: _key,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _tap(d.localPosition),
          onLongPressStart: (d) => _dragStart(d.localPosition),
          onLongPressMoveUpdate: (d) => _dragMove(d.localPosition),
          onLongPressEnd: (_) => _dragEnd(),
          onHorizontalDragEnd: _swipe,
          child: SizedBox.expand(
            child: AnimatedBuilder(
              animation: _sway,
              builder: (context, _) => CustomPaint(
                painter: PokevillePainter(
                  c,
                  sprites,
                  _hits,
                  sway: _sway.isAnimating
                      ? (_sway.value * 2 - 1).abs() * 2 - 1
                      : 0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pokéville's front door: the Box when [folder] has a box.json, else a
/// friendly page ("Pokéville comes from the PC through Cross-Save; sync
/// first") with Look again (A) and Back (B).
class PokevilleHome extends StatefulWidget {
  const PokevilleHome(
    this.folder,
    this.cacheDir, {
    super.key,
    this.onLeave,
    this.swapAB = false,
    this.fetcher,
    this.games,
    this.guard,
  });

  final String folder;
  final String cacheDir;
  final VoidCallback? onLeave;
  final bool swapAB;
  final SpriteFetcher? fetcher;

  /// The host's Pokémon game saves (see [PokevilleScreen.games]).
  final PokeGames? games;
  final SaveGuard? guard;

  @override
  State<PokevilleHome> createState() => _PokevilleHomeState();
}

class _PokevilleHomeState extends State<PokevilleHome>
    with WidgetsBindingObserver {
  bool? _has;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _look();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _has != true) _look();
  }

  void _look() {
    final has = File(p.join(widget.folder, PokeBoxStore.index)).existsSync();
    if (has != _has) setState(() => _has = has);
  }

  void _leave() {
    if (widget.onLeave != null) {
      widget.onLeave!();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_has == true) {
      return PokevilleScreen(
        widget.folder,
        widget.cacheDir,
        onLeave: widget.onLeave,
        swapAB: widget.swapAB,
        fetcher: widget.fetcher,
        games: widget.games,
        guard: widget.guard,
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, e) {
          if (e is! KeyDownEvent) return KeyEventResult.ignored;
          var b = pokeButtonFor(e.logicalKey);
          if (widget.swapAB && e.logicalKey == LogicalKeyboardKey.gameButtonA) {
            b = PokeButton.b;
          } else if (widget.swapAB &&
              e.logicalKey == LogicalKeyboardKey.gameButtonB) {
            b = PokeButton.a;
          }
          if (b == PokeButton.b) {
            _leave();
          } else if (b == PokeButton.a) {
            _look();
          } else {
            return KeyEventResult.ignored;
          }
          return KeyEventResult.handled;
        },
        child: _NoBox(onLook: _look, onBack: _leave),
      ),
    );
  }
}

/// "Pokéville comes from the PC through Cross-Save; sync first."
class _NoBox extends StatelessWidget {
  const _NoBox({required this.onLook, required this.onBack});

  final VoidCallback onLook;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    Widget button(String key, String what, VoidCallback onTap) => Material(
      color: Look.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Look.line, width: 2.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 14, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: Look.buttons[key],
                child: Text(key, style: Pen.style(Face.title, 13, Look.white)),
              ),
              const SizedBox(width: 8),
              Text(what, style: Pen.style(Face.title, 16, Look.ink)),
            ],
          ),
        ),
      ),
    );

    return ColoredBox(
      color: Look.bg,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Look.paper,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Look.line, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: Look.line.withValues(alpha: 0.35),
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/poke-ball.png',
                        package: Look.package,
                        width: 60,
                        height: 60,
                        filterQuality: FilterQuality.none,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No Pokéville here yet',
                        textAlign: TextAlign.center,
                        style: Pen.style(Face.title, 22, Look.ink),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Pokéville comes from the PC through Cross-Save; '
                        'sync first, then come back.',
                        textAlign: TextAlign.center,
                        style: Pen.style(
                          Face.text,
                          15,
                          Look.soft,
                        ).copyWith(height: 1.4),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        alignment: WrapAlignment.center,
                        children: [
                          button('A', 'Look again', onLook),
                          button('B', 'Back', onBack),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Adds the two fonts' SIL OFL 1.1 texts to the app's licence page.
void registerPokevilleLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (font, file) in [
      ('Pixelify Sans', 'OFL-PixelifySans.txt'),
      ('DotGothic16', 'OFL-DotGothic16.txt'),
    ]) {
      final text = await rootBundle.loadString(
        'packages/pokeville/assets/fonts/$file',
      );
      yield LicenseEntryWithLineBreaks(['pokeville', font], text);
    }
  });
}
