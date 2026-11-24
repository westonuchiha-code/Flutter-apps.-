# Chip Cam

Windows, Android, Linux. Built on `app_shell`, `video_kit` and
`light_capture` (desktop webcams; Android uses the `camera` plugin).

The camera through emulations of old video hardware and signals. Each effect
works at its machine's own resolution and limits, then is shown scaled up
with sharp pixels (or on a pretend CRT).

- Machines: ZX Spectrum (attribute clash), Commodore 64 (multicolour, 4 per
  cell), Atari 2600 (NTSC palette, per-line limits), Game Boy Camera,
  slow handheld LCD (ghosting), Teletext (mosaic graphics), PXL-2000.
- Signals: NTSC composite (dot crawl, colour bleed), CGA / Apple II artifact
  colour, VHS (tracking, dropouts, head switching), bad antenna, lost sync,
  interlace.
- Strange: Rutt/Etra scan processor, video feedback, slit-scan, slow-scan TV.
- Digital: JPEG/MPEG blocks, datamosh (motion vectors smearing old frames).
- Knobs per effect; CRT view (aperture grille, scan lines, glow).
- Snapshot (PNG) and GIF clips up to 6 s at 10 fps, saved to the Asset
  Locker (Pictures) or shared. With the CRT on, snapshots include it.
- Video clips with microphone sound, up to 60 s at 15 fps, exactly as shown
  (each machine's own resolution), saved to the Asset Locker (Videos) as
  Chip Cam clips (`.lfclip`, see `video_kit`) for Lo-Fi Video Maker.
- No camera? The test card works everywhere.

Effects run in a worker isolate; frames arriving while it is busy are
dropped, so the picture stays live.
