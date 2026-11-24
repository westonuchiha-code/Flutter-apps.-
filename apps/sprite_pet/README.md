# Sprite Pet

Windows, Android, Linux. Built on `app_shell` and `pixel_kit`; Android
widget via `home_widget`, desktop mini window via `window_manager` (0.5),
battery via `battery_plus`, weather from Open-Meteo (free, no key).

- Eight pets drawn in code (`lib/src/art/`): slime, cube ooze, cat, cat
  girl, robot, transforming robot (robot by day, car asleep, transforms when
  happy), car, dinosaur. Or any Pixel Forge sprite.
- Eight moods with 4-frame animations: content, happy, sleepy, asleep,
  hungry, eating, bored, scared. Shared faces and extras (Z's, hearts,
  food, thought bubbles) so every pet does every mood.
- Needs (food, energy, fun) change with real time, also while closed.
  Sleeps at bedtime (an hour longer at weekends), naps when exhausted.
- Reacts to: weather (umbrella in rain, woolly hat in snow, shades when hot,
  scared in thunderstorms), the battery (charging, low), and new things
  saved to the Asset Locker (treats, up to 6 a day).
- Feed, pet, play, bed/wake; a diary of what happened.
- Android home-screen widget: the app precomputes the next 24 hours of
  moods and frames; the widget (`PetWidgetProvider.kt`) shows the right one,
  updated every half hour; Feed/Pet/Play buttons run in the background.
- Windows/Linux: a small always-on-top mini pet window.
- Save the pet (all moods) to the Asset Locker as a Pixel Forge sprite.

Not verified on a device yet: the widget (CI compiles it), the mini window,
weather (no network in the build container; parsing is tested).
