import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pad_input/pad_input.dart';

import '../bindings.dart';
import '../models.dart';
import '../tv_controller.dart';
import 'skins.dart';

bool get isDesktop =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// Bar that slides over the bottom of the picture when you move the mouse
/// or tap the screen.
class ControlBar extends StatelessWidget {
  const ControlBar({
    super.key,
    required this.controller,
    required this.onGuide,
    required this.onSettings,
    required this.onThemes,
    required this.onFullscreen,
    required this.fullscreen,
    required this.onVideoOnly,
    required this.videoOnly,
  });

  final TvController controller;
  final VoidCallback? onVideoOnly;
  final bool videoOnly;
  final VoidCallback onThemes;
  final VoidCallback onGuide;
  final VoidCallback onSettings;
  final VoidCallback? onFullscreen;
  final bool fullscreen;

  @override
  Widget build(BuildContext context) {
    final tv = controller;
    final ch = tv.channel;
    final s = tv.settings;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 28, 8, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.0),
            Colors.black.withValues(alpha: 0.85),
          ],
        ),
      ),
      // A small screen (the Retroid Pocket, a phone on its side) has no
      // room for the channel name or the volume slider (the picture shows
      // both when they change), and the buttons shrink to fit.
      child: LayoutBuilder(
        builder: (context, box) {
          final narrow = box.maxWidth < 640;
          final row = Row(
            mainAxisSize: narrow ? MainAxisSize.min : MainAxisSize.max,
            children: [
              _btn(Icons.power_settings_new, 'Power (P)', tv.togglePower),
              _btn(
                Icons.keyboard_arrow_down,
                'Channel down (↓)',
                tv.channelDown,
              ),
              _btn(Icons.keyboard_arrow_up, 'Channel up (↑)', tv.channelUp),
              _btn(Icons.history, 'Last channel (L)', tv.previousChannel),
              _btn(Icons.replay, 'Start this video over (R)', tv.restartVideo),
              if (!narrow) const SizedBox(width: 8),
              if (!narrow)
                Expanded(
                  child: Text(
                    ch == null
                        ? ''
                        : '${TvController.channelText(ch.number)}  ${ch.label}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              _btn(
                s.muted ? Icons.volume_off : Icons.volume_up,
                'Mute (M)',
                tv.toggleMute,
              ),
              if (isDesktop && !narrow)
                SizedBox(
                  width: 110,
                  child: Slider(
                    value: s.muted ? 0.0 : s.volume,
                    min: 0,
                    max: 100,
                    onChanged: (v) => tv.setVolume(v),
                  ),
                ),
              _btn(Icons.info_outline, 'What\'s on (I)', tv.showInfo),
              _btn(Icons.view_list, 'Guide (G)', onGuide),
              _btn(Icons.palette_outlined, 'Themes (T)', onThemes),
              _btn(Icons.settings, 'Settings (S)', onSettings),
              if (onVideoOnly != null)
                _btn(
                  videoOnly ? Icons.tv : Icons.fit_screen,
                  videoOnly
                      ? 'Bring the TV cabinet back (Esc)'
                      : 'Video only, no cabinet (V)',
                  onVideoOnly!,
                ),
              if (onFullscreen != null)
                _btn(
                  fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  'Full screen (F)',
                  onFullscreen!,
                ),
            ],
          );
          return IconTheme(
            data: const IconThemeData(color: Colors.white),
            child: narrow ? FittedBox(fit: BoxFit.scaleDown, child: row) : row,
          );
        },
      ),
    );
  }

  Widget _btn(IconData icon, String tip, VoidCallback onPressed) =>
      IconButton(icon: Icon(icon), tooltip: tip, onPressed: onPressed);
}

/// One controller button drawn the way it looks on the controller: a
/// coloured ring for the four face buttons, a key cap for the rest.
class PadGlyph extends StatelessWidget {
  const PadGlyph({
    super.key,
    required this.button,
    required this.kind,
    this.text,
  });

  final PadButton button;
  final PadKind kind;

  /// Replaces the button's own name (used to merge "D-pad ↑" and "↓").
  final String? text;

  static const _playstation = {
    PadButton.south: Color(0xFF7CB2E8),
    PadButton.east: Color(0xFFF2685F),
    PadButton.west: Color(0xFFE59ACB),
    PadButton.north: Color(0xFF52C6A6),
  };
  static const _xbox = {
    PadButton.south: Color(0xFF6BC04B),
    PadButton.east: Color(0xFFE5483B),
    PadButton.west: Color(0xFF4A9BE8),
    PadButton.north: Color(0xFFF2C230),
  };

  @override
  Widget build(BuildContext context) {
    final label = text ?? padLabel(button, kind);
    final color = (kind == PadKind.playstation ? _playstation : _xbox)[button];
    if (color != null && text == null) {
      return Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF1B1B1E),
          border: Border.all(color: color, width: 1.6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      );
    }
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF2E2E33),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white30),
      ),
      child: Center(
        widthFactor: 1,
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// A reminder of what the controller's buttons do right now, drawn with the
/// symbols printed on the controller that's in use.
class PadHintBar extends StatelessWidget {
  const PadHintBar({super.key, required this.kind, required this.bindings});

  final PadKind kind;
  final Bindings bindings;

  @override
  Widget build(BuildContext context) {
    Widget hint(Widget glyph, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        glyph,
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );

    final hints = <Widget>[];
    final merged = <TvAction>{};
    // An untouched d-pad reads better as one hint per axis.
    void mergeAxis(
      TvAction a,
      PadButton forA,
      TvAction b,
      PadButton forB,
      String text,
      String label,
    ) {
      if (bindings.padFor(a) == forA && bindings.padFor(b) == forB) {
        hints.add(hint(PadGlyph(button: forA, kind: kind, text: text), label));
        merged
          ..add(a)
          ..add(b);
      }
    }

    mergeAxis(
      TvAction.channelUp,
      PadButton.up,
      TvAction.channelDown,
      PadButton.down,
      'D-pad ↕',
      'Channel',
    );
    mergeAxis(
      TvAction.volumeUp,
      PadButton.right,
      TvAction.volumeDown,
      PadButton.left,
      'D-pad ↔',
      'Volume',
    );
    for (final action in TvAction.values) {
      final button = bindings.padFor(action);
      if (button == null || merged.contains(action)) continue;
      hints.add(hint(PadGlyph(button: button, kind: kind), action.shortLabel));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 18,
        runSpacing: 8,
        children: hints,
      ),
    );
  }
}

/// The TV/VCR's clock, forever blinking 12:00 because nobody ever set it.
class VcrClock extends StatefulWidget {
  const VcrClock({super.key});

  @override
  State<VcrClock> createState() => _VcrClockState();
}

class _VcrClockState extends State<VcrClock> {
  late final Timer _blink;
  bool _lit = true;

  @override
  void initState() {
    super.initState();
    _blink = Timer.periodic(
      const Duration(milliseconds: 600),
      (_) => setState(() => _lit = !_lit),
    );
  }

  @override
  void dispose() {
    _blink.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const glow = Color(0xFF5CFFD0);
    return LayoutBuilder(
      builder: (context, box) => Center(
        child: Text(
          '12:00',
          maxLines: 1,
          style: TextStyle(
            color: _lit ? glow : glow.withValues(alpha: 0.1),
            fontSize: box.maxHeight * 0.62,
            fontWeight: FontWeight.w700,
            letterSpacing: box.maxHeight * 0.06,
            height: 1,
            fontFamily: 'monospace',
            fontFamilyFallback: const [
              'Consolas',
              'Courier New',
              'DejaVu Sans Mono',
              'Menlo',
            ],
            shadows: _lit
                ? [
                    Shadow(
                      color: glow.withValues(alpha: 0.8),
                      blurRadius: box.maxHeight * 0.3,
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );
  }
}

/// What the cabinet's controls show and do, kept apart from the TV itself so
/// a cabinet can be drawn on its own.
class PanelState {
  const PanelState({
    required this.skin,
    this.channelNumber = 0,
    this.volume = 50,
    this.powerOn = true,
    this.fullscreen = false,
    this.onChannelUp = _nothing,
    this.onChannelDown = _nothing,
    this.onVolumeUp = _nothing,
    this.onVolumeDown = _nothing,
    this.onRestart = _nothing,
    this.onPower = _nothing,
    this.onFullscreen = _nothing,
    this.onVideoOnly = _nothing,
  });

  factory PanelState.of(
    TvController tv, {
    VoidCallback? onFullscreen,
    VoidCallback? onVideoOnly,
    bool fullscreen = false,
  }) => PanelState(
    skin: tv.settings.skin,
    channelNumber: tv.channel?.number ?? 0,
    volume: tv.settings.muted ? 0 : tv.settings.volume,
    powerOn: tv.powerOn,
    fullscreen: fullscreen,
    onChannelUp: tv.channelUp,
    onChannelDown: tv.channelDown,
    onVolumeUp: () => tv.volumeStep(1),
    onVolumeDown: () => tv.volumeStep(-1),
    onRestart: tv.restartVideo,
    onPower: tv.togglePower,
    onFullscreen: onFullscreen ?? _nothing,
    onVideoOnly: onVideoOnly ?? _nothing,
  );

  static void _nothing() {}

  final SkinStyle skin;
  final int channelNumber;

  /// 0..100, already 0 when muted.
  final double volume;
  final bool powerOn;
  final bool fullscreen;
  final VoidCallback onChannelUp;
  final VoidCallback onChannelDown;
  final VoidCallback onVolumeUp;
  final VoidCallback onVolumeDown;
  final VoidCallback onRestart;
  final VoidCallback onPower;
  final VoidCallback onFullscreen;
  final VoidCallback onVideoOnly;
}

/// The controls in the cabinet's right-hand pillar: dials or push buttons,
/// whichever the cabinet has.
class SidePanel extends StatelessWidget {
  const SidePanel({super.key, required this.state, required this.width});

  final PanelState state;
  final double width;

  @override
  Widget build(BuildContext context) {
    final skin = state.skin;
    final screenIcon = state.fullscreen
        ? Icons.fullscreen_exit
        : Icons.fullscreen;
    final look = ButtonLook.of(skin);
    if (look != null) {
      return _ButtonPanel(
        state: state,
        width: width,
        look: look,
        screenIcon: screenIcon,
      );
    }

    final colors = SkinColors.of(skin);
    final big = min(width * 0.62, 140.0);
    final small = big * 0.55;
    final labelStyle = TextStyle(
      color: colors.text.withValues(alpha: 0.8),
      fontSize: max(9.0, big * 0.11),
      letterSpacing: 2,
      fontWeight: FontWeight.w600,
    );
    final dial = DialLook.of(skin);
    Widget button(IconData icon, VoidCallback onPressed) => _PanelButton(
      icon: icon,
      onPressed: onPressed,
      size: small * 0.6,
      look: dial,
    );
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('CHANNEL', style: labelStyle),
        SizedBox(height: big * 0.08),
        _Knob(
          size: big,
          angle: (state.channelNumber % 12) / 12 * pi * 2,
          style: skin,
          onUp: state.onChannelUp,
          onDown: state.onChannelDown,
          tooltip: 'Click the top half for up, bottom half for down',
        ),
        SizedBox(height: big * 0.3),
        Text('VOLUME', style: labelStyle),
        SizedBox(height: big * 0.08),
        _Knob(
          size: small,
          angle: state.volume / 100 * pi * 1.5 - pi * 0.75,
          style: skin,
          onUp: state.onVolumeUp,
          onDown: state.onVolumeDown,
          tooltip: 'Click the top half for louder, bottom half for quieter',
        ),
        SizedBox(height: big * 0.3),
        Text('RESTART', style: labelStyle),
        SizedBox(height: big * 0.08),
        Tooltip(
          message: 'Start this video over (R)',
          waitDuration: const Duration(seconds: 1),
          child: button(Icons.replay, state.onRestart),
        ),
        SizedBox(height: big * 0.22),
        Text('FULL SCREEN', style: labelStyle),
        SizedBox(height: big * 0.08),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: 'Full screen (F)',
              waitDuration: const Duration(seconds: 1),
              child: button(screenIcon, state.onFullscreen),
            ),
            SizedBox(width: small * 0.12),
            Tooltip(
              message: 'Video only, no cabinet (V)',
              waitDuration: const Duration(seconds: 1),
              child: button(Icons.fit_screen, state.onVideoOnly),
            ),
          ],
        ),
        SizedBox(height: big * 0.3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Led(
              on: state.powerOn,
              size: small * 0.17,
              color: const Color(0xFFFF3B30),
            ),
            SizedBox(width: small * 0.18),
            button(Icons.power_settings_new, state.onPower),
          ],
        ),
      ],
    );
  }
}

class _Led extends StatelessWidget {
  const _Led({required this.on, required this.size, required this.color});

  final bool on;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? color : Color.lerp(color, Colors.black, 0.75),
        boxShadow: on
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.8),
                  blurRadius: size * 1.1,
                ),
              ]
            : null,
      ),
    );
  }
}

/// Push buttons under the right speaker, styled by the cabinet.
class _ButtonPanel extends StatelessWidget {
  const _ButtonPanel({
    required this.state,
    required this.width,
    required this.look,
    required this.screenIcon,
  });

  final PanelState state;
  final double width;
  final ButtonLook look;
  final IconData screenIcon;

  @override
  Widget build(BuildContext context) {
    final u = min(width * 0.26, 54.0);
    final label = TextStyle(
      color: look.text.withValues(alpha: 0.85),
      fontSize: max(8.0, u * 0.22),
      letterSpacing: u * 0.05,
      fontWeight: FontWeight.w700,
      fontFamily: look.mono ? 'monospace' : null,
      fontFamilyFallback: look.mono
          ? const ['Consolas', 'Courier New', 'DejaVu Sans Mono', 'Menlo']
          : null,
    );
    var made = 0;
    Widget button(
      IconData icon,
      VoidCallback onPressed, {
      double wide = 1,
      double scale = 0.5,
    }) {
      final colour = look.rainbow == null
          ? null
          : look.rainbow![made % look.rainbow!.length];
      made++;
      return _PushButton(
        width: u * wide,
        height: u * 0.62,
        look: look,
        colour: colour,
        onPressed: onPressed,
        child: Icon(icon, size: u * scale, color: look.icon),
      );
    }

    Widget pair(
      String text,
      IconData down,
      VoidCallback onDown,
      IconData up,
      VoidCallback onUp,
    ) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, style: label),
        SizedBox(height: u * 0.14),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            button(down, onDown),
            SizedBox(width: u * 0.2),
            button(up, onUp),
          ],
        ),
      ],
    );

    Widget jack(Color color) => Container(
      width: u * 0.36,
      height: u * 0.36,
      margin: EdgeInsets.symmetric(horizontal: u * 0.09),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.black54, width: 1),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 2, offset: Offset(0, 1)),
        ],
      ),
      alignment: Alignment.center,
      child: Container(
        width: u * 0.14,
        height: u * 0.14,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF0A0A0A),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, box) {
        final h = box.maxHeight;
        return Padding(
          // The top of this pillar is the speaker or decoration the skin paints.
          padding: EdgeInsets.only(top: h * 0.43, bottom: h * 0.06),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  pair(
                    'CHANNEL',
                    Icons.keyboard_arrow_down,
                    state.onChannelDown,
                    Icons.keyboard_arrow_up,
                    state.onChannelUp,
                  ),
                  SizedBox(height: u * 0.42),
                  pair(
                    'VOLUME',
                    Icons.remove,
                    state.onVolumeDown,
                    Icons.add,
                    state.onVolumeUp,
                  ),
                  SizedBox(height: u * 0.42),
                  Text('RESTART', style: label),
                  SizedBox(height: u * 0.14),
                  button(Icons.replay, state.onRestart, wide: 2.2, scale: 0.42),
                  SizedBox(height: u * 0.42),
                  pair(
                    'FULL SCREEN',
                    screenIcon,
                    state.onFullscreen,
                    Icons.fit_screen,
                    state.onVideoOnly,
                  ),
                  SizedBox(height: u * 0.42),
                  Text('POWER', style: label),
                  SizedBox(height: u * 0.14),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Led(on: state.powerOn, size: u * 0.2, color: look.led),
                      SizedBox(width: u * 0.25),
                      button(
                        Icons.power_settings_new,
                        state.onPower,
                        wide: 1.75,
                        scale: 0.42,
                      ),
                    ],
                  ),
                  if (look.jacks) ...[
                    SizedBox(height: u * 0.6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        jack(const Color(0xFFE2B93B)),
                        jack(const Color(0xFFE9E9E4)),
                        jack(const Color(0xFFC0392B)),
                      ],
                    ),
                    SizedBox(height: u * 0.12),
                    Text(
                      'VIDEO  L-AUDIO-R',
                      style: label.copyWith(fontSize: max(7.0, u * 0.17)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A push button that sinks when pressed.
class _PushButton extends StatefulWidget {
  const _PushButton({
    required this.width,
    required this.height,
    required this.look,
    required this.onPressed,
    required this.child,
    this.colour,
  });

  final double width;
  final double height;
  final ButtonLook look;
  final Color? colour;
  final VoidCallback onPressed;
  final Widget child;

  @override
  State<_PushButton> createState() => _PushButtonState();
}

class _PushButtonState extends State<_PushButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    final flat = widget.colour;
    final travel = look.hardShadow ? 2.5 : 1.5;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onPressed();
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: widget.width,
          height: widget.height,
          transform: Matrix4.translationValues(
            _down && look.hardShadow ? travel : 0,
            _down ? travel : 0,
            0,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.height * 0.16),
            color: flat == null
                ? null
                : (_down ? Color.lerp(flat, Colors.black, 0.2) : flat),
            gradient: flat != null
                ? null
                : LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: _down ? look.down : look.up,
                  ),
            border: Border.all(color: look.border, width: look.borderWidth),
            boxShadow: [
              if (!_down)
                look.hardShadow
                    ? const BoxShadow(
                        color: Color(0xFF111111),
                        offset: Offset(2.5, 2.5),
                      )
                    : const BoxShadow(
                        color: Colors.black54,
                        blurRadius: 3,
                        offset: Offset(0, 2),
                      ),
              if (look.glow != null)
                BoxShadow(
                  color: look.glow!.withValues(alpha: _down ? 0.9 : 0.45),
                  blurRadius: _down ? 9 : 6,
                ),
            ],
          ),
          alignment: Alignment.center,
          child: widget.child,
        ),
      ),
    );
  }
}

class _Knob extends StatelessWidget {
  const _Knob({
    required this.size,
    required this.angle,
    required this.style,
    required this.onUp,
    required this.onDown,
    required this.tooltip,
  });

  final double size;
  final double angle;
  final SkinStyle style;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(seconds: 1),
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            if (event.scrollDelta.dy < 0) {
              onUp();
            } else if (event.scrollDelta.dy > 0) {
              onDown();
            }
          }
        },
        child: GestureDetector(
          onTapUp: (d) {
            if (d.localPosition.dy < size / 2) {
              onUp();
            } else {
              onDown();
            }
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: angle),
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutBack,
              builder: (context, a, _) => CustomPaint(
                size: Size.square(size),
                painter: KnobPainter(angle: a, style: style),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelButton extends StatelessWidget {
  const _PanelButton({
    required this.icon,
    required this.onPressed,
    required this.size,
    required this.look,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final double size;
  final DialLook look;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: size * 1.4,
          height: size * 0.8,
          decoration: BoxDecoration(
            color: look.button,
            borderRadius: BorderRadius.circular(size * 0.12),
            border: Border.all(color: look.buttonBorder),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: look.buttonIcon, size: size * 0.5),
        ),
      ),
    );
  }
}

/// A TV remote, shown under the picture when a phone is held upright.
class RemotePanel extends StatelessWidget {
  const RemotePanel({
    super.key,
    required this.controller,
    required this.onGuide,
    required this.onSettings,
  });

  final TvController controller;
  final VoidCallback onGuide;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final tv = controller;
    final skin = tv.settings.skin;
    final colors = SkinColors.of(skin);
    final ch = tv.channel;
    return CustomPaint(
      painter: SkinPainter(
        style: skin == SkinStyle.none ? SkinStyle.black : skin,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            children: [
              Text(
                ch == null
                    ? 'NO CHANNEL'
                    : '${TvController.channelText(ch.number)}  ·  ${ch.label}'
                          .toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.text,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _RoundButton(
                    icon: Icons.power_settings_new,
                    label: 'POWER',
                    color: const Color(0xFFB3261E),
                    onPressed: tv.togglePower,
                  ),
                  _RoundButton(
                    icon: tv.settings.muted
                        ? Icons.volume_off
                        : Icons.volume_mute,
                    label: 'MUTE',
                    onPressed: tv.toggleMute,
                  ),
                  _RoundButton(
                    icon: Icons.history,
                    label: 'LAST',
                    onPressed: tv.previousChannel,
                  ),
                  _RoundButton(
                    icon: Icons.replay,
                    label: 'RESTART',
                    onPressed: tv.restartVideo,
                  ),
                  _RoundButton(
                    icon: Icons.info_outline,
                    label: 'INFO',
                    onPressed: tv.showInfo,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _Rocker(
                    label: 'VOL',
                    upIcon: Icons.add,
                    downIcon: Icons.remove,
                    onUp: () => tv.volumeStep(1),
                    onDown: () => tv.volumeStep(-1),
                  ),
                  _NumberPad(controller: tv),
                  _Rocker(
                    label: 'CH',
                    upIcon: Icons.keyboard_arrow_up,
                    downIcon: Icons.keyboard_arrow_down,
                    onUp: tv.channelUp,
                    onDown: tv.channelDown,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: onGuide,
                      icon: const Icon(Icons.view_list),
                      label: const Text('Guide'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: onSettings,
                      icon: const Icon(Icons.settings),
                      label: const Text('Settings'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color ?? const Color(0xFF2A2A2A),
          shape: const CircleBorder(),
          elevation: 3,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 10,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}

class _Rocker extends StatelessWidget {
  const _Rocker({
    required this.label,
    required this.upIcon,
    required this.downIcon,
    required this.onUp,
    required this.onDown,
  });

  final String label;
  final IconData upIcon;
  final IconData downIcon;
  final VoidCallback onUp;
  final VoidCallback onDown;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF2A2A2A),
      borderRadius: BorderRadius.circular(30),
      elevation: 3,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 60,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: onUp,
              child: SizedBox(
                height: 64,
                child: Center(
                  child: Icon(upIcon, color: Colors.white, size: 30),
                ),
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                letterSpacing: 1.5,
              ),
            ),
            InkWell(
              onTap: onDown,
              child: SizedBox(
                height: 64,
                child: Center(
                  child: Icon(downIcon, color: Colors.white, size: 30),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NumberPad extends StatelessWidget {
  const _NumberPad({required this.controller});

  final TvController controller;

  @override
  Widget build(BuildContext context) {
    Widget key(String text, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: const Color(0xFF3A3A3A),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 36,
            child: Center(
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Widget digit(int d) => key('$d', () => controller.enterDigit(d));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [digit(1), digit(2), digit(3)],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [digit(4), digit(5), digit(6)],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [digit(7), digit(8), digit(9)],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            key('—', controller.previousChannel),
            digit(0),
            key('OK', controller.commitDigits),
          ],
        ),
      ],
    );
  }
}
