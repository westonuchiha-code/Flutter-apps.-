import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:app_shell/app_shell.dart';
import 'package:audio_kit/audio_kit.dart' show ClipPlayer;
import 'package:engine3d/engine3d.dart';
import 'package:landscape/landscape.dart' as land;
import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart' hide Action;
import 'package:path_provider/path_provider.dart';

import '../animals.dart';
import '../cast.dart';
import '../export.dart';
import '../figure.dart';
import '../look.dart';
import '../movie.dart';
import '../props.dart';
import '../moves.dart';
import '../places.dart';
import '../staging.dart';
import '../sets.dart';

const _palette = [
  0xFFF0C8A8, 0xFFE0B090, 0xFFC89070, 0xFFA06A48, 0xFF7A4A30, 0xFF4A2E20, //
  0xFF1E1612, 0xFF7A3A22, 0xFFE0B040, 0xFFD8D8D8, 0xFFC0485A, 0xFF3E6AB0,
  0xFF4EA05A, 0xFFE07AB0, 0xFF6A4AA0, 0xFF2E3440, 0xFFE8E0D0, 0xFFE8A030,
  0xFFF2F0EA, 0xFFF0AAB4, 0xFFC08A50, 0xFF8A5432, 0xFF8A8A92, 0xFF2A2420,
  0xFFD83A30, 0xFFE8B030, 0xFF4A7AC8,
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
  // Animals.
  'tail': 'Tail',
  'legFL': 'Front L leg',
  'shinFL': 'Front L shin',
  'legFR': 'Front R leg',
  'shinFR': 'Front R shin',
  'legBL': 'Back L leg',
  'shinBL': 'Back L shin',
  'legBR': 'Back R leg',
  'shinBR': 'Back R shin',
  'wingL': 'L wing',
  'wingR': 'R wing',
  'legL': 'L leg',
  'legR': 'R leg',
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
  final _places = <int, BuiltPlace>{};
  final _placeKeys = <int, String>{};

  /// The place shown while editing (shots pick their own when playing).
  int _view = 0;
  ClipPlayer? _player;
  String? _musicLoaded;
  final _actors = <String, Figure>{};

  /// What each figure was built from (rebuilt only when that changes).
  final _built = <String, String>{};
  final _modelBytes = <String, Uint8List>{};
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

  Shot? get _shotNow =>
      _useShots && (_playing || _tab == 2) ? _movie.shotAt(_t) : null;

  int get _shownPlace =>
      (_shotNow?.place ?? _view).clamp(0, _movie.placeCount - 1);

  Scene? get _scene => _places[_shownPlace]?.scene;

  FilmLook get _lookNow => _shotNow?.look ?? _movie.look;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

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
    final count = _movie.placeCount;
    for (var i = 0; i < count; i++) {
      final place = _movie.placeAt(i);
      final key = jsonEncode(place.toJson());
      if (_placeKeys[i] != key || _places[i] == null) {
        if (place.land != null) setState(() => _busy = true);
        try {
          _places[i] = await buildPlace(place);
        } catch (e) {
          _places[i] = BuiltPlace(await buildSet(StageSet.studio));
          if (mounted) _snack('Could not build ${place.label}: $e');
        }
        _placeKeys[i] = key;
        if (mounted) setState(() => _busy = false);
      }
    }
    _places.removeWhere((i, _) => i >= count);
    _placeKeys.removeWhere((i, _) => i >= count);
    final oldRoots = {for (final f in _actors.values) f.root};
    final ids = {for (final a in _movie.actors) a.id};
    _actors.removeWhere((id, _) => !ids.contains(id));
    for (final a in _movie.actors) {
      final key = jsonEncode([
        a.kind.name,
        a.animal?.name,
        a.prop?.name,
        a.body.toJson(),
        [for (final e in a.extras) e.name]..sort(),
        a.scale,
        a.look.toJson(),
        a.model?.toJson(),
        a.size,
        a.turn,
        a.ownWalk,
      ]);
      if (_built[a.id] != key || _actors[a.id] == null) {
        _actors[a.id] = await _figureFor(a);
        _built[a.id] = key;
      }
      _actors[a.id]!.hold(a.holds);
    }
    final roots = {...oldRoots, for (final f in _actors.values) f.root};
    for (final pl in _places.values) {
      pl.scene.root.children.removeWhere(roots.contains);
    }
    for (final a in _movie.actors) {
      _places[a.place.clamp(0, count - 1)]?.scene.root.add(_actors[a.id]!.root);
    }
    if (!mounted) {
      return;
    }
    setState(() {});
    _poseAll(_t);
  }

  Future<Figure> _figureFor(Actor a) async {
    final ref = a.model;
    if (ref != null) {
      try {
        var bytes = _modelBytes[ref.id];
        if (bytes == null) {
          final locker = Shell.of(context).locker;
          if (locker.ready || await locker.connect()) {
            bytes = await locker.read(
              AssetInfo(
                id: ref.id,
                type: AssetType.model,
                name: ref.name,
                extension: ref.extension,
                app: '',
                created: DateTime(2000),
              ),
            );
          }
        }
        if (bytes != null) {
          _modelBytes[ref.id] = bytes;
          return await loadModelFigure(
            bytes,
            ref.extension,
            height: a.size,
            turn: a.turn,
            ownWalk: a.ownWalk,
            name: ref.name,
          );
        }
        _snack('"${ref.name}" is not in the Asset Locker any more');
      } catch (e) {
        _snack('Could not load "${ref.name}": $e');
      }
      // Stand-in so the movie still opens.
      return BuiltFigure(
        buildCharacter(
          Kind.man,
          const Look(
            skin: 0xFF9A9A9A,
            hair: 0xFF6A6A6A,
            top: 0xFF8A8A8A,
            bottom: 0xFF6A6A6A,
          ),
        ),
      );
    }
    return builtFigure(a);
  }

  /// The name of a move for [a]'s figure.
  String? _moveLabel(Actor a, String id) {
    for (final m in _actors[a.id]?.moves ?? const <MoveChoice>[]) {
      if (m.id == id) return m.label;
    }
    return null;
  }

  void _poseAll(double t) {
    for (final a in _movie.actors) {
      final fig = _actors[a.id];
      if (fig == null) {
        continue;
      }
      final st = stateAt(a, t);
      final p = _pose;
      final ground =
          _places[a.place.clamp(0, _movie.placeCount - 1)]?.ground(
            st.x,
            st.z,
          ) ??
          0;
      if (p != null && a.id == _selected && !_playing) {
        // Show the pose being edited.
        fig.show(
          ActorState(st.x, st.z, st.facing, 'idle', 0, pose: p),
          groundY: ground,
          now: t,
        );
      } else {
        fig.show(st, groundY: ground, now: t);
      }
    }
  }

  void _frameTick(double dt) {
    if (_playing) {
      _t += dt;
      if (_t >= _movie.duration) {
        _t = _movie.duration;
        _playing = false;
        unawaited(_player?.stop());
      }
      setState(() {});
    }
    _poseAll(_t);
    if (_shotNow != null) {
      cameraAt(_movie, _t, _shotRig.camera);
    }
    _places[_shownPlace]?.follow(_rig.camera);
  }

  /// Starts or stops playback (with the music).
  Future<void> _playPause() async {
    final d = _movie.duration;
    setState(() {
      if (!_playing && _t >= d - 0.01) {
        _t = 0;
      }
      _pose = null;
      _playing = !_playing;
    });
    final m = _movie.music;
    if (!_playing || m == null) {
      await _player?.stop();
      return;
    }
    try {
      final player = _player ??= ClipPlayer();
      if (_musicLoaded != m.id) {
        final bytes = await _readMusic(m);
        if (bytes == null) return;
        final dir = await getTemporaryDirectory();
        final f = File(
          '${dir.path}${Platform.pathSeparator}puppet_music.${m.extension}',
        );
        await f.writeAsBytes(bytes, flush: true);
        await player.load(f);
        _musicLoaded = m.id;
      }
      if (_playing) await player.play(from: m.start + _t);
    } catch (_) {
      // The picture still plays without sound.
    }
  }

  Future<Uint8List?> _readMusic(MusicRef m) async {
    final locker = Shell.of(context).locker;
    if (!locker.ready && !await locker.connect()) return null;
    for (final type in const [
      AssetType.sample,
      AssetType.recording,
      AssetType.other,
    ]) {
      try {
        final b = await locker.read(
          AssetInfo(
            id: m.id,
            type: type,
            name: m.name,
            extension: m.extension,
            app: '',
            created: DateTime(2000),
          ),
        );
        if (b != null) return b;
      } catch (_) {}
    }
    if (mounted) _snack('"${m.name}" is not in the Asset Locker any more');
    return null;
  }

  Future<void> _pickMusic() async {
    final locker = Shell.of(context).locker;
    if (!locker.ready && !await locker.connect()) return;
    if (!mounted) return;
    final info = await pickFromLocker(
      context,
      locker,
      types: const [AssetType.sample, AssetType.recording, AssetType.other],
    );
    if (info == null) return;
    if (info.extension.toLowerCase() != 'wav') {
      _snack('Music must be a WAV file');
      return;
    }
    final bytes = await locker.read(info);
    final pcm = bytes == null ? null : decodeWav(bytes);
    if (pcm == null) {
      _snack('Could not read "${info.name}"');
      return;
    }
    await _player?.stop();
    setState(() {
      _playing = false;
      _movie.music = MusicRef(
        info.id,
        info.extension,
        info.name,
        seconds: pcm.length / 2 / 44100,
      );
      _musicLoaded = null;
    });
  }

  CameraRig get _rig => _shotNow != null ? _shotRig : _orbit;

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
    if (_places.length < _movie.placeCount) {
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
      final m = _movie.music;
      Int16List? music;
      if (m != null) {
        final b = await _readMusic(m);
        music = b == null ? null : decodeWav(b);
      }
      file = await exportMovie(
        movie: _movie,
        places: [for (var i = 0; i < _movie.placeCount; i++) _places[i]!],
        pose: _poseAll,
        fallbackCamera: _orbit.camera,
        fallbackPlace: _view,
        music: music,
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
                child: _lookNow.isNone
                    ? _viewport(scene)
                    : ColorFiltered(
                        colorFilter: ColorFilter.matrix(
                          previewMatrix(_lookNow),
                        ),
                        child: _viewport(scene),
                      ),
              ),
              if (_lookNow.vignette > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          radius: 0.85,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(
                              alpha: 0.75 * _lookNow.vignette,
                            ),
                          ],
                          stops: const [0.55, 1],
                        ),
                      ),
                    ),
                  ),
                ),
              if (_lookNow.letterbox)
                Positioned.fill(
                  child: IgnorePointer(
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final bar = math.max(
                          0.0,
                          (box.maxHeight - box.maxWidth / 2.35) / 2,
                        );
                        return Column(
                          children: [
                            Container(height: bar, color: Colors.black),
                            const Spacer(),
                            Container(height: bar, color: Colors.black),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              if (_movie.placeCount > 1)
                Positioned(
                  left: 8,
                  bottom: 6,
                  child: IgnorePointer(
                    child: Text(
                      _movie.placeAt(_shownPlace).label,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        shadows: [Shadow(blurRadius: 3)],
                      ),
                    ),
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
          onPressed: _playPause,
        ),
        Expanded(
          child: Slider(
            value: _t.clamp(0, d),
            max: d,
            onChanged: (v) {
              if (_playing) unawaited(_player?.stop());
              setState(() {
                _playing = false;
                _t = v;
              });
            },
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

  Widget _viewport(Scene scene) => Viewport3D(
    scene: scene,
    rig: _rig,
    options: _clean ? RenderOptions.clean : const RenderOptions(),
    onFrame: _frameTick,
    onTap: _onTap,
    joystick: false,
  );

  Widget _castTab() {
    final a = _actor;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            FilledButton.tonalIcon(
              onPressed: _addSheet,
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
            OutlinedButton.icon(
              onPressed: _import,
              icon: const Icon(Icons.view_in_ar_outlined, size: 18),
              label: const Text('Import 3D model'),
            ),
          ],
        ),
        const Divider(),
        for (final act in _movie.actors)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            selected: act.id == _selected,
            leading: act.model != null
                ? const Icon(Icons.view_in_ar_outlined)
                : CircleAvatar(
                    radius: 12,
                    backgroundColor: Color(act.look.top),
                  ),
            title: Text(act.name),
            subtitle: Text(
              '${act.what} · ${act.actions.length} action${act.actions.length == 1 ? '' : 's'}',
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
          if (_movie.placeCount > 1)
            Row(
              children: [
                const SizedBox(width: 70, child: Text('In')),
                Expanded(
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: a.place.clamp(0, _movie.placeCount - 1),
                    items: [
                      for (var i = 0; i < _movie.placeCount; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(_movie.placeAt(i).label),
                        ),
                    ],
                    onChanged: (v) {
                      setState(() {
                        a.place = v ?? 0;
                        _view = a.place;
                      });
                      unawaited(_rebuild());
                    },
                  ),
                ),
              ],
            ),
          if (a.model != null) ..._modelControls(a),
          if (a.model == null && a.animal == null && a.prop == null) ...[
            Row(
              children: [
                const SizedBox(width: 70, child: Text('Holds')),
                Expanded(
                  child: DropdownButton<Prop?>(
                    isExpanded: true,
                    value: a.holds,
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Nothing'),
                      ),
                      for (final p in _holdable)
                        DropdownMenuItem(value: p, child: Text(p.label)),
                    ],
                    onChanged: (v) {
                      setState(() => a.holds = v);
                      _actors[a.id]?.hold(v);
                    },
                  ),
                ),
              ],
            ),
            ..._personControls(a),
          ],
          if (a.animal != null || a.prop != null)
            Row(
              children: [
                const SizedBox(width: 70, child: Text('Size')),
                Expanded(
                  child: Slider(
                    value: a.scale.clamp(0.25, 4),
                    min: 0.25,
                    max: 4,
                    onChanged: (v) => setState(() => a.scale = v),
                    onChangeEnd: (_) => _rebuild(),
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    '×${a.scale.toStringAsFixed(2)}',
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          if (a.model == null)
            for (final (label, get, set) in [
              (
                a.prop != null
                    ? 'Detail'
                    : a.animal != null
                    ? 'Nose'
                    : 'Skin',
                (Look l) => l.skin,
                (Look l, int c) => l.copyWith(skin: c),
              ),
              (
                a.prop != null
                    ? 'Accent'
                    : a.animal != null
                    ? 'Mane'
                    : 'Hair',
                (Look l) => l.hair,
                (Look l, int c) => l.copyWith(hair: c),
              ),
              (
                a.prop != null
                    ? 'Main'
                    : a.animal != null
                    ? 'Coat'
                    : 'Top',
                (Look l) => l.top,
                (Look l, int c) => l.copyWith(top: c),
              ),
              (
                a.prop != null
                    ? 'Second'
                    : a.animal != null
                    ? 'Patches'
                    : 'Bottom',
                (Look l) => l.bottom,
                (Look l, int c) => l.copyWith(bottom: c),
              ),
              if (a.animal == null && a.prop == null)
                (
                  'Extras',
                  (Look l) => l.accent,
                  (Look l, int c) => l.copyWith(accent: c),
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

  Future<void> _addActor(Actor actor) async {
    setState(() {
      _movie.actors.add(actor);
      _selected = actor.id;
    });
    await _rebuild();
  }

  /// Where the next one stands.
  (double, double) get _nextSpot {
    final n = _movie.actors.length;
    return ((n % 4 - 1.5) * 1.2, n ~/ 4 * -1.2);
  }

  /// Picks something to add: people, animals (and more).
  Future<void> _addSheet() async {
    final pick = await showModalBottomSheet<Actor>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final (x, z) = _nextSpot;
        final n = _movie.actors.length + 1;
        Widget section(String title, List<(IconData, String, Actor)> items) =>
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final (icon, label, actor) in items)
                        ActionChip(
                          avatar: Icon(icon, size: 16),
                          label: Text(label),
                          onPressed: () => Navigator.pop(context, actor),
                        ),
                    ],
                  ),
                ],
              ),
            );
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                section('People', [
                  for (final k in Kind.values)
                    (
                      Icons.person_outline,
                      k.label,
                      Actor(kind: k, name: '${k.label} $n', x: x, z: z),
                    ),
                ]),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _addFromTemplate();
                    },
                    icon: const Icon(Icons.bookmarks_outlined, size: 18),
                    label: const Text('From a saved template…'),
                  ),
                ),
                section('Animals', [
                  for (final an in Animal.values)
                    (
                      Icons.pets,
                      an.label,
                      Actor(
                        kind: Kind.man,
                        animal: an,
                        name: '${an.label} $n',
                        x: x,
                        z: z,
                      ),
                    ),
                ]),
                for (final g in {for (final p in Prop.values) p.group})
                  section(g, [
                    for (final p in Prop.values.where((p) => p.group == g))
                      (
                        switch (g) {
                          'Plants' => Icons.park_outlined,
                          'Furniture' => Icons.chair_outlined,
                          'Outdoors' => Icons.directions_car_outlined,
                          _ => Icons.category_outlined,
                        },
                        p.label,
                        Actor(
                          kind: Kind.man,
                          prop: p,
                          name: p.label,
                          x: x,
                          z: z,
                        ),
                      ),
                  ]),
              ],
            ),
          ),
        );
      },
    );
    if (pick != null) await _addActor(pick);
  }

  List<Widget> _modelControls(Actor a) {
    final fig = _actors[a.id];
    final hasOwn = fig is ModelFigure && fig.own.isNotEmpty;
    return [
      Row(
        children: [
          const SizedBox(width: 70, child: Text('Height')),
          Expanded(
            child: Slider(
              value: a.size.clamp(0.1, 10),
              min: 0.1,
              max: 10,
              onChanged: (v) => setState(() => a.size = v),
              onChangeEnd: (_) => _rebuild(),
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              '${a.size.toStringAsFixed(a.size < 2 ? 2 : 1)} m',
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
      Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: () {
              setState(() => a.turn = (a.turn + 180) % 360);
              _rebuild();
            },
            icon: const Icon(Icons.flip_camera_android_outlined, size: 18),
            label: const Text('Faces the wrong way'),
          ),
          if (hasOwn && fig.humanoid)
            FilterChip(
              label: const Text('Its own walk/run'),
              selected: a.ownWalk,
              onSelected: (v) {
                setState(() => a.ownWalk = v);
                _rebuild();
              },
            ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          fig is ModelFigure
              ? [
                  if (fig.humanoid)
                    'Skeleton found: it can do every move and be posed.'
                  else
                    'No person skeleton: it slides when walking.',
                  if (hasOwn) '${fig.own.length} animations of its own.',
                ].join(' ')
              : '',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ];
  }

  /// Body sliders, things to wear and saving as a template.
  List<Widget> _personControls(Actor a) => [
    ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      title: const Text('Body'),
      subtitle: a.body.isDefault ? null : const Text('changed'),
      children: [
        for (final (k, label) in [
          ('height', 'Height'),
          ('build', 'Build'),
          ('head', 'Head'),
          ('arms', 'Arms'),
          ('legs', 'Legs'),
        ])
          Row(
            children: [
              SizedBox(width: 70, child: Text(label)),
              Expanded(
                child: Slider(
                  value: a.body[k].clamp(
                    Body.ranges[k]!.$1,
                    Body.ranges[k]!.$2,
                  ),
                  min: Body.ranges[k]!.$1,
                  max: Body.ranges[k]!.$2,
                  onChanged: (v) => setState(() => a.body = a.body.with_(k, v)),
                  onChangeEnd: (_) => _rebuild(),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  '${(a.body[k] * 100).round()}%',
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: a.body.isDefault
                ? null
                : () {
                    setState(() => a.body = const Body());
                    _rebuild();
                  },
            child: const Text('Reset body'),
          ),
        ),
      ],
    ),
    Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final e in Extra.values)
          FilterChip(
            label: Text(e.label),
            selected: a.extras.contains(e),
            onSelected: (on) {
              setState(() {
                if (on) {
                  a.extras.add(e);
                  // One thing on the head at a time.
                  if (e == Extra.hat) a.extras.remove(Extra.cap);
                  if (e == Extra.cap) a.extras.remove(Extra.hat);
                } else {
                  a.extras.remove(e);
                }
              });
              _rebuild();
            },
          ),
      ],
    ),
    Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => _saveTemplate(a),
        icon: const Icon(Icons.bookmark_add_outlined, size: 18),
        label: const Text('Save as a template'),
      ),
    ),
  ];

  Future<void> _saveTemplate(Actor a) async {
    final locker = Shell.of(context).locker;
    if (!locker.ready && !await locker.connect()) return;
    await locker.save(
      type: AssetType.preset,
      name: a.name,
      bytes: utf8.encode(jsonEncode(templateJson(a))),
      extension: 'json',
      tags: const ['puppet stage', 'template'],
      extra: {'kind': templateKind},
    );
    _snack('Saved "${a.name}" as a template (Asset Locker, Presets)');
  }

  Future<void> _addFromTemplate() async {
    final locker = Shell.of(context).locker;
    if (!locker.ready && !await locker.connect()) return;
    if (!mounted) return;
    final info = await pickFromLocker(
      context,
      locker,
      types: const [AssetType.preset],
    );
    if (info == null) return;
    try {
      final (x, z) = _nextSpot;
      final a = actorFromTemplate(
        jsonDecode(utf8.decode((await locker.read(info))!)),
        x: x,
        z: z,
      );
      if (a == null) {
        _snack('That preset is not a Puppet Stage template');
        return;
      }
      await _addActor(a);
    } catch (e) {
      _snack('Could not read that template: $e');
    }
  }

  /// How long a move action lasts when added.
  double _lengthOf(Actor a, String id) {
    final fig = _actors[a.id];
    if (id.startsWith(ownPrefix) && fig is ModelFigure) {
      final d = fig.own[id.substring(ownPrefix.length)]?.duration ?? 2;
      return d < 0.8 ? d * 3 : d;
    }
    final m = moveById(id, _actors[a.id]?.rig?.rig ?? 'human');
    if (m == null) return 2;
    return m.loop ? m.duration * 2 : m.duration + 0.5;
  }

  /// Adds a 3D model (from the Asset Locker or a file) to the cast.
  Future<void> _import() async {
    final shell = Shell.of(context);
    final where = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '.glb, .gltf (one file) or .obj. People with a skeleton '
                '(Mixamo, Quaternius, Kenney, VRoid…) can do every move; '
                'animated models also bring their own moves.',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('From the Asset Locker (Models)'),
              onTap: () => Navigator.pop(context, 'locker'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('From a file'),
              onTap: () => Navigator.pop(context, 'file'),
            ),
          ],
        ),
      ),
    );
    if (where == null || !mounted) return;
    final locker = shell.locker;
    if (!locker.ready && !await locker.connect()) return;
    if (!mounted) return;
    AssetInfo? info;
    Uint8List? bytes;
    try {
      if (where == 'file') {
        final f = await openFile(
          acceptedTypeGroups: const [
            XTypeGroup(
              label: '3D models',
              extensions: ['glb', 'gltf', 'obj'],
              uniformTypeIdentifiers: ['public.item'],
            ),
          ],
        );
        if (f == null) return;
        bytes = await f.readAsBytes();
        final dot = f.name.lastIndexOf('.');
        final ext = dot < 0 ? 'glb' : f.name.substring(dot + 1).toLowerCase();
        // Kept in the Locker so saved movies can find it again.
        info = await locker.save(
          type: AssetType.model,
          name: dot < 0 ? f.name : f.name.substring(0, dot),
          bytes: bytes,
          extension: ext,
          tags: const ['puppet stage'],
        );
      } else {
        if (!mounted) return;
        info = await pickFromLocker(
          context,
          locker,
          types: const [AssetType.model],
        );
        if (info == null) return;
        bytes = await locker.read(info);
      }
    } catch (e) {
      _snack('Could not open that file: $e');
      return;
    }
    if (bytes == null) return;
    _modelBytes[info.id] = bytes;
    final (x, z) = _nextSpot;
    await _addActor(
      Actor(
        kind: Kind.man,
        name: info.name,
        model: ModelRef(info.id, info.extension, info.name),
        x: x,
        z: z,
      ),
    );
    if (where == 'file') _snack('Also saved to the Asset Locker (Models)');
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
            title: Text(
              a.actions[i].describe(_moveLabel(a, a.actions[i].move)),
            ),
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
        if (_actors[a.id]?.moves.isNotEmpty ?? false)
          Text('Moves', style: Theme.of(context).textTheme.labelLarge),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final m in _actors[a.id]?.moves ?? const <MoveChoice>[])
              ActionChip(
                label: Text(m.label),
                onPressed: () => setState(
                  () => a.actions.add(
                    Action(
                      ActionType.move,
                      move: m.id,
                      seconds: _lengthOf(a, m.id),
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
                act.describe(_moveLabel(a, act.move)),
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

  static const _holdable = [
    Prop.mic,
    Prop.sword,
    Prop.candle,
    Prop.lantern,
    Prop.cup,
    Prop.ball,
    Prop.boombox,
  ];

  static String _lookName(FilmLook l) {
    final j = jsonEncode(l.toJson());
    for (final e in FilmLook.presets.entries) {
      if (jsonEncode(e.value.toJson()) == j) return e.key;
    }
    return 'Custom';
  }

  Widget _lookMenu(
    FilmLook? value,
    void Function(FilmLook?) onSet, {
    String? inherit,
  }) {
    final name = value == null ? (inherit ?? 'Clean') : _lookName(value);
    return PopupMenuButton<String>(
      tooltip: 'Film look',
      onSelected: (k) => onSet(k == '' ? null : FilmLook.presets[k]),
      itemBuilder: (context) => [
        if (inherit != null)
          CheckedPopupMenuItem(
            value: '',
            checked: value == null,
            child: Text('Movie look ($inherit)'),
          ),
        for (final k in FilmLook.presets.keys)
          CheckedPopupMenuItem(
            value: k,
            checked: value != null && name == k,
            child: Text(k),
          ),
      ],
      child: Chip(
        avatar: const Icon(Icons.filter_vintage_outlined, size: 18),
        label: Text(name),
      ),
    );
  }

  Future<void> _addPlace() async {
    final choice = await showDialog<Place>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Add a place'),
        children: [
          for (final st in StageSet.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, Place(set: st)),
              child: Text(st.label),
            ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 4, 24, 4),
            child: Text('Vista landscapes'),
          ),
          for (final e in land.presets.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(
                context,
                Place(land: e.value.$2, name: e.value.$1),
              ),
              child: Text(e.value.$1),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, const Place(name: '?')),
            child: const Text('A Vista landscape from the Locker…'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    var place = choice;
    if (choice.name == '?' && choice.set == null && choice.land == null) {
      final locker = Shell.of(context).locker;
      if (!locker.ready && !await locker.connect()) return;
      if (!mounted) return;
      final info = await pickFromLocker(
        context,
        locker,
        types: const [AssetType.preset],
      );
      if (info == null) return;
      try {
        final j = jsonDecode(utf8.decode((await locker.read(info))!));
        place = Place(
          land: land.LandSettings.fromJson(j as Map),
          name: info.name,
        );
      } catch (e) {
        _snack('Not a Vista landscape: $e');
        return;
      }
    }
    setState(() {
      _movie.places.add(place);
      _view = _movie.placeCount - 1;
    });
    await _rebuild();
  }

  void _addShot() {
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
          place: _view,
        ),
      );
      _movie.shots.sort((a, b) => a.time.compareTo(b.time));
    });
  }

  Widget _cameraTab() => ListView(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
    children: [
      Text('Places', style: Theme.of(context).textTheme.titleSmall),
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (var i = 0; i < _movie.placeCount; i++)
            InputChip(
              label: Text(_movie.placeAt(i).label),
              selected: _view == i,
              onPressed: () => setState(() => _view = i),
              onDeleted: i == 0
                  ? null
                  : () {
                      setState(() {
                        _movie.places.removeAt(i - 1);
                        for (final a in _movie.actors) {
                          if (a.place == i) a.place = 0;
                          if (a.place > i) a.place--;
                        }
                        for (final s in _movie.shots) {
                          if (s.place == i) s.place = 0;
                          if (s.place > i) s.place--;
                        }
                        _view = 0;
                        _places.clear();
                        _placeKeys.clear();
                      });
                      unawaited(_rebuild());
                    },
            ),
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: const Text('Place'),
            onPressed: _busy ? null : _addPlace,
          ),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _lookMenu(
            _movie.look,
            (l) => setState(() => _movie.look = l ?? FilmLook.none),
          ),
          ActionChip(
            avatar: const Icon(Icons.music_note_outlined, size: 18),
            label: Text(_movie.music?.name ?? 'Music…'),
            onPressed: _pickMusic,
          ),
          if (_movie.music != null)
            IconButton(
              tooltip: 'No music',
              icon: const Icon(Icons.music_off_outlined),
              onPressed: () => setState(() {
                unawaited(_player?.stop());
                _movie.music = null;
                _musicLoaded = null;
              }),
            ),
        ],
      ),
      const Divider(),
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
        onPressed: _addShot,
        icon: const Icon(Icons.videocam_outlined),
        label: Text('Shot at ${_t.toStringAsFixed(1)} s'),
      ),
      for (final s in _movie.shots) ...[
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.videocam_outlined),
          title: Text(
            'From ${s.time.toStringAsFixed(1)} s'
            '${_movie.placeCount > 1 ? ' · ${_movie.placeAt(s.place).label}' : ''}'
            '${s.end != null ? ' · drifts' : ''}',
          ),
          onTap: () => setState(() {
            _t = s.time;
            _view = s.place.clamp(0, _movie.placeCount - 1);
          }),
          trailing: IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _movie.shots.remove(s)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 40),
          child: Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _lookMenu(
                s.look,
                (l) => setState(() => s.look = l),
                inherit: _lookName(_movie.look),
              ),
              TextButton.icon(
                icon: const Icon(Icons.open_with, size: 18),
                label: Text(
                  s.end == null ? 'Drift to this view' : 'New drift end',
                ),
                onPressed: () {
                  final c = _orbit.camera;
                  setState(
                    () => s.end = [
                      c.position.x,
                      c.position.y,
                      c.position.z,
                      c.yaw,
                      c.pitch,
                    ],
                  );
                },
              ),
              if (s.end != null)
                TextButton(
                  onPressed: () => setState(() => s.end = null),
                  child: const Text('No drift'),
                ),
            ],
          ),
        ),
      ],
    ],
  );

  Widget _poseTab() {
    final a = _actor, rig = _actors[_selected]?.rig;
    if (a == null) {
      return const Center(child: Text('Add someone in Cast first.'));
    }
    if (rig == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            a.model != null
                ? 'This model has no skeleton the Pose tab understands '
                      '(people with arms and legs work).'
                : 'Nothing to pose on ${a.name}: it can be placed, turned '
                      'and moved along.',
            textAlign: TextAlign.center,
          ),
        ),
      );
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
              _pose = poseOf(rig);
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
            for (final j in rig.joints.keys)
              ChoiceChip(
                label: Text(_jointLabels[j] ?? j),
                selected: _joint == j,
                onSelected: (_) => setState(() => _joint = j),
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
