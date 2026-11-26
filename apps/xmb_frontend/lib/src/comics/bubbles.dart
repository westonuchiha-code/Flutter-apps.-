/// Finds the lettering on a page (speech balloons, captions), for the
/// balloon pop-out. Ported from the PC's ComicBubbles.gd: mark dark pixels
/// right next to light ones, smear them so letters join into words, lines
/// and blocks, keep blocks that look like text. Works on a grey picture
/// [lum] ([w]×[h]), ideally 640 wide. Rects are 0..1 of the page, in
/// reading order, with a margin so the balloon shows round the words.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'panels.dart' show PRect;

const bubbleWorkWidth = 640;
const _light = 185, _inkLevel = 125, _near = 2, _joinX = 5, _joinY = 3;
const _minW = 14, _minH = 6, _maxArea = 0.08, _minStrokes = 0.07;
const _maxStrokes = 0.55, _minPaper = 0.7, _minCrossings = 0.09, _margin = 0.35;

typedef _B = ({int x, int y, int w, int h});

List<PRect> findBubbles(Uint8List lum, int w, int h, {bool rtl = false}) {
  final n = w * h;
  final light = Uint8List(n);
  for (var i = 0; i < n; i++) {
    light[i] = lum[i] >= _light ? 1 : 0;
  }
  final nearLight = _dilate(light, w, h, _near, _near);
  final stroke = Uint8List(n);
  for (var i = 0; i < n; i++) {
    stroke[i] = lum[i] <= _inkLevel && nearLight[i] == 1 ? 1 : 0;
  }
  final blocks = _dilate(stroke, w, h, _joinX, _joinY);
  final seen = Uint8List(n);
  final found = <_B>[];
  final stack = <int>[];
  for (var start = 0; start < n; start++) {
    if (blocks[start] == 0 || seen[start] == 1) continue;
    var x0 = w, y0 = h, x1 = -1, y1 = -1;
    stack
      ..clear()
      ..add(start);
    seen[start] = 1;
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      final x = i % w, y = i ~/ w;
      if (x < x0) x0 = x;
      if (x > x1) x1 = x;
      if (y < y0) y0 = y;
      if (y > y1) y1 = y;
      for (final j in [
        if (x > 0) i - 1,
        if (x < w - 1) i + 1,
        if (y > 0) i - w,
        if (y < h - 1) i + w,
      ]) {
        if (blocks[j] == 1 && seen[j] == 0) {
          seen[j] = 1;
          stack.add(j);
        }
      }
    }
    // Undo the smear's growth before judging.
    final box = (
      x: x0 + _joinX,
      y: y0 + _joinY,
      w: x1 - x0 + 1 - 2 * _joinX,
      h: y1 - y0 + 1 - 2 * _joinY,
    );
    if (_isText(lum, stroke, w, box, n.toDouble())) found.add(box);
  }
  return [
    for (final r in _readingOrder(found, rtl))
      () {
        final m = r.h * _margin + 4;
        final gx0 = math.max(0.0, r.x - m), gy0 = math.max(0.0, r.y - m);
        final gx1 = math.min(w.toDouble(), r.x + r.w + m);
        final gy1 = math.min(h.toDouble(), r.y + r.h + m);
        return (x: gx0 / w, y: gy0 / h, w: (gx1 - gx0) / w, h: (gy1 - gy0) / h);
      }(),
  ];
}

bool _isText(Uint8List lum, Uint8List stroke, int w, _B box, double pageArea) {
  if (box.w < _minW || box.h < _minH) return false;
  final area = (box.w * box.h).toDouble();
  if (area > _maxArea * pageArea) return false;
  var strokes = 0, paper = 0, crossings = 0;
  for (var y = box.y; y < box.y + box.h; y++) {
    final row = y * w;
    var prev = stroke[row + box.x];
    for (var x = box.x; x < box.x + box.w; x++) {
      final s = stroke[row + x];
      if (s == 1) {
        strokes++;
      } else if (lum[row + x] >= _light) {
        paper++;
      }
      if (s != prev) crossings++;
      prev = s;
    }
  }
  final sFrac = strokes / area;
  final pFrac = paper / math.max(area - strokes, 1);
  final cRate = crossings / area;
  return sFrac >= _minStrokes &&
      sFrac <= _maxStrokes &&
      pFrac >= _minPaper &&
      cRate >= _minCrossings;
}

/// Grows the 1s of [mask] by [rx] sideways and [ry] up and down.
Uint8List _dilate(Uint8List mask, int w, int h, int rx, int ry) {
  final tmp = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    final row = y * w;
    var count = 0;
    for (var x = -rx; x < w + rx; x++) {
      final add = x + rx;
      if (add < w && mask[row + add] == 1) count++;
      final drop = x - rx - 1;
      if (drop >= 0 && mask[row + drop] == 1) count--;
      if (x >= 0 && x < w) tmp[row + x] = count > 0 ? 1 : 0;
    }
  }
  final out = Uint8List(w * h);
  for (var x = 0; x < w; x++) {
    var count = 0;
    for (var y = -ry; y < h + ry; y++) {
      final add = y + ry;
      if (add < h && tmp[add * w + x] == 1) count++;
      final drop = y - ry - 1;
      if (drop >= 0 && tmp[drop * w + x] == 1) count--;
      if (y >= 0 && y < h) out[y * w + x] = count > 0 ? 1 : 0;
    }
  }
  return out;
}

List<_B> _readingOrder(List<_B> boxes, bool rtl) {
  final sorted = [...boxes]..sort((a, b) => a.y.compareTo(b.y));
  final rows = <List<_B>>[];
  for (final b in sorted) {
    var placed = false;
    for (final row in rows) {
      final top = row[0];
      if (b.y < top.y + top.h * 0.6) {
        row.add(b);
        placed = true;
        break;
      }
    }
    if (!placed) rows.add([b]);
  }
  return [
    for (final row in rows)
      ...(row..sort((a, b) => rtl ? b.x.compareTo(a.x) : a.x.compareTo(b.x))),
  ];
}
