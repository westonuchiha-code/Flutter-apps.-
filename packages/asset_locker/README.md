# asset_locker

One shared library where every app saves and finds its creations.

- Windows/Linux: `Documents/Asset Locker`.
- Android: each app asks once for the folder (Android's folder picker opens at
  Documents; tap "Use this folder"). Files go in `Documents/Asset Locker`.
- Layout: `<Type>/<id>.<ext>` + `<id>.json` (name, tags, app, date) +
  optional `<id>.thumb.png`. `_dev/` holds error reports and the to-do list
  for the Dev Dashboard.
- UI: `LockerBrowser`, `pickFromLocker`, `saveToLocker`, `LockerConnectCard`.

Apps built on `app_shell` get it as `Shell.of(context).locker`.
