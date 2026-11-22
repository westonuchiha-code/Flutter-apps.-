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
- Keep `flutter analyze` clean and add tests (`flutter test`) for logic.

## Repository layout

```
apps/        # one folder per Flutter application
packages/    # shared Dart/Flutter packages used by several apps (optional)
```

## Note on the cloud environment

The cloud container is Linux, so it can run `flutter analyze`, `flutter test`
and `flutter build linux` (and `flutter build apk` if the Android SDK is
installed). Windows builds must be verified on a Windows machine or in CI
(e.g. a GitHub Actions `windows-latest` runner).
