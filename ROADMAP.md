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
2. ⬜ **Asset Locker + Dev Dashboard.** One on-phone library where every app
   saves and finds its creations (samples, presets, sprites, palettes, maps,
   recordings). Plus build status, one-tap install of the latest APKs, crash
   reports and a shared to-do list.

## Phase 1 · Audio

3. ⬜ **Field Recorder.** A polished mic recorder (levels, markers, trimming,
   tags) that saves to the Asset Locker. Builds the shared mic recording,
   waveform view and sample library.
4. ⬜ **Sample Pad + Loop Station.** Pads loaded with recorded samples (trim,
   pitch, reverse) and layered loops in sync. Builds the shared tempo/clock
   and step sequencer.
5. ⬜ **Waveform Painter.** Draw a wave shape or picture and play it as an
   instrument. Builds shared custom wavetables for every synth.
6. ⬜ **Sound Lab.** Playground for the synth engines: chain effects, live
   waveform/spectrum, save presets every music app can load. Builds the shared
   effects library and preset format.
7. ⬜ **Ambience Machine.** Layered, slowly drifting looping atmospheres.
   Uses the recorder, samples, effects and presets above.
8. ⬜ **Speech Chip Lab.** Upgrade of the speech-chip voice in
   `packages/chip_synth`: type text, hear it on emulated speech chips, tweak
   and export. Reuses the existing code rather than a rebuild.

## Phase 2 · Visual

9. ⬜ **Pixel Forge.** Aseprite-style pixel editor for touch: layers,
   animation frames, onion-skinning, sprite animation previews; palettes and
   tile sets made from photos (camera or upload); a tile-map painting mode;
   sprite-sheet export. Builds the shared palette, image and art pipeline.
10. ⬜ **Chip Cam.** The camera image runs through emulations of odd old video
    hardware (ZX Spectrum colour clash, Atari 2600 scan-line limits, Game Boy
    Camera, composite video bleed, Rutt-Etra scan processing, Teletext…).
    The owner has more ideas to add. Builds the shared live video processing.
11. ⬜ **Texture Capture.** Photo → game-ready texture: perspective
    flattening, even lighting, seamless tiling, highest-quality master, plus
    console presets (PS1, PS2…) at the sizes and colour depths they used.
    Warns when a photo won't make a good texture.
12. ⬜ **Lo-Fi Video Maker.** Short videos combining Chip Cam footage, Sample
    Pad music and Pixel Forge graphics. Best after Chip Cam proves itself.
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
