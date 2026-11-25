# App icons

Every app's launcher icon is 16×16 pixel art drawn with `packages/pixel_kit`
(the engine of Pixel Forge) in `bin/make_icons.dart`: a tile colour and a
picture, outlined in the 16-bit style.

    dart run tool/icons/bin/make_icons.dart          # every app
    dart run tool/icons/bin/make_icons.dart vista    # one app

For each app it writes `apps/<app>/icon/` (the Pixel Forge sprite
`icon.pixel_sprite.json`, `icon.png`, `icon_256.png`), Android's
`mipmap-*/ic_launcher.png` plus an adaptive icon (`mipmap-anydpi-v26`, the
tile over `@color/ic_launcher_background`), and Windows' `app_icon.ico`
(16, 32, 48, 256). `all_icons.png` is a contact sheet. CI fails any app
without an icon.
