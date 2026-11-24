import 'dart:typed_data';

import 'effects.dart';

/// Effects in order. [configure] keeps running effects (and their tails)
/// when only knobs change or the order changes.
class FxChain {
  FxChain(this.sampleRate);

  static const maxEffects = 8;

  final double sampleRate;
  final _running = <int, Effect>{};
  List<EffectSpec> _specs = const [];

  List<EffectSpec> get specs => _specs;

  void configure(List<EffectSpec> specs) {
    final keep = <int>{};
    for (final s in specs.take(maxEffects)) {
      keep.add(s.id);
      final e = _running[s.id];
      if (e != null && e.spec.kind == s.kind) {
        e.set(s);
      } else {
        _running[s.id] = Effect.create(s, sampleRate);
      }
    }
    _running.removeWhere((id, _) => !keep.contains(id));
    _specs = List.of(specs.take(maxEffects));
  }

  Effect? effect(int id) => _running[id];

  void process(Float32List buf, int frames) {
    for (final s in _specs) {
      if (s.on) _running[s.id]!.process(buf, frames);
    }
  }
}
