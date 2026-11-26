/// Any console's save icon: PS2 3D models, 2D frames (PS1, Dreamcast,
/// GameCube, N64/Saturn/Neo Geo stand-ins) on a thick tile, the PS3
/// picture; all swaying gently like the PC's.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:save_kit/save_kit.dart';

import 'art_images.dart';
import 'icon_render.dart';

class SaveIcon extends StatefulWidget {
  const SaveIcon(
    this.save, {
    super.key,
    this.kind = 0,
    this.size = 96,
    this.animate = true,
    this.selected = false,
    this.dim = false,
    this.wide = false,
    this.phase,
  });

  final CardSave save;

  /// Which PS2 model: 0 list, 1 copy, 2 delete (falls back to the list one).
  final int kind;

  /// The square it's drawn in (the model fills about 90% of it).
  final double size;

  /// Off: one still pose, no ticker.
  final bool animate;

  /// The chosen one turns further and grows a little.
  final bool selected;

  /// Darkened (behind a dialog).
  final bool dim;

  /// A PS3 save's own wide picture instead of its square tile.
  final bool wide;

  /// Where in its sway it starts; default: from the save's id, so
  /// neighbours don't move in step.
  final double? phase;

  /// The 2D frames' rate (the PC steps them at 3.5 a second).
  static const framesPerSecond = 3.5;

  /// How often a moving icon is redrawn: plenty for a slow sway, and half
  /// the work of 60 for a grid of them.
  static const redrawPerSecond = 30.0;

  @override
  State<SaveIcon> createState() => _SaveIconState();
}

class _SaveIconState extends State<SaveIcon>
    with SingleTickerProviderStateMixin {
  final _clock = ValueNotifier<double>(0);
  Ticker? _ticker;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(SaveIcon old) {
    super.didUpdateWidget(old);
    if (old.animate != widget.animate) _sync();
  }

  void _sync() {
    if (widget.animate) {
      _ticker ??= createTicker((elapsed) {
        final s = elapsed.inMicroseconds / 1e6;
        final q =
            (s * SaveIcon.redrawPerSecond).floorToDouble() /
            SaveIcon.redrawPerSecond;
        if (q != _clock.value) _clock.value = q;
      });
      if (!_ticker!.isActive) _ticker!.start();
    } else {
      _ticker?.stop();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.save;
    return Semantics(
      image: true,
      label: s.cellName(),
      child: SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(
          painter: _IconPainter(
            save: s,
            kind: widget.kind,
            selected: widget.selected,
            dim: widget.dim,
            wide: widget.wide,
            phase: widget.phase ?? (Bytes.hash(s.id) % 628) / 100,
            clock: _clock,
          ),
        ),
      ),
    );
  }
}

class _IconPainter extends CustomPainter {
  _IconPainter({
    required this.save,
    required this.kind,
    required this.selected,
    required this.dim,
    required this.wide,
    required this.phase,
    required this.clock,
  }) : super(repaint: Listenable.merge([clock, ArtImages.loaded]));

  final CardSave save;
  final int kind;
  final bool selected, dim, wide;
  final double phase;
  final ValueListenable<double> clock;

  static const _dimShade = 0.42;

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value;
    final pose = IconPose.at(t, phase, selected: selected);
    final box = Offset.zero & size;
    final shade = dim ? _dimShade : 1.0;
    final k = kind.clamp(0, 2);
    final ico = save.icons[k] ?? save.icons[0];
    if (ico != null) {
      final tex = ico.texture == null ? null : ArtImages.peek(ico.texture!);
      // Wait for the texture rather than flash an untextured model.
      if (ico.texture != null && tex == null) return;
      IconRender.paintPs2(
        canvas,
        box,
        ico,
        save,
        tex,
        pose,
        t + phase * 0.3,
        shade: shade,
      );
      return;
    }
    final useWide = wide && save.wide != null;
    ui.Image? face;
    if (useWide) {
      face = ArtImages.peek(save.wide!, solid: true);
    } else if (save.frames.isNotEmpty) {
      final f =
          (t * SaveIcon.framesPerSecond + phase).floor() % save.frames.length;
      face = ArtImages.peek(save.frames[f], solid: true);
      // Keep showing the last frame while the next one is being made.
      face ??= ArtImages.peek(save.frames.first, solid: true);
    }
    IconRender.paintTile(canvas, box, face, pose, wide: useWide, shade: shade);
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.save != save ||
      old.kind != kind ||
      old.selected != selected ||
      old.dim != dim ||
      old.wide != wide ||
      old.phase != phase;
}
