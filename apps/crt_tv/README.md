# CRT TV

Your own retro TV. Point it at a folder of shows, movies and commercials, and
it turns them into channels that play around the clock, with commercial
breaks between videos, static when you change channels, and a 4:3 tube look.

Runs on **Windows, Linux and Android** from the same code.

**In this repo:** CI builds it on every push (Android APK, Windows zip, Linux
tarball as the `crt_tv-latest` pre-release; see the repo's CLAUDE.md). On
Android it makes and uses `Internal storage › XMB Frontend › TV` (next to
the XMB Frontend's ROMs and Comics, with a `HOW TO ADD SHOWS.txt` in it)
once it's allowed **All files access**; another folder can still be chosen
in Menu → TV FOLDER. Screenshots of every screen at TV, Retroid Pocket
Classic and phone sizes: `flutter test tool/shot_test.dart --dart-define=OUT=<folder>`. (iPhone and Mac
can build it too, but they haven't been set up for yet; see the end.)

---

## 1. Set up your TV folder

```
TV/
├── Commercials/              ← plays on every channel without its own
├── Channel 3/
│   ├── your shows & movies   (subfolders like "Season 1" are fine)
│   └── Commercials/          ← only plays on channel 3
├── Channel 5 - Cartoons/
│   ├── ...cartoons...
│   └── Commercials/          ← 80s commercials, only on channel 5
└── Channel 8 - Movies/
```

* Any folder named **Channel** + a number becomes that channel. Text after
  the number ("- Cartoons") becomes the channel's name. `Ch 5` and `5 Cartoons` work too.
* A folder named **Channel** + just a name ("Channel Gojira") works too. It
  gets the lowest free channel number, in alphabetical order.
* Videos play **in order** (Episode 2 comes before Episode 10), or
  **shuffled** if you turn that on for the channel in the Guide.
* A channel's own `Commercials` folder is used only on that channel. A
  channel without one uses the main `Commercials` folder.
* Most video types work: mp4, mkv, avi, mov, wmv, webm, mpg, ts and more.

## 2. Install Flutter (one time)

Follow the official guide for your computer: <https://docs.flutter.dev/get-started/install>

* **Windows:** also install **Visual Studio 2022** (the free Community
  edition) with the **"Desktop development with C++"** option ticked.
* **Linux (Ubuntu/Debian):**
  ```bash
  sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libmpv-dev mpv
  ```
* **Android phone:** install **Android Studio** (it brings the Android SDK), then run
  `flutter doctor --android-licenses` and accept them.

Run `flutter doctor` until the platforms you want show a green check.

## 3. Get the packages (one time)

The `windows/`, `linux/` and `android/` folders are already here. Open a
terminal **in this folder** and run:

```bash
flutter pub get
```

Each platform has to be built on its own kind of machine: Windows on
Windows, Linux on Linux. Android builds from either.

## 4. Run it

```bash
flutter run -d windows        # on a Windows PC
flutter run -d linux          # on a Linux PC
flutter run                   # with your Android phone plugged in (USB debugging on)
```

## 5. Build the finished app

| Platform | Command | Where the app ends up |
|---|---|---|
| Windows | `flutter build windows` | `build\windows\x64\runner\Release\` (run `crt_tv.exe`; keep the whole folder together) |
| Linux | `flutter build linux` | `build/linux/x64/release/bundle/` (run `./crt_tv`) |
| Android | `flutter build apk` | `build/app/outputs/flutter-apk/app-release.apk` (copy to your phone and open it to install) |

---

## Using it

**Keyboard:** ↑ ↓ change channel · type numbers to jump to a channel · L last
channel · ← → volume · M mute · I what's on · R start this video over ·
Space pause · C subtitles · A audio track · G guide ·
S menu · T themes · F (or double-click) full screen · V video only
(no cabinet; Esc brings it back) · P power

**Sound and subtitles:** Menu → Sound & Subtitles switches the audio and
subtitle track for the video that's on, and sets your defaults for every
video: a preferred audio language, a subtitle language, and whether
subtitles are off, on, or on only when the video has no audio in your
language. **Level Volume** measures each video the first time it plays
and turns it up or down so everything plays at about the same loudness.

**Controller (Xbox, PlayStation or generic USB pads; Windows, Linux and
Android):** everything works from the pad, only while the TV window is in
front. On Linux your user needs to be able to read `/dev/input/js*` (it
normally can). These are the
defaults; **Menu (S) → Controls** lets you change any key or button (and
reset them). Number keys, Enter, Esc and F1 always stay as they are.
On Android (the Retroid Pocket's own buttons too) the d-pad and buttons
arrive as key presses and work the same way; the system Back button closes
the menu (or video only) before it leaves the app.

| PlayStation / Xbox | On the TV | In menus |
|---|---|---|
| D-pad or left stick ↑ ↓ | Channel up / down | Move |
| D-pad or left stick ← → | Volume | Move |
| ✕ / A | Pause / play | Select |
| ○ / B | Last channel | Back |
| □ / X | Mute | |
| △ / Y | Start this video over | |
| L1 / LB | What's on | |
| R1 / RB | Guide | |
| L2 / LT | Video only (no cabinet) | |
| R2 / RT | Full screen | |
| Options / Start | Settings | Back |
| Share / Back | Themes | |
| R3 (click right stick) | Power | |

**Phone:** swipe up or down on the picture to change channels. Hold the
phone upright for a remote under the picture, or sideways for full screen.

**Guide:** shows what's on every channel. The ⚙ button next to a channel
sets shuffle, commercials just for that channel, or starts it over.

**Settings:**
* *Commercials between videos:* Off, 1, 2, 3, or random 1–3. Each channel
  can override this.
* *Channels keep playing when you change away:* on (like real TV, where the
  show moves on while you're gone) or off (each channel waits for you).
* *Tube look:* scanlines and rounded glass, Off / Subtle / Strong.
* *TV cabinet:* wood, black plastic, silver or none, shown only in the
  empty space beside the 4:3 picture on wide screens.
* *Widescreen videos:* letterbox, zoom to fill, or stretch.

Everything is saved automatically: settings, where every channel is, and
the length of each video. That data lives in the app's private data
folder, separate from your videos. Your videos are never changed.

## Troubleshooting

* **Linux: "Choose folder" does nothing.** The picker uses the desktop's
  file portal. Install `xdg-desktop-portal-gtk` (or `-kde`), or use **Type a path**.
* **Android: no videos show up.** The TV needs **All files access** (the
  video player opens files by their path). Menu → TV FOLDER →
  **ALLOW ACCESS TO FILES** opens Android's page for it; switch it on and
  come back.
* **A video is skipped.** If a file won't play within a few seconds, the TV moves
  on to the next one. Check that the file plays in a normal player like VLC.
* **Live channels take a moment the first time.** The app checks each
  video's length in the background (progress shows in Settings). After that,
  tuning in is instant.
* **Android build warns about the "NDK version".** Do what the message
  says: copy the `ndkVersion = "..."` line it suggests into
  `android/app/build.gradle.kts`.

## Making it yours

* **Name:** change `CRT TV` in `lib/main.dart` and in
  `android/app/src/main/AndroidManifest.xml` (`android:label`).
* **Icon:** a 16×16 pixel picture drawn in the repo's
  `tool/icons/bin/make_icons.dart` (`crt_tv` entry); run
  `dart run tool/icons/bin/make_icons.dart crt_tv` from the repo root.
* **Look:** cabinet colors are in `lib/src/ui/skins.dart`, the green
  on-screen text in `lib/src/ui/osd.dart`, and the scanlines in
  `lib/src/ui/crt_overlay.dart`.

## How the code is organized

| File | What it does |
|---|---|
| `lib/src/library_scanner.dart` | Reads the TV folder into channels |
| `lib/src/channel_engine.dart` | Decides what plays next: videos, breaks, shuffle, live catch-up |
| `lib/src/tv_controller.dart` | The TV itself: tuning, playback, remote buttons |
| `lib/src/app_store.dart` | Saves settings and progress |
| `lib/src/ui/` | The screens: TV, guide, settings, welcome |
| `test/widget_test.dart` | Tests for the scheduling and folder reading (`flutter test`) |

## iPhone / Mac

Add `ios,macos` to the `--platforms` list in step 3. You'll need a Mac with
Xcode to build. iPhones only let apps see files inside their own folder, so
the iPhone version still needs extra work before it can read a TV folder.

## Licenses

All of the code in `lib/` and `test/` is yours, and it doesn't have to be open source.
The Flutter libraries it uses (media_kit, path_provider, ffi, and the
repo's app_shell) are MIT or BSD licensed. Those licenses let you keep
the app closed. They only ask that their license notices travel with the app,
and Flutter includes those automatically. Video playback uses the mpv player
library, which is loaded as a separate file. For your own use there's
nothing to do. If you ever give the app to other people or sell it,
double-check mpv's license terms for the platforms you ship (I'm not a lawyer).
