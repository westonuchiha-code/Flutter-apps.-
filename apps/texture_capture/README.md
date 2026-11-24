# Texture Capture

Windows, Android, Linux. Built on `app_shell` and `pixel_kit`; photos via
`image_picker` (camera on Android, files everywhere) or the Asset Locker.

Photo → game-ready texture:
- **Corners:** drag 4 corners onto the surface (magnifier while dragging,
  perspective grid); turn the texture; use the whole photo.
- **Texture (master):** flattened at 256–2048 px; even lighting (removes
  light falloff and soft shadows, keeps detail); make seamless (cross-fades
  each edge with a half-shifted copy, keeping contrast); 3×3 tile preview.
- **Checks:** too small for the chosen size, steep angle, too dark, glare,
  uneven light / strong shadows, blurry, very plain, seams.
- **Console versions,** with each machine's real limits and video memory
  use:
  - PS1: 4/8-bit CLUT (15-bit colours) or 15-bit direct, up to 256, no
    filtering.
  - N64: CI4, CI8, RGBA16, I4; everything fits the 4 KB TMEM.
  - PS2: 4/8-bit CLUT (32-bit colours) or 32-bit.
  - GameCube: CMPR (S3TC/DXT1 blocks), RGB565, C8.
  - Dreamcast: VQ (256-entry 2×2 codebook) or RGB565.
  - Optional ordered dithering; preview filtered or sharp like the hardware.
- Save the master or the console version to the Asset Locker (Pictures) or
  export a PNG.

Engine (pure Dart, `lib/src/engine/`): `warp.dart` (homography),
`surface.dart` (lighting, seamless, checks), `formats.dart` (console
formats), `pipeline.dart`.
