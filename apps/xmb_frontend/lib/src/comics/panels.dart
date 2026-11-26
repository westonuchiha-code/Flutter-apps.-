/// Finds a page's panels by its gutters (the plain strips between panels),
/// recursively: split the page into rows where whole rows of pixels are
/// plain, then each row into columns, then again inside each. That gives
/// reading order for free: top to bottom, left to right (right to left for
/// manga). Ported from the PC's ComicPanels.gd. Works on a grey picture
/// [lum] ([w]×[h], 0..255), ideally 320 wide. Rects are 0..1 of the page.
library;

import 'dart:math' as math;
import 'dart:typed_data';

typedef PRect = ({double x, double y, double w, double h});
typedef _IRect = ({int x, int y, int w, int h});

const panelWorkWidth = 320;
const _ink = 0.16, _gutterFill = 0.012, _minGutter = 0.006, _minPanel = 0.015;

List<PRect> findPanels(Uint8List lum, int w, int h, {bool rtl = false}) {
  final bg = _gutterColour(lum, w, h);
  final ink = Uint8List(w * h);
  for (var i = 0; i < w * h; i++) {
    ink[i] = (lum[i] / 255 - bg).abs() > _ink ? 1 : 0;
  }
  final found = <_IRect>[];
  _cut(ink, w, h, (x: 0, y: 0, w: w, h: h), rtl, true, found, 0);
  final minArea = _minPanel * w * h;
  final out = <PRect>[
    for (final r in found)
      if (r.w * r.h >= minArea)
        (x: r.x / w, y: r.y / h, w: r.w / w, h: r.h / h),
  ];
  // One "panel" that's nearly the whole page = no panels found.
  if (out.length == 1 && out[0].w * out[0].h > 0.8) out.clear();
  return out;
}

double _gutterColour(Uint8List lum, int w, int h) {
  final hist = List.filled(16, 0);
  for (var x = 0; x < w; x++) {
    hist[lum[x] >> 4]++;
    hist[lum[(h - 1) * w + x] >> 4]++;
  }
  for (var y = 0; y < h; y++) {
    hist[lum[y * w] >> 4]++;
    hist[lum[y * w + w - 1] >> 4]++;
  }
  var best = 0;
  for (var i = 0; i < 16; i++) {
    if (hist[i] > hist[best]) best = i;
  }
  return (best * 16 + 8) / 255;
}

void _cut(
  Uint8List ink,
  int w,
  int h,
  _IRect r,
  bool rtl,
  bool rowsFirst,
  List<_IRect> out,
  int depth,
) {
  r = _trim(ink, w, r);
  if (r.w <= 2 || r.h <= 2) return;
  if (depth > 8) {
    out.add(r);
    return;
  }
  for (var attempt = 0; attempt < 2; attempt++) {
    final horizontal = attempt == 0 ? rowsFirst : !rowsFirst;
    var parts = _split(ink, w, h, r, horizontal);
    if (parts.length > 1) {
      if (!horizontal && rtl) parts = parts.reversed.toList();
      for (final part in parts) {
        _cut(ink, w, h, part, rtl, !horizontal, out, depth + 1);
      }
      return;
    }
  }
  out.add(r);
}

List<_IRect> _split(Uint8List ink, int w, int h, _IRect r, bool horizontal) {
  final n = horizontal ? r.h : r.w;
  final across = horizontal ? r.w : r.h;
  final minGap = math.max(1, (_minGutter * (horizontal ? h : w)).toInt());
  final plain = Uint8List(n);
  for (var i = 0; i < n; i++) {
    var count = 0;
    for (var j = 0; j < across; j++) {
      final x = r.x + (horizontal ? j : i);
      final y = r.y + (horizontal ? i : j);
      count += ink[y * w + x];
    }
    plain[i] = count <= _gutterFill * across ? 1 : 0;
  }
  final parts = <_IRect>[];
  var start = 0, i = 0;
  while (i < n) {
    if (plain[i] == 1) {
      var j = i;
      while (j < n && plain[j] == 1) {
        j++;
      }
      if (j - i >= minGap && i > start) {
        parts.add(_piece(r, start, i, horizontal));
        start = j;
      } else if (i == start) {
        start = j;
      }
      i = j;
    } else {
      i++;
    }
  }
  if (start < n) parts.add(_piece(r, start, n, horizontal));
  return parts;
}

_IRect _piece(_IRect r, int a, int b, bool horizontal) => horizontal
    ? (x: r.x, y: r.y + a, w: r.w, h: b - a)
    : (x: r.x + a, y: r.y, w: b - a, h: r.h);

_IRect _trim(Uint8List ink, int w, _IRect r) {
  var x0 = r.x + r.w, y0 = r.y + r.h, x1 = r.x - 1, y1 = r.y - 1;
  for (var y = r.y; y < r.y + r.h; y++) {
    for (var x = r.x; x < r.x + r.w; x++) {
      if (ink[y * w + x] == 1) {
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
  }
  if (x1 < x0) return (x: r.x, y: r.y, w: 0, h: 0);
  return (x: x0, y: y0, w: x1 - x0 + 1, h: y1 - y0 + 1);
}
