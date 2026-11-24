import 'dart:async';
import 'dart:math' as math;

import 'package:audio_kit/audio_kit.dart';
import 'package:chip_synth/chip_synth.dart';
import 'package:flutter/foundation.dart';

import 'output.dart';
import 'patch.dart';
import 'shape.dart';

enum DrawTool { pen, line }

/// Sound defaults that show off a drawn wave (one oscillator, open filter).
const defaultSpec = PolySpec(
  osc2Mix: 0,
  sub: 0,
  cutoff: 0.8,
  resonance: 0.15,
  attack: 0.01,
  release: 0.3,
  glideMs: 0,
  delayMix: 0.1,
  reverbMix: 0.15,
);

class PainterController extends ChangeNotifier {
  PainterController(this.output);

  final WaveOutput output;

  String name = 'New wave';
  final waves = <Float32List>[WavePreset.sine.build()];
  int selected = 0;
  PolySpec spec = defaultSpec;
  double morph = 0;
  int octave = 4;
  DrawTool tool = DrawTool.pen;
  final _undo = <List<Float32List>>[];
  final touches = List<Touch>.filled(maxVoices, const Touch());

  /// Which MIDI note each voice slot holds (-1 = free).
  final _slotNote = List<int>.filled(maxVoices, -1);
  Timer? _tableTimer;

  Float32List get wave => waves[selected];
  bool get canUndo => _undo.isNotEmpty;

  Future<void> init() async {
    await output.init();
    _sendTable();
    _sendState();
  }

  @override
  void dispose() {
    _tableTimer?.cancel();
    unawaited(output.dispose());
    super.dispose();
  }

  Wavetable buildTable() =>
      Wavetable.fromCycles([for (final w in waves) w.toList()]);

  void _sendTable() => output.setTable(buildTable());

  void _sendState() => output.update(spec, touches, morph);

  /// Called while drawing: redraw now, send the sound a moment later.
  void _changed({bool immediate = false}) {
    notifyListeners();
    _tableTimer?.cancel();
    if (immediate) {
      _sendTable();
    } else {
      _tableTimer = Timer(const Duration(milliseconds: 60), _sendTable);
    }
  }

  // ---- Editing ----

  /// Saves the current waves for undo (call once per stroke/action).
  void checkpoint() {
    _undo.add([for (final w in waves) Float32List.fromList(w)]);
    if (_undo.length > 40) _undo.removeAt(0);
  }

  void undo() {
    if (_undo.isEmpty) return;
    final prev = _undo.removeLast();
    waves
      ..clear()
      ..addAll(prev);
    selected = selected.clamp(0, waves.length - 1);
    _changed(immediate: true);
  }

  void stroke(double x0, double y0, double x1, double y1) {
    drawSegment(wave, x0, y0, x1, y1);
    _changed();
  }

  /// Replaces the selected wave (with undo).
  void apply(Float32List Function(Float32List w) op) {
    checkpoint();
    waves[selected] = op(wave);
    _changed(immediate: true);
  }

  void setTool(DrawTool t) {
    tool = t;
    notifyListeners();
  }

  void select(int i) {
    selected = i.clamp(0, waves.length - 1);
    // Hear the wave being edited.
    if (waves.length > 1) morph = selected / (waves.length - 1);
    _sendState();
    notifyListeners();
  }

  void addWave() {
    if (waves.length >= maxWaves) return;
    checkpoint();
    waves.add(Float32List.fromList(wave));
    select(waves.length - 1);
    _changed(immediate: true);
  }

  void removeWave() {
    if (waves.length <= 1) return;
    checkpoint();
    waves.removeAt(selected);
    select(math.min(selected, waves.length - 1));
    _changed(immediate: true);
  }

  // ---- Sound ----

  void setSpec(PolySpec s) {
    spec = s;
    _sendState();
    notifyListeners();
  }

  void setMorph(double m) {
    morph = m.clamp(0, 1);
    _sendState();
    notifyListeners();
  }

  void setOctave(int o) {
    octave = o.clamp(1, 7);
    notifyListeners();
  }

  static double noteHz(int note) =>
      440 * math.pow(2, (note - 69) / 12).toDouble();

  bool isDown(int note) => _slotNote.contains(note);

  void noteOn(int note, {double velocity = 0.8}) {
    if (isDown(note)) return;
    var slot = _slotNote.indexOf(-1);
    if (slot < 0) slot = 0; // steal the first voice
    _slotNote[slot] = note;
    touches[slot] = Touch(down: true, hz: noteHz(note), y: velocity);
    _sendState();
    notifyListeners();
  }

  void noteOff(int note) {
    final slot = _slotNote.indexOf(note);
    if (slot < 0) return;
    _slotNote[slot] = -1;
    touches[slot] = Touch(
      down: false,
      hz: touches[slot].hz,
      y: touches[slot].y,
    );
    _sendState();
    notifyListeners();
  }

  void allOff() {
    for (var i = 0; i < maxVoices; i++) {
      if (_slotNote[i] >= 0) noteOff(_slotNote[i]);
    }
  }

  // ---- Patches & export ----

  WavePatch toPatch() => WavePatch(
    name: name,
    waves: [for (final w in waves) Float32List.fromList(w)],
    spec: spec,
  );

  void loadPatch(WavePatch p) {
    checkpoint();
    allOff();
    name = p.name;
    waves
      ..clear()
      ..addAll(p.waves);
    selected = 0;
    spec = p.spec;
    morph = 0;
    _sendState();
    _changed(immediate: true);
  }

  /// One full-bandwidth cycle at the current morph, as a WAV (2048 samples
  /// at 44.1 kHz, the usual single-cycle format).
  Uint8List singleCycleWav() =>
      encodeWavMono16(buildTable().cycleAt(morph), 44100);

  /// Renders a held note (default middle C) through the synth, for use as a
  /// sample (e.g. on a Sample Pad pad).
  Uint8List renderNoteWav({int note = 60, double seconds = 2}) =>
      renderNote(buildTable(), spec, morph, noteHz(note), seconds);
}

/// Renders [seconds] of one note (held, then released for the last third).
Uint8List renderNote(
  Wavetable table,
  PolySpec spec,
  double morph,
  double hz,
  double seconds,
) {
  final synth = PolySynth(synthRate.toDouble())
    ..configure(spec)
    ..wavetable = table
    ..morph = morph;
  final total = (seconds * synthRate).round();
  final hold = (total * 2 / 3).round();
  final out = Float32List(total * 2);
  synth.setTouch(0, Touch(down: true, hz: hz, y: 0.8));
  const block = 512;
  for (var at = 0; at < total; at += block) {
    if (at >= hold) synth.setTouch(0, Touch(hz: hz, y: 0.8));
    final n = math.min(block, total - at);
    synth.render(out, n, offset: at);
  }
  // Mono mix-down: pads are mono.
  final mono = Float32List(total);
  for (var i = 0; i < total; i++) {
    mono[i] = (out[i * 2] + out[i * 2 + 1]) / 2;
  }
  return encodeWavMono16(mono, synthRate);
}
