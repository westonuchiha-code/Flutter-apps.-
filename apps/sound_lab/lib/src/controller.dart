import 'dart:async';
import 'dart:math' as math;

import 'package:chip_synth/chip_synth.dart';
import 'package:flutter/foundation.dart';
import 'package:fx_kit/fx_kit.dart';

import 'engine.dart';
import 'output.dart';

/// Sound Lab's starting sound: a plain saw so effects are easy to hear.
const labDefaultSpec = PolySpec(
  osc2Mix: 0.3,
  detune: 6,
  sub: 0.2,
  cutoff: 0.7,
  resonance: 0.2,
  attack: 0.01,
  release: 0.4,
  glideMs: 0,
  delayMix: 0,
  reverbMix: 0,
);

class LabController extends ChangeNotifier {
  LabController(this.output);

  final LabOutput output;
  StreamSubscription<Float32List>? _scopeSub;

  String name = 'New sound';
  SourceKind source = SourceKind.analog;
  PolySpec spec = labDefaultSpec;
  List<EffectSpec> fx = [
    EffectSpec(EffectKind.reverb, values: {'mix': 0.2}),
  ];
  int octave = 3;

  // Wavetable source.
  List<List<double>> waves = const [];
  String waveName = '';
  double morph = 0;

  // Sample source.
  Float32List? sample;
  String sampleName = '';
  String? sampleId, sampleType;
  int sampleRoot = 60;

  /// Latest scope snapshot.
  final scope = ValueNotifier<Float32List>(Float32List(scopeSize));

  final touches = List<Touch>.filled(maxVoices, const Touch());
  final _slotNote = List<int>.filled(maxVoices, -1);

  Future<void> init() async {
    _scopeSub = output.scope.listen((s) => scope.value = s);
    await output.init();
    _push();
  }

  @override
  void dispose() {
    unawaited(_scopeSub?.cancel());
    unawaited(output.dispose());
    scope.dispose();
    super.dispose();
  }

  PolySpec get _engineSpec => switch (source) {
    SourceKind.chip => spec.copyWith(engine: EngineKind.chip),
    _ => spec.copyWith(engine: EngineKind.analog),
  };

  void _push() => output.update(
    LabUpdate(
      _engineSpec,
      List.of(fx),
      List.of(touches),
      morph,
      source == SourceKind.sample,
    ),
  );

  Wavetable? get table => source == SourceKind.wavetable && waves.isNotEmpty
      ? Wavetable.fromCycles(waves)
      : null;

  // ---- Source ----

  void setSource(SourceKind s) {
    allOff();
    source = s;
    output.send(TableMsg(table));
    _push();
    notifyListeners();
  }

  void setSpec(PolySpec s) {
    spec = s;
    _push();
    notifyListeners();
  }

  void setWaves(String name, List<List<double>> w) {
    waves = w;
    waveName = name;
    morph = 0;
    source = SourceKind.wavetable;
    output.send(TableMsg(table));
    _push();
    notifyListeners();
  }

  void setMorph(double m) {
    morph = m.clamp(0, 1);
    _push();
    notifyListeners();
  }

  void setSample(String name, Float32List? data, {String? id, String? type}) {
    allOff();
    sample = data;
    sampleName = name;
    sampleId = id;
    sampleType = type;
    source = SourceKind.sample;
    output.send(SampleMsg(data, sampleRoot));
    _push();
    notifyListeners();
  }

  void setSampleRoot(int note) {
    sampleRoot = note.clamp(24, 96);
    output.send(SampleMsg(sample, sampleRoot));
    notifyListeners();
  }

  // ---- Effects ----

  bool get canAddEffect => fx.length < FxChain.maxEffects;

  void addEffect(EffectKind k) {
    if (!canAddEffect) return;
    fx = [...fx, EffectSpec(k)];
    _push();
    notifyListeners();
  }

  void updateEffect(EffectSpec s) {
    fx = [for (final e in fx) e.id == s.id ? s : e];
    _push();
    notifyListeners();
  }

  void removeEffect(EffectSpec s) {
    fx = [
      for (final e in fx)
        if (e.id != s.id) e,
    ];
    _push();
    notifyListeners();
  }

  /// Moves the effect at [from] so it ends up at index [to].
  void moveEffect(int from, int to) {
    final list = List.of(fx);
    final e = list.removeAt(from);
    list.insert(to.clamp(0, list.length), e);
    fx = list;
    _push();
    notifyListeners();
  }

  // ---- Keys ----

  void setOctave(int o) {
    octave = o.clamp(1, 7);
    notifyListeners();
  }

  static double noteHz(int note) =>
      440 * math.pow(2, (note - 69) / 12).toDouble();

  bool isDown(int note) => _slotNote.contains(note);

  void noteOn(int note) {
    if (isDown(note)) return;
    var slot = _slotNote.indexOf(-1);
    if (slot < 0) slot = 0;
    _slotNote[slot] = note;
    touches[slot] = Touch(down: true, hz: noteHz(note), y: 0.8);
    _push();
    notifyListeners();
  }

  void noteOff(int note) {
    final slot = _slotNote.indexOf(note);
    if (slot < 0) return;
    _slotNote[slot] = -1;
    touches[slot] = Touch(hz: touches[slot].hz, y: 0.8);
    _push();
    notifyListeners();
  }

  void allOff() {
    for (final n in List.of(_slotNote)) {
      if (n >= 0) noteOff(n);
    }
  }

  // ---- Presets & rendering ----

  SoundPreset toPreset() => SoundPreset(
    name: name,
    source: source,
    synth: spec.toJson(),
    waves: source == SourceKind.wavetable ? waves : const [],
    sampleId: source == SourceKind.sample ? sampleId : null,
    sampleType: source == SourceKind.sample ? sampleType : null,
    sampleRoot: sampleRoot,
    fx: List.of(fx),
  );

  /// Applies a preset. A sample source needs its decoded [sampleData].
  void applyPreset(
    SoundPreset p, {
    Float32List? sampleData,
    String sampleLabel = '',
  }) {
    allOff();
    name = p.name;
    spec = p.synth.isEmpty ? labDefaultSpec : PolySpec.fromJson(p.synth);
    fx = [for (final e in p.fx) EffectSpec(e.kind, values: e.values, on: e.on)];
    sampleRoot = p.sampleRoot;
    waves = p.waves;
    waveName = p.waves.isEmpty ? '' : p.name;
    morph = 0;
    source = p.source;
    sample = sampleData;
    sampleName = sampleLabel;
    sampleId = p.sampleId;
    sampleType = p.sampleType;
    if (source == SourceKind.sample && sampleData == null) {
      source = SourceKind.analog;
    }
    if (source == SourceKind.wavetable && waves.isEmpty) {
      source = SourceKind.analog;
    }
    output
      ..send(TableMsg(table))
      ..send(SampleMsg(sample, sampleRoot));
    _push();
    notifyListeners();
  }

  LabSnapshot snapshot() => LabSnapshot(
    spec: _engineSpec,
    fx: List.of(fx),
    table: table,
    sample: sample,
    sampleRoot: sampleRoot,
    useSample: source == SourceKind.sample,
  );
}
