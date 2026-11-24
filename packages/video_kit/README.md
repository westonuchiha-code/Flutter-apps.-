# video_kit

Pure-Dart live video processing (used by Chip Cam).

- `VideoFrame`: ARGB pixels; resize (area average), rotate, mirror, BGRA in
  and out, from luma; `yuv420ToFrame` for Android camera images.
- `VideoEffect`: id, name, about, `knobs` (sliders or choices), its own input
  resolution (`inputSize`), `process(frame, time)`, `reset()`.
- `allEffects()` (19 effects) and `runEffect(effect, frame, time)` (resizes
  to the effect's resolution first). `testCard(time)` for when there is no
  camera.

Effects copy real hardware limits (resolution, colours per cell, palettes,
signal bandwidth); keep them faithful rather than prettier. Each one is
tested to stay within its machine's limits and under ~25 ms per frame.

Chip Cam clips (`clip.dart`): `ClipWriter` records frames (PNG when ≤256
colours, otherwise JPEG) with times and optional mono sound into one
`.lfclip` file; `VideoClip` reads it (`frameAt(t)`, `sound`).
