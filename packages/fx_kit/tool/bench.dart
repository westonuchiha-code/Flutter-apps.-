// Rough speed check of a full 8-effect chain.
import 'dart:typed_data';

import 'package:fx_kit/fx_kit.dart';

void main() {
  final chain = FxChain(48000)
    ..configure([
      for (final k in [
        EffectKind.filter,
        EffectKind.eq,
        EffectKind.drive,
        EffectKind.compressor,
        EffectKind.chorus,
        EffectKind.phaser,
        EffectKind.echo,
        EffectKind.reverb,
      ])
        EffectSpec(k),
    ]);
  final buf = Float32List(192 * 2)..fillRange(0, 384, 0.1);
  final sw = Stopwatch()..start();
  const seconds = 20;
  for (var i = 0; i < 48000 * seconds ~/ 192; i++) {
    chain.process(buf, 192);
  }
  final t = sw.elapsedMilliseconds / 1000;
  print('8 effects: ${(seconds / t).toStringAsFixed(0)}x real time');
}
