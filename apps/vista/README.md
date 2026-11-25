# Vista

Windows, Android, Linux. Landscapes in the spirit of 90s landscape
renderers (roadmap #18). Built on `engine3d` and `video_encoder`.

- **Land:** fractal terrain (warped gradient noise, ridges), hydraulic
  erosion; presets Alps, Desert, Islands, Canyon, Moon; height,
  roughness, ridges, erosion, sea level; a seed per world; sand / grass /
  rock / snow colours placed by height and slope.
- **Sky:** time of day (sunrise, noon, sunset, night with stars and moon),
  where the sun rises, clouds, haze. The Moon has a black sky.
- **Explore:** fly, or walk on the ground (PS1 look by default; clean look
  in Sky).
- **Stills:** ray traced on all cores (shadows, water with reflections and
  shallows, ripples, haze towards the sun, clouds, stars), sharpening pass
  by pass; 640×360 to 1920×1080; save to the Asset Locker or share.
- **Flyovers:** add camera points while flying; smooth path; preview; MP4
  (fast: drawn like the explorer, 854×480 30 fps; ray traced: 480×270
  15 fps, slow).
- Landscapes (settings + camera path) save to the Asset Locker (Presets,
  kind `vista_landscape`); height map as a picture.

Pure-Dart core (tested): `land.dart`, `sky.dart`, `raytrace.dart`,
`flyover.dart`; `world.dart` builds the real-time scene.
