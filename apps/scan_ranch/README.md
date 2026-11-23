# Scan Ranch (Android)

Scan real barcodes to find monsters, then raise them on a ranch.

- **Scan** (camera or type a code): every barcode always gives the same species;
  each catch is a unique individual (shade, size, personality, rare shiny).
  Some barcodes hold food items instead (once per day each).
- **Ranch:** up to 8 monsters roam, get hungry, seek and eat food you drop,
  greet each other, and react when you tap (pet) them. Long-press for details.
- **Box:** all your monsters — nickname, stats, move between Ranch and Box,
  release.
- Hunger and happiness change in real time; everything is saved on the phone.

**Art status:** placeholder. Only the two owner-approved designs (drake, hound)
are used, in 12 palettes, with the required CRT look. Read
[`HANDOFF.md`](HANDOFF.md) before touching the art.

Code: `lib/model` (genome, creatures, items, game state & saving),
`lib/sim` (ranch behaviour), `lib/render` (monster art + CRT, background),
`lib/ui` (screens). Tests: `flutter test`.
