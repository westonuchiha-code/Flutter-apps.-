import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:app_shell/app_shell.dart';
import 'package:engine3d/engine3d.dart';
import 'package:material_ui/material_ui.dart' hide Action;
import 'package:path_provider/path_provider.dart';

import '../cast.dart';
import '../export.dart';
import '../movie.dart';
import '../moves.dart';
import '../sets.dart';

const _palette = [
  0xFFF0C8A8, 0xFFE0B090, 0xFFC89070, 0xFFA06A48, 0xFF7A4A30, 0xFF4A2E20, //
  0xFF1E1612, 0xFF7A3A22, 0xFFE0B040, 0xFFD8D8D8, 0xFFC0485A, 0xFF3E6AB0,
  0xFF4EA05A, 0xFFE07AB0, 0xFF6A4AA0, 0xFF2E3440, 0xFFE8E0D0, 0xFFE8A030,
];

const _jointLabels = {
  'head': 'Head',
  'neck': 'Neck',
  'chest': 'Chest',
  'spine': 'Waist',
  'hips': 'Hips',
  'upperArmL': 'L arm',
  'lowerArmL': 'L forearm',
  'handL': 'L hand',
  'upperArmR': 'R arm',
  'lowerArmR': 'R forearm',
  'handR': 'R hand',
  'upperLegL': 'L thigh',
  'lowerLegL': 'L shin',
  'footL': 'L foot',
  'upperLegR': 'R thigh',
  'lowerLegR': 'R shin',
  'footR': 'R foot',
};

/// Plays camera shots.
class _ShotRig extends CameraRig {
  @override
  final camera = Camera();
  @override
  void drag(double dx, double dy) {}
  @override
  void zoom(double factor) {}
  @override
  void move(double forward, double strafe, double dt) {}
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.movie});

  /// For tests and screenshots.
  final Movie? movie;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Movie _movie = widget.movie ?? _starter();
  Scene? _scene;
  final _actors = <String, (Character, Map<String, AnimationClip>)>{};
  final _orbit = OrbitRig(
    target: Vector3(0, 1, 0),
    distance: 8,
    yaw: 0,
    pitch: -0.25,
  );
  final _shotRig = _ShotRig();
  double _t = 0;
  bool _playing = false, _useShots = true, _clean = false;
  String? _selected;

  /// Waiting for a tap on the floor: 'walk', 'run' or 'place'.
  String? _pending;

  // Stop-motion pose being edited (for the selected actor).
  Pose? _pose;
  String _joint = 'upperArmR';
  double _frame = 0.25;
  int _tab = 0;
  bool _busy = false;

  static Movie _starter() => Movie(
    actors: [
      Actor(
        kind: Kind.woman,
        name: 'Ann',
        x: -1,
        z: 0,
        actions: [Action(ActionType.move, move: 'wave', seconds: 2.4)],
      ),
      Actor(
        kind: Kind.man,
        name: 'Ben',
        x: 1.2,
        z: -0.5,
        facing: -20,
        actions: [Action(ActionType.move, move: 'talk', seconds: 3)],
      ),
    ],
  );

  @override
  void initState() {
    super.initState();
    _selected = _movie.actors.isEmpty ? null : _movie.actors.first.id;
    unawaited(_rebuild());
  }

  void _snack(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Actor? get _actor =>
      _movie.actors.where((a) => a.id == _selected).firstOrNull;

  /// Rebuilds the set and the cast's figures.
  Future<void> _rebuild() async {
    final scene = await buildSet(_movie.set);
    _actors.clear();
    for (final a in _movie.actors) {
      final c = buildCharacter(a.kind, a.look);
      _actors[a.id] = (c, clipsFor(c));
      scene.root.add(c.root);
    }
    if (!mounted) {
      return;
    }
    setState(() => _scene = scene);
    _poseAll(_t);
  }

  void _poseAll(double t) {
    for (final a in _movie.actors) {
      final entry = _actors[a.id];
      if (entry == null) {
        continue;
      }
      applyState(entry.$1, entry.$2, stateAt(a, t));
    }
    final p = _pose, sel = _actors[_selected];
    if (p != null && sel != null && !_playing) {
      // Show the pose being edited.
      final c = sel.$1;
      restPose(c);
      p.forEach((name, e) {
        final r = c.rest[name] ?? (0.0, 0.0, 0.0);
        c.joints[name]?.rotation = euler(r.$1 + e.$1, r.$2 + e.$2, r.$3 + e.$3);
      });
    }
  }

  void _frameTick(double dt) {
    if (_playing) {
      _t += dt;
      if (_t >= _movie.duration) {
        _t = _movie.duration;
        _playing = false;
      }
      setState(() {});
    }
    _poseAll(_t);
    final shot = _useShots && (_playing || _tab == 2)
        ? _movie.shotAt(_t)
        : null;
    if (shot != null) {
      applyShot(_shotRig.camera, shot);
    }
  }

  CameraRig get _rig =>
      _useShots && (_playing || _tab == 2) && _movie.shotAt(_t) != null
      ? _shotRig
      : _orbit;

  void _onTap(Offset p, Size size) {
    final cam = _rig.camera;
    final g = groundPoint(cam, size.width, size.height, p.dx, p.dy);
    if (g == null) {
      return;
    }
    final a = _actor;
    final pending = _pending;
    if (pending != null && a != null) {
      setState(() {
        if (pending == 'place') {
          a
            ..x = g.x
            ..z = g.z;
        } else {
          a.actions.add(
            Action(
              pending == 'run' ? ActionType.run : ActionType.walk,
              x: g.x,
              z: g.z,
            ),
          );
        }
        _pending = null;
      });
      return;
    }
    // Select the nearest actor to the tap.
    String? best;
    var bestD = 1.2;
    for (final act in _movie.actors) {
      final s = stateAt(act, _t);
      final d = math.sqrt(math.pow(s.x - g.x, 2) + math.pow(s.z - g.z, 2));
      if (d < bestD) {
        bestD = d;
        best = act.id;
      }
    }
    if (best != null) {
      setState(() => _selected = best);
    }
  }

  // ---- Files ----

  Future<void> _save() async {
    final shell = Shell.of(context);
    final field = TextEditingController(text: _movie.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save movie'),
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
    setState(() => _movie.name = name);
    final locker = shell.locker;
    if (!locker.ready && !await locker.connect()) {
      return;
    }
    await locker.save(
      type: AssetType.preset,
      name: name,
      bytes: utf8.encode(jsonEncode(_movie.toJson())),
      extension: 'json',
      tags: const ['puppet stage', 'movie'],
      extra: {'kind': Movie.kind},
    );
    _snack('Saved "$name" to Presets');
  }

  Future<void> _open() async {
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
      final m = Movie.fromJson(
        jsonDecode(utf8.decode((await locker.read(info))!)),
      );
      setState(() {
        _movie = m;
        _t = 0;
        _selected = m.actors.isEmpty ? null : m.actors.first.id;
        _pose = null;
      });
      await _rebuild();
    } catch (e) {
      _snack('Not a Puppet Stage movie: $e');
    }
  }

  Future<void> _export() async {
    final scene = _scene;
    if (scene == null) {
      return;
    }
    final shell = Shell.of(context);
    setState(() {
      _playing = false;
      _pose = null;
      _busy = true;
    });
    var progress = 0.0, cancelled = false;
    StateSetter? update;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => StatefulBuilder(
          builder: (context, set) {
            update = set;
            return AlertDialog(
              title: const Text('Making the video'),
              content: LinearProgressIndicator(value: progress),
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
      file = await exportMovie(
        movie: _movie,
        scene: scene,
        pose: _poseAll,
        fallbackCamera: _orbit.camera,
        options: _clean ? RenderOptions.clean : const RenderOptions(),
        basePath: '${dir.path}${Platform.pathSeparator}puppet_movie',
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
    setState(() => _busy = false);
    if (error != null) {
      _snack('Could not make the video: $error');
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
          'Video ready (${(bytes.length / 1048576).toStringAsFixed(1)} MB)',
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
        name: _movie.name,
        bytes: bytes,
        extension: ext,
        tags: const ['puppet stage'],
      );
      _snack('Saved to Videos');
    } else if (how == 'share') {
      await shell.exporter.exportFile(
        'puppet_movie.$ext',
        bytes,
        mimeType: ext == 'mp4' ? 'video/mp4' : 'video/x-msvideo',
      );
    }
  }

  // ---- Building ----

  @override
  Widget build(BuildContext context) {
    final scene = _scene;
    final d = _movie.duration;
    final view = scene == null
        ? const ColoredBox(
            color: Color(0xFF15171C),
            child: Center(child: CircularProgressIndicator()),
          )
        : Stack(
            children: [
              Positioned.fill(
                child: Viewport3D(
                  scene: scene,
                  rig: _rig,
                  options: _clean ? RenderOptions.clean : const RenderOptions(),
                  onFrame: _frameTick,
                  onTap: _onTap,
                  joystick: false,
                ),
              ),
              if (_pending != null)
                Positioned(
                  left: 12,
                  right: 12,
                  top: 8,
                  child: Material(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _pending == 'place'
                                  ? 'Tap the floor where they stand'
                                  : 'Tap the floor where they ${_pending == 'run' ? 'run' : 'walk'} to',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(() => _pending = null),
                            child: const Text('Cancel'),
                          ),
                        ],
                      ),
                    ),
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
    final transport = Row(
      children: [
        IconButton(
          tooltip: _playing ? 'Pause' : 'Play',
          icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
          onPressed: () => setState(() {
            if (!_playing && _t >= d - 0.01) {
              _t = 0;
            }
            _pose = null;
            _playing = !_playing;
          }),
        ),
        Expanded(
          child: Slider(
            value: _t.clamp(0, d),
            max: d,
            onChanged: (v) => setState(() {
              _playing = false;
              _t = v;
            }),
          ),
        ),
        Text('${_t.toStringAsFixed(1)} / ${d.toStringAsFixed(1)} s'),
        const SizedBox(width: 8),
      ],
    );
    final panel = DefaultTabController(
      length: 4,
      child: Builder(
        builder: (context) {
          final tc = DefaultTabController.of(context);
          tc.addListener(() {
            if (_tab != tc.index) {
              setState(() {
                _tab = tc.index;
                if (_tab != 3) {
                  _pose = null;
                }
              });
            }
          });
          return Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(text: 'Cast'),
                  Tab(text: 'Actions'),
                  Tab(text: 'Camera'),
                  Tab(text: 'Pose'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _castTab(),
                    _actionsTab(),
                    _cameraTab(),
                    _poseTab(),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(_movie.name, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<StageSet>(
            tooltip: 'Set',
            icon: const Icon(Icons.landscape_outlined),
            onSelected: (s) {
              setState(() => _movie.set = s);
              unawaited(_rebuild());
            },
            itemBuilder: (context) => [
              for (final s in StageSet.values)
                CheckedPopupMenuItem(
                  value: s,
                  checked: s == _movie.set,
                  child: Text(s.label),
                ),
            ],
          ),
          IconButton(
            tooltip: 'Make video',
            icon: const Icon(Icons.movie_creation_outlined),
            onPressed: _busy ? null : _export,
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'save':
                  await _save();
                case 'open':
                  await _open();
                case 'clean':
                  setState(() => _clean = !_clean);
                case 'new':
                  setState(() {
                    _movie = Movie();
                    _t = 0;
                    _selected = null;
                    _pose = null;
                  });
                  await _rebuild();
              }
            },
            itemBuilder: (context) => [
              CheckedPopupMenuItem(
                value: 'clean',
                checked: _clean,
                child: const Text('Clean look'),
              ),
              const PopupMenuItem(value: 'save', child: Text('Save movie')),
              const PopupMenuItem(value: 'open', child: Text('Open movie')),
              const PopupMenuItem(value: 'new', child: Text('New movie')),
            ],
          ),
          ...shellActions(context),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            final surface = Theme.of(context).colorScheme.surface;
            if (box.maxWidth >= 900) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(child: view),
                        transport,
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 400,
                    child: Material(color: surface, child: panel),
                  ),
                ],
              );
            }
            return Column(
              children: [
                Expanded(child: view),
                transport,
                SizedBox(
                  height: math.min(320, box.maxHeight * 0.42),
                  child: Material(color: surface, child: panel),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _castTab() {
    final a = _actor;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final k in Kind.values)
              ActionChip(
                avatar: const Icon(Icons.add, size: 16),
                label: Text(k.label),
                onPressed: () async {
                  final n = _movie.actors.length;
                  final actor = Actor(
                    kind: k,
                    name: '${k.label} ${n + 1}',
                    x: (n % 4 - 1.5) * 1.2,
                    z: n ~/ 4 * -1.2,
                  );
                  setState(() {
                    _movie.actors.add(actor);
                    _selected = actor.id;
                  });
                  await _rebuild();
                },
              ),
          ],
        ),
        const Divider(),
        for (final act in _movie.actors)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            selected: act.id == _selected,
            leading: CircleAvatar(
              radius: 12,
              backgroundColor: Color(act.look.top),
            ),
            title: Text(act.name),
            subtitle: Text(
              '${act.kind.label} · ${act.actions.length} action${act.actions.length == 1 ? '' : 's'}',
            ),
            onTap: () => setState(() => _selected = act.id),
            trailing: IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                setState(() {
                  _movie.actors.remove(act);
                  if (_selected == act.id) {
                    _selected = _movie.actors.isEmpty
                        ? null
                        : _movie.actors.first.id;
                  }
                });
                await _rebuild();
              },
            ),
          ),
        if (a != null) ...[
          const Divider(),
          Row(
            children: [
              Expanded(
                child: Text(
                  a.name,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              TextButton(
                onPressed: () => _rename(a),
                child: const Text('Rename'),
              ),
              TextButton(
                onPressed: () => setState(() => _pending = 'place'),
                child: const Text('Place'),
              ),
            ],
          ),
          Row(
            children: [
              const SizedBox(width: 70, child: Text('Facing')),
              Expanded(
                child: Slider(
                  value: (a.facing % 360 + 360) % 360,
                  max: 359,
                  onChanged: (v) => setState(() => a.facing = v),
                ),
              ),
            ],
          ),
          for (final (label, get, set) in [
            (
              'Skin',
              (Look l) => l.skin,
              (Look l, int c) => l.copyWith(skin: c),
            ),
            (
              'Hair',
              (Look l) => l.hair,
              (Look l, int c) => l.copyWith(hair: c),
            ),
            ('Top', (Look l) => l.top, (Look l, int c) => l.copyWith(top: c)),
            (
              'Bottom',
              (Look l) => l.bottom,
              (Look l, int c) => l.copyWith(bottom: c),
            ),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(width: 70, child: Text(label)),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final c in _palette)
                            InkWell(
                              onTap: () async {
                                setState(() => a.look = set(a.look, c));
                                await _rebuild();
                              },
                              child: Container(
                                width: 24,
                                height: 24,
                                margin: const EdgeInsets.only(right: 3),
                                decoration: BoxDecoration(
                                  color: Color(c),
                                  border: Border.all(
                                    color: get(a.look) == c
                                        ? Colors.white
                                        : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _rename(Actor a) async {
    final field = TextEditingController(text: a.name);
    final n = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Name'),
        content: TextField(controller: field, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (n != null && n.isNotEmpty) {
      setState(() => a.name = n);
    }
  }

  Widget _actionsTab() {
    final a = _actor;
    if (a == null) {
      return const Center(child: Text('Add someone in Cast first.'));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      children: [
        Text(
          '${a.name} does, in order:',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        for (var i = 0; i < a.actions.length; i++)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Text('${i + 1}'),
            title: Text(a.actions[i].describe()),
            onTap: () => _editAction(a, a.actions[i]),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (i > 0)
                  IconButton(
                    tooltip: 'Earlier',
                    icon: const Icon(Icons.arrow_upward, size: 18),
                    onPressed: () => setState(
                      () => a.actions.insert(i - 1, a.actions.removeAt(i)),
                    ),
                  ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => a.actions.removeAt(i)),
                ),
              ],
            ),
          ),
        const Divider(),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            FilledButton.tonalIcon(
              onPressed: () => setState(() => _pending = 'walk'),
              icon: const Icon(Icons.directions_walk, size: 18),
              label: const Text('Walk to'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => setState(() => _pending = 'run'),
              icon: const Icon(Icons.directions_run, size: 18),
              label: const Text('Run to'),
            ),
            OutlinedButton(
              onPressed: () => setState(
                () => a.actions.add(Action(ActionType.turn, angle: 90)),
              ),
              child: const Text('Turn left'),
            ),
            OutlinedButton(
              onPressed: () => setState(
                () => a.actions.add(Action(ActionType.turn, angle: -90)),
              ),
              child: const Text('Turn right'),
            ),
            OutlinedButton(
              onPressed: () => setState(
                () => a.actions.add(Action(ActionType.wait, seconds: 1)),
              ),
              child: const Text('Wait'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('Moves', style: Theme.of(context).textTheme.labelLarge),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final m in moves.where((m) => m.id != 'walk' && m.id != 'run'))
              ActionChip(
                label: Text(m.label),
                onPressed: () => setState(
                  () => a.actions.add(
                    Action(
                      ActionType.move,
                      move: m.id,
                      seconds: m.loop ? m.duration * 2 : m.duration + 0.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _editAction(Actor a, Action act) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, set) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                act.describe(),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (act.type == ActionType.turn)
                Slider(
                  value: act.angle.clamp(-180, 180),
                  min: -180,
                  max: 180,
                  divisions: 24,
                  label: '${act.angle.round()}°',
                  onChanged: (v) {
                    set(() => act.angle = v);
                    setState(() {});
                  },
                )
              else if (act.type != ActionType.walk &&
                  act.type != ActionType.run)
                Slider(
                  value: act.seconds.clamp(0.05, 20),
                  min: 0.05,
                  max: 20,
                  label: '${act.seconds.toStringAsFixed(1)} s',
                  divisions: 399,
                  onChanged: (v) {
                    set(() => act.seconds = v);
                    setState(() {});
                  },
                )
              else
                const Text(
                  'Tap "Walk to" / "Run to" again to add another route.',
                ),
              TextButton(
                onPressed: () {
                  setState(
                    () => a.actions.insert(
                      a.actions.indexOf(act) + 1,
                      act.copy(),
                    ),
                  );
                  Navigator.pop(context);
                },
                child: const Text('Duplicate'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _cameraTab() => ListView(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
    children: [
      const Text(
        'Move the camera (drag to turn, pinch to zoom), then save the angle as a shot at the current time. Playback cuts between shots.',
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Use shots when playing'),
        value: _useShots,
        onChanged: (v) => setState(() => _useShots = v),
      ),
      FilledButton.tonalIcon(
        onPressed: () {
          final c = _orbit.camera;
          setState(() {
            _movie.shots.removeWhere((s) => (s.time - _t).abs() < 0.05);
            _movie.shots.add(
              Shot(
                _t,
                c.position.x,
                c.position.y,
                c.position.z,
                c.yaw,
                c.pitch,
                fov: c.fov,
              ),
            );
            _movie.shots.sort((a, b) => a.time.compareTo(b.time));
          });
        },
        icon: const Icon(Icons.videocam_outlined),
        label: Text('Shot at ${_t.toStringAsFixed(1)} s'),
      ),
      for (final s in _movie.shots)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.videocam_outlined),
          title: Text('From ${s.time.toStringAsFixed(1)} s'),
          onTap: () => setState(() => _t = s.time),
          trailing: IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _movie.shots.remove(s)),
          ),
        ),
    ],
  );

  Widget _poseTab() {
    final a = _actor, entry = _actors[_selected];
    if (a == null || entry == null) {
      return const Center(child: Text('Add someone in Cast first.'));
    }
    final pose = _pose;
    if (pose == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        children: [
          const Text(
            'Stop motion: pose a joint at a time, add the pose as a frame, change it a little, add again. '
            'Frames play one after another.',
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => setState(() {
              _playing = false;
              _pose = poseOf(entry.$1);
            }),
            icon: const Icon(Icons.accessibility_new),
            label: Text('Start posing ${a.name}'),
          ),
        ],
      );
    }
    final e = pose[_joint] ?? (0.0, 0.0, 0.0);
    void setAngle(int axis, double v) => setState(() {
      final n = [e.$1, e.$2, e.$3]..[axis] = v;
      pose[_joint] = (n[0], n[1], n[2]);
    });
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      children: [
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final j in _jointLabels.entries)
              ChoiceChip(
                label: Text(j.value),
                selected: _joint == j.key,
                onSelected: (_) => setState(() => _joint = j.key),
              ),
          ],
        ),
        for (final (axis, label) in [(0, 'Bend'), (1, 'Twist'), (2, 'Tilt')])
          Row(
            children: [
              SizedBox(width: 56, child: Text(label)),
              Expanded(
                child: Slider(
                  value: [e.$1, e.$2, e.$3][axis].clamp(-180, 180),
                  min: -180,
                  max: 180,
                  onChanged: (v) => setAngle(axis, v),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  '${[e.$1, e.$2, e.$3][axis].round()}°',
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        Row(
          children: [
            const SizedBox(width: 56, child: Text('Frame')),
            Expanded(
              child: Slider(
                value: _frame,
                min: 0.04,
                max: 1,
                onChanged: (v) => setState(() => _frame = v),
              ),
            ),
            SizedBox(
              width: 44,
              child: Text(
                '${_frame.toStringAsFixed(2)} s',
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => setState(() {
                a.actions.add(
                  Action(ActionType.pose, seconds: _frame, pose: Map.of(pose)),
                );
                _t = plan(a).last.start;
              }),
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Add frame'),
            ),
            OutlinedButton(
              onPressed: () => setState(() => pose.remove(_joint)),
              child: const Text('Reset joint'),
            ),
            TextButton(
              onPressed: () => setState(() => _pose = null),
              child: const Text('Done'),
            ),
          ],
        ),
      ],
    );
  }
}
