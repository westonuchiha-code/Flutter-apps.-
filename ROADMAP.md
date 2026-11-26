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
12. ✅ **Lo-Fi Video Maker.** Short 4:3 videos (up to 60 s) from Chip Cam
    clips (Chip Cam now records video with sound), pictures, Pixel Forge
    sprites and title cards, each through a Chip Cam effect; retro
    transitions (dither, VHS roll, lost sync, Teletext page, datamosh);
    text/sprite overlays; cuts on the beat; music from the Asset Locker.
    Exports MP4 (H.264 + AAC) via the system encoders
    (`packages/video_encoder`; AVI fallback). MP4 export still to be
    confirmed on a real phone/PC (in-app Test export).
13. ✅ **Sprite Pet.** Pixel pet that lives through the day: eight pets drawn
    in code (slime, cube ooze, cat, cat girl, robot, transforming robot, car,
    dinosaur) or a Pixel Forge sprite; eight animated moods; needs, sleep
    schedule, weather (Open-Meteo), battery, Asset Locker creations as
    treats. Android home-screen widget with Feed/Pet/Play; mini window on
    PC. Owner may swap in found art later.
14. ✅ **Photo Tile Quilt.** Photo → patchwork quilt: classic blocks (plain,
    half-square triangles, four-patch, stripes) picked per patch, palette from
    the photo or Pixel Forge, seams and stitches. Bare-minimum prototype
    (photomosaic mode left out).

## Phase 3 · 3D

15. ✅ **3D Engine.** `packages/engine3d`: scene graph, meshes and terrain,
    glTF/OBJ models, orbit and walk cameras with collisions, vertex lighting,
    fog, triangles sorted far to near and drawn on the GPU; PS1 look by
    default (owner's choice), clean look optional. Test app: 3D Lab.
    Skinned, animated glTF characters added with #19.
16. ⏸ **Desktop Aquarium.** *(On hold, owner's choice.)* PS1-style low-poly fish wearing real fish photo
    textures (made with Texture Capture), swimming in a tank on the home
    screen or desktop. The smallest 3D app, so it tests the engine first.
17. ⬜ **3D Internet City.** A web browser you walk through Doom-style, in the
    spirit of Labyrinth, eWorld and Sega's online city. Websites are buildings
    on themed streets, with trees and NPCs, and you can build the world out
    over time. Replaces the earlier 2D Internet City idea.
18. ✅ **Bryce for 2026** (app: **Vista**). Fractal landscapes with erosion,
    presets (Alps, Desert, Islands, Canyon, Moon), sky and time of day,
    clouds and haze; fly or walk (PS1 look); ray-traced stills with shadows
    and water reflections; flyover videos (fast or ray traced); landscapes
    and height maps to the Asset Locker.
19. ✅ **3D Choreographer, modern** (app: **Puppet Stage**). Little movies
    without skill: four sets, six kinds of people (PS1-style figures made in
    code), 18 moves plus walk/run to a tapped spot, turn and wait, camera
    shots, stop-motion posing, MP4 export. Imports rigged 3D models (built-in
    moves retargeted onto their skeletons), 7 animals with their own moves,
    22 plants and props, person templates (body sliders, extras, saved to
    the Locker).
    Music videos added after: places (sets + Vista landscapes), film looks,
    music; an "Auto music video" pipeline (song map, six styles after Dead
    Prez, Hieroglyphics, People Under the Stairs, Tool, Cake and
    Parliament, a director that cuts on the bar) with a song per style from
    `tool/album` (instrumental album "Twelve-Bit Science", own MP3 encoder
    `packages/mp3_kit`).

## Phase 4 · XMB Frontend for Android

20. 🔨 **XMB Frontend (Android).** The PC XMB Frontend's companion for the
    phone and the Retroid Pocket Classic, in parts:
    1. ✅ XMB menu, game library (PC folder rules), launching RetroArch /
       PPSSPP / DuckStation / Dolphin, pins, history, play time.
    2. ✅ Cross saves through the private `Cross-Save` GitHub repo, following
       its PROTOCOL.md (GitHub API, git blob hashes; pull before a game, push
       after; conflicts keep both and the player picks; backups first).
    3. ✅ Comic reader: CBZ/ZIP/EPUB, CBT, PDF (pdfrx), CBR (RAR 4, junrar)
       and CB7 (Commons Compress) unpacked page by page, image folders;
       ported from the PC (natural page order, ComicInfo manga, panels from
       gutters, balloon pop-out, places by path inside the Comics folder).
       RAR 5 .cbr files can't be unpacked yet.
    4. 🔨 Save manager, as full as the PC's (owner: for preservation and
       portability, PS3 saves included): `packages/save_kit` ✅ (every format
       read+write, checked on real downloaded cards), the standalone
       `apps/save_manager` (Android, Windows, Linux) 🔨, then a Saves row in
       the XMB.
    5. ⬜ Pokéville: view and arrange the Box synced from the PC.
    6. ⬜ CRT TV (from the PC suite's `apps/crt_tv`).

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
