import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_shell/app_shell.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_kit/video_kit.dart';

import '../controller.dart';
import '../processor.dart';
import 'crt.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.controller});

  /// For tests.
  final ChipCamController? controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final ChipCamController c =
      widget.controller ?? ChipCamController(processor: IsolateProcessor());
  final _screenKey = GlobalKey();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) unawaited(c.init());
  }

  @override
  void dispose() {
    if (widget.controller == null) c.dispose();
    super.dispose();
  }

  void _snack(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<bool> _locker() async {
    final l = Shell.of(context).locker;
    if (l.ready || await l.connect()) return true;
    _snack('Connect the Asset Locker first.');
    return false;
  }

  /// PNG of what is on screen (with the CRT if it is on).
  Future<Uint8List?> _screenPng() async {
    if (!c.crt) return c.snapshotPng();
    final boundary =
        _screenKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return c.snapshotPng();
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  }

  Future<void> _snapshot() async {
    final png = await _screenPng();
    if (png == null || !mounted) return;
    final where = await _where('Snapshot');
    if (where == null) return;
    await _guard(() async {
      final name =
          '${c.effect.name} ${DateTime.now().toLocal().toString().substring(0, 19)}';
      if (where == 'locker') {
        if (!await _locker() || !mounted) return;
        await Shell.of(context).locker.save(
          type: AssetType.picture,
          name: name,
          bytes: png,
          extension: 'png',
          thumbnail: png.length < 400000 ? png : null,
          tags: ['chip cam', c.effect.id],
        );
        _snack('Saved to Pictures');
      } else {
        await Shell.of(context).exporter
            .exportFile('chip_cam.png', png, mimeType: 'image/png');
      }
    });
  }

  Future<String?> _where(String what) => showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(what),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'locker'),
          child: const Text('Save to Asset Locker (Pictures)'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'share'),
          child: const Text('Export / share'),
        ),
      ],
    ),
  );

  Future<void> _guard(Future<void> Function() work) async {
    setState(() => _busy = true);
    try {
      await work();
    } catch (e) {
      _snack('Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clip() async {
    if (!c.recording) {
      c.startClip();
      return;
    }
    c.stopClip();
    final frames = List<VideoFrame>.of(c.clip);
    if (frames.length < 2) return;
    final where = await _where(
      'GIF clip (${(frames.length / clipFps).toStringAsFixed(1)} s)',
    );
    if (where == null) return;
    await _guard(() async {
      final gif = await Isolate.run(
        () => clipToGif(frames, scale: frames.first.width < 200 ? 2 : 1),
      );
      if (!mounted) return;
      if (where == 'locker') {
        if (!await _locker()) return;
        if (!mounted) return;
        await Shell.of(context).locker.save(
          type: AssetType.picture,
          name: '${c.effect.name} clip',
          bytes: gif,
          extension: 'gif',
          tags: ['chip cam', 'clip', c.effect.id],
          extra: {'frames': frames.length, 'fps': clipFps},
        );
        _snack('Saved the clip to Pictures');
      } else {
        await Shell.of(context).exporter
            .exportFile('chip_cam.gif', gif, mimeType: 'image/gif');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final screen = RepaintBoundary(
          key: _screenKey,
          child: ScreenView(image: c.image, crt: c.crt),
        );
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: Text(c.effect.name, overflow: TextOverflow.ellipsis),
            actions: [
              if (c.sources.length > 1)
                PopupMenuButton<int>(
                  tooltip: 'Camera',
                  icon: const Icon(Icons.cameraswitch_outlined),
                  onSelected: (i) => c.useSource(c.sources[i]),
                  itemBuilder: (context) => [
                    for (var i = 0; i < c.sources.length; i++)
                      CheckedPopupMenuItem(
                        value: i,
                        checked: c.sources[i] == c.current,
                        child: Text(c.sources[i].label),
                      ),
                  ],
                ),
              IconButton(
                tooltip: c.crt ? 'Plain screen' : 'Show on a CRT',
                isSelected: c.crt,
                icon: const Icon(Icons.tv_outlined),
                selectedIcon: const Icon(Icons.tv),
                onPressed: c.toggleCrt,
              ),
              ...shellActions(context),
            ],
          ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, box) {
                final wide = box.maxWidth >= 900;
                final preview = Stack(
                  children: [
                    Positioned.fill(child: screen),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Text(
                        '${c.fps.toStringAsFixed(0)} fps${c.current == null ? '' : ' · ${c.current!.label}'}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (c.recording)
                      Positioned(
                        right: 12,
                        top: 8,
                        child: Text(
                          '● REC ${(c.clip.length / clipFps).toStringAsFixed(1)} s',
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    if (c.error != null)
                      Positioned(
                        left: 8,
                        right: 8,
                        bottom: 8,
                        child: Text(
                          c.error!,
                          style: const TextStyle(color: Colors.orangeAccent),
                        ),
                      ),
                    if (_busy)
                      const Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        child: LinearProgressIndicator(),
                      ),
                  ],
                );
                final controls = _Controls(
                  c: c,
                  onSnapshot: _snapshot,
                  onClip: _clip,
                  list: wide,
                );
                if (wide) {
                  return Row(
                    children: [
                      Expanded(child: preview),
                      SizedBox(
                        width: 340,
                        child: Material(
                          color: Theme.of(context).colorScheme.surface,
                          child: controls,
                        ),
                      ),
                    ],
                  );
                }
                return Column(
                  children: [
                    Expanded(child: preview),
                    Material(
                      color: Theme.of(context).colorScheme.surface,
                      child: controls,
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.c,
    required this.onSnapshot,
    required this.onClip,
    required this.list,
  });

  final ChipCamController c;
  final VoidCallback onSnapshot, onClip;

  /// Side panel (desktop): effects as a list instead of a strip.
  final bool list;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = c.effect;
    final picker = list
        ? Expanded(
            child: ListView(
              children: [
                for (var i = 0; i < c.effects.length; i++)
                  ListTile(
                    dense: true,
                    selected: i == c.effectIndex,
                    title: Text(c.effects[i].name),
                    onTap: () => c.selectEffect(i),
                  ),
              ],
            ),
          )
        : SizedBox(
            height: 48,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: c.effects.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
                child: ChoiceChip(
                  label: Text(c.effects[i].name),
                  selected: i == c.effectIndex,
                  onSelected: (_) => c.selectEffect(i),
                ),
              ),
            ),
          );
    final knobs = [
      for (final k in e.knobs)
        if (k.choices != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Row(
              children: [
                Expanded(child: Text(k.label, overflow: TextOverflow.ellipsis)),
                SegmentedButton<int>(
                  segments: [
                    for (var i = 0; i < k.choices!.length; i++)
                      ButtonSegment(value: i, label: Text(k.choices![i])),
                  ],
                  selected: {e.knob(k.id).round()},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) =>
                      c.setKnob(k.id, s.first.toDouble()),
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    k.label,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: e.knob(k.id).clamp(k.min, k.max),
                    min: k.min,
                    max: k.max,
                    onChanged: (v) => c.setKnob(k.id, v),
                  ),
                ),
              ],
            ),
          ),
    ];
    final buttons = Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton.filledTonal(
            iconSize: 28,
            tooltip: c.recording
                ? 'Stop the clip'
                : 'Record a GIF clip (up to ${maxClipSeconds.round()} s)',
            icon: Icon(
              c.recording ? Icons.stop : Icons.videocam_outlined,
              color: c.recording ? Colors.redAccent : null,
            ),
            onPressed: onClip,
          ),
          IconButton.filled(
            iconSize: 36,
            tooltip: 'Snapshot',
            icon: const Icon(Icons.camera),
            onPressed: onSnapshot,
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
    final aboutText = Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
      child: Text(e.about, style: theme.textTheme.bodySmall),
    );
    if (list) {
      return Column(
        children: [
          picker,
          const Divider(height: 1),
          aboutText,
          ...knobs,
          buttons,
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [picker, aboutText, ...knobs, buttons],
    );
  }
}
