# XMB Frontend (Android)

Android only (owner's request). The Android companion to the PC's XMB
Frontend (Godot): a PS3-style menu that starts games in real Android
emulators, so in-game saves are the same files as on the PC and can cross
over (cross saves come in part 3, through the `Cross-Save` GitHub repo).

## Part 1 (this version)

- **XMB menu** (`lib/src/ui/xmb.dart`): categories across, items down,
  folders, a right-hand options panel, A/B/Y and LB/RB hints like the PC.
  Controller (d-pad, A, B, Y, LB/RB letter jump), keyboard and touch (tap,
  swipe, long-press for options). "Swap A and B" for Nintendo layouts.
  Works landscape (TV, Retroid Pocket Classic) and on an upright phone.
- **Game library** (`lib/src/library/`): the PC's ConsoleScanner rules:
  one folder per console with the PC's folder names, strict file types per
  folder, two folders deep, `.cue/.gdi/.ccd/.m3u` hide the files they list,
  `Demo Discs/<console>`, art from a picture with the game's name, region
  tags dropped from titles. Cached; "Refresh Game Library" re-reads it.
- **Game row**: pinned games, then recently played; All Games, one folder
  per console, Demo Discs, Play History, Refresh. Game options: pin/unpin,
  move pin, information, sort (title / last played / console), hide.
  Play time is counted from launch until the menu comes back.
- **Launching** (`lib/src/launch.dart`, `MainActivity.kt`):
  - RetroArch (`com.retroarch.aarch64`, `com.retroarch`, `com.retroarch.ra32`):
    `RetroActivityFuture` with `ROM`, `LIBRETRO`
    (`/data/data/<pkg>/cores/<core>_libretro_android.so`) and `CONFIGFILE`.
  - PPSSPP (`org.ppsspp.ppsspp[gold]`): `PpssppActivity`, VIEW, file data.
  - DuckStation (`com.github.stenzek.duckstation`): `EmulationActivity`,
    extra `bootPath`. PS1 prefers it, as on the PC.
  - Dolphin: `MainActivity` with `AutoStartFiles`.
  Cores match the PC (Gambatte, mGBA, …) because RetroArch keeps saves in a
  folder per core. Settings > Emulators shows what each console uses, lets
  you pick a core and has "Test Launch".
- **Screen orientation**: never locked by default (`fullUser`). The Retroid
  Pocket Classic is held upright but its 1240×1080 screen is wider than
  tall, so Android treats it as landscape; apps locked to portrait show up
  sideways there. Settings > Screen can force Wide / Tall (and upside down)
  if a device ever needs it. Layouts are checked at 1240×1080 at densities
  2.0 and 2.75 (about 450×390 dp).
- **Storage**: "All files access" (MANAGE_EXTERNAL_STORAGE; a personal app,
  not for the Play Store) so ROMs can be anywhere and their paths handed to
  the emulators. The ROMs folder is picked with an XMB folder browser
  (internal storage and SD cards).
  By default the menu makes and uses its own folder, `XMB Frontend/ROMs`
  in the device's main storage, with a folder per console and a
  `HOW TO ADD GAMES.txt` guide: drop games in (file manager or USB) and
  they show up when the menu comes back to the front. "Choose Another
  Folder" in Settings > ROMs Folder points it elsewhere.

The intents follow each emulator's documented extras but must be tried on
the device: paths differ between Play Store and sideloaded builds.

## Cross saves (part 3)

Follows the `Cross-Save` repo's PROTOCOL.md (see its `devices/android.md`):
`lib/src/sync/` (`cross_save.dart` the table and sync over a `SaveRepo`,
`github.dart` GitHub's REST API, `setup.dart` the `XMB Frontend` folders and
RetroArch settings, `controller.dart` token, state and conflicts).

- Everything lives in `XMB Frontend/` (shared storage): `ROMs/`, `BIOS/`,
  `Saves/RetroArch/<Core>/`, `Saves/DuckStation/memcards/`,
  `Saves/PPSSPP/PSP/SAVEDATA/`, `Saves/Dolphin/GC/` + `Saves/Dolphin/Wii/title/`
  (the PC's `saves/dolphin`: GCI folder cards and `.raw` cards, Wii title
  saves without system titles and `content`), `Pokeville/`, `Backups/`. RetroArch is started
  with the menu's own `RetroArch/retroarch.cfg` (saves sorted by core, as on
  the PC); PPSSPP's memory stick and DuckStation's memory card folder are set
  once by the player (Settings > Cross Save > Save Folders).
- Settings > Cross Save: GitHub token (fine-grained, Cross-Save only,
  Contents read/write), Sync Now, Changed on Both Sides (pick a side), This
  Device (`phone` / `retroid`), Save Folders, RetroArch Settings.
- Dolphin for Android can't be pointed at `Saves/Dolphin`: on Android 11+
  its user folder is app-private and its path settings are locked ("Due to
  the Scoped Storage policy..."). Get Emulators › Dolphin › Set It Up tells
  the player to copy `GC/USA/Card A` by hand through Dolphin's Settings ›
  Config › User Data › Open User Data Folder (Dolphin's document provider).
  Next step, if wanted: the menu reaches that provider itself (a one-time
  folder pick of Dolphin's user folder, then copy before/after a GameCube
  game).
- When it syncs (owner's decision: saves on the phone are only replaced
  when a game is opened, because an emulator left in the background could
  write its old copy back over the PC's):
  - **Full sync** (sends and takes): right before a game starts (waits for a
    sync already running, 12 s at most in all; once it gives up and the
    emulator starts, `stopTakes` lets nothing more be replaced), Sync Now,
    and right after signing in (or, if storage access wasn't allowed yet,
    when the player comes back with it allowed).
  - **Send-only** (`CrossSaveController.sendOnly()`: uploads this device's
    changes, writes nothing here; newer saves wait, conflicts are still
    listed): when the menu starts, after a game, on resume every 10 min, and
    after picking a side of a conflict.
  - Settings > Cross Save > When It Syncs says this in plain words.
- **Start game from the Save Manager app**: it sends an explicit intent to
  `MainActivity` with `start_game_system` (save_kit's console), `_title`,
  `_serial`, `_file`; the menu (cold: the launching intent, warm:
  `onNewIntent` → `startRequest`) takes it with `takeStartRequest`, finds
  the game like the Memory Card row (`lib/src/save_start.dart`) and starts
  it, or says "No game in the library matches …".
- `tool/github_read_test.dart`: a read-only check against the real repo.

## Next parts

2. (with 1) — 3. Cross saves via the `Cross-Save` repo — 4. Comic reader —
5. Save manager (PS1 cards, PSP saves) — 6. Pokéville (view and arrange the
Box) — 7. CRT TV.

Screenshots: `tool/shot_test.dart` (`--dart-define=OUT=<folder>`).

## Comics (part 3)

The **Comics** row reads `XMB Frontend/Comics` (made with the other folders;
Settings → Comics Folder to use another, like `Documents/Comics`): loose
books and one folder per series, each showing New / Page x of y / Finished.
Books: `.cbz .zip .epub .cbt`, PDF (drawn by pdfrx), `.cbr` (RAR 4 and
older, junrar) and `.cb7` (Apache Commons Compress) unpacked page by page
into the app's cache on Android (`ComicArchives.kt`; solid archives keep
the pages they pass), or a folder of page pictures. A `.cbr` that is really
a zip opens as one. RAR 5 isn't supported yet. Pages in natural order;
`__MACOSX` and hidden files skipped.

The reader (`lib/src/ui/comic_reader.dart`) is the PC's ComicReader.gd:
Left/Right pages (or panels; flipped for manga), A panel by panel, X pops
out the next speech balloon (B puts it back), LB/RB pages, LT/RT zoom,
Start/Y switches manga ↔ comic for the series, B closes. Touch: tap the
sides, swipe, double-tap for panels, hold for a balloon, pinch to zoom.
Panels (`comics/panels.dart`) and balloons (`comics/bubbles.dart`) are
ports of the PC's finders, run in the background per page. Manga: your
setting for the series, else ComicInfo.xml, else the names. Your place is
in `comics.json`, keyed by the path inside the Comics folder.
`tool/comic_shot_test.dart` makes screenshots at the Retroid's size.
