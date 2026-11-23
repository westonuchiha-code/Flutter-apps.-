# Touch Synth (Android)

A multi-touch synthesizer in landscape.

- **Pad (left):** left→right = pitch (smooth slide, note lines as guides),
  bottom→top = filter brightness / volume (analog) or sound shape (chip).
  Each finger is its own voice (up to 6) — play chords and slide them.
- **Controls (right):** presets; engine **Analog** (2 oscillators, detune,
  sub, noise, resonant filter, attack/release, glide) or **Chip** (all retro
  chip sounds from `packages/chip_synth`); vibrato, drive, ping-pong delay,
  reverb; pad range (lowest note, octaves); master volume. Settings are saved.

Engine: `packages/chip_synth/lib/src/poly.dart` (pure Dart, tested), streamed
from a background isolate through `flutter_soloud`.
