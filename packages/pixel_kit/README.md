# pixel_kit

Pure-Dart pixel art core (no Flutter) shared by the visual apps.

- `Sprite`: width × height, layers (name, visible, opacity) × frames (one
  ARGB cel per layer, duration). Flatten, merge, resize, JSON format
  (kind `pixel_sprite`).
- `Palette`: built-in machine palettes (Game Boy, PICO-8 style, C64, ZX
  Spectrum, CGA, NES, greys), nearest colour, JSON (kind `palette`) and GIMP
  `.gpl`.
- `Canvas`: brush, Bresenham lines, rectangles, pixel-centre ellipses, span
  flood fill (contiguous or global), mirror drawing, selection masks.
- `PixelPatch`: copy/flip/rotate/stamp selections. `Rect`.
- `spriteToPng`, `decodePicture` (via `package:image`).
