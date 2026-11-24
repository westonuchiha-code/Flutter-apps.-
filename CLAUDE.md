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
- Audio: `flutter_soloud` works on Android, Windows and Linux (built via Dart
  build hooks; no extra setup). It is pinned to an exact version because the
  theremin uses its experimental real-time stream API. Microphone input:
  `packages/audio_kit` (`MicRecorder`, built on `flutter_recorder`, also
  pinned; Linux builds need `libasound2-dev`).
- Save user creations (samples, presets, sprites, palettes, maps,
  recordings) to the Asset Locker (`Shell.of(context).locker`,
  `saveToLocker` / `pickFromLocker`) so other apps can use them.
- Scan Ranch art: the owner is handing the art to another tool. Only the two
  approved designs (drake, hound) are in use; the CRT effect is applied to
  monsters only, always on, never a toggle. Read apps/scan_ranch/HANDOFF.md
  and get the owner's approval on any new art before building on it.
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
packages/    # shared Dart/Flutter packages
             #   app_shell     - shared app foundation (theme, settings, crash-safe
             #                   storage, error log, about page, export/share)
             #   asset_locker  - shared library of creations every app saves to
             #                   (Documents/Asset Locker; Android: folder picked once per app)
             #   audio_kit     - mic recording to WAV, WAV read/write, waveform view,
             #                   level meter, clip playback (flutter_recorder + flutter_soloud)
             #   beat_kit      - pure-Dart beat engine: tempo clock + swing, step sequencer,
             #                   sample voices, synced loop layers, kit format
             #   light_capture - webcam brightness frames on Windows/Linux
             #                   (the official camera plugin can't stream frames on Windows)
             #   chip_synth    - pure-Dart synth engines: retro chips + polyphonic analog,
             #                   band-limited morphing wavetables (Wavetable; set
             #                   PolySynth.wavetable to play drawn waves)
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
