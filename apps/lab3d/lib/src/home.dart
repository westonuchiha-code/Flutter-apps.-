import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_shell/app_shell.dart';
import 'package:engine3d/engine3d.dart';
import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';

import 'world.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.world});

  /// For tests and screenshots.
  final LabWorld? world;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  LabWorld? _world;
  late CameraRig _rig;
  bool _walk = true;
  RenderOptions _options = const RenderOptions();

  static const _resolutions = [
    (240, '240 (PS1)'),
    (360, '360'),
    (480, '480'),
    (0, 'Full'),
  ];

  @override
  void initState() {
    super.initState();
    final w = widget.world;
    if (w != null) {
      _use(w);
    } else {
      unawaited(
        LabWorld.build().then((w) => mounted ? setState(() => _use(w)) : null),
      );
    }
  }

  void _use(LabWorld w) {
    _world = w;
    _rig = _makeRig();
  }

  CameraRig _makeRig() => _walk
      ? WalkRig(
          start: Vector3(0, 1.6, 8),
          walls: _world!.walls,
          ground: LabWorld.hills,
        )
      : OrbitRig(target: Vector3(0, 1.4, 0), distance: 5, autoSpin: 0);

  void _snack(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _loadModel() async {
    final shell = Shell.of(context);
    final where = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('Model file on this device'),
              subtitle: const Text(
                '.glb (or .gltf with everything inside) or .obj',
              ),
              onTap: () => Navigator.pop(context, 'file'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_shared_outlined),
              title: const Text('From the Asset Locker (Models)'),
              onTap: () => Navigator.pop(context, 'locker'),
            ),
            if (_world?.model != null)
              ListTile(
                leading: const Icon(Icons.clear),
                title: const Text('Back to the cube'),
                onTap: () => Navigator.pop(context, 'clear'),
              ),
          ],
        ),
      ),
    );
    if (where == null || !mounted) {
      return;
    }
    if (where == 'clear') {
      setState(() => _world!.setModel(null));
      return;
    }
    try {
      Uint8List? bytes;
      String name = 'model', ext = 'glb';
      if (where == 'file') {
        final f = await openFile(
          acceptedTypeGroups: [
            const XTypeGroup(
              label: '3D models',
              extensions: ['glb', 'gltf', 'obj'],
              uniformTypeIdentifiers: ['public.item'],
            ),
          ],
        );
        if (f == null) {
          return;
        }
        bytes = await f.readAsBytes();
        name = f.name.contains('.')
            ? f.name.substring(0, f.name.lastIndexOf('.'))
            : f.name;
        ext = f.name.contains('.')
            ? f.name.split('.').last.toLowerCase()
            : 'glb';
      } else {
        final locker = shell.locker;
        if (!locker.ready && !await locker.connect()) {
          return;
        }
        if (!mounted) {
          return;
        }
        final info = await pickFromLocker(
          context,
          locker,
          types: const [AssetType.model],
        );
        if (info == null) {
          return;
        }
        bytes = await locker.read(info);
        name = info.name;
        ext = info.extension;
      }
      if (bytes == null) {
        return;
      }
      final node = ext == 'obj'
          ? loadObj(utf8.decode(bytes, allowMalformed: true), name: name)
          : await loadGltf(bytes, name: name);
      if (!mounted) {
        return;
      }
      setState(() => _world!.setModel(node));
      if (where == 'file') {
        final save = await _ask(
          'Keep "$name" in the Asset Locker (Models) for other apps?',
        );
        if (save == true) {
          final locker = shell.locker;
          if (!locker.ready && !await locker.connect()) {
            return;
          }
          await locker.save(
            type: AssetType.model,
            name: name,
            bytes: bytes,
            extension: ext,
            tags: const ['3d lab'],
          );
          _snack('Saved to Models');
        }
      }
    } catch (e) {
      _snack('Could not load that model: $e');
    }
  }

  Future<bool?> _ask(String q) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(q),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('No'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Yes'),
        ),
      ],
    ),
  );

  Future<void> _texture() async {
    final locker = Shell.of(context).locker;
    if (!locker.ready && !await locker.connect()) {
      return;
    }
    if (!mounted) {
      return;
    }
    final info = await pickFromLocker(
      context,
      locker,
      types: const [AssetType.picture],
    );
    if (info == null) {
      return;
    }
    try {
      final bytes = await locker.read(info);
      if (bytes == null) {
        return;
      }
      final img = await imageFromBytes(bytes);
      if (!mounted) {
        return;
      }
      final target = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text('Use "${info.name}" on'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'cube'),
              child: const Text('The spinning cube'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'floor'),
              child: const Text('The floor (tiled)'),
            ),
          ],
        ),
      );
      if (target == null) {
        return;
      }
      setState(() {
        final node = target == 'cube' ? _world!.cube : _world!.floor;
        node.material!.texture = img;
      });
    } catch (e) {
      _snack('Could not use that picture: $e');
    }
  }

  Future<void> _settings() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, set) {
        void update(RenderOptions o) {
          setState(() => _options = o);
          set(() {});
        }

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Picture height',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final (v, label) in _resolutions)
                      ChoiceChip(
                        label: Text(label),
                        selected: _options.lowRes == v,
                        onSelected: (_) => update(_options.copyWith(lowRes: v)),
                      ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Wobble'),
                  subtitle: const Text(
                    'Corners snap to whole pixels, like the PS1',
                  ),
                  value: _options.wobble,
                  onChanged: (v) => update(_options.copyWith(wobble: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Fog'),
                  value: _options.fog,
                  onChanged: (v) => update(_options.copyWith(fog: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Lighting'),
                  value: _options.lighting,
                  onChanged: (v) => update(_options.copyWith(lighting: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Smooth textures'),
                  subtitle: const Text('Off: sharp texels, like the PS1'),
                  value: _options.smoothTextures,
                  onChanged: (v) =>
                      update(_options.copyWith(smoothTextures: v)),
                ),
                Row(
                  children: [
                    const SizedBox(width: 110, child: Text('Draw distance')),
                    Expanded(
                      child: Slider(
                        value: _options.drawDistance,
                        min: 10,
                        max: 120,
                        onChanged: (v) =>
                            update(_options.copyWith(drawDistance: v)),
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text('${_options.drawDistance.round()} m'),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () => update(const RenderOptions()),
                      child: const Text('PS1 look'),
                    ),
                    OutlinedButton(
                      onPressed: () => update(RenderOptions.clean),
                      child: const Text('Clean look'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final w = _world;
    return Scaffold(
      appBar: AppBar(
        title: const Text('3D Lab'),
        actions: [
          IconButton(
            tooltip: _walk ? 'Orbit the showcase' : 'Walk around',
            icon: Icon(_walk ? Icons.threesixty : Icons.directions_walk),
            onPressed: w == null
                ? null
                : () => setState(() {
                    _walk = !_walk;
                    _rig = _makeRig();
                  }),
          ),
          IconButton(
            tooltip: 'Load a model',
            icon: const Icon(Icons.view_in_ar_outlined),
            onPressed: w == null ? null : _loadModel,
          ),
          IconButton(
            tooltip: 'Use a picture as a texture',
            icon: const Icon(Icons.texture),
            onPressed: w == null ? null : _texture,
          ),
          IconButton(
            tooltip: 'Look',
            icon: const Icon(Icons.tune),
            onPressed: _settings,
          ),
          ...shellActions(context),
        ],
      ),
      body: w == null
          ? const Center(child: CircularProgressIndicator())
          : Viewport3D(
              scene: w.scene,
              rig: _rig,
              options: _options,
              onFrame: w.tick,
              showStats: true,
            ),
    );
  }
}
