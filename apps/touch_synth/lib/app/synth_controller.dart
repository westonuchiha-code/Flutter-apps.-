import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:chip_synth/chip_synth.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../audio/poly_output.dart';

double midiToHz(double midi) => 440.0 * math.pow(2, (midi - 69) / 12);

/// Settings saved between launches.
abstract class SettingsStore {
  Future<Map<String, Object?>?> load();
  Future<void> save(Map<String, Object?> json);
}

class FileSettingsStore implements SettingsStore {
  FileSettingsStore(this.dir);
  final Directory dir;
  File get _file => File(p.join(dir.path, 'touch_synth.json'));

  @override
  Future<Map<String, Object?>?> load() async {
    try {
      if (!await _file.exists()) return null;
      return (jsonDecode(await _file.readAsString()) as Map)
          .cast<String, Object?>();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(Map<String, Object?> json) async {
    await dir.create(recursive: true);
    await _file.writeAsString(jsonEncode(json));
  }
}

class MemorySettingsStore implements SettingsStore {
  Map<String, Object?>? saved;
  @override
  Future<Map<String, Object?>?> load() async => saved;
  @override
  Future<void> save(Map<String, Object?> json) async => saved = json;
}

/// The instrument's state: sound settings, pad range and the fingers.
class SynthController extends ChangeNotifier {
  SynthController({required this.output, SettingsStore? store})
    : store = store ?? MemorySettingsStore();

  final PolyOutput output;
  final SettingsStore store;

  PolySpec spec = const PolySpec();

  /// Lowest note on the pad (MIDI) and how many octaves it spans.
  int lowNote = 45; // A2
  int octaves = 3;

  String? audioError;
  final List<Touch> touches = List.filled(maxVoices, const Touch());

  /// Finger positions on the pad (0–1), for drawing.
  final List<Offset?> fingers = List.filled(maxVoices, null);
  final Map<int, int> _pointerSlot = {};
  Timer? _saveTimer;

  Future<void> init() async {
    final saved = await store.load();
    if (saved != null) {
      if (saved['spec'] is Map) {
        spec = PolySpec.fromJson(
          (saved['spec']! as Map).cast<String, Object?>(),
        );
      }
      lowNote = ((saved['low'] as num?)?.toInt() ?? lowNote).clamp(24, 84);
      octaves = ((saved['octaves'] as num?)?.toInt() ?? octaves).clamp(1, 5);
    }
    try {
      await output.init();
      output.update(spec, touches);
    } catch (e) {
      audioError = 'No sound output available ($e).';
    }
    notifyListeners();
  }

  double hzAt(double x) => midiToHz(lowNote + x.clamp(0.0, 1.0) * octaves * 12);

  /// Pointer handling: [pos] in fractions of the pad (y: 0 = top).
  void fingerDown(int pointer, Offset pos) {
    if (_pointerSlot.containsKey(pointer)) return;
    final slot = touches.indexWhere((t) => !t.down);
    if (slot < 0) return; // all voices in use
    _pointerSlot[pointer] = slot;
    _set(slot, pos, true);
  }

  void fingerMove(int pointer, Offset pos) {
    final slot = _pointerSlot[pointer];
    if (slot != null) _set(slot, pos, true);
  }

  void fingerUp(int pointer) {
    final slot = _pointerSlot.remove(pointer);
    if (slot == null) return;
    touches[slot] = Touch(
      down: false,
      hz: touches[slot].hz,
      y: touches[slot].y,
    );
    fingers[slot] = null;
    output.update(spec, touches);
    notifyListeners();
  }

  void _set(int slot, Offset pos, bool down) {
    final x = pos.dx.clamp(0.0, 1.0), y = pos.dy.clamp(0.0, 1.0);
    touches[slot] = Touch(down: down, hz: hzAt(x), y: 1 - y);
    fingers[slot] = Offset(x, y);
    output.update(spec, touches);
    notifyListeners();
  }

  void setSpec(PolySpec next) {
    spec = next;
    output.update(spec, touches);
    _scheduleSave();
    notifyListeners();
  }

  void setRange({int? low, int? oct}) {
    lowNote = (low ?? lowNote).clamp(24, 84);
    octaves = (oct ?? octaves).clamp(1, 5);
    _scheduleSave();
    notifyListeners();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(
        store.save({'spec': spec.toJson(), 'low': lowNote, 'octaves': octaves}),
      );
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    unawaited(output.dispose());
    super.dispose();
  }
}
