# app_shell

Shared foundation for every app in this repo (Windows, Android, Linux).

- `runShellApp(config, home)`: sets up storage, settings, error logging and
  theme, then runs the app.
- **Theme:** light/dark/system from one accent colour (user picks in Settings).
- **Settings:** declare `BoolSetting`, `ChoiceSetting`, `SliderSetting`,
  `TextSetting` in `AppShellConfig.settings`; they save themselves and the
  Settings screen is generated. Read with `Shell.of(context).settings.get(s)`.
- **Storage:** `AppStorage` writes atomically and keeps a `.bak` copy, so a
  corrupt or half-written save falls back to the previous one.
- **Error log:** uncaught errors go to `crashes.json`; viewable, shareable and
  clearable from About → Error log.
- **Export/share:** `Exporter.exportFile` / `exportText` (save dialog on
  desktop, share sheet on Android).
- `shellActions(context)`: Settings and About buttons for an app bar.

New app: `tool/new_app.sh <app_name> ["Display Name"] [--android-only]`.
