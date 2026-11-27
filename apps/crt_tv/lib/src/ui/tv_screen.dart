import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models.dart';
import '../tv_controller.dart';
import 'crt_overlay.dart';
import 'osd.dart';
import 'osd_menu.dart';
import 'static_noise.dart';

/// The picture tube: video, snow, on-screen display and the CRT look,
/// always shown at 4:3.
class TvScreen extends StatelessWidget {
  const TvScreen({
    super.key,
    required this.controller,
    this.menu,
    this.controlsShown = false,
  });

  final TvController controller;

  /// The control bar is up: the title at the bottom makes way for it.
  final bool controlsShown;

  /// The on-screen menu, drawn under the tube effect like the rest of the picture.
  final OsdMenu? menu;

  BoxFit get _fit => switch (controller.settings.videoFit) {
    VideoFit.fit => BoxFit.contain,
    VideoFit.stretch => BoxFit.fill,
    VideoFit.zoom => BoxFit.cover,
  };

  @override
  Widget build(BuildContext context) {
    final tv = controller;
    final settings = tv.settings;
    final menuOpen = menu?.isOpen ?? false;
    return LayoutBuilder(
      builder: (context, box) {
        final radius = screenCornerRadius(settings.crtEffect, box.maxHeight);
        return ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: ColoredBox(
            color: Colors.black,
            child: PowerTransition(
              on: tv.powerOn,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (tv.video case final video?)
                    Video(
                      controller: video,
                      controls: NoVideoControls,
                      fit: _fit,
                      fill: Colors.black,
                      subtitleViewConfiguration: SubtitleViewConfiguration(
                        visible: !TvController.drawsOwnSubtitles,
                      ),
                    )
                  else if (tv.pictureStandIn case final standIn?)
                    Builder(builder: standIn),
                  if (tv.switching && !tv.staticVisible)
                    const ColoredBox(color: Colors.black),
                  if (tv.staticVisible) StaticNoise(label: _noiseLabel(tv)),
                  if (tv.scanning && tv.channel == null)
                    const Center(child: CircularProgressIndicator()),
                  if (!tv.scanning && tv.library != null && tv.channels.isEmpty)
                    const _ScreenMessage(
                      'NO CHANNELS FOUND\n\nMake folders named "Channel 3", "Channel Cartoons" and so on '
                      'inside your TV folder, put videos in them, then choose RESCAN under TV FOLDER in the menu.',
                    ),
                  if (!tv.scanning && !tv.hasLibrary && !menuOpen)
                    _ScreenMessage(
                      tv.android
                          ? 'WELCOME TO CRT TV\n\nOpen the menu to choose your TV folder: '
                                'press START on the controller, or tap the picture and then the gear.'
                          : 'WELCOME TO CRT TV\n\nOpen the menu to choose your TV folder: '
                                'press S on a keyboard or START on a controller.',
                    ),
                  if (tv.troubleVisible && !tv.staticVisible)
                    const TroubleCard(),
                  if (menu != null) OsdMenuView(menu: menu!),
                  CrtOverlay(effect: settings.crtEffect),
                  if (!menuOpen)
                    ChannelOsd(
                      channel: tv.osdChannel,
                      name: tv.osdName,
                      title: controlsShown ? null : tv.osdTitle,
                    ),
                  if (!menuOpen && tv.volumeOsdVisible)
                    VolumeOsd(volume: settings.volume, muted: settings.muted),
                  if (!menuOpen && tv.paused) const _PausedBadge(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String? _noiseLabel(TvController tv) {
    if (tv.switching) return null;
    final ch = tv.channel;
    if (ch == null) return null;
    if (ch.programs.isEmpty && tv.commercialsFor(ch).isEmpty) {
      return 'NO SIGNAL';
    }
    return null;
  }
}

/// "Technical difficulties, please stand by" over colour bars: what's shown
/// while a video that won't play is skipped.
class TroubleCard extends StatelessWidget {
  const TroubleCard({super.key});

  static const _bars = [
    Color(0xFFC0C0C0),
    Color(0xFFC0C000),
    Color(0xFF00C0C0),
    Color(0xFF00C000),
    Color(0xFFC000C0),
    Color(0xFFC00000),
    Color(0xFF0000C0),
  ];

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, box) {
          final size = max(11.0, box.maxHeight * 0.05);
          TextStyle style(double scale) => TextStyle(
            color: Colors.white,
            fontSize: size * scale,
            fontWeight: FontWeight.w700,
            letterSpacing: size * 0.08,
            height: 1.2,
            fontFamily: 'monospace',
            fontFamilyFallback: const [
              'Consolas',
              'Courier New',
              'DejaVu Sans Mono',
              'Menlo',
            ],
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final color in _bars)
                    Expanded(child: ColoredBox(color: color)),
                ],
              ),
              Center(
                child: Container(
                  color: Colors.black,
                  padding: EdgeInsets.symmetric(
                    horizontal: size * 1.2,
                    vertical: size * 0.8,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'TECHNICAL DIFFICULTIES',
                        textAlign: TextAlign.center,
                        style: style(1),
                      ),
                      SizedBox(height: size * 0.4),
                      Text(
                        'PLEASE STAND BY',
                        textAlign: TextAlign.center,
                        style: style(0.8),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PausedBadge extends StatelessWidget {
  const _PausedBadge();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, box) => Align(
          alignment: const Alignment(-0.88, -0.86),
          child: Text(
            'II PAUSE',
            style: osdStyle(max(14.0, box.maxHeight * 0.06)),
          ),
        ),
      ),
    );
  }
}

/// A few lines of green text in the middle of an otherwise empty screen.
class _ScreenMessage extends StatelessWidget {
  const _ScreenMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = max(12.0, box.maxHeight * 0.045);
        return Center(
          child: Padding(
            padding: EdgeInsets.all(box.maxHeight * 0.08),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: osdStyle(size),
            ),
          ),
        );
      },
    );
  }
}

/// The classic tube power-off: the picture squashes into a bright line,
/// then a dot, then fades. Power-on plays it in reverse, faster.
class PowerTransition extends StatefulWidget {
  const PowerTransition({super.key, required this.on, required this.child});

  final bool on;
  final Widget child;

  @override
  State<PowerTransition> createState() => _PowerTransitionState();
}

class _PowerTransitionState extends State<PowerTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    value: widget.on ? 1.0 : 0.0,
    duration: const Duration(milliseconds: 420),
    reverseDuration: const Duration(milliseconds: 620),
  );

  @override
  void didUpdateWidget(PowerTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.on != oldWidget.on) {
      if (widget.on) {
        _anim.forward();
      } else {
        _anim.reverse();
      }
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      child: widget.child,
      builder: (context, child) {
        // The tree below stays the same shape at every step, so the video
        // underneath is never rebuilt from scratch.
        final t = _anim.value;
        final full = t >= 1.0;
        // 0.35..1: squash vertically. 0..0.35: shrink sideways to a dot.
        final scaleY = full
            ? 1.0
            : (t > 0.35
                  ? 0.004 + 0.996 * Curves.easeIn.transform((t - 0.35) / 0.65)
                  : 0.004);
        final scaleX = full ? 1.0 : (t > 0.35 ? 1.0 : max(0.002, t / 0.35));
        final glow = full ? 0.0 : (t > 0.35 ? (1 - (t - 0.35) / 0.65) : 1.0);
        final fade = t <= 0.0 ? 0.0 : 1.0;
        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black),
            Opacity(
              opacity: fade,
              child: Transform.scale(
                scaleX: scaleX,
                scaleY: scaleY,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    child!,
                    ColoredBox(
                      color: Colors.white.withValues(
                        alpha: min(1.0, glow * 0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
