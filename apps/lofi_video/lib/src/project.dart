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
  }) : id = id ?? _newId(),
       knobs = knobs ?? {};

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

  String? get assetId => asset?['id'] as String?;

  Scene copy({bool newId = false}) =>
      Scene.fromJson(toJson(), id: newId ? _newId() : null);

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
  }) : scenes = scenes ?? [];

  static const kind = 'lofi_video';

  String name;
  final List<Scene> scenes;

  /// Asset Locker details of the music (a WAV).
  Map<String, Object?>? music;

  /// Seconds into the music where the video starts.
  double musicStart;
  double musicVolume, clipVolume;

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
    );
  }
}
