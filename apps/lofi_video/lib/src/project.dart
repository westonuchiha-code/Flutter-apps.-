import 'dart:math' as math;

/// Longest video (keeps exports quick on a phone).
const maxSeconds = 60.0;

/// The picture every scene is drawn on (4:3, lo-fi).
const canvasWidth = 320, canvasHeight = 240;

enum SceneKind {
  clip('Chip Cam clip'),
  picture('Picture'),
  sprite('Pixel Forge sprite'),
  title('Title card'),
  bars('Test bars');

  const SceneKind(this.label);
  final String label;
}

enum Fit { contain, cover }

/// How a scene arrives (over its first moments, from the previous scene).
enum Transition {
  cut('Cut'),
  dither('Dither dissolve'),
  vhs('VHS tracking roll'),
  sync('Lost sync'),
  teletext('Teletext page'),
  mosh('Datamosh smear');

  const Transition(this.label);
  final String label;
}

enum OverlayKind { text, sprite }

/// Text or a sprite drawn on top of a scene.
class SceneOverlay {
  SceneOverlay({
    String? id,
    required this.kind,
    this.asset,
    this.text = 'TEXT',
    this.color = 0xFFFFFFFF,
    this.outline = true,
    this.x = 0.5,
    this.y = 0.85,
    this.scale = 2,
    this.from = 0,
    this.to = 0,
    this.aboveEffect = false,
  }) : id = id ?? Scene._newId();

  final String id;
  final OverlayKind kind;
  final Map<String, Object?>? asset;
  String text;
  int color;
  bool outline;

  /// Centre, as a fraction of the picture (0..1).
  double x, y;

  /// Size in canvas pixels per sprite pixel (sprites) or text size step.
  int scale;

  /// Shown from..to seconds into the scene (to 0 = until the end).
  double from, to;

  /// Drawn after the scene's effect (clean) instead of going through it.
  bool aboveEffect;

  String? get assetId => asset?['id'] as String?;

  bool visibleAt(double lt) => lt >= from && (to <= 0 || lt < to);

  /// Key that changes whenever the text picture must be redrawn.
  String get textKey => '$id:$text:$color:$outline:$scale';

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'asset': ?asset,
    'text': text,
    'color': color,
    'outline': outline,
    'x': x,
    'y': y,
    'scale': scale,
    'from': from,
    'to': to,
    'above': aboveEffect,
  };

  factory SceneOverlay.fromJson(Map j, {bool newId = false}) => SceneOverlay(
    id: newId ? null : j['id'] as String?,
    kind: OverlayKind.values.firstWhere(
      (k) => k.name == j['kind'],
      orElse: () => OverlayKind.text,
    ),
    asset: (j['asset'] as Map?)?.cast<String, Object?>(),
    text: (j['text'] as String?) ?? '',
    color: ((j['color'] as num?) ?? 0xFFFFFFFF).toInt(),
    outline: j['outline'] != false,
    x: ((j['x'] as num?) ?? 0.5).toDouble(),
    y: ((j['y'] as num?) ?? 0.85).toDouble(),
    scale: ((j['scale'] as num?) ?? 2).toInt().clamp(1, 8),
    from: ((j['from'] as num?) ?? 0).toDouble(),
    to: ((j['to'] as num?) ?? 0).toDouble(),
    aboveEffect: j['above'] == true,
  );
}

/// One shot of the storyboard.
class Scene {
  Scene({
    String? id,
    required this.kind,
    this.asset,
    this.label = '',
    this.duration = 3,
    this.effectId,
    Map<String, double>? knobs,
    this.clipStart = 0,
    this.clipSound = true,
    this.fit = Fit.contain,
    this.text = '',
    this.textColor = 0xFFFFFFFF,
    this.background = 0xFF000000,
    this.transition = Transition.cut,
    this.transitionLength = 0.6,
    List<SceneOverlay>? overlays,
  }) : id = id ?? _newId(),
       knobs = knobs ?? {},
       overlays = overlays ?? [];

  static int _counter = 0;
  static String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_counter++).toRadixString(36)}';

  final String id;
  final SceneKind kind;

  /// Asset Locker details (AssetInfo JSON) of the source, if any.
  final Map<String, Object?>? asset;
  String label;
  double duration;
  String? effectId;
  Map<String, double> knobs;
  double clipStart;
  bool clipSound;
  Fit fit;
  String text;
  int textColor, background;
  Transition transition;
  double transitionLength;
  final List<SceneOverlay> overlays;

  String? get assetId => asset?['id'] as String?;

  /// A copy; with [newId], it and its overlays get new ids.
  Scene copy({bool newId = false}) {
    final j = toJson();
    if (newId) {
      j['overlays'] = [
        for (final o in overlays)
          SceneOverlay.fromJson(o.toJson(), newId: true).toJson(),
      ];
    }
    return Scene.fromJson(j, id: newId ? _newId() : null);
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'asset': ?asset,
    'label': label,
    'duration': duration,
    'effect': ?effectId,
    if (knobs.isNotEmpty) 'knobs': knobs,
    'clipStart': clipStart,
    'clipSound': clipSound,
    'fit': fit.name,
    'text': text,
    'textColor': textColor,
    'background': background,
    if (transition != Transition.cut) 'transition': transition.name,
    'transitionLength': transitionLength,
    if (overlays.isNotEmpty) 'overlays': [for (final o in overlays) o.toJson()],
  };

  factory Scene.fromJson(Map j, {String? id}) => Scene(
    id: id ?? j['id'] as String?,
    kind: SceneKind.values.firstWhere(
      (k) => k.name == j['kind'],
      orElse: () => SceneKind.title,
    ),
    asset: (j['asset'] as Map?)?.cast<String, Object?>(),
    label: (j['label'] as String?) ?? '',
    duration: ((j['duration'] as num?) ?? 3).toDouble().clamp(0.2, maxSeconds),
    effectId: j['effect'] as String?,
    knobs: {
      for (final e in ((j['knobs'] as Map?) ?? const {}).entries)
        e.key as String: (e.value as num).toDouble(),
    },
    clipStart: ((j['clipStart'] as num?) ?? 0).toDouble(),
    clipSound: j['clipSound'] != false,
    fit: Fit.values.firstWhere(
      (f) => f.name == j['fit'],
      orElse: () => Fit.contain,
    ),
    text: (j['text'] as String?) ?? '',
    textColor: ((j['textColor'] as num?) ?? 0xFFFFFFFF).toInt(),
    background: ((j['background'] as num?) ?? 0xFF000000).toInt(),
    transition: Transition.values.firstWhere(
      (t) => t.name == j['transition'],
      orElse: () => Transition.cut,
    ),
    transitionLength: ((j['transitionLength'] as num?) ?? 0.6).toDouble().clamp(
      0.1,
      2.0,
    ),
    overlays: [
      for (final o in (j['overlays'] as List?) ?? const [])
        SceneOverlay.fromJson(o as Map),
    ],
  );
}

/// A storyboard: scenes in order, one music track.
class Project {
  Project({
    this.name = 'My video',
    List<Scene>? scenes,
    this.music,
    this.musicStart = 0,
    this.musicVolume = 0.8,
    this.clipVolume = 1,
    this.bpm = 120,
    this.snap = false,
  }) : scenes = scenes ?? [];

  static const kind = 'lofi_video';

  String name;
  final List<Scene> scenes;

  /// Asset Locker details of the music (a WAV).
  Map<String, Object?>? music;

  /// Seconds into the music where the video starts.
  double musicStart;
  double musicVolume, clipVolume;

  /// Tempo for snapping cuts to the beat (from a Sample Pad mix, typed in
  /// or tapped).
  double bpm;

  /// Scene lengths are whole beats.
  bool snap;

  double get beat => 60 / bpm;

  /// [seconds] rounded to whole beats (at least one) when snapping.
  double snapped(double seconds) {
    if (!snap) return seconds;
    final beats = math.max(1, (seconds / beat).round());
    return beats * beat;
  }

  double get duration => scenes.fold(0.0, (a, s) => a + s.duration);

  /// Start time of each scene.
  List<double> get starts {
    final out = <double>[];
    var t = 0.0;
    for (final s in scenes) {
      out.add(t);
      t += s.duration;
    }
    return out;
  }

  /// (scene index, time into that scene) at [t].
  (int, double) sceneAt(double t) {
    var start = 0.0;
    for (var i = 0; i < scenes.length; i++) {
      final end = start + scenes[i].duration;
      if (t < end || i == scenes.length - 1) {
        return (i, math.max(0, t - start));
      }
      start = end;
    }
    return (-1, 0);
  }

  Map<String, Object?> toJson() => {
    'kind': kind,
    'version': 1,
    'name': name,
    'scenes': [for (final s in scenes) s.toJson()],
    'music': ?music,
    'musicStart': musicStart,
    'musicVolume': musicVolume,
    'clipVolume': clipVolume,
    'bpm': bpm,
    'snap': snap,
  };

  factory Project.fromJson(Object? j) {
    if (j is! Map || j['kind'] != kind) {
      throw const FormatException('Not a Lo-Fi Video project');
    }
    return Project(
      name: (j['name'] as String?) ?? 'My video',
      scenes: [
        for (final s in (j['scenes'] as List?) ?? const [])
          Scene.fromJson(s as Map),
      ],
      music: (j['music'] as Map?)?.cast<String, Object?>(),
      musicStart: ((j['musicStart'] as num?) ?? 0).toDouble(),
      musicVolume: ((j['musicVolume'] as num?) ?? 0.8).toDouble(),
      clipVolume: ((j['clipVolume'] as num?) ?? 1).toDouble(),
      bpm: ((j['bpm'] as num?) ?? 120).toDouble().clamp(30, 300),
      snap: j['snap'] == true,
    );
  }
}
