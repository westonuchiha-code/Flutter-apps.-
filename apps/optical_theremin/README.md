# Optical Theremin

A light-controlled synthesizer. Shade the camera with your hands to play:
the phone's camera on Android, or a webcam on Windows (and Linux).

- **Two zones** (default): left half of the image controls pitch, right half
  controls volume, like a theremin's two antennas.
- **Calibrate**: sweep your hand from covering the camera to fully away so the
  app learns your lighting.
- **Touch pad**: play without a camera by dragging (left/right = pitch,
  up/down = volume).
- Sine/triangle/saw/square tones, pitch range, scale snapping
  (chromatic, major, minor, pentatonic, blues), glide, master volume.
- Camera auto-exposure is locked so the camera doesn't cancel out your
  light changes.

## How it works

| Part | Android | Windows / Linux |
|------|---------|-----------------|
| Camera frames | `camera` plugin image stream | [`light_capture`](../../packages/light_capture) plugin (Media Foundation / V4L2) |
| Sound | `flutter_soloud` waveform synth | same |

Frames are shrunk to a 160 px wide brightness image (`LumaImage`), the
brightness of each zone is calibrated to 0–1, and `ThereminEngine` maps it to
a pitch and volume with glide smoothing.

Code: `lib/src/core` (pure logic, unit tested), `lib/src/input` (cameras),
`lib/src/audio`, `lib/src/app/theremin_controller.dart` (state), `lib/src/ui`.
