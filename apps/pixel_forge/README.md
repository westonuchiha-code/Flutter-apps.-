# Pixel Forge

Windows, Android, Linux. Built on `app_shell` and `pixel_kit`.

Pass 1 (this build): pixel editor for touch and desktop.
- One finger draws; two fingers pan and zoom (and cancel the stroke they
  interrupted). Mouse: wheel zooms, right/middle drag pans.
- Tools: pencil, eraser (1–8 px), line, rectangle, ellipse (outline or
  filled), fill (area or every pixel of a colour), colour picker, select
  (move, flip, rotate, copy, paste, delete). Mirror drawing left-right and
  up-down. Undo/redo.
- Layers: add, duplicate, merge down, delete, hide, opacity, rename, reorder.
- Palettes: classic machines, colours of this sprite, add colours, snap the
  sprite to the palette, save/load palettes in the Asset Locker.
- Sprites save to the Asset Locker (editable format plus a preview); open
  Pixel Forge sprites or any picture; export PNG ×1–×16.
- Keys: B E L U O G I M tools, X swap colours, [ ] brush size,
  Ctrl+Z/Y/C/V/A/S, Del, Esc.

Pass 2:
- Animation: frames (copy or blank), per-frame timing, move/delete, onion
  skin (previous red, next blue), looping preview.
- Tile maps: cut the sprite into 8/16/32 px tiles (duplicates merged), paint,
  erase, fill and pick on a map, resize, re-cut tiles after editing; maps
  save to the Asset Locker (Maps); export PNG.
- Palettes from a photo (camera on Android) or any picture: 2–32 colours.
- Add a picture as a layer: shrunk to fit, optionally snapped to the palette
  with ordered dithering.
- Export sprite sheets (PNG) and animated GIFs with exact colours.
