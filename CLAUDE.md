# Flutter Apps Monorepo — Guidelines

This repository holds multiple Flutter applications.

## Platform priorities

| Priority | Platform | Expectation |
|----------|----------|-------------|
| Primary  | **Windows** | Full support; must build, run and be tested. |
| Primary  | **Android** | Full support; must build, run and be tested. |
| Secondary | **Linux** | Make every *reasonable* effort to support it. If Linux support costs extra work that would take time away from Windows/Android, Windows/Android win. Document any Linux gaps. |

iOS, macOS and Web are out of scope unless explicitly requested.

## Rules for writing apps here

- Create each app with only the target platforms:
  `flutter create --platforms=windows,android,linux <app_name>` (inside `apps/`).
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
  theremin uses its experimental real-time stream API.
- Owner's sound priorities (Optical Theremin, inspired by their Chiptune Pad
  Studio): chips should behave like the real hardware — register-quantized
  pitch (don't "fix" hardware tuning), real volume steps, frame-rate effects,
  machine output filters; no clicks or clipping the hardware never had.

## Toolchain

- Flutter **3.50.1** (stable), Dart 3.14. The version is pinned in
  `.github/workflows/ci.yml` (`FLUTTER_VERSION`) and `tool/setup_linux_dev.sh`;
  bump both together.
- Android builds use JDK 21 (Android lint needs it).
- `tool/setup_linux_dev.sh` installs Flutter and the Linux desktop toolchain.

## CI (`.github/workflows/ci.yml`)

Runs on every push and pull request, for every app found in `apps/*/pubspec.yaml`:

| Job | Runner | Blocking? | Output artifact |
|-----|--------|-----------|-----------------|
| Analyze & test (format, analyze, test) | ubuntu | yes | — |
| Android release APK | ubuntu | yes | `<app>-android-apk` |
| Windows release build (+ tests) | windows | yes | `<app>-windows-x64` |
| Linux release build | ubuntu | no (best-effort) | `<app>-linux-x64` |

New apps are picked up automatically — no workflow edits needed.

After each push, the `publish` job replaces the `<app>-latest` GitHub
pre-release with the new APK, Windows zip and Linux tarball (installable
from a phone via the repo's Releases page).

## Repository layout

```
apps/        # one folder per Flutter application
             #   starter_app      - CI smoke test
             #   optical_theremin - light-controlled synthesizer (camera/webcam)
packages/    # shared Dart/Flutter packages
             #   light_capture - webcam brightness frames on Windows/Linux
             #                   (the official camera plugin can't stream frames on Windows)
tool/        # developer scripts
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
