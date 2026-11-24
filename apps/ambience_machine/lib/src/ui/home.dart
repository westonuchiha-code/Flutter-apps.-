import 'dart:async';
import 'dart:io';

import 'package:app_shell/app_shell.dart';
import 'package:audio_kit/audio_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../controller.dart';
import '../library.dart';
import '../output.dart';
import '../scene.dart';
import 'layer_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.controller});

  /// For tests; normally created here with real audio.
  final AmbienceController? controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  AmbienceController? _c;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      var c = widget.controller;
      if (c == null) {
        c = AmbienceController(SoLoudAmbOutput());
        await c.init();
      }
      if (mounted) setState(() => _c = c);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not start audio: $e');
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) _c?.dispose();
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

  Future<String?> _askName(String title, String initial) async {
    final ctl = TextEditingController(text: initial);
    final v = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctl.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    ctl.dispose();
    return v == null || v.isEmpty ? null : v;
  }

  // ---- Adding layers ----

  Future<void> _addLayer() async {
    final c = _c!;
    if (!c.canAddLayer) {
      _snack('An ambience can have ${SceneSpec.maxLayers} layers.');
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      // Tall enough for every option without scrolling on most phones.
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.graphic_eq),
              title: const Text('Recording or sample'),
              subtitle: const Text('From the Asset Locker, looped seamlessly'),
              onTap: () => Navigator.pop(context, 'sample'),
            ),
            ListTile(
              leading: const Icon(Icons.piano_outlined),
              title: const Text('Slow notes: a Sound Lab sound'),
              subtitle: const Text('Or a Waveform Painter wave'),
              onTap: () => Navigator.pop(context, 'sound'),
            ),
            ListTile(
              leading: const Icon(Icons.piano_outlined),
              title: const Text('Slow notes: soft pad'),
              onTap: () => Navigator.pop(context, 'pad'),
            ),
            for (final t in NoiseType.values)
              ListTile(
                leading: Icon(
                  layerIcon(LayerSpec(kind: LayerKind.noise, noise: t)),
                ),
                title: Text(t.label),
                subtitle: const Text('Built-in texture'),
                onTap: () => Navigator.pop(context, 'noise:${t.name}'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice.startsWith('noise:')) {
      c.addLayer(
        LayerSpec(
          kind: LayerKind.noise,
          noise: NoiseType.byName(choice.substring(6)),
        ),
      );
    } else if (choice == 'pad') {
      c.addLayer(LayerSpec(kind: LayerKind.synth, volume: 0.5));
    } else if (choice == 'sample') {
      await _pickSample();
    } else {
      final sound = await _pickSound();
      if (sound != null) {
        c.addLayer(LayerSpec(kind: LayerKind.synth, sound: sound, volume: 0.5));
      }
    }
  }

  Future<void> _pickSample() async {
    if (!await _locker() || !mounted) return;
    final locker = Shell.of(context).locker;
    final info = await pickFromLocker(
      context,
      locker,
      types: const [AssetType.recording, AssetType.sample],
    );
    if (info == null) return;
    await _guard(() async {
      final data = await AmbLibrary(locker).decode(info);
      _c!
        ..provideSample(info.id, data, name: info.name)
        ..addLayer(
          LayerSpec(
            kind: LayerKind.sample,
            sampleKey: info.id,
            sampleType: info.type.name,
          ),
        );
    });
  }

  Future<Map<String, Object?>?> _pickSound() async {
    if (!await _locker() || !mounted) return null;
    final locker = Shell.of(context).locker;
    final info = await pickFromLocker(
      context,
      locker,
      types: const [AssetType.preset],
    );
    if (info == null) return null;
    Map<String, Object?>? sound;
    await _guard(() async {
      sound = await AmbLibrary(locker).readSound(info);
      if (sound == null) {
        _snack('"${info.name}" is not a Sound Lab sound or a drawn wave.');
      }
    });
    return sound;
  }

  // ---- Menus ----

  Future<void> _menu(String action) async {
    final c = _c!;
    final shell = Shell.of(context);
    final lib = AmbLibrary(shell.locker);
    switch (action) {
      case 'new':
        c.switchTo(SceneSpec(name: 'New ambience'));
      case 'starter':
        c.switchTo(starterScene());
      case 'rename':
        final n = await _askName('Rename', c.scene.name);
        if (n != null) c.rename(n);
      case 'load':
        if (!await _locker() || !mounted) return;
        final info = await pickFromLocker(
          context,
          shell.locker,
          types: const [AssetType.preset],
        );
        if (info == null) return;
        await _guard(() async {
          final (scene, missing) = await lib.loadScene(c, info);
          c.switchTo(scene);
          _snack(
            missing == 0
                ? 'Loaded "${scene.name}"'
                : 'Loaded "${scene.name}" ($missing samples missing)',
          );
        });
      case 'save':
        if (!await _locker()) return;
        final n = await _askName('Save ambience', c.scene.name);
        if (n == null) return;
        await _guard(() async {
          await lib.saveScene(c, n);
          _snack('Saved "$n" to Presets');
        });
      case 'export':
        final minutes = await showDialog<double>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('How long?'),
            children: [
              for (final m in [0.5, 1.0, 2.0, 3.0])
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, m),
                  child: Text(
                    m < 1
                        ? '30 seconds'
                        : '${m.round()} minute${m == 1 ? '' : 's'}',
                  ),
                ),
            ],
          ),
        );
        if (minutes == null || !mounted) return;
        final where = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Where to?'),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, 'locker'),
                child: const Text('Asset Locker (Recordings)'),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, 'share'),
                child: const Text('Export / share a WAV'),
              ),
            ],
          ),
        );
        if (where == null) return;
        if (where == 'locker' && !await _locker()) return;
        await _guard(() async {
          final wav = await AmbLibrary.exportWav(c, minutes * 60);
          if (where == 'locker') {
            await shell.locker.save(
              type: AssetType.recording,
              name: c.scene.name,
              bytes: wav,
              extension: 'wav',
              tags: const ['ambience', 'ambience machine'],
              extra: {'seconds': minutes * 60},
            );
            _snack('Saved "${c.scene.name}" to Recordings');
          } else {
            await shell.exporter.exportFile(
              '${c.scene.name}.wav',
              wav,
              mimeType: 'audio/wav',
            );
          }
        });
    }
  }

  Future<void> _sleep() async {
    final c = _c!;
    final choice = await showDialog<double>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Stop playing after'),
        children: [
          for (final m in [15.0, 30.0, 45.0, 60.0, 90.0])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, m),
              child: Text('${m.round()} minutes'),
            ),
          if (c.sleepLeft != null)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, -1),
              child: const Text('Turn the timer off'),
            ),
        ],
      ),
    );
    if (choice == null) return;
    c.setSleep(choice < 0 ? null : choice);
  }

  void _effects() {
    final c = _c!;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Effects on everything')),
          body: ListenableBuilder(
            listenable: c,
            builder: (context, _) => EffectChainEditor(
              effects: c.scene.fx,
              onAdd: c.addEffect,
              onChanged: c.updateEffect,
              onRemove: c.removeEffect,
              onMove: c.moveEffect,
            ),
          ),
        ),
      ),
    );
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ambience Machine')),
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : Text(_error!),
        ),
      );
    }
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final sleep = c.sleepLeft;
        return Scaffold(
          appBar: AppBar(
            title: GestureDetector(
              onTap: () => _menu('rename'),
              child: Text(c.scene.name, overflow: TextOverflow.ellipsis),
            ),
            actions: [
              IconButton(
                tooltip: 'Sleep timer',
                icon: Icon(
                  sleep == null ? Icons.bedtime_outlined : Icons.bedtime,
                ),
                onPressed: _sleep,
              ),
              IconButton(
                tooltip: 'Effects',
                icon: const Icon(Icons.tune),
                onPressed: _effects,
              ),
              PopupMenuButton<String>(
                tooltip: 'Ambience',
                icon: const Icon(Icons.folder_outlined),
                onSelected: _menu,
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'new', child: Text('New (empty)')),
                  PopupMenuItem(
                    value: 'starter',
                    child: Text('Starter ambience'),
                  ),
                  PopupMenuItem(value: 'rename', child: Text('Rename…')),
                  PopupMenuItem(
                    value: 'load',
                    child: Text('Load (crossfades)…'),
                  ),
                  PopupMenuItem(value: 'save', child: Text('Save…')),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'export', child: Text('Render to WAV…')),
                ],
              ),
              ...shellActions(context),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _addLayer,
            icon: const Icon(Icons.add),
            label: const Text('Layer'),
          ),
          body: SafeArea(
            child: Column(
              children: [
                if (_busy) const LinearProgressIndicator(),
                _PlayHeader(c: c),
                Expanded(
                  child: c.scene.layers.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Add layers: your recordings, slow notes from a Sound Lab sound, '
                              'or built-in wind, rain, waves and rumble.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                              children: [
                                for (final l in c.scene.layers)
                                  LayerCard(
                                    key: ValueKey(l.id),
                                    layer: l,
                                    level: c.levels[l.id] ?? 0,
                                    sampleName:
                                        c.sampleNames[l.sampleKey] ?? '',
                                    missing:
                                        l.kind == LayerKind.sample &&
                                        !c.hasSample(l.sampleKey ?? ''),
                                    onChanged: c.updateLayer,
                                    onRemove: () => c.removeLayer(l),
                                    onChangeSound: l.kind == LayerKind.synth
                                        ? () async {
                                            final sound = await _pickSound();
                                            if (sound != null) {
                                              c.removeLayer(l);
                                              c.addLayer(
                                                LayerSpec(
                                                  kind: LayerKind.synth,
                                                  sound: sound,
                                                  volume: l.volume,
                                                  root: l.root,
                                                  scale: l.scale,
                                                  octaves: l.octaves,
                                                  density: l.density,
                                                  noteLength: l.noteLength,
                                                ),
                                              );
                                            }
                                          }
                                        : null,
                                  ),
                              ],
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PlayHeader extends StatelessWidget {
  const _PlayHeader({required this.c});

  final AmbienceController c;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sleep = c.sleepLeft;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 64,
            child: IconButton.filled(
              iconSize: 36,
              tooltip: c.playing ? 'Stop' : 'Play',
              icon: Icon(c.playing ? Icons.stop : Icons.play_arrow),
              onPressed: () => c.setPlaying(!c.playing),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.playing
                      ? (sleep == null
                            ? 'Playing'
                            : 'Playing · stops in ${_mins(sleep)}')
                      : 'Stopped',
                  style: theme.textTheme.titleMedium,
                ),
                Row(
                  children: [
                    const Icon(Icons.volume_down, size: 18),
                    Expanded(
                      child: Slider(value: c.master, onChanged: c.setMaster),
                    ),
                  ],
                ),
                if (Platform.isAndroid && c.playing)
                  Text(
                    'Keeps playing with the screen off.',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _mins(double s) {
    final m = (s / 60).ceil();
    return m <= 1 ? 'under a minute' : '$m min';
  }
}
