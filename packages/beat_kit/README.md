# beat_kit

Pure-Dart beat engine (no Flutter; runs inside the audio isolate).

- `Transport`: tempo and swing; 16 steps per bar; step start frames are
  computed from zero so nothing drifts.
- `BeatEngine`: 16 sample pads (trim, pitch, reverse, volume, pan,
  one-shot/hold/loop), a step sequencer up to 32 steps, and loop layers locked
  to the bar. Sample-accurate; short fades so cuts and trims don't click; a
  soft limiter instead of hard clipping. Controlled with `BeatCommand`s,
  reports `StepEvent` and `PadActivity`.
- `Kit`: JSON kit format (samples referenced by Asset Locker id).

`dart run tool/bench.dart` prints how much faster than real time it renders.
