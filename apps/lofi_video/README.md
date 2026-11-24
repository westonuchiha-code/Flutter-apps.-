# Lo-Fi Video Maker

Windows, Android, Linux. Built on `app_shell`, `video_kit`, `video_encoder`,
`audio_kit` and `pixel_kit`.

Short 4:3 videos (up to 60 s) made as a storyboard:
- Scenes: Chip Cam clips (with their sound), pictures (snapshots, textures,
  GIFs), Pixel Forge sprites (animated), title cards (two-colour chunky
  text), test bars.
- Every scene can go through any of Chip Cam's 19 effects, with its knobs.
- Length, clip start point, whole picture or fill the screen, background.
- Music: a WAV from the Asset Locker (Sample Pad mixes, recordings,
  samples), start point, volumes; clip sound on/off. Soft limiter, no
  clicks at cuts, faded end.
- Preview with sound; drag scenes to reorder. Saved automatically.
- Export 320×240, 640×480 or 960×720 at 12–30 fps: MP4 (H.264 + AAC) with
  the phone's or PC's own encoder; pixels scaled sharp. Save to the Asset
  Locker (Videos) or share. Linux: AVI, turned into MP4 if `ffmpeg` is
  installed.
- Menu → Test export (2 s) checks this device can make videos.

Pure-Dart core (tested): `project.dart` (storyboard JSON), `media.dart`
(decoding), `render.dart` (frames), `mix.dart` (soundtrack), `export.dart`.

Not yet: retro transitions, overlays, beat-snapped cuts (roadmap step 3).
