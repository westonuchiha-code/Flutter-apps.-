# save_kit

Pure-Dart save manager core, ported from the PC XMB Frontend's
(`scripts/memcard`, `scripts/memcard_write`). Reads and writes memory cards of
PS1, PS2 (images and PCSX2 folder cards), Dreamcast VMU, GameCube (images and
.gci folders), N64 Controller Pak (also mupen's 4-pak .srm), Saturn (plain,
byte-expanded, gzipped), Neo Geo, and PS3 savedata folders.

- `MemoryCards.readAll(dirs, games:, played:)` - every card and save under some
  folders, named and matched to a game list.
- `CardImage.find/take/put` - a card's own bytes out of its file and back.
- `<Console>Writer` - blank, check, delete, export (.mcs .psu .dci .gci .note
  .bup .ngs .zip), import; all return `CardEdit`.
- `CardStore` - the only thing that writes: refuses while the emulator runs
  (`CardOwners`), if the file changed since it was read, or without a backup
  that reads back; writes a temp file, swaps, reads back.
- `CardFavorites`, `CardNames`, `CardLooks` - stars, names and card looks.

Tests: `dart test`. With `SAVE_SAMPLES=<folder of downloaded saves>` they also
sweep real cards (export, delete, re-import byte for byte). Samples are only
read. Backups are gzip (the PC uses ZSTD).
