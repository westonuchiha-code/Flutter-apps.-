# fx_kit

Pure-Dart stereo effects (no Flutter; runs in the audio isolate).

- Effects: filter (LP/HP/BP, gliding cutoff), 3-band EQ, drive, bitcrush,
  compressor, chorus, phaser, tremolo/auto-pan, ring mod, echo (ping-pong,
  darkening, gliding time), reverb (Freeverb-style).
- `EffectKind.params` describe every knob (range, log travel, units,
  choices) so UIs can be generated. `EffectSpec` holds values + on/off.
- `FxChain.configure` keeps running effects (and their tails) when knobs
  or order change. Up to 8 effects.
- `SoundPreset`: the shared sound format (source + synth JSON + waves or
  sample reference + effects), Asset Locker kind `sound`.

`dart run tool/bench.dart` prints how fast a full chain runs.
