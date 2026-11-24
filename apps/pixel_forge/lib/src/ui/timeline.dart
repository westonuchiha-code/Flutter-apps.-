import 'dart:async';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../editor.dart';

/// Frame strip: pick a frame, add/copy/delete, timing, onion skin, play.
class Timeline extends StatelessWidget {
  const Timeline({super.key, required this.e});

  final Editor e;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final frames = e.sprite.frames;
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Onion skin (see the frames before and after)',
            isSelected: e.onionSkin,
            style: IconButton.styleFrom(
              backgroundColor: e.onionSkin ? scheme.secondaryContainer : null,
            ),
            icon: const Icon(Icons.layers_clear_outlined),
            onPressed: e.toggleOnion,
          ),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: frames.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                child: ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  label: Text('${i + 1}'),
                  tooltip: '${frames[i].durationMs} ms',
                  selected: i == e.frame,
                  onSelected: (_) => e.selectFrame(i),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Add a copy of this frame',
            icon: const Icon(Icons.add_to_photos_outlined),
            onPressed: e.addFrame,
          ),
          IconButton(
            tooltip: 'Play the animation',
            icon: const Icon(Icons.play_arrow),
            onPressed: frames.length < 2 ? null : () => showPreview(context, e),
          ),
          PopupMenuButton<String>(
            tooltip: 'Frame options',
            onSelected: (a) => _action(context, a),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'blank',
                child: Text('Add a blank frame'),
              ),
              const PopupMenuItem(value: 'time', child: Text('Frame time…')),
              if (e.frame > 0)
                const PopupMenuItem(value: 'left', child: Text('Move earlier')),
              if (e.frame < frames.length - 1)
                const PopupMenuItem(value: 'right', child: Text('Move later')),
              if (frames.length > 1)
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete this frame'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _action(BuildContext context, String a) async {
    switch (a) {
      case 'blank':
        e.addFrame(copy: false);
      case 'left':
        e.moveFrame(e.frame, e.frame - 1);
      case 'right':
        e.moveFrame(e.frame, e.frame + 1);
      case 'delete':
        e.deleteFrame(e.frame);
      case 'time':
        var ms = e.sprite.frames[e.frame].durationMs.toDouble();
        final all = await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, set) => AlertDialog(
              title: Text(
                'Frame ${e.frame + 1}: ${ms.round()} ms (${(1000 / ms).toStringAsFixed(1)} per second)',
              ),
              content: Slider(
                value: ms,
                min: 20,
                max: 1000,
                divisions: 49,
                onChanged: (v) => set(() => ms = v),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('All frames'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('This frame'),
                ),
              ],
            ),
          ),
        );
        if (all != null) e.setFrameDuration(e.frame, ms.round(), all: all);
    }
  }
}

/// Plays the animation in a loop with each frame's own timing.
Future<void> showPreview(BuildContext context, Editor e) async {
  final s = e.sprite;
  final images = <ui.Image>[];
  for (var f = 0; f < s.frames.length; f++) {
    final px = s.flatten(f);
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      px.buffer.asUint8List(),
      s.width,
      s.height,
      ui.PixelFormat.bgra8888,
      c.complete,
    );
    images.add(await c.future);
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => _Preview(
      images: images,
      durations: [for (final f in s.frames) f.durationMs],
    ),
  );
  for (final i in images) {
    i.dispose();
  }
}

class _Preview extends StatefulWidget {
  const _Preview({required this.images, required this.durations});
  final List<ui.Image> images;
  final List<int> durations;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  int _i = 0;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    _t = Timer(Duration(milliseconds: widget.durations[_i]), () {
      if (!mounted) return;
      setState(() => _i = (_i + 1) % widget.images.length);
      _schedule();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Frame ${_i + 1} of ${widget.images.length}'),
    content: SizedBox.square(
      dimension: 240,
      child: RawImage(
        image: widget.images[_i],
        fit: BoxFit.contain,
        filterQuality: FilterQuality.none,
      ),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}
