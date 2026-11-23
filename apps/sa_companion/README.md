# SA Companion (Android)

Unofficial companion for GTA San Andreas on PS2 — a native Flutter port of
the owner's single-file web app. **Android only** (no Windows/Linux builds).

- **Home:** progress radar, story/collectible/side-job meters, next mission,
  quick or favourite cheats.
- **Cheats:** 91 codes with PS2 button glyphs, search, categories, favourites,
  and a button-by-button follow-along sheet (keeps the screen on, vibrates on
  each step).
- **Missions:** 97 story missions with tips, per chapter, tick to pass
  ("Mission passed" banner).
- **100%:** collectibles counters (tap the number to type a value), side jobs,
  schools, races, challenges, import/export cars, backup/restore/share.
- **Guide:** places by area and a PS2 reference (controls, rewards, schools,
  girlfriends, notes).

Progress is saved on the phone. Backups use the same JSON as the web version,
so a backup copied from the web app restores here (and vice versa).

Code: `lib/data` (game data, progress & stats), `lib/app` (state, storage),
`lib/ui` (screens & widgets). `tool/screenshots_test.dart` renders screenshots.
Fonts: Bowlby One, Barlow, Barlow Condensed (SIL OFL, `assets/fonts`).
