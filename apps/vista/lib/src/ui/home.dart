import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:app_shell/app_shell.dart';
import 'package:engine3d/engine3d.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import '../flyover.dart';
import '../land.dart';
import '../world.dart';
import 'still_page.dart';

HeightField _generate(LandSettings s) => generate(s);

Uint8List _heightPng(HeightField f) {
  final px = heightMapPixels(f);
  final image = img.Image(width: f.n, height: f.n);
  for (final p in image) {
    final c = px[p.y * f.n + p.x] & 255;
    p
      ..r = c
      ..g = c
      ..b = c;
  }
  return img.encodePng(image);
}

const _palette = [
  0xFFD8C690,
  0xFFE2B878,
  0xFF5E8A3E,
  0xFF3E6A2E,
  0xFF8AA050,
  0xFF7A7068,
  0xFF5A5450,
  0xFFB0583A, //
  0xFF9A9A9A,
  0xFFF2F4F8,
  0xFFC8855A,
  0xFF6A8AA8,
  0xFF8E5E9A,
  0xFFD0C0A0,
  0xFF2E2A26,
  0xFFE0E8C0,
];

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.initial});

  /// For tests: start from this landscape.
  final LandSettings? initial;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late LandSettings _s = widget.initial ?? const LandSettings();
  late String _name = presets[_s.preset]?.$1 ?? 'Landscape';
  HeightField? _field;
  VistaWorld? _world;
  CameraRig? _rig;
  bool _fly = true, _busy = false;
  RenderOptions _options = const RenderOptions(drawDistance: 600);
  CameraPath _path = CameraPath();
  double _seconds = 12;
  bool _rayFlyover = false;
  PathRig? _playing;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_regenerate());
  }

  void _snack(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _regenerate() async {
    final gen = ++_gen;
    setState(() => _busy = true);
    final s = _s;
    final field = await runInBackground(_generate, s);
    if (gen != _gen || !mounted) {
      return;
    }
    _field = field;
    await _rebuild(keepCamera: _rig != null);
  }

  Future<void> _rebuild({bool keepCamera = true}) async {
    final field = _field;
    if (field == null) {
      return;
    }
    final world = await VistaWorld.build(
      _s,
      field,
      detail: Platform.isAndroid ? 73 : 97,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      final old = _rig?.camera;
      _world = world;
      _rig = _makeRig(world);
      if (keepCamera && old != null) {
        _rig!.camera
          ..position = old.position.clone()
          ..yaw = old.yaw
          ..pitch = old.pitch;
      }
      _busy = false;
    });
  }

  CameraRig _makeRig(VistaWorld w) {
    final startY = w.groundAt(0, 170) + 45;
    if (_fly) {
      return FlyRig(
        start: Vector3(0, startY, 170),
        pitch: -0.22,
        speed: 25,
        ground: w.groundAt,
      );
    }
    return WalkRig(
      start: Vector3(0, startY, 170),
      speed: 6,
      eyeHeight: 1.8,
      ground: w.groundAt,
    );
  }

  void _change(LandSettings s, {bool regen = true}) {
    setState(() => _s = s);
    if (regen) {
      unawaited(_regenerate());
    } else {
      unawaited(_rebuild());
    }
  }

  void _toggleWalk() {
    final w = _world;
    if (w == null) {
      return;
    }
    setState(() {
      final old = _rig!.camera;
      _fly = !_fly;
      _rig = _makeRig(w);
      _rig!.camera
        ..position = Vector3(
          old.position.x,
          w.groundAt(old.position.x, old.position.z) + (_fly ? 20 : 1.8),
          old.position.z,
        )
        ..yaw = old.yaw
        ..pitch = _fly ? -0.2 : 0;
    });
  }

  void _frame(double dt) {
    final w = _world, r = _rig;
    if (w == null || r == null) {
      return;
    }
    w.follow(r.camera);
    final p = _playing;
    if (p != null && p.finished) {
      setState(() {
        _playing = null;
        _rig = _makeRig(w);
        _rig!.camera
          ..position = p.camera.position.clone()
          ..yaw = p.camera.yaw
          ..pitch = p.camera.pitch;
      });
    }
  }

  // ---- Saving ----

  Future<void> _saveLandscape() async {
    final shell = Shell.of(context);
    final field = TextEditingController(text: _name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save landscape'),
        content: TextField(controller: field, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) {
      return;
    }
    _name = name;
    final locker = shell.locker;
    if (!locker.ready && !await locker.connect()) {
      return;
    }
    final json = {
      ..._s.toJson(),
      'path': pathToJson(_path),
      'seconds': _seconds,
    };
    await locker.save(
      type: AssetType.preset,
      name: name,
      bytes: utf8.encode(jsonEncode(json)),
      extension: 'json',
      tags: const ['vista', 'landscape'],
      extra: {'kind': LandSettings.kind, 'preset': _s.preset},
    );
    _snack('Saved "$name" to Presets');
  }

  Future<void> _openLandscape() async {
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
      types: const [AssetType.preset],
    );
    if (info == null) {
      return;
    }
    try {
      final j = jsonDecode(utf8.decode((await locker.read(info))!));
      final s = LandSettings.fromJson(j);
      setState(() {
        _name = info.name;
        _path = pathFromJson((j as Map)['path']);
        _seconds = ((j['seconds'] as num?) ?? 12).toDouble();
      });
      _change(s);
    } catch (e) {
      _snack('Not a Vista landscape: $e');
    }
  }

  Future<void> _exportHeightMap() async {
    final f = _field;
    if (f == null) {
      return;
    }
    final shell = Shell.of(context);
    final png = await runInBackground(_heightPng, f);
    final locker = shell.locker;
    if (!locker.ready && !await locker.connect()) {
      return;
    }
    await locker.save(
      type: AssetType.picture,
      name: '$_name height map',
      bytes: png,
      extension: 'png',
      tags: const ['vista', 'height map'],
      extra: {
        'heightMap': true,
        'maxHeight': LandSettings.maxHeight,
        'size': LandSettings.worldSize,
      },
    );
    _snack('Height map saved to Pictures');
  }

  // ---- Renders ----

  Future<void> _still(int w, int h) async {
    final rig = _rig, field = _field;
    if (rig == null || field == null) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StillPage(
          settings: _s,
          field: field,
          shot: shotOf(rig.camera),
          width: w,
          height: h,
          name: _name,
        ),
      ),
    );
  }

  void _play() {
    final w = _world;
    if (w == null || _path.keys.length < 2) {
      return;
    }
    setState(() => _playing = PathRig(_path, _seconds, ground: w.groundAt));
  }

  Future<void> _exportFlyover() async {
    final w = _world;
    if (w == null || _path.keys.length < 2) {
      return;
    }
    final shell = Shell.of(context);
    var progress = 0.0;
    var cancelled = false;
    StateSetter? update;
    final watch = Stopwatch()..start();
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => StatefulBuilder(
          builder: (context, set) {
            update = set;
            final left = progress > 0.02
                ? watch.elapsedMilliseconds / progress * (1 - progress) / 1000
                : null;
            return AlertDialog(
              title: Text(_rayFlyover ? 'Ray-traced flyover' : 'Flyover'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 8),
                  Text(
                    '${(progress * 100).round()}%${left == null ? '' : ' · about ${left < 90 ? '${left.round()} s' : '${(left / 60).round()} min'} left'}',
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => cancelled = true,
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        ),
      ),
    );
    File? file;
    String? error;
    try {
      final dir = await getTemporaryDirectory();
      file = await exportFlyover(
        world: w,
        path: _path,
        seconds: _seconds,
        basePath: '${dir.path}${Platform.pathSeparator}vista_flyover',
        rayTraced: _rayFlyover,
        options: _options,
        width: _rayFlyover ? 480 : 854,
        height: _rayFlyover ? 270 : 480,
        fps: _rayFlyover ? 15 : 30,
        progress: (p) {
          progress = p;
          update?.call(() {});
        },
        cancelled: () => cancelled,
      );
    } catch (e) {
      error = '$e';
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context, rootNavigator: true).pop();
    if (error != null) {
      _snack('Flyover failed: $error');
      return;
    }
    if (file == null) {
      return;
    }
    final bytes = await file.readAsBytes();
    final ext = file.path.split('.').last;
    if (!mounted) {
      return;
    }
    final how = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(
          'Flyover ready (${(bytes.length / 1048576).toStringAsFixed(1)} MB)',
        ),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'locker'),
            child: const Text('Save to Asset Locker (Videos)'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'share'),
            child: const Text('Export / share'),
          ),
        ],
      ),
    );
    if (how == 'locker') {
      final locker = shell.locker;
      if (!locker.ready && !await locker.connect()) {
        return;
      }
      await locker.save(
        type: AssetType.video,
        name: '$_name flyover',
        bytes: bytes,
        extension: ext,
        tags: const ['vista', 'flyover'],
      );
      _snack('Saved to Videos');
    } else if (how == 'share') {
      await shell.exporter.exportFile(
        'vista_flyover.$ext',
        bytes,
        mimeType: ext == 'mp4' ? 'video/mp4' : 'video/x-msvideo',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = _world, rig = _playing ?? _rig;
    final view = w == null || rig == null
        ? const ColoredBox(
            color: Color(0xFF101418),
            child: Center(child: CircularProgressIndicator()),
          )
        : Stack(
            children: [
              Positioned.fill(
                child: Viewport3D(
                  scene: w.scene,
                  rig: rig,
                  options: _options,
                  onFrame: _frame,
                  showStats: true,
                ),
              ),
              if (_busy)
                const Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: LinearProgressIndicator(),
                ),
              if (_playing != null)
                Positioned(
                  right: 12,
                  top: 8,
                  child: FilledButton.tonal(
                    onPressed: () => setState(() => _playing = null),
                    child: const Text('Stop'),
                  ),
                ),
            ],
          );
    final panel = DefaultTabController(
      length: 4,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Land'),
              Tab(text: 'Sky'),
              Tab(text: 'Render'),
              Tab(text: 'Flyover'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [_landTab(), _skyTab(), _renderTab(), _flyoverTab()],
            ),
          ),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text('Vista · $_name', overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: _fly ? 'Walk on the ground' : 'Fly',
            icon: Icon(_fly ? Icons.directions_walk : Icons.flight),
            onPressed: w == null ? null : _toggleWalk,
          ),
          PopupMenuButton<String>(
            onSelected: (v) => switch (v) {
              'save' => _saveLandscape(),
              'open' => _openLandscape(),
              _ => _exportHeightMap(),
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'save', child: Text('Save landscape')),
              PopupMenuItem(value: 'open', child: Text('Open landscape')),
              PopupMenuItem(
                value: 'height',
                child: Text('Save height map (picture)'),
              ),
            ],
          ),
          ...shellActions(context),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            if (box.maxWidth >= 900) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: view),
                  SizedBox(
                    width: 380,
                    child: Material(
                      color: Theme.of(context).colorScheme.surface,
                      child: panel,
                    ),
                  ),
                ],
              );
            }
            return Column(
              children: [
                Expanded(child: view),
                SizedBox(
                  height: math.min(330, box.maxHeight * 0.45),
                  child: Material(
                    color: Theme.of(context).colorScheme.surface,
                    child: panel,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _slider(
    String label,
    double v,
    ValueChanged<double> onEnd, {
    double min = 0,
    double max = 1,
    String? text,
  }) => _LiveSlider(
    label: label,
    value: v,
    min: min,
    max: max,
    text: text,
    onEnd: onEnd,
  );

  Widget _landTab() => ListView(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
    children: [
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final e in presets.entries)
            ChoiceChip(
              label: Text(e.value.$1),
              selected: _s.preset == e.key,
              onSelected: (_) {
                _name = e.value.$1;
                _change(e.value.$2.copyWith(seed: _s.seed));
              },
            ),
        ],
      ),
      Row(
        children: [
          Text('Seed ${_s.seed}'),
          const Spacer(),
          TextButton.icon(
            onPressed: () =>
                _change(_s.copyWith(seed: math.Random().nextInt(999999) + 1)),
            icon: const Icon(Icons.casino_outlined),
            label: const Text('New land'),
          ),
        ],
      ),
      _slider('Height', _s.height, (v) => _change(_s.copyWith(height: v))),
      _slider(
        'Roughness',
        _s.roughness,
        (v) => _change(_s.copyWith(roughness: v)),
      ),
      _slider('Ridges', _s.ridges, (v) => _change(_s.copyWith(ridges: v))),
      _slider('Erosion', _s.erosion, (v) => _change(_s.copyWith(erosion: v))),
      if (_s.water)
        _slider(
          'Sea level',
          _s.seaLevel,
          (v) => _change(_s.copyWith(seaLevel: v), regen: false),
          max: 0.7,
        ),
      const SizedBox(height: 6),
      Row(
        children: [
          for (final (label, c, set) in [
            ('Sand', _s.sand, (int v) => _s.copyWith(sand: v)),
            ('Grass', _s.grass, (int v) => _s.copyWith(grass: v)),
            ('Rock', _s.rock, (int v) => _s.copyWith(rock: v)),
            ('Snow', _s.snow, (int v) => _s.copyWith(snow: v)),
          ])
            Expanded(
              child: InkWell(
                onTap: () async {
                  final pick = await showDialog<int>(
                    context: context,
                    builder: (context) => SimpleDialog(
                      title: Text(label),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final p in _palette)
                                InkWell(
                                  onTap: () => Navigator.pop(context, p),
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    color: Color(p),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                  if (pick != null) {
                    _change(set(pick), regen: false);
                  }
                },
                child: Column(
                  children: [
                    Container(
                      height: 22,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: Color(c),
                    ),
                    Text(label, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
        ],
      ),
    ],
  );

  String _clock(double t) {
    final h = t.floor() % 24, m = ((t - t.floor()) * 60).round() % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  Widget _skyTab() => ListView(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
    children: [
      _slider(
        'Time',
        _s.time,
        (v) => _change(_s.copyWith(time: v), regen: false),
        max: 24,
        text: _clock(_s.time),
      ),
      _slider(
        'Sun from',
        _s.sunTurn,
        (v) => _change(_s.copyWith(sunTurn: v), regen: false),
      ),
      if (_s.preset != 'moon')
        _slider(
          'Clouds',
          _s.clouds,
          (v) => _change(_s.copyWith(clouds: v), regen: false),
        ),
      if (_s.preset != 'moon')
        _slider(
          'Haze',
          _s.haze,
          (v) => _change(_s.copyWith(haze: v), regen: false),
        ),
      const Divider(),
      Text('Explorer look', style: Theme.of(context).textTheme.labelLarge),
      Wrap(
        spacing: 6,
        children: [
          ChoiceChip(
            label: const Text('PS1'),
            selected: _options.lowRes > 0,
            onSelected: (_) => setState(
              () => _options = const RenderOptions(drawDistance: 600),
            ),
          ),
          ChoiceChip(
            label: const Text('Clean'),
            selected: _options.lowRes == 0,
            onSelected: (_) => setState(
              () => _options = RenderOptions.clean.copyWith(drawDistance: 600),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _renderTab() => ListView(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
    children: [
      const Text(
        'Ray-traced still of the current view: real shadows, water reflections, haze and clouds. It sharpens as it goes.',
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (w, h) in const [(640, 360), (1280, 720), (1920, 1080)])
            FilledButton.tonal(
              onPressed: _world == null ? null : () => _still(w, h),
              child: Text('$w × $h'),
            ),
        ],
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _field == null ? null : _exportHeightMap,
        icon: const Icon(Icons.terrain),
        label: const Text('Save height map (picture)'),
      ),
    ],
  );

  Widget _flyoverTab() => ListView(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
    children: [
      Text(
        '${_path.keys.length} camera point${_path.keys.length == 1 ? '' : 's'}. Fly to a view and add it; the camera glides through them in order.',
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.tonalIcon(
            onPressed: _rig == null
                ? null
                : () => setState(() => _path.keys.add(shotOf(_rig!.camera))),
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Add this view'),
          ),
          OutlinedButton(
            onPressed: _path.keys.isEmpty
                ? null
                : () => setState(() => _path.keys.removeLast()),
            child: const Text('Undo'),
          ),
          OutlinedButton(
            onPressed: _path.keys.isEmpty
                ? null
                : () => setState(() => _path.keys.clear()),
            child: const Text('Clear'),
          ),
        ],
      ),
      _slider(
        'Length',
        _seconds,
        (v) => setState(() => _seconds = v.roundToDouble()),
        min: 4,
        max: 30,
        text: '${_seconds.round()} s',
      ),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('Fast (854×480)')),
          ButtonSegment(value: true, label: Text('Ray-traced (480×270)')),
        ],
        selected: {_rayFlyover},
        showSelectedIcon: false,
        onSelectionChanged: (v) => setState(() => _rayFlyover = v.first),
      ),
      if (_rayFlyover)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Slow: every frame is ray traced (15 fps). Can take many minutes on a phone.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _path.keys.length < 2 ? null : _play,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Preview'),
          ),
          FilledButton.icon(
            onPressed: _path.keys.length < 2 ? null : _exportFlyover,
            icon: const Icon(Icons.movie_creation_outlined),
            label: const Text('Make video'),
          ),
        ],
      ),
    ],
  );
}

/// A slider that shows its value while dragging and reports on release.
class _LiveSlider extends StatefulWidget {
  const _LiveSlider({
    required this.label,
    required this.value,
    required this.onEnd,
    this.min = 0,
    this.max = 1,
    this.text,
  });
  final String label;
  final double value, min, max;
  final String? text;
  final ValueChanged<double> onEnd;

  @override
  State<_LiveSlider> createState() => _LiveSliderState();
}

class _LiveSliderState extends State<_LiveSlider> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final v = (_drag ?? widget.value).clamp(widget.min, widget.max);
    return Row(
      children: [
        SizedBox(width: 84, child: Text(widget.label)),
        Expanded(
          child: Slider(
            value: v,
            min: widget.min,
            max: widget.max,
            onChanged: (x) => setState(() => _drag = x),
            onChangeEnd: (x) {
              setState(() => _drag = null);
              widget.onEnd(x);
            },
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(
            widget.text ??
                '${((v - widget.min) / (widget.max - widget.min) * 100).round()}%',
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
