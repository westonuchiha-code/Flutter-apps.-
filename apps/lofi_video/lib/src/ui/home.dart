import 'dart:async';
import 'dart:ui' as ui;

import 'package:app_shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_kit/video_kit.dart';

import '../controller.dart';
import '../media.dart';
import '../preview.dart';
import '../project.dart';
import '../title.dart';
import 'export_sheet.dart';
import 'scene_sheet.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.controller});

  /// For tests.
  final VideoController? controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  VideoController? _c;
  VideoController get c => _c!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c != null) {
      return;
    }
    if (widget.controller != null) {
      _c = widget.controller;
    } else {
      final shell = Shell.of(context);
      _c = VideoController(
        preview: IsolatePreview(),
        locker: shell.locker,
        storage: shell.storage,
      );
      unawaited(c.init());
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      unawaited(c.flush());
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<AssetInfo?> _pick(List<AssetType> types) async {
    final locker = Shell.of(context).locker;
    if (!locker.ready && !await locker.connect()) {
      _snack('Connect the Asset Locker first.');
      return null;
    }
    if (!mounted) {
      return null;
    }
    return pickFromLocker(context, locker, types: types);
  }

  Future<void> _addScene() async {
    final kind = await showModalBottomSheet<SceneKind>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (k, icon, sub) in [
              (
                SceneKind.clip,
                Icons.videocam_outlined,
                'Recorded in Chip Cam (Videos)',
              ),
              (
                SceneKind.picture,
                Icons.photo_outlined,
                'Snapshots, textures, GIFs (Pictures)',
              ),
              (SceneKind.sprite, Icons.grid_on, 'Animated sprites (Sprites)'),
              (SceneKind.title, Icons.title, 'Text on a colour'),
              (SceneKind.bars, Icons.view_week_outlined, 'Colour bars'),
            ])
              ListTile(
                leading: Icon(icon),
                title: Text(k.label),
                subtitle: Text(sub),
                onTap: () => Navigator.pop(context, k),
              ),
          ],
        ),
      ),
    );
    if (kind == null || !mounted) {
      return;
    }
    final types = switch (kind) {
      SceneKind.clip => [AssetType.video],
      SceneKind.picture => [AssetType.picture, AssetType.sprite],
      SceneKind.sprite => [AssetType.sprite],
      _ => null,
    };
    Map<String, Object?>? asset;
    var label = kind.label;
    if (types != null) {
      final info = await _pick(types);
      if (info == null) {
        return;
      }
      if (kind == SceneKind.clip && info.extension != clipExtension) {
        _snack('Only Chip Cam clips can be used as clips for now.');
        return;
      }
      asset = info.toJson();
      label = info.name;
    }
    final scene = Scene(
      kind: kind,
      asset: asset,
      label: label,
      text: kind == SceneKind.title ? 'TITLE' : '',
      textColor: kind == SceneKind.title ? 0xFFFFEC27 : 0xFFFFFFFF,
      background: kind == SceneKind.title ? 0xFF1D2B53 : 0xFF000000,
      duration: kind == SceneKind.bars ? 2 : 3,
    );
    await c.addScene(scene);
    final i = c.project.scenes.indexOf(scene);
    if (i >= 0) {
      await c.seek(c.project.starts[i] + 0.01);
    }
    if (mounted && kind == SceneKind.title) {
      await _editScene(scene);
    }
  }

  Future<void> _editScene(Scene s) async {
    final i = c.project.scenes.indexOf(s);
    if (i >= 0) {
      await c.seek(c.project.starts[i] + 0.01);
    }
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.75,
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) => SceneSheet(
            c: c,
            scene: s,
            pickSprite: () async =>
                (await _pick([AssetType.sprite, AssetType.picture]))?.toJson(),
          ),
        ),
      ),
    );
  }

  Future<void> _music() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final p = c.project;
          final m = p.music == null ? null : c.media[p.music!['id']];
          final length = m is SoundMedia ? m.seconds : 0.0;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.music_note_outlined),
                    title: Text(
                      p.music == null
                          ? 'No music'
                          : (p.music!['name'] as String? ?? 'Music'),
                    ),
                    subtitle: Text(
                      p.music == null
                          ? 'Pick a WAV: a Sample Pad mix, a recording or a sample'
                          : '${length.toStringAsFixed(1)} s',
                    ),
                    trailing: Wrap(
                      children: [
                        IconButton(
                          tooltip: 'Pick music',
                          icon: const Icon(Icons.library_music_outlined),
                          onPressed: () async {
                            final info = await _pick([
                              AssetType.recording,
                              AssetType.sample,
                              AssetType.other,
                            ]);
                            if (info == null) {
                              return;
                            }
                            if (info.extension.toLowerCase() != 'wav') {
                              _snack('Music must be a WAV file.');
                              return;
                            }
                            await c.setMusic(info.toJson());
                          },
                        ),
                        if (p.music != null)
                          IconButton(
                            tooltip: 'No music',
                            icon: const Icon(Icons.clear),
                            onPressed: () => c.setMusic(null),
                          ),
                      ],
                    ),
                  ),
                  if (length > 1)
                    _LabeledSlider(
                      label: 'Start at',
                      text: '${p.musicStart.toStringAsFixed(1)} s',
                      value: p.musicStart.clamp(0, length - 1),
                      max: length - 1,
                      onChanged: (v) =>
                          c.edit((p) => p.musicStart = (v * 10).round() / 10),
                    ),
                  Row(
                    children: [
                      const SizedBox(width: 110, child: Text('Tempo')),
                      IconButton(
                        tooltip: 'Slower',
                        icon: const Icon(Icons.remove),
                        onPressed: () => c.edit(
                          (p) => p.bpm = (p.bpm - 1)
                              .clamp(30, 300)
                              .roundToDouble(),
                        ),
                      ),
                      Text(
                        '${p.bpm.toStringAsFixed(p.bpm % 1 == 0 ? 0 : 1)} BPM',
                      ),
                      IconButton(
                        tooltip: 'Faster',
                        icon: const Icon(Icons.add),
                        onPressed: () => c.edit(
                          (p) => p.bpm = (p.bpm + 1)
                              .clamp(30, 300)
                              .roundToDouble(),
                        ),
                      ),
                      const Spacer(),
                      OutlinedButton(onPressed: _tap, child: const Text('Tap')),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Cuts on the beat'),
                    subtitle: const Text('Scene lengths are whole beats'),
                    value: p.snap,
                    onChanged: (v) => c.setSnap(v),
                  ),
                  _LabeledSlider(
                    label: 'Music volume',
                    text: '${(p.musicVolume * 100).round()}%',
                    value: p.musicVolume,
                    onChanged: (v) => c.edit((p) => p.musicVolume = v),
                  ),
                  _LabeledSlider(
                    label: 'Clip sound',
                    text: '${(p.clipVolume * 100).round()}%',
                    value: p.clipVolume,
                    onChanged: (v) => c.edit((p) => p.clipVolume = v),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  final _taps = <int>[];

  /// Tap tempo: the average of the last few taps.
  void _tap() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_taps.isNotEmpty && now - _taps.last > 2000) _taps.clear();
    _taps.add(now);
    if (_taps.length > 6) _taps.removeAt(0);
    if (_taps.length >= 3) {
      final avg = (_taps.last - _taps.first) / (_taps.length - 1);
      unawaited(
        c.edit((p) => p.bpm = (60000 / avg).clamp(30, 300).roundToDouble()),
      );
    }
  }

  Future<void> _rename() async {
    final field = TextEditingController(text: c.project.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Video name'),
        content: TextField(
          controller: field,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await c.edit((p) => p.name = name.trim());
    }
  }

  Future<void> _export({bool test = false}) async {
    await c.stop();
    if (!mounted) {
      return;
    }
    Project project;
    Map<String, VideoFrame> titles;
    if (test) {
      final title = Scene(
        kind: SceneKind.title,
        text: 'TEST\nEXPORT',
        textColor: 0xFFFFEC27,
        background: 0xFF7E2553,
        duration: 1,
      );
      project = Project(
        name: 'Lo-Fi test',
        scenes: [
          Scene(kind: SceneKind.bars, duration: 1, effectId: 'vhs'),
          title,
        ],
      );
      titles = {title.id: await renderTitle(title)};
    } else {
      project = Project.fromJson(c.project.toJson());
      titles = {
        for (final s in project.scenes) ...{
          if (c.titles[s.id] != null) s.id: c.titles[s.id]!,
          for (final o in s.overlays)
            if (c.titles[o.id] != null) o.id: c.titles[o.id]!,
        },
      };
    }
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isDismissible: false,
      builder: (context) => ExportSheet(
        project: project,
        media: Map.of(c.media),
        titles: titles,
        test: test,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final p = c.project;
        final canExport = p.scenes.isNotEmpty && !c.tooLong;
        return Scaffold(
          appBar: AppBar(
            title: InkWell(
              onTap: _rename,
              child: Text(p.name, overflow: TextOverflow.ellipsis),
            ),
            actions: [
              IconButton(
                tooltip: c.tooLong
                    ? 'Over ${maxSeconds.round()} s: shorten it to export'
                    : 'Export video',
                icon: const Icon(Icons.movie_creation_outlined),
                onPressed: canExport ? _export : null,
              ),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'new') {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Start a new video?'),
                        content: const Text(
                          'The current storyboard is cleared (your clips stay in the Asset Locker).',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('New video'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await c.newProject();
                    }
                  } else if (v == 'test') {
                    await _export(test: true);
                  } else if (v == 'rename') {
                    await _rename();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'new', child: Text('New video')),
                  PopupMenuItem(
                    value: 'test',
                    child: Text('Test export (2 s)'),
                  ),
                ],
              ),
              ...shellActions(context),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _addScene,
            icon: const Icon(Icons.add),
            label: const Text('Add scene'),
          ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, box) {
                final wide = box.maxWidth >= 900;
                final player = _Player(
                  c: c,
                  maxHeight: wide ? box.maxHeight - 120 : box.maxHeight * 0.4,
                );
                final board = _Storyboard(
                  c: c,
                  onEdit: _editScene,
                  onMusic: _music,
                );
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: Center(child: player)),
                      SizedBox(
                        width: 400,
                        child: Material(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerLow,
                          child: board,
                        ),
                      ),
                    ],
                  );
                }
                return Column(
                  children: [
                    player,
                    Expanded(child: board),
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

class _Player extends StatelessWidget {
  const _Player({required this.c, required this.maxHeight});
  final VideoController c;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final d = c.duration;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: ColoredBox(
              color: Colors.black,
              child: c.image == null
                  ? Center(
                      child: Text(
                        c.project.scenes.isEmpty ? 'Add a scene to start' : '',
                        style: const TextStyle(color: Colors.white54),
                      ),
                    )
                  : CustomPaint(
                      painter: _FramePainter(c.image!),
                      size: Size.infinite,
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              IconButton(
                tooltip: c.playing ? 'Stop' : 'Play',
                icon: Icon(c.playing ? Icons.stop : Icons.play_arrow),
                onPressed: c.project.scenes.isEmpty
                    ? null
                    : (c.playing ? c.stop : c.play),
              ),
              Expanded(
                child: Slider(
                  value: d <= 0 ? 0 : c.position.clamp(0, d),
                  max: d <= 0 ? 1 : d,
                  onChanged: d <= 0
                      ? null
                      : (v) {
                          unawaited(c.stop());
                          unawaited(c.seek(v));
                        },
                ),
              ),
              Text(
                '${c.position.toStringAsFixed(1)} / ${d.toStringAsFixed(1)} s',
                style: TextStyle(color: c.tooLong ? Colors.orangeAccent : null),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ],
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter(this.image);
  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    // Stretch to 4:3 (machine pictures like 160×200 had non-square pixels).
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.none,
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.image != image;
}

class _Storyboard extends StatelessWidget {
  const _Storyboard({
    required this.c,
    required this.onEdit,
    required this.onMusic,
  });
  final VideoController c;
  final void Function(Scene) onEdit;
  final VoidCallback onMusic;

  @override
  Widget build(BuildContext context) {
    final p = c.project;
    final current = c.currentScene;
    final musicName = p.music == null
        ? null
        : (p.music!['name'] as String? ?? 'Music');
    return ReorderableListView.builder(
      padding: const EdgeInsets.only(bottom: 88),
      buildDefaultDragHandles: false,
      header: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.music_note_outlined),
            title: Text(musicName ?? 'Add music'),
            subtitle: Text(
              musicName == null
                  ? 'A Sample Pad mix, recording or sample (WAV)'
                  : 'Volume ${(p.musicVolume * 100).round()}%',
            ),
            onTap: onMusic,
          ),
          if (c.tooLong)
            ListTile(
              leading: const Icon(
                Icons.timer_outlined,
                color: Colors.orangeAccent,
              ),
              title: Text('Over ${maxSeconds.round()} seconds'),
              subtitle: const Text('Shorten or remove scenes to export.'),
            ),
          const Divider(height: 1),
        ],
      ),
      itemCount: p.scenes.length,
      onReorderItem: (a, b) => c.moveScene(a, b),
      itemBuilder: (context, i) {
        final s = p.scenes[i];
        final missing = s.assetId != null && c.failed[s.assetId] != null;
        final loading =
            s.assetId != null && !c.media.containsKey(s.assetId) && !missing;
        return ListTile(
          key: ValueKey(s.id),
          selected: i == current,
          leading: Icon(switch (s.kind) {
            SceneKind.clip => Icons.videocam_outlined,
            SceneKind.picture => Icons.photo_outlined,
            SceneKind.sprite => Icons.grid_on,
            SceneKind.title => Icons.title,
            SceneKind.bars => Icons.view_week_outlined,
          }),
          title: Text(
            s.kind == SceneKind.title
                ? (s.text.trim().isEmpty
                      ? 'Title'
                      : s.text.trim().replaceAll('\n', ' '))
                : s.label,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            [
              '${s.duration.toStringAsFixed(1)} s',
              if (i > 0 && s.transition != Transition.cut)
                '→ ${s.transition.label}',
              if (s.effectId != null) effectName(s.effectId),
              if (s.overlays.isNotEmpty) '+${s.overlays.length} on top',
              if (missing) 'missing!',
              if (loading) 'loading…',
            ].join(' · '),
            style: TextStyle(color: missing ? Colors.orangeAccent : null),
          ),
          onTap: () => onEdit(s),
          trailing: ReorderableDragStartListener(
            index: i,
            child: const Icon(Icons.drag_handle),
          ),
        );
      },
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.text,
    required this.value,
    required this.onChanged,
    this.max = 1,
  });
  final String label, text;
  final double value, max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 110, child: Text(label)),
      Expanded(
        child: Slider(value: value, max: max, onChanged: onChanged),
      ),
      SizedBox(width: 52, child: Text(text, textAlign: TextAlign.end)),
    ],
  );
}
