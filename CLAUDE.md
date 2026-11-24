# Flutter Apps Monorepo — Guidelines

This repository holds multiple Flutter applications.

## Platform priorities

| Priority | Platform | Expectation |
|----------|----------|-------------|
| Primary  | **Windows** | Full support; must build, run and be tested. |
| Primary  | **Android** | Full support; must build, run and be tested. |
| Secondary | **Linux** | Make every *reasonable* effort to support it. If Linux support costs extra work that would take time away from Windows/Android, Windows/Android win. Document any Linux gaps. |

iOS, macOS and Web are out of scope unless explicitly requested.

**Per-app exceptions:** the owner can limit an app to fewer platforms.
Create it with only those platforms; CI builds an app for a platform only if
the app has that platform's folder (`android/`, `windows/`, `linux/`).
- `sa_companion` — **Android only** (owner's request).
- `scan_ranch` — **Android only** (owner's request).
- `touch_synth` — **Android only** (owner's request).

## Rules for writing apps here

- Create new apps with `tool/new_app.sh <app_name> ["Display Name"] [--android-only]`:
  it runs `flutter create` with the right platforms/org and wires the app to
  `packages/app_shell` (theme, settings, storage, error log, about, export).
- Before adding a package, check pub.dev platform support: it must support
  **Windows and Android**. Prefer packages that also support Linux.
- Never use `dart:html` / web-only APIs. Guard platform-specific code with
  `Platform.isWindows` / `Platform.isAndroid` / `Platform.isLinux`
  (or `defaultTargetPlatform`) and provide a fallback.
- Handle file paths with `package:path` and `path_provider`; never hard-code
  `/` or `\` separators or absolute paths.
- Design UI to be responsive: it must work on a phone (touch, small screen,
  portrait/landscape) and on desktop (mouse, keyboard, resizable window).
- Platform channels / native code: implement for Windows and Android;
  Linux implementation is best-effort.
- Keep `flutter analyze` clean, code formatted with `dart format`, and add
  tests (`flutter test`) for logic.
- Import Material from `package:material_ui/material_ui.dart` (the template
  default); `package:flutter/material.dart` is deprecated as of Flutter 3.47.
- Use an application ID / org of `com.westonuchiha` for new apps.
- Camera on Windows: `camera_windows` has no frame streaming. Use
  `packages/light_capture` when an app needs live frames on Windows/Linux.
- Video effects: use `packages/video_kit` (`VideoEffect`, `runEffect`); run
  them off the UI thread (see `apps/chip_cam/lib/src/processor.dart`). Effects
  emulate real hardware limits (resolution, colours, signal) - keep them
  faithful rather than prettier. Still pictures go to the Locker as
  `AssetType.picture`; videos and Chip Cam clips as `AssetType.video`.
- Video files: `packages/video_encoder` (`openVideoWriter`). Its MP4 path is
  native and only compiled by CI; check new uses with the app's "Test export".
- Background work: use `runInBackground(topLevelFunction, arg)` from
  `app_shell`, never `Isolate.run(() => ...)` inside a widget or controller
  (the closure can drag the State and its ports along: "object is
  unsendable"). Entry points for `Isolate.spawn` must be top-level/static.
- Audio: `flutter_soloud` works on Android, Windows and Linux (built via Dart
  build hooks; no extra setup). It is pinned to an exact version because the
  theremin uses its experimental real-time stream API. Microphone input:
  `packages/audio_kit` (`MicRecorder`, built on `flutter_recorder`, also
  pinned; Linux builds need `libasound2-dev`).
- Effects: use `packages/fx_kit` (`FxChain`) rather than writing new ones;
  sounds are shared as `SoundPreset` JSON (kind `sound`) in the Asset Locker.
- Audio that must keep playing with the screen off (Android): copy
  `apps/ambience_machine`'s `PlaybackService` (mediaPlayback foreground
  service + notification) and `lib/src/keeper.dart`.
- Pixel art: use `packages/pixel_kit` (`Sprite`, `Palette`, `Canvas`) and its
  file formats (kinds `pixel_sprite`, `palette`, `tile_map`) so every visual app
  shares them.
- Asset Locker details live in `<id>.info.json` (0.1 used `<id>.json`, which
  overwrote JSON assets' data; old details files are still read).
- Save user creations (samples, presets, sprites, palettes, maps,
  recordings) to the Asset Locker (`Shell.of(context).locker`,
  `saveToLocker` / `pickFromLocker`) so other apps can use them.
- Scan Ranch art: the owner is handing the art to another tool. Only the two
  approved designs (drake, hound) are in use; the CRT effect is applied to
  monsters only, always on, never a toggle. Read apps/scan_ranch/HANDOFF.md
  and get the owner's approval on any new art before building on it.
- Speech: `chip_synth`'s `SpeechSynth` must never clip (a test checks every
  chip at low, middle and high voices); keep its chip quirks (pitch tables,
  frame rates, number precision) rather than smoothing them away.
- Owner's sound priorities (Optical Theremin, inspired by their Chiptune Pad
  Studio): chips should behave like the real hardware — register-quantized
  pitch (don't "fix" hardware tuning), real volume steps, frame-rate effects,
  machine output filters; no clicks or clipping the hardware never had.

## Toolchain

- Flutter **3.50.1** (stable), Dart 3.14. The version is pinned in
  `.github/workflows/ci.yml` (`FLUTTER_VERSION`) and `tool/setup_linux_dev.sh`;
  bump both together.
- Android builds use JDK 21 (Android lint needs it).
- CI signs APKs with the shared, non-secret debug key in
  `.github/android/debug.keystore`, so new builds install as updates over old
  ones (keeping app data). Not for Play Store releases.
- `tool/setup_linux_dev.sh` installs Flutter and the Linux desktop toolchain.

## CI (`.github/workflows/ci.yml`)

Runs on every push and pull request, for every app found in `apps/*/pubspec.yaml`:

| Job | Runner | Blocking? | Output artifact |
|-----|--------|-----------|-----------------|
| Analyze & test (format, analyze, test) | ubuntu | yes | — |
| Android release APK | ubuntu | yes | `<app>-android-apk` |
| Windows release build (+ tests) | windows | yes | `<app>-windows-x64` |
| Linux release build | ubuntu | no (best-effort) | `<app>-linux-x64` |

(Platform jobs only include apps that have that platform's folder.)

New apps are picked up automatically — no workflow edits needed. An app with a
`.ci-skip` file is left out (work in progress, nothing published).

After each push, the `publish` job replaces the `<app>-latest` GitHub
pre-release with the new APK, Windows zip and Linux tarball (installable
from a phone via the repo's Releases page).

## Repository layout

```
apps/        # one folder per Flutter application
             #   starter_app      - CI smoke test
             #   optical_theremin - light-controlled synthesizer (camera/webcam)
             #   sa_companion     - GTA San Andreas PS2 companion (Android only)
             #   scan_ranch       - barcode monster ranch (Android only; prototype,
             #                      art handed off - see apps/scan_ranch/HANDOFF.md)
             #   touch_synth      - multi-touch pad synthesizer (Android only)
             #   dev_dashboard    - CI status, install latest builds, error reports,
             #                      Asset Locker browser, shared to-do list
             #   field_recorder   - mic recorder: markers, trim, tags, saves WAV to the Asset Locker
             #   sample_pad       - 16 sample pads, step sequencer, loop station, kits, mix export
             #   waveform_painter - draw waves (or from pictures), morph, play; saves wavetables
             #   sound_lab        - synths/waves/samples through an 8-slot effect chain, scope,
             #                      shared sound presets
             #   ambience_machine - drifting layered atmospheres, scene crossfades, sleep timer;
             #                      Android background playback via a media foreground service
             #   speech_chip_lab  - text to speech on TMS5220/SP0256/Votrax recreations; sing mode
             #   pixel_forge      - pixel art editor: layers, frames/onion skin, palettes (also from
             #                      photos), selections, tile maps, PNG/sheet/GIF; all to the Locker
             #   chip_cam         - camera through 19 old video hardware/signal emulations, CRT
             #                      view, snapshots/GIFs (Pictures), video+sound clips (Videos)
             #   lofi_video       - Lo-Fi Video Maker: storyboard of clips/pictures/sprites/titles
             #                      through video_kit effects + music -> MP4 (60 s max, 4:3)
             #   sprite_pet       - pixel pet (8 built-in species drawn in code, or a Pixel Forge
             #                      sprite): needs, sleep, weather, Locker treats; Android
             #                      home-screen widget (home_widget), desktop mini window
             #   texture_capture  - photo -> game texture: perspective corners, even lighting,
             #                      seamless tiling, photo checks, PS1/N64/PS2/GameCube/Dreamcast
             #                      formats (CLUT, S3TC, VQ) with their memory limits
packages/    # shared Dart/Flutter packages
             #   app_shell     - shared app foundation (theme, settings, crash-safe
             #                   storage, error log, about page, export/share,
             #                   runInBackground)
             #   asset_locker  - shared library of creations every app saves to
             #                   (Documents/Asset Locker; Android: folder picked once per app)
             #   audio_kit     - mic recording to WAV, WAV read/write, waveform view,
             #                   level meter, piano keyboard, effect-chain editor, clip playback
             #                   (flutter_recorder + flutter_soloud)
             #   beat_kit      - pure-Dart beat engine: tempo clock + swing, step sequencer,
             #                   sample voices, synced loop layers, kit format
             #   fx_kit        - pure-Dart stereo effects (11), FxChain, SoundPreset format
             #   pixel_kit     - pure-Dart pixel art core: sprites (layers x frames), palettes,
             #                   median-cut + dithering, drawing tools, selections, tile sets/maps,
             #                   PNG, sprite sheets, exact-colour GIF (package:image)
             #   light_capture - webcam frames on Windows/Linux, brightness or colour (BGRA,
             #                   `color: true, width: N`); the official camera plugin can't
             #                   stream frames on Windows
             #   video_kit     - pure-Dart live video: VideoFrame (ARGB), YUV420 conversion,
             #                   VideoEffect + knobs, 19 hardware/signal effects (allEffects),
             #                   Chip Cam clip format (ClipWriter / VideoClip, .lfclip)
             #   video_encoder - video files with sound: MP4 (H.264+AAC) via Android
             #                   MediaCodec / Windows Media Foundation (Mp4Writer); pure-Dart
             #                   MJPEG AVI everywhere (AviWriter); openVideoWriter picks
             #   chip_synth    - pure-Dart synth engines: retro chips + polyphonic analog,
             #                   band-limited morphing wavetables (Wavetable; set
             #                   PolySynth.wavetable to play drawn waves), speech chips
             #                   (SpeechSynth, textToSpeech)
             #                   (used by optical_theremin, touch_synth, waveform_painter)
tool/        # developer scripts (setup_linux_dev.sh, new_app.sh)
ROADMAP.md   # agreed app ideas and build order - keep it updated
```

## Note on the cloud environment

The cloud container is Linux, so it can run `flutter analyze`, `flutter test`
and `flutter build linux` (and `flutter build apk` if the Android SDK is
installed). Windows builds must be verified on a Windows machine or in CI
(e.g. a GitHub Actions `windows-latest` runner).

## Working style

The owner works from the Claude **mobile app** and often has no computer.
Never require steps that need a desktop (environment approval cards,
local IDEs, Windows machines). Verify through this container (analyze, test,
Linux build) and GitHub Actions (Android + Windows builds). Make test builds
easy to install from a phone.
