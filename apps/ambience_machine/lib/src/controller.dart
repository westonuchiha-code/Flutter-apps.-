import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fx_kit/fx_kit.dart';

import 'engine.dart';
import 'keeper.dart';
import 'output.dart';
import 'scene.dart';

SceneSpec starterScene() => SceneSpec(
  name: 'First light',
  layers: [
    LayerSpec(
      kind: LayerKind.noise,
      noise: NoiseType.waves,
      name: 'Waves',
      volume: 0.6,
    ),
    LayerSpec(
      kind: LayerKind.noise,
      noise: NoiseType.wind,
      name: 'Wind',
      volume: 0.35,
      tone: 0.6,
    ),
    LayerSpec(
      kind: LayerKind.synth,
      name: 'Soft notes',
      volume: 0.5,
      density: 6,
      noteLength: 4,
    ),
  ],
  fx: [
    EffectSpec(EffectKind.reverb, values: {'size': 0.85, 'mix': 0.35}),
  ],
);

class AmbienceController extends ChangeNotifier {
  AmbienceController(this.output, {PlaybackKeeper? keeper}) {
    this.keeper =
        keeper ?? PlaybackKeeper(onStopRequested: () => setPlaying(false));
  }

  final AmbOutput output;
  late final PlaybackKeeper keeper;
  StreamSubscription<Object?>? _sub;

  SceneSpec scene = starterScene();
  bool playing = false;
  double master = 0.8;

  /// Seconds of crossfade when switching scenes.
  double crossfade = 8;
  Map<int, double> levels = const {};
  double? sleepLeft;

  /// Display names of loaded samples, by key.
  final sampleNames = <String, String>{};
  final _sentSamples = <String, Float32List>{};

  Future<void> init() async {
    _sub = output.events.listen(_onEvent);
    await output.init();
    output
      ..send(SetMaster(master))
      ..send(SetScene(scene));
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(keeper.stop());
    unawaited(output.dispose());
    super.dispose();
  }

  void _onEvent(Object? e) {
    switch (e) {
      case LevelsEvent():
        levels = e.levels;
        sleepLeft = e.sleepLeft;
        notifyListeners();
      case StoppedEvent():
        playing = false;
        sleepLeft = null;
        unawaited(keeper.stop());
        notifyListeners();
    }
  }

  void _send() => output.send(SetScene(scene));

  // ---- Playback ----

  void setPlaying(bool on) {
    if (on == playing) return;
    playing = on;
    output.send(SetPlaying(on, fade: on ? 3 : 2));
    if (on) {
      unawaited(keeper.start(scene.name, 'Playing'));
    } else {
      sleepLeft = null;
      unawaited(keeper.stop());
    }
    notifyListeners();
  }

  void setMaster(double v) {
    master = v.clamp(0, 1);
    output.send(SetMaster(master));
    notifyListeners();
  }

  /// Stops after [minutes] (fading out over the last minute); null cancels.
  void setSleep(double? minutes) {
    output.send(SetSleep(minutes == null ? null : minutes * 60));
    sleepLeft = minutes == null ? null : minutes * 60;
    if (minutes != null && !playing) setPlaying(true);
    notifyListeners();
  }

  // ---- Samples ----

  bool hasSample(String key) => _sentSamples.containsKey(key);

  /// Hands a decoded sample to the engine (once per key).
  void provideSample(String key, Float32List data, {String name = ''}) {
    sampleNames[key] = name;
    if (_sentSamples.containsKey(key)) return;
    _sentSamples[key] = data;
    output.send(SetSample(key, data));
  }

  Map<String, Float32List> get samples => Map.of(_sentSamples);

  // ---- Layers ----

  bool get canAddLayer => scene.layers.length < SceneSpec.maxLayers;

  void addLayer(LayerSpec l) {
    if (!canAddLayer) return;
    scene = scene.copyWith(layers: [...scene.layers, l]);
    _send();
    notifyListeners();
  }

  void updateLayer(LayerSpec l) {
    scene = scene.copyWith(
      layers: [for (final x in scene.layers) x.id == l.id ? l : x],
    );
    _send();
    notifyListeners();
  }

  void removeLayer(LayerSpec l) {
    scene = scene.copyWith(
      layers: [
        for (final x in scene.layers)
          if (x.id != l.id) x,
      ],
    );
    _send();
    notifyListeners();
  }

  // ---- Effects ----

  void setFx(List<EffectSpec> fx) {
    scene = scene.copyWith(fx: fx);
    _send();
    notifyListeners();
  }

  void addEffect(EffectKind k) {
    if (scene.fx.length < FxChain.maxEffects) {
      setFx([...scene.fx, EffectSpec(k)]);
    }
  }

  void updateEffect(EffectSpec s) =>
      setFx([for (final e in scene.fx) e.id == s.id ? s : e]);

  void removeEffect(EffectSpec s) => setFx([
    for (final e in scene.fx)
      if (e.id != s.id) e,
  ]);

  void moveEffect(int from, int to) {
    final list = List.of(scene.fx);
    final e = list.removeAt(from);
    list.insert(to.clamp(0, list.length), e);
    setFx(list);
  }

  // ---- Scenes ----

  void rename(String name) {
    scene = scene.copyWith(name: name);
    if (playing) unawaited(keeper.start(name, 'Playing'));
    notifyListeners();
  }

  /// Switches to [next], crossfading if playing.
  void switchTo(SceneSpec next) {
    scene = next;
    output.send(SetScene(next, fade: playing ? crossfade : 0));
    if (playing) unawaited(keeper.start(next.name, 'Playing'));
    notifyListeners();
  }
}
