import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show AppExitResponse;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../bindings.dart';
import '../diag.dart';
import '../gamepad.dart';
import '../tv_controller.dart';
import 'controls.dart';
import 'osd_menu.dart';
import 'skins.dart';
import 'tv_screen.dart';

/// The main screen: the 4:3 picture, the cabinet around it, and the remote.
class TvPage extends StatefulWidget {
  const TvPage({
    super.key,
    required this.controller,
    this.startFullscreen = false,
  });

  final TvController controller;

  /// Go straight to full screen once the window is up.
  final bool startFullscreen;

  @override
  State<TvPage> createState() => _TvPageState();
}

class _TvPageState extends State<TvPage> {
  TvController get tv => widget.controller;

  late final AppLifecycleListener _lifecycle;
  final FocusNode _focus = FocusNode(debugLabel: 'tv');
  late final GamepadInput _gamepad;
  bool _controlsVisible = false;
  Timer? _hideTimer;
  bool _fullscreen = false;
  bool _videoOnly = false;

  /// True while a system window (folder picker, path box) is in front.
  bool _inMenu = false;
  late final OsdMenu _menu;

  static const _padHintTime = Duration(seconds: 6);
  static const _padIdle = Duration(seconds: 30);
  DateTime? _lastPadInput;
  Timer? _padHintTimer;

  /// The controller whose button hints are on screen, or null for none.
  PadKind? _padHints;
  PadKind _padHintsShown = PadKind.xbox;
  bool _fullscreenBeforeVideoOnly = false;

  static const List<LogicalKeyboardKey> _digitKeys = [
    LogicalKeyboardKey.digit0,
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];

  /// Controller buttons that arrive as keys (all of them on Android).
  late final PadKeys _padKeys = PadKeys(android: tv.android);
  static const List<LogicalKeyboardKey> _numpadKeys = [
    LogicalKeyboardKey.numpad0,
    LogicalKeyboardKey.numpad1,
    LogicalKeyboardKey.numpad2,
    LogicalKeyboardKey.numpad3,
    LogicalKeyboardKey.numpad4,
    LogicalKeyboardKey.numpad5,
    LogicalKeyboardKey.numpad6,
    LogicalKeyboardKey.numpad7,
    LogicalKeyboardKey.numpad8,
    LogicalKeyboardKey.numpad9,
  ];

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) => diag('window state: ${state.name}'),
      onHide: () => unawaited(tv.saveForExit()),
      onPause: () => unawaited(tv.saveForExit()),
      // Android: "All files" access may have just been given in Settings.
      onResume: () => unawaited(tv.onResumed()),
      onExitRequested: () async {
        await tv.saveForExit();
        return AppExitResponse.exit;
      },
    );
    _menu = OsdMenu(tv, runDialog: _runDialog, onQuit: isDesktop ? _quit : null)
      ..addListener(_onMenuChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.startFullscreen) {
        // On Linux the window is created full screen (see the runner);
        // asking again here would resize it after it's already up.
        if (Platform.isLinux) {
          setState(() => _fullscreen = true);
        } else {
          unawaited(_toggleFullscreen());
        }
      }
      // First run: nothing to watch yet, so open the menu where the TV
      // folder is chosen.
      if (!tv.hasLibrary) _menu.open(_menu.folderPage());
    });
    _gamepad = GamepadInput(
      onButton: _onPad,
      onQuitHold: isDesktop ? () => unawaited(_quit()) : null,
      onChanged: () {
        tv.setControllers(_gamepad.kind, _gamepad.connected);
        // Hints already on screen switch to the new controller's symbols.
        if (mounted && _padHints != null) {
          setState(() => _padHints = _gamepad.kind);
        }
      },
      isActive: () {
        if (!mounted) return false;
        if (Platform.isWindows) return GamepadInput.appInFront();
        // On a console (started full screen on Linux) this is the only
        // thing on screen, and the window manager there doesn't always say
        // the window has focus. Waiting to be told left the controller dead.
        if (Platform.isLinux && widget.startFullscreen) return true;
        return WidgetsBinding.instance.lifecycleState ==
            AppLifecycleState.resumed;
      },
    )..start();
    diag(
      'window state at start: ${WidgetsBinding.instance.lifecycleState?.name ?? 'not reported'}',
    );
  }

  void _onPad(PadButton button) {
    tv.setControllers(_gamepad.kind, _gamepad.connected);
    // The menu's hint line names controller buttons from now on.
    _menu.usingPad = true;
    if (_menu.isOpen && !_inMenu) {
      _onPadInOsd(button);
      return;
    }
    final now = DateTime.now();
    final last = _lastPadInput;
    _lastPadInput = now;
    if (_inMenu) {
      _onPadInMenu(button);
      return;
    }
    // The hints come up when the pad is picked up, stay for a few seconds
    // however much it's used, and wait for it to be put down before
    // showing again.
    if (last == null || now.difference(last) > _padIdle) _showPadHints();
    final action = tv.bindings.actionForPad(button);
    if (action != null) _perform(action);
  }

  void _perform(TvAction action) {
    switch (action) {
      case TvAction.channelUp:
        tv.channelUp();
      case TvAction.channelDown:
        tv.channelDown();
      case TvAction.volumeUp:
        tv.volumeStep(1);
      case TvAction.volumeDown:
        tv.volumeStep(-1);
      case TvAction.pause:
        unawaited(tv.togglePause());
      case TvAction.lastChannel:
        tv.previousChannel();
      case TvAction.mute:
        unawaited(tv.toggleMute());
      case TvAction.restart:
        unawaited(tv.restartVideo());
      case TvAction.subtitles:
        tv.stepSubtitleTrack(1);
      case TvAction.audioTrack:
        tv.stepAudioTrack(1);
      case TvAction.info:
        tv.showInfo();
      case TvAction.guide:
        _openGuide();
      case TvAction.videoOnly:
        unawaited(_toggleVideoOnly());
      case TvAction.fullscreen:
        unawaited(_toggleFullscreen());
      case TvAction.settings:
        _openSettings();
      case TvAction.themes:
        _openThemes();
      case TvAction.power:
        unawaited(tv.togglePower());
    }
  }

  void _showPadHints() {
    setState(() => _padHints = _gamepad.kind);
    _padHintTimer?.cancel();
    _padHintTimer = Timer(_padHintTime, () {
      if (mounted) setState(() => _padHints = null);
    });
  }

  /// Guide, Settings, Themes and the welcome screen: the pad moves the
  /// highlight, ✕/A presses what's highlighted and ○/B goes back.
  void _onPadInMenu(PadButton button) {
    // Makes the highlight visible even though no keyboard is in use.
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    final focused = FocusManager.instance.primaryFocus;
    void move(TraversalDirection direction) {
      if (focused == null) return;
      if (focused is FocusScopeNode || focused.context == null) {
        focused.nextFocus();
      } else {
        focused.focusInDirection(direction);
      }
    }

    switch (button) {
      case PadButton.up:
        move(TraversalDirection.up);
      case PadButton.down:
        move(TraversalDirection.down);
      case PadButton.left:
        move(TraversalDirection.left);
      case PadButton.right:
        move(TraversalDirection.right);
      case PadButton.south:
        final target = focused?.context;
        if (target != null) Actions.maybeInvoke(target, const ActivateIntent());
      case PadButton.east || PadButton.start:
        if (_inMenu) unawaited(Navigator.of(context).maybePop());
      default:
        break;
    }
  }

  Future<void> _quit() async {
    await tv.saveForExit();
    exit(0);
  }

  void _onMenuChanged() {
    if (mounted) setState(() {});
  }

  void _onPadInOsd(PadButton button) {
    _menu.usingPad = true;
    if (_menu.capturing) {
      if (_menu.capturePad) {
        _menu.capturePadButton(button);
      } else if (button == PadButton.east) {
        _menu.cancelCapture();
      }
      return;
    }
    switch (button) {
      case PadButton.up:
        _menu.move(-1);
      case PadButton.down:
        _menu.move(1);
      case PadButton.left:
        _menu.change(-1);
      case PadButton.right:
        _menu.change(1);
      case PadButton.south:
        _menu.select();
      case PadButton.east || PadButton.start:
        _menu.back();
      default:
        break;
    }
  }

  KeyEventResult _onKeyInOsd(LogicalKeyboardKey key, bool repeat) {
    _menu.usingPad = false;
    if (_menu.capturing) {
      if (!repeat) _menu.captureKey(key);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _menu.move(-1);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _menu.move(1);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _menu.change(-1);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _menu.change(1);
    } else if (repeat) {
      // Only moving and changing repeat.
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.space) {
      _menu.select();
    } else if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.backspace) {
      _menu.back();
    }
    return KeyEventResult.handled;
  }

  /// For the few things that still need a system window.
  Future<void> _runDialog(
    Future<void> Function(BuildContext context) body,
  ) async {
    if (_inMenu) return;
    _inMenu = true;
    try {
      await body(context);
    } finally {
      _inMenu = false;
    }
    if (mounted) _focus.requestFocus();
  }

  @override
  void dispose() {
    _gamepad.stop();
    _menu.dispose();
    _padHintTimer?.cancel();
    _lifecycle.dispose();
    _hideTimer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _pokeControls() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  Future<void> _toggleFullscreen() async {
    if (!isDesktop) return;
    final goFull = !_fullscreen;
    if (goFull) {
      await defaultEnterNativeFullscreen();
    } else {
      await defaultExitNativeFullscreen();
    }
    if (mounted) setState(() => _fullscreen = goFull);
  }

  /// Video only: no cabinet, the picture takes the whole screen.
  Future<void> _toggleVideoOnly() async {
    if (!_videoOnly) {
      _fullscreenBeforeVideoOnly = _fullscreen;
      if (!_fullscreen) await _toggleFullscreen();
      if (!mounted) return;
      setState(() => _videoOnly = true);
      tv.showMessage('VIDEO ONLY', 'Esc or L2 brings the TV back');
    } else {
      if (_fullscreen && !_fullscreenBeforeVideoOnly) await _toggleFullscreen();
      if (mounted) setState(() => _videoOnly = false);
    }
  }

  void _openGuide() => _menu.open(_menu.guidePage());

  void _openThemes() => _menu.open(_menu.themePage());

  void _openSettings() => _menu.open(_menu.mainPage());

  int? _digitFor(LogicalKeyboardKey key) {
    final d = _digitKeys.indexOf(key);
    if (d >= 0) return d;
    final n = _numpadKeys.indexOf(key);
    return n >= 0 ? n : null;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // Android hands a controller's buttons over as keys (releases too, so
    // a held d-pad stops repeating).
    final pad = _padKeys.read(event);
    if (pad != null) {
      if (tv.android) {
        // No other way to see it's there: a pad key means a controller.
        _gamepad
          ..kind = PadKind.xbox
          ..connected = max(1, _gamepad.connected);
      }
      if (pad.fire) _onPad(pad.button);
      return KeyEventResult.handled;
    }
    final down = event is KeyDownEvent;
    final repeat = event is KeyRepeatEvent;
    if (!down && !repeat) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (_menu.isOpen) return _onKeyInOsd(key, repeat);

    // Keys the TV keeps for itself (see Bindings.isReserved).
    if (!repeat) {
      final digit = _digitFor(key);
      if (digit != null) {
        tv.enterDigit(digit);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter) {
        tv.commitDigits();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        if (_videoOnly) {
          unawaited(_toggleVideoOnly());
        } else if (_fullscreen) {
          unawaited(_toggleFullscreen());
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.f1) {
        _showPadHints();
        return KeyEventResult.handled;
      }
    }

    final action = tv.bindings.actionForKey(key);
    if (action == null || (repeat && !action.repeats)) {
      return KeyEventResult.ignored;
    }
    _perform(action);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tv,
      builder: (context, _) {
        return Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          // A phone's back button closes the menu (or video only) before
          // it leaves the app.
          child: PopScope(
            canPop: !_menu.isOpen && !_videoOnly,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              if (_menu.isOpen) {
                _menu.back();
              } else if (_videoOnly) {
                unawaited(_toggleVideoOnly());
              }
            },
            child: Scaffold(
              backgroundColor: Colors.black,
              body: LayoutBuilder(
                builder: (context, constraints) {
                  final size = constraints.biggest;
                  return size.height > size.width
                      ? _portrait()
                      : _landscape(size);
                },
              ),
            ),
          ),
        );
      },
    );
  }

  /// Wide window or phone on its side: the screen fills the height, the
  /// cabinet skin fills whatever is left at the sides.
  Widget _landscape(Size size) {
    final skin = tv.settings.skin;
    final layout = CabinetLayout.of(size, skin);
    final screenRect = layout.screenRect;
    final bezel = layout.bezel;
    final pillar = layout.pillar;
    final decorate = layout.decorate && !_videoOnly;

    return MouseRegion(
      cursor: _controlsVisible || !_fullscreen
          ? SystemMouseCursors.basic
          : SystemMouseCursors.none,
      onHover: (_) => _pokeControls(),
      child: Stack(
        children: [
          if (!_videoOnly)
            Positioned.fill(
              child: CustomPaint(
                painter: SkinPainter(
                  style: skin,
                  screenRect: screenRect,
                  bezel: bezel,
                  speaker: decorate,
                  chin: layout.chin,
                ),
              ),
            ),
          if (!_videoOnly && layout.clock != null)
            Positioned.fromRect(
              rect: layout.clock!,
              child: const IgnorePointer(child: VcrClock()),
            ),
          if (decorate)
            Positioned(
              left: screenRect.right + bezel,
              top: 0,
              bottom: 0,
              width: pillar,
              child: SidePanel(
                width: pillar,
                state: PanelState.of(
                  tv,
                  onFullscreen: isDesktop ? _toggleFullscreen : null,
                  onVideoOnly: isDesktop ? _toggleVideoOnly : null,
                  fullscreen: _fullscreen,
                ),
              ),
            ),
          // Keyed so the player keeps its place when the cabinet comes and goes.
          Positioned.fromRect(
            key: const ValueKey('screen'),
            rect: _videoOnly ? Offset.zero & size : screenRect,
            child: _screen(showBar: true),
          ),
          Positioned.fromRect(
            rect: _videoOnly ? Offset.zero & size : screenRect,
            child: IgnorePointer(
              child: Align(
                alignment: const Alignment(0, 0.9),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: AnimatedOpacity(
                    opacity: _padHints == null || _menu.isOpen ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 350),
                    // Keeps the last symbols on screen while it fades out.
                    child: PadHintBar(
                      kind: _padHintsShown = _padHints ?? _padHintsShown,
                      bindings: tv.bindings,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Phone held upright: the screen across the top, a remote underneath.
  Widget _portrait() {
    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, box) {
          final width = box.maxWidth;
          return Column(
            children: [
              SizedBox(
                width: width,
                height: width * 3 / 4,
                child: _screen(showBar: false),
              ),
              Expanded(
                child: RemotePanel(
                  controller: tv,
                  onGuide: _openGuide,
                  onSettings: _openSettings,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _screen({required bool showBar}) {
    // While the menu is up it owns the picture: a double-click or swipe
    // here would otherwise swallow or delay clicks on its lines.
    final menuOpen = _menu.isOpen;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: menuOpen ? null : _pokeControls,
      onDoubleTap: isDesktop && !menuOpen ? _toggleFullscreen : null,
      onVerticalDragEnd: menuOpen
          ? null
          : (details) {
              final v = details.primaryVelocity ?? 0;
              if (v < -250) {
                tv.channelUp();
              } else if (v > 250) {
                tv.channelDown();
              }
            },
      child: Stack(
        fit: StackFit.expand,
        children: [
          TvScreen(
            controller: tv,
            menu: _menu,
            controlsShown: _controlsVisible,
          ),
          if (showBar)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                // Hidden under the menu, whose last line it would cover.
                ignoring: !_controlsVisible || menuOpen,
                child: AnimatedOpacity(
                  opacity: _controlsVisible && !menuOpen ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: ControlBar(
                    controller: tv,
                    onGuide: _openGuide,
                    onSettings: _openSettings,
                    onThemes: _openThemes,
                    onVideoOnly: isDesktop ? _toggleVideoOnly : null,
                    videoOnly: _videoOnly,
                    onFullscreen: isDesktop ? _toggleFullscreen : null,
                    fullscreen: _fullscreen,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
