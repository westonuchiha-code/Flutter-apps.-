# Roadmap

App ideas agreed with the owner, in build order. The order puts shared
foundations first so every later app is quicker to build. Each phase's apps
reuse what the earlier phases produce.

Status key: ⬜ not started · 🔨 in progress · ✅ done · ⏸ on hold

## Already built

- ✅ Optical Theremin: light-controlled chip synth (camera/webcam)
- ✅ SA Companion: San Andreas PS2 companion (Android)
- ✅ Scan Ranch: barcode monster ranch prototype (Android; art handed off,
  see `apps/scan_ranch/HANDOFF.md`)
- ✅ Touch Synth: multi-touch pad synth (Android; owner considers it a failed
  prototype, kept for its engine)

## Phase 0 · Foundations (everything else builds on these)

1. ✅ **App Shell Kit.** Shared starter for every new app: settings screen,
   save/load, theme, about page, crash-safe storage, export/share, error
   reporting. `packages/app_shell` plus `tool/new_app.sh`.
2. ✅ **Asset Locker + Dev Dashboard.** One on-phone library where every app
   saves and finds its creations (samples, presets, sprites, palettes, maps,
   recordings). Plus build status, one-tap install of the latest APKs, crash
   reports and a shared to-do list. `packages/asset_locker` +
   `apps/dev_dashboard`. Gaps: on Android each app asks once for the shared
   folder; the to-do list is per device (not synced between phone and PC).

## Phase 1 · Audio

3. ✅ **Field Recorder.** A polished mic recorder (levels, markers, trimming,
   tags) that saves to the Asset Locker. Builds the shared mic recording,
   waveform view and sample library. `apps/field_recorder` +
   `packages/audio_kit`. Gap: on Android the screen must stay on while
   recording (the app keeps it on); no background recording yet.
4. ✅ **Sample Pad + Loop Station.** Pads loaded with recorded samples (trim,
   pitch, reverse) and layered loops in sync. Builds the shared tempo/clock
   and step sequencer. `apps/sample_pad` + `packages/beat_kit`. Gaps: loop
   layers are not saved in kits (export the mix instead); loop timing
   depends on the device's latency (adjustable in Settings).
5. ✅ **Waveform Painter.** Draw a wave shape or picture and play it as an
   instrument. Builds shared custom wavetables for every synth.
   `apps/waveform_painter` + `Wavetable` in `packages/chip_synth`
   (band-limited, morphable; `PolySynth.wavetable`).
6. ✅ **Sound Lab.** Playground for the synth engines: chain effects, live
   waveform/spectrum, save presets every music app can load. Builds the shared
   effects library and preset format. `apps/sound_lab` + `packages/fx_kit`
   (11 effects, chain, `SoundPreset`); the piano keyboard moved to
   `audio_kit` for every app.
7. ✅ **Ambience Machine.** Layered, slowly drifting looping atmospheres.
   Uses the recorder, samples, effects and presets above. `apps/ambience_machine`:
   up to 8 drifting layers (seamless sample loops, slow notes from Sound Lab
   sounds or drawn waves, wind/rain/waves/rumble), shared effects, scene
   crossfades, sleep timer, WAV render, Android background playback (media
   foreground service with a Stop button).
8. ✅ **Speech Chip Lab.** Upgrade of the speech-chip voice in
   `packages/chip_synth`: type text, hear it on emulated speech chips, tweak
   and export. Reuses the existing code rather than a rebuild.
   `apps/speech_chip_lab` + `packages/chip_synth/lib/src/speech/`: text →
   sounds (dictionary + spelling rules, [sounds] input), TMS5220 / SP0256 /
   Votrax SC-01 recreations, sing mode, samples to the Asset Locker. The
   theremin's vowel voice is unchanged.

## Phase 2 · Visual

9. ✅ **Pixel Forge.** Aseprite-style pixel editor for touch: layers,
   animation frames, onion-skinning, sprite animation previews; palettes and
   tile sets made from photos (camera or upload); a tile-map painting mode;
   sprite-sheet export. Builds the shared palette, image and art pipeline.
   Pass 1 done (`apps/pixel_forge` + `packages/pixel_kit`): canvas with
   touch zoom/pan, pencil/eraser/line/rect/ellipse/fill/picker/select,
   mirror drawing, move/flip/rotate/copy/paste, layers, palettes (classic
   machines, from the sprite, snap to palette, save/load), PNG export,
   sprites in the Asset Locker. Pass 2 done: animation frames with timing,
   onion skin, preview; tile maps (tiles cut from the sprite, paint/fill,
   maps in the Asset Locker); palettes from photos (median cut); pictures
   as layers (fit, palette snap, ordered dither); sprite sheets and
   exact-colour animated GIFs.
10. ✅ **Chip Cam.** The camera image runs through 19 emulations of old video
    hardware and signals: ZX Spectrum, C64, Atari 2600, Game Boy Camera, slow
    handheld LCD, Teletext, PXL-2000, CGA/Apple II artifact colour, NTSC
    composite, VHS, bad antenna, lost sync, interlace, Rutt/Etra, video
    feedback, slit-scan, slow-scan TV, JPEG blocks, datamosh. CRT view,
    snapshots and GIF clips. Shared code: `packages/video_kit`, colour frames
    in `light_capture`. The owner has more ideas to add.
11. ✅ **Texture Capture.** Photo → game-ready texture: perspective
    corners (with magnifier), even lighting, seamless tiling, 256–2048
    master, console versions (PS1, N64, PS2, GameCube, Dreamcast) in their
    real formats (CLUT, RGBA16/565, S3TC/CMPR, VQ) and memory limits. Warns
    when a photo won't make a good texture.
12. 🟨 **Lo-Fi Video Maker.** Short 4:3 videos (up to 60 s) from Chip Cam
    clips (Chip Cam now records video with sound), pictures, Pixel Forge
    sprites and title cards, each through a Chip Cam effect, with music from
    the Asset Locker. Exports MP4 (H.264 + AAC) via the system encoders
    (`packages/video_encoder`; AVI fallback). Done: steps 1–2 (encoder,
    recording, storyboard, export). Next: step 3 - retro transitions (VHS
    roll, lost sync, Teletext page, datamosh), text/sprite overlays, cuts
    snapped to the beat. MP4 export not yet confirmed on a real phone/PC.
13. ⬜ **Sprite Pet.** Pixel pet in a home-screen widget that reacts to the
    day. Uses Pixel Forge sprites.
14. ⬜ **Photo Tile Quilt.** Photos → tiled mosaic with a palette. Bottom of
    the list, bare-minimum prototype.

## Phase 3 · 3D

15. ⬜ **3D Engine.** Shared lightweight 3D foundation: rendering, camera,
    models, textures, simple lighting, walking around. Everything below runs
    on it.
16. ⬜ **Desktop Aquarium.** PS1-style low-poly fish wearing real fish photo
    textures (made with Texture Capture), swimming in a tank on the home
    screen or desktop. The smallest 3D app, so it tests the engine first.
17. ⬜ **3D Internet City.** A web browser you walk through Doom-style, in the
    spirit of Labyrinth, eWorld and Sega's online city. Websites are buildings
    on themed streets, with trees and NPCs, and you can build the world out
    over time. Replaces the earlier 2D Internet City idea.
18. ⬜ **Bryce for 2026.** Generate fractal landscapes (mountains, water,
    skies, fog, suns and moons) with simple controls, explore them in real
    time, and render stills or flyover videos.
19. ⬜ **3D Choreographer, modern.** Make little movies without skill: a
    stage, generic characters (man, woman, boy, girl, old man, old woman), tens
    to hundreds of preset animations applied with a tap, camera shots, and a
    stop-motion mode for posing by hand. The biggest app on the list; free,
    openly licensed animation libraries can help.

## On hold · needs AI (voices or a language model)

The owner won't pay a per-minute voice or AI service. These wait until voices can
run locally: free open-source text-to-speech models, run on the owner's PC
(RTX 5090) or on the phone, with audio generated ahead of time and bundled so
the apps work offline.

- ⏸ **Voice Cast Studio.** Write scripts, cast voices per character, generate
  and cache audio. Must come before the two below.
- ⏸ **Voiced Text Adventure.** A text adventure that plays like an audiobook.
- ⏸ **Archive Radio.** An offline simulated radio. Each station turns
  public-domain or openly licensed material (history books, public news,
  open encyclopedias) into real-information conversations: deep dives,
  history comedy, and so on. No copyrighted sources, no made-up facts.

- ⏸ **Story Coach.** A writing app that reads your story and asks questions to
  keep you writing. Needs a language model, so it waits until one can run
  locally (owner's PC or the phone).

## Dropped

- Offline Survival Kit (owner's decision).
