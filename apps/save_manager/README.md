# Save Manager

The PC XMB Frontend's save manager as its own app (Android, Windows, Linux):
memory cards of PS1, PS2, Dreamcast, GameCube, N64, Saturn and Neo Geo
emulators, and PS3 saves. Copy, move, back up, restore, undelete, export,
import, favorites, card names and looks. The card formats and every change
are `packages/save_kit`; every change is backed up first.

- `lib/src/state.dart`, `flow.dart`, `controller.dart`: the PC's logic.
- `lib/src/ui/`: the screens. Wide screens (≥ 1000×600 dp) use the PC's
  1920×1080 layout, stretched; smaller ones (a phone, the Retroid Pocket
  Classic at ~450×390 dp) stack it: tabs strip, card strip, grid, buttons.
- `lib/src/host.dart`: folders per platform. The app's own files
  (backups, favorites, names, looks, stickers) live in
  `Documents/Save Manager`, so they outlive an uninstall.

Controls: d-pad / arrows move, A / Enter select, B / Esc back, Y options,
X mark (hold: the whole game), RT / F favorite, LB RB / Page Up Down tabs.
Touch: tap to highlight, tap again to choose; long press = options.

Android needs "All files access" (asked on first start). It can't see
whether an emulator is running, so before anything changes a card it asks
you to close them; a yes counts for two minutes.

Screenshots: `SAVE_SAMPLES=/path/to/cards flutter test
test/screens_shots_test.dart` writes `build/shots/screen_*.png`.
