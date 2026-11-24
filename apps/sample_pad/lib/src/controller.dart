import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:app_shell/app_shell.dart' show runInBackground;
import 'package:audio_kit/audio_kit.dart';
import 'package:beat_kit/beat_kit.dart';
import 'package:flutter/foundation.dart';

import 'output.dart';

/// One pad as the UI sees it.
class PadSlot {
  PadSlot({
    this.name = '',
    this.sample,
    this.settings = const PadSettings(),
    this.assetId,
    this.assetType,
  }) : peaks = sample == null
           ? Float32List(0)
           : floatPeaks(sample, engineRate ~/ 100);

  final String name;
  final Float32List? sample;
  final PadSettings settings;

  /// Where the sample lives in the Asset Locker (null = not saved yet).
  final String? assetId;
  final String? assetType;
  final Float32List peaks;

  bool get isEmpty => sample == null;
  double get seconds => (sample?.length ?? 0) / engineRate;

  PadSlot withSettings(PadSettings s) => PadSlot(
    name: name,
    sample: sample,
    settings: s,
    assetId: assetId,
    assetType: assetType,
  );

  PadSlot withAsset(String id, String type) => PadSlot(
    name: name,
    sample: sample,
    settings: settings,
    assetId: id,
    assetType: type,
  );

  PadSlot withName(String n) => PadSlot(
    name: n,
    sample: sample,
    settings: settings,
    assetId: assetId,
    assetType: assetType,
  );
}

class LayerInfo {
  LayerInfo(this.id, this.name, this.bars, this.data, this.startBar);
  final int id;
  final String name;
  final int bars;
  final Float32List data;
  final int startBar;
  double gain = 1;
  bool muted = false;
}

enum LayerRec { idle, starting, waiting, recording, processing }

/// Longest sample a pad keeps.
const maxSampleSeconds = 30.0;

class PadController extends ChangeNotifier {
  PadController({
    required this.output,
    required this.tempDir,
    MicRecorder Function()? micFactory,
  }) : _micFactory = micFactory ?? MicRecorder.new;

  final BeatOutput output;
  final Directory tempDir;
  final MicRecorder Function() _micFactory;
  StreamSubscription<Object?>? _sub;

  final pads = List<PadSlot>.generate(padCount, (_) => PadSlot());
  List<int> masks = List.filled(padCount, 0);
  int steps = 16;
  double bpm = 110;
  double swing = 0;
  bool playing = false;
  int currentStep = -1;
  int activePads = 0;
  String kitName = 'New kit';
  double latencyMs = 60;

  final layers = <LayerInfo>[];
  LayerRec layerRec = LayerRec.idle;
  int layerBars = 2;
  int _recStartBar = 0;
  double _recMark = 0;
  MicRecorder? _layerMic;
  File? _layerFile;
  int _nextLayerId = 1;
  String? message;

  final _taps = <DateTime>[];

  Transport get transport =>
      Transport(bpm: bpm, swing: swing, sampleRate: engineRate);

  Future<void> init() async {
    _sub = output.events.listen(_onEvent);
    await output.init();
    _sendTempo();
    _sendPattern();
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(_layerMic?.stop());
    unawaited(output.dispose());
    super.dispose();
  }

  void _onEvent(Object? e) {
    switch (e) {
      case StepEvent():
        currentStep = e.step;
        _barNow = e.bar;
        if (e.isBarStart) _onBar(e.bar);
        notifyListeners();
      case PadActivity(:final active):
        activePads = active;
        notifyListeners();
    }
  }

  // ---- Pads ----

  void setSample(
    int pad,
    Float32List? data, {
    String name = '',
    String? assetId,
    String? assetType,
  }) {
    pads[pad] = data == null
        ? PadSlot()
        : PadSlot(
            name: name,
            sample: data,
            settings: pads[pad].settings,
            assetId: assetId,
            assetType: assetType,
          );
    output.send(SetSample(pad, data));
    output.send(SetPad(pad, pads[pad].settings));
    if (data == null) {
      masks[pad] = 0;
      _sendPattern();
    }
    notifyListeners();
  }

  void setPad(int pad, PadSettings s) {
    pads[pad] = pads[pad].withSettings(s);
    output.send(SetPad(pad, s));
    notifyListeners();
  }

  void renamePad(int pad, String name) {
    pads[pad] = pads[pad].withName(name);
    notifyListeners();
  }

  void padDown(int pad) {
    if (pads[pad].isEmpty) return;
    output.send(Trigger(pad));
  }

  void padUp(int pad) => output.send(Release(pad));

  /// Moves the trim start past leading silence.
  void trimSilence(int pad, {double threshold = 0.02}) {
    final data = pads[pad].sample;
    if (data == null) return;
    var i = 0;
    while (i < data.length && data[i].abs() < threshold) {
      i++;
    }
    if (i >= data.length) return;
    final s = pads[pad].settings;
    final start = math.max(0, i - engineRate ~/ 200) / data.length; // keep 5 ms
    if (start < s.end) setPad(pad, s.copyWith(start: start));
  }

  // ---- Sequencer ----

  bool stepOn(int pad, int step) => (masks[pad] >> step) & 1 == 1;

  void toggleStep(int pad, int step) {
    masks[pad] ^= 1 << step;
    _sendPattern();
    notifyListeners();
  }

  void clearPattern() {
    masks = List.filled(padCount, 0);
    _sendPattern();
    notifyListeners();
  }

  void setSteps(int n) {
    steps = n;
    _sendPattern();
    notifyListeners();
  }

  void _sendPattern() => output.send(SetPattern(List.of(masks), steps));

  /// Tempo can't change while loop layers exist (they would drift).
  bool get tempoLocked => layers.isNotEmpty || layerRec != LayerRec.idle;

  void setBpm(double v) {
    if (tempoLocked) return;
    bpm = v.clamp(40, 240).roundToDouble();
    _sendTempo();
    notifyListeners();
  }

  void setSwing(double v) {
    if (tempoLocked) return;
    swing = v.clamp(0, 0.5);
    _sendTempo();
    notifyListeners();
  }

  /// Sets the tempo from the last few taps.
  void tapTempo([DateTime? now]) {
    final t = now ?? DateTime.now();
    if (_taps.isNotEmpty && t.difference(_taps.last).inMilliseconds > 2000) {
      _taps.clear();
    }
    _taps.add(t);
    if (_taps.length > 5) _taps.removeAt(0);
    if (_taps.length < 2) return;
    final ms =
        _taps.last.difference(_taps.first).inMicroseconds /
        1000 /
        (_taps.length - 1);
    setBpm(60000 / ms);
  }

  void _sendTempo() => output.send(SetTempo(bpm, swing));

  void setPlaying(bool on) {
    if (!on && layerRec != LayerRec.idle) unawaited(_cancelLayer());
    playing = on;
    if (!on) currentStep = -1;
    output.send(SetPlaying(on));
    notifyListeners();
  }

  void setMaster(double v) => output.send(SetMaster(v));

  // ---- Loop layers ----

  MicRecorder? get layerMic => _layerMic;

  void setLayerBars(int bars) {
    layerBars = bars;
    notifyListeners();
  }

  /// Records the mic for [layerBars] bars, starting at the next bar.
  Future<void> recordLayer() async {
    if (layerRec != LayerRec.idle) return;
    message = null;
    layerRec = LayerRec.starting;
    notifyListeners();
    final mic = _micFactory();
    final file = File(
      '${tempDir.path}${Platform.pathSeparator}layer-${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    final ok = await mic.start(file, sampleRate: engineRate);
    if (!ok) {
      message = mic.error ?? 'Could not start the microphone.';
      layerRec = LayerRec.idle;
      notifyListeners();
      return;
    }
    _layerMic = mic;
    _layerFile = file;
    layerRec = LayerRec.waiting;
    if (!playing) setPlaying(true);
    notifyListeners();
  }

  void _onBar(int bar) {
    final mic = _layerMic;
    if (mic == null) return;
    if (layerRec == LayerRec.waiting) {
      _recStartBar = bar;
      _recMark = mic.seconds;
      layerRec = LayerRec.recording;
    } else if (layerRec == LayerRec.recording &&
        bar >= _recStartBar + layerBars) {
      unawaited(_finishLayer());
    }
  }

  /// Bars recorded so far while recording a layer.
  int get layerBarsDone =>
      layerRec == LayerRec.recording ? math.max(0, _barNow - _recStartBar) : 0;
  int _barNow = 0;

  Future<void> _finishLayer() async {
    layerRec = LayerRec.processing;
    notifyListeners();
    final mic = _layerMic!;
    final file = _layerFile!;
    _layerMic = null;
    _layerFile = null;
    try {
      await mic.stop();
      final bytes = await file.readAsBytes();
      final mark = _recMark;
      final latency = latencyMs;
      final bars = layerBars;
      final startBar = _recStartBar;
      final frames = transport.barFrames * bars;
      final data = await runInBackground(_cutLayer, (
        bytes,
        mark,
        latency,
        frames,
      ));
      addLayer(data, bars, startBar);
    } catch (e) {
      message = 'Could not record the loop: $e';
    } finally {
      mic.dispose();
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      layerRec = LayerRec.idle;
      notifyListeners();
    }
  }

  Future<void> _cancelLayer() async {
    final mic = _layerMic;
    final file = _layerFile;
    _layerMic = null;
    _layerFile = null;
    layerRec = LayerRec.idle;
    await mic?.stop();
    mic?.dispose();
    if (file != null && await file.exists()) await file.delete();
    notifyListeners();
  }

  void addLayer(Float32List data, int bars, int startBar) {
    final id = _nextLayerId++;
    layers.add(LayerInfo(id, 'Loop $id', bars, data, startBar));
    output.send(AddLayer(id, data, startBar));
    notifyListeners();
  }

  void updateLayer(LayerInfo l, {double? gain, bool? muted}) {
    if (gain != null) l.gain = gain;
    if (muted != null) l.muted = muted;
    output.send(SetLayer(l.id, gain: l.gain, muted: l.muted));
    notifyListeners();
  }

  void removeLayer(LayerInfo l) {
    layers.remove(l);
    output.send(RemoveLayer(l.id));
    notifyListeners();
  }

  void undoLayer() {
    if (layers.isNotEmpty) removeLayer(layers.last);
  }

  void clearLayers() {
    for (final l in List.of(layers)) {
      removeLayer(l);
    }
  }

  // ---- Kits ----

  Kit toKit() => Kit(
    name: kitName,
    bpm: bpm,
    swing: swing,
    steps: steps,
    masks: List.of(masks),
    pads: [
      for (final p in pads)
        KitPad(
          sampleId: p.isEmpty ? null : p.assetId,
          sampleType: p.isEmpty ? null : p.assetType,
          name: p.name,
          settings: p.settings,
        ),
    ],
  );

  /// Applies a kit; [samples] holds the decoded sample of each pad (or null).
  void applyKit(Kit kit, List<Float32List?> samples) {
    clearLayers();
    if (playing) setPlaying(false);
    kitName = kit.name;
    bpm = kit.bpm;
    swing = kit.swing;
    steps = kit.steps;
    for (var i = 0; i < padCount; i++) {
      final kp = kit.pads[i];
      final data = samples[i];
      pads[i] = data == null
          ? PadSlot(settings: kp.settings)
          : PadSlot(
              name: kp.name,
              sample: data,
              settings: kp.settings,
              assetId: kp.sampleId,
              assetType: kp.sampleType,
            );
      output.send(SetSample(i, data));
      output.send(SetPad(i, kp.settings));
    }
    masks = [
      for (var i = 0; i < padCount; i++) samples[i] == null ? 0 : kit.masks[i],
    ];
    _sendTempo();
    _sendPattern();
    notifyListeners();
  }

  void newKit() {
    applyKit(const Kit(name: 'New kit'), List.filled(padCount, null));
    for (var i = 0; i < padCount; i++) {
      setPad(i, const PadSettings());
    }
  }

  /// Everything needed to render the mix away from the UI isolate.
  MixSnapshot snapshot() => MixSnapshot(
    samples: [for (final p in pads) p.sample],
    pads: [for (final p in pads) p.settings],
    masks: List.of(masks),
    steps: steps,
    bpm: bpm,
    swing: swing,
    layers: [
      for (final l in layers)
        if (!l.muted) (l.data, l.startBar, l.gain),
    ],
  );
}

/// Cuts a recorded mic take into a loop layer: [frames] long, starting
/// [markSeconds] + latency into the take (zero-padded if short).
Float32List cutLayer(
  Uint8List wav, {
  required double markSeconds,
  required double latencyMs,
  required int frames,
}) {
  final mono = decodeWavMono(wav, targetRate: engineRate);
  final start = ((markSeconds + latencyMs / 1000) * engineRate).round();
  final out = Float32List(frames);
  for (var i = 0; i < frames; i++) {
    final j = start + i;
    if (j >= 0 && j < mono.length) out[i] = mono[j];
  }
  // Short fades at the seam so the loop doesn't click.
  const fade = 96;
  for (var i = 0; i < fade && i < frames; i++) {
    out[i] *= i / fade;
    out[frames - 1 - i] *= i / fade;
  }
  return out;
}

class MixSnapshot {
  const MixSnapshot({
    required this.samples,
    required this.pads,
    required this.masks,
    required this.steps,
    required this.bpm,
    required this.swing,
    required this.layers,
  });

  final List<Float32List?> samples;
  final List<PadSettings> pads;
  final List<int> masks;
  final int steps;
  final double bpm, swing;
  final List<(Float32List, int, double)> layers;
}

/// Renders [bars] bars of the beat (pattern + loop layers) to a stereo WAV.
Uint8List renderMix(MixSnapshot s, int bars) {
  final e = BeatEngine(sampleRate: engineRate)
    ..handle(SetTempo(s.bpm, s.swing))
    ..handle(SetPattern(s.masks, s.steps))
    ..handle(const SetMaster(0.8));
  for (var i = 0; i < padCount; i++) {
    e
      ..handle(SetSample(i, s.samples[i]))
      ..handle(SetPad(i, s.pads[i]));
  }
  var id = 0;
  for (final (data, startBar, gain) in s.layers) {
    e.handle(AddLayer(id++, data, startBar, gain: gain));
  }
  e.handle(const SetPlaying(true));
  final frames =
      Transport(bpm: s.bpm, swing: s.swing, sampleRate: engineRate).barFrames *
      bars;
  final out = Float32List(frames * 2);
  const block = 1024;
  final tmp = Float32List(block * 2);
  for (var at = 0; at < frames; at += block) {
    final n = math.min(block, frames - at);
    e.render(tmp, n);
    out.setRange(at * 2, (at + n) * 2, tmp);
  }
  return encodeWavStereo16(out, engineRate);
}

Float32List _cutLayer((Uint8List, double, double, int) a) =>
    cutLayer(a.$1, markSeconds: a.$2, latencyMs: a.$3, frames: a.$4);
