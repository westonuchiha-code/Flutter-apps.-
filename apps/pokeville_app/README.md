# pokeville_app

Pokéville standalone (`packages/pokeville`): the PC's Pokémon Box.

- **Android**: opens the XMB Frontend's `Pokeville` folder and syncs it with
  Cross-Save itself (`pokeville/` plus only the Pokémon game saves it found
  under `saves/retroarch`). It uses the XMB Frontend's GitHub sign-in when
  there is one.
- **Windows**: opens the PC menu's own folder (XMB Pokemon Box); the PC XMB
  Frontend does the syncing.

## When it syncs (Android)

- **Opening Pokéville** (start, and coming back to it): a full sync. Saves
  from other devices arrive and replace the ones here (backed up first).
- **Leaving it** (paused): send-only. What changed here goes to the repo;
  nothing on the device is replaced, so a game started next never has a
  save swapped under it.
- **Sync now** (and signing in): a full sync.
