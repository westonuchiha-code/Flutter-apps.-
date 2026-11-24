# Photo Tile Quilt

Windows, Android, Linux. Built on `app_shell` and `pixel_kit`. Bare-minimum
prototype.

A photo becomes a patchwork quilt:
- Grid of 12–64 patches across; each patch is the classic block that best
  matches that part of the photo: plain, half-square triangle (either
  diagonal), four-patch, or stripes. "Detail" sets how readily busier
  blocks are used.
- Fabric colours: 4–32 taken from the photo (median cut) or any Pixel Forge
  palette.
- Seams (width and colour), quilting stitches, fabric texture.
- Save the quilt to the Asset Locker (Pictures), export a PNG, or save its
  palette for Pixel Forge.

Engine: `lib/src/quilt.dart` (pure Dart, tested).
