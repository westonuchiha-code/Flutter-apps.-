/// Colours are 32-bit ARGB ints (0xAARRGGBB). 0 is fully transparent.
library;

int argb(int a, int r, int g, int b) =>
    ((a & 255) << 24) | ((r & 255) << 16) | ((g & 255) << 8) | (b & 255);

int alphaOf(int c) => (c >> 24) & 255;
int redOf(int c) => (c >> 16) & 255;
int greenOf(int c) => (c >> 8) & 255;
int blueOf(int c) => c & 255;

/// Opaque colour from 0xRRGGBB.
int rgb(int hex) => 0xFF000000 | (hex & 0xFFFFFF);

String hexOf(int c) =>
    '#${(c & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Parses #RGB, #RRGGBB or #AARRGGBB (the # is optional).
int? parseHex(String s) {
  var h = s.trim().replaceFirst('#', '');
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  return int.tryParse(h, radix: 16);
}

/// "Over" blending of [top] (with extra [opacity]) onto [bottom].
int blendOver(int bottom, int top, [double opacity = 1]) {
  final ta = alphaOf(top) / 255 * opacity;
  if (ta <= 0) return bottom;
  final ba = alphaOf(bottom) / 255;
  final oa = ta + ba * (1 - ta);
  if (oa <= 0) return 0;
  int mix(int t, int b) =>
      ((t * ta + b * ba * (1 - ta)) / oa).round().clamp(0, 255);
  return argb(
    (oa * 255).round(),
    mix(redOf(top), redOf(bottom)),
    mix(greenOf(top), greenOf(bottom)),
    mix(blueOf(top), blueOf(bottom)),
  );
}

/// Squared distance between two colours (weighted for the eye).
int colorDistance(int a, int b) {
  final dr = redOf(a) - redOf(b),
      dg = greenOf(a) - greenOf(b),
      db = blueOf(a) - blueOf(b);
  return 3 * dr * dr + 4 * dg * dg + 2 * db * db;
}
