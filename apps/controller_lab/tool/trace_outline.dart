// Traces the Wii U Pro Controller's outline from a photo and prints the
// Dart constants lib/src/layouts/wii_u_pro.dart draws it from.
//
//   dart run tool/trace_outline.dart <photo.jpg> [overlay.png]
//
// The photo is Nintendo's official straight-on shot of the black
// controller on a white background (about 500×340; not kept in the repo).
// What it does:
//  1. thresholds the dark body against the white background and keeps the
//     largest dark blob (body + the L/R shoulders on the top corners);
//  2. walks its outer contour (Moore neighbour tracing);
//  3. makes it left/right symmetric: splits it at the centre line into
//     halves, resamples both by arc length and averages the right half
//     with the mirrored left;
//  4. cuts the shoulder humps off the top edge: over the shoulders' span
//     the body's own top is bridged with a cubic Hermite curve that meets
//     the traced edge (position and slope) on both sides; the humps above
//     the bridge are printed separately (the L/R buttons);
//  5. simplifies with Douglas–Peucker and maps photo pixels to the
//     drawing's design box (1000 wide);
//  6. maps the controls measured off the same photo ([controls], photo
//     pixels, read from 4× zoomed crops with a 10 px grid) the same way.
// With an overlay path it also writes the photo with the traced outline,
// bridge and controls drawn over it, to check the numbers by eye.
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Darker than this (0..255 luminance) is controller.
const threshold = 150;

/// Where the shoulder humps sit on the top edge, as distances from the
/// centre line in photo pixels (inner end, outer end): the step up at the
/// outer side and the blend into the top edge on the inner side.
const shoulderSpan = (92.0, 190.0);

/// Bridge tangent length as a fraction of its chord: under 1 keeps the
/// body's top corner lower than the shoulder hump (the L/R buttons wrap
/// the corner, so the body itself is lower there).
const bridgeTension = 0.35;

/// Smoothing window (resampled points each side) that takes the pixel
/// stair-steps out of the traced edge before it is simplified.
const smoothing = 4;

/// Douglas–Peucker tolerance, photo pixels.
const tolerance = 0.35;

/// Design box: the outline is scaled to [designWidth] minus [sideMargin]
/// on each side, with its highest point (the shoulders) at [topMargin].
const designWidth = 1000.0;
const sideMargin = 24.0;
const topMargin = 70.0;
const bottomMargin = 26.0;

/// Controls measured off the photo: name -> (x, y, radius) in photo
/// pixels. Pairs are averaged around [controlsCentre] (the photo is a
/// hair off square: the controls centre on 246.5, the silhouette on its
/// own centre, and each is mapped about its own).
const controlsCentre = 246.5;
const controls = <String, (double, double, double)>{
  // Stick caps (x, y, cap radius); ring radius is 'stickRing'.
  'leftStick': (98.75, 80.0, 27.0),
  'rightStick': (391.25, 81.25, 27.0),
  'stickRing': (0, 0, 39.5),
  'stickDish': (0, 0, 19.0),
  // D-pad centre, overall size (as radius = half), arm width as y.
  'dpad': (154.5, 162.0, 35.0),
  'dpadArm': (0, 21.0, 0),
  // Face diamond centre and the X/A/B/Y button radius; gap as y.
  'face': (338.75, 163.0, 14.25),
  'faceGap': (0, 33.0, 0),
  'minus': (205.5, 104.5, 9.6),
  'home': (247.0, 106.0, 10.4),
  'plus': (287.5, 104.5, 9.6),
  'power': (246.5, 164.5, 10.0),
  'selectLabel': (205.5, 123.75, 0),
  'powerLabel': (246.5, 182.5, 0),
  'batteryLabel': (247.5, 34.0, 0),
  'batteryLed': (247.5, 44.5, 1.5),
  // Logo centre, height as radius (its width is 56 px).
  'logo': (248.0, 73.5, 8.0),
  // Player lights: first one (x, y), spacing 20 px.
  'led1': (216.0, 225.0, 2.0),
  'ledGap': (20.0, 0, 0),
};

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/trace_outline.dart <photo> [out.png]');
    exit(64);
  }
  final photo = img.decodeImage(File(args[0]).readAsBytesSync())!;
  // Pad with white so a body touching the frame still has an outside.
  const pad = 4;
  final w = photo.width + 2 * pad, h = photo.height + 2 * pad;
  final dark = List.generate(h, (_) => List.filled(w, false));
  for (var y = 0; y < photo.height; y++) {
    for (var x = 0; x < photo.width; x++) {
      final p = photo.getPixel(x, y);
      final l = (p.r * 299 + p.g * 587 + p.b * 114) / 1000;
      dark[y + pad][x + pad] = l < threshold;
    }
  }
  final blob = _largestBlob(dark);
  final contour = _trace(blob)
      .map((p) => _P(p.x - pad + 0.5, p.y - pad + 0.5))
      .toList();
  stderr.writeln('contour: ${contour.length} px');

  var minX = double.infinity, maxX = -double.infinity;
  var minY = double.infinity, maxY = -double.infinity;
  for (final p in contour) {
    minX = math.min(minX, p.x);
    maxX = math.max(maxX, p.x);
    minY = math.min(minY, p.y);
    maxY = math.max(maxY, p.y);
  }
  final cx = (minX + maxX) / 2;
  stderr.writeln('blob x $minX..$maxX y $minY..$maxY, centre line x = $cx');

  // Right half: from where the contour crosses the centre line on the
  // top edge, clockwise to where it crosses it in the arch at the bottom.
  // Left half: from the top crossing anticlockwise to the bottom one,
  // mirrored. (The contour runs clockwise in image coordinates.)
  final crossings = <int>[];
  for (var i = 0; i < contour.length; i++) {
    final a = contour[i], b = contour[(i + 1) % contour.length];
    if ((a.x - cx) * (b.x - cx) <= 0 && a.x != b.x) crossings.add(i);
  }
  crossings.sort((a, b) => contour[a].y.compareTo(contour[b].y));
  final topI = crossings.first, botI = crossings.last;
  List<_P> walk(int from, int to, int dir) {
    final out = <_P>[];
    for (var i = from; ; i = (i + dir) % contour.length) {
      if (i < 0) i += contour.length;
      out.add(contour[i]);
      if (i == to) break;
    }
    return out;
  }

  var right = walk(topI, botI, 1);
  var left = walk(topI, botI, -1);
  if (right.map((p) => p.x).reduce(math.max) < cx) {
    final t = right;
    right = left;
    left = t;
  }
  const n = 600;
  final r = _resample(right, n);
  final l = _resample(left.map((p) => _P(2 * cx - p.x, p.y)).toList(), n);
  final raw = [
    for (var i = 0; i < n; i++)
      _P((r[i].x + l[i].x) / 2 - cx, (r[i].y + l[i].y) / 2),
  ];
  // Moving average along the edge (ends held), to drop pixel steps.
  final half = [
    for (var i = 0; i < n; i++)
      if (i < smoothing || i >= n - smoothing)
        raw[i]
      else
        _P(
          [for (var j = -smoothing; j <= smoothing; j++) raw[i + j].x]
                  .reduce((a, b) => a + b) /
              (2 * smoothing + 1),
          [for (var j = -smoothing; j <= smoothing; j++) raw[i + j].y]
                  .reduce((a, b) => a + b) /
              (2 * smoothing + 1),
        ),
  ];
  // Pin the ends to the centre line.
  half[0] = _P(0, half[0].y);
  half[n - 1] = _P(0, half[n - 1].y);

  // Shoulder bridge on the top edge (x is now relative to the centre).
  final (s0, s1) = shoulderSpan;
  final i0 = half.indexWhere((p) => p.x >= s0);
  final i1 = half.indexWhere((p) => p.x >= s1);
  const k = 6;
  _P slope(_P a, _P b) => _P(b.x - a.x, b.y - a.y);
  final p0 = half[i0], p1 = half[i1];
  final t0 = slope(half[i0 - k], p0), t1 = slope(p1, half[i1 + k]);
  // Hermite tangents scaled to the span (unit tangent × chord length).
  final chord =
      bridgeTension *
      math.sqrt(math.pow(p1.x - p0.x, 2) + math.pow(p1.y - p0.y, 2));
  _P unit(_P v) {
    final m = math.sqrt(v.x * v.x + v.y * v.y);
    return _P(v.x / m, v.y / m);
  }

  final m0 = unit(t0), m1 = unit(t1);
  final bridge = <_P>[];
  for (var j = 0; j <= 40; j++) {
    final t = j / 40, t2 = t * t, t3 = t2 * t;
    final h00 = 2 * t3 - 3 * t2 + 1, h10 = t3 - 2 * t2 + t;
    final h01 = -2 * t3 + 3 * t2, h11 = t3 - t2;
    bridge.add(
      _P(
        h00 * p0.x + h10 * chord * m0.x + h01 * p1.x + h11 * chord * m1.x,
        h00 * p0.y + h10 * chord * m0.y + h01 * p1.y + h11 * chord * m1.y,
      ),
    );
  }
  final hump = half.sublist(i0, i1 + 1);
  final body = [...half.sublist(0, i0), ...bridge, ...half.sublist(i1 + 1)];

  // Map photo pixels (relative to the centre) to design units.
  final scale = (designWidth - 2 * sideMargin) / (maxX - minX);
  _P design(_P p) =>
      _P(designWidth / 2 + p.x * scale, topMargin + (p.y - minY) * scale);
  final designHeight = topMargin + (maxY - minY) * scale + bottomMargin;

  final bodyPts = _simplify(body, tolerance).map(design).toList();
  final humpPts = _simplify(hump, tolerance).map(design).toList();
  final bridgePts = _simplify(bridge, tolerance).map(design).toList();

  final out = StringBuffer()
    ..writeln('  // ---- generated by tool/trace_outline.dart ----')
    ..writeln('  static const designWidth = ${_f(designWidth)};')
    ..writeln('  static const designHeight = ${_f(designHeight)};')
    ..writeln('  /// Photo pixels to design units.')
    ..writeln('  static const photoScale = ${scale.toStringAsFixed(4)};')
    ..writeln()
    ..writeln(
      '  /// The body\'s right half (${bodyPts.length} points), clockwise '
      'from the top centre to the bottom centre; the left half is its '
      'mirror.',
    )
    ..writeln('  static const bodyRight = <Offset>[');
  for (final p in bodyPts) {
    out.writeln('    Offset(${_f(p.x)}, ${_f(p.y)}),');
  }
  out
    ..writeln('  ];')
    ..writeln()
    ..writeln(
      '  /// The right shoulder\'s hump above the body (R), inner end to '
      'outer end.',
    )
    ..writeln('  static const shoulderRight = <Offset>[');
  for (final p in humpPts) {
    out.writeln('    Offset(${_f(p.x)}, ${_f(p.y)}),');
  }
  out
    ..writeln('  ];')
    ..writeln()
    ..writeln('  // Controls (design units).');
  _P ctl(double x, double y) =>
      design(_P(x - controlsCentre, y)); // controls about their own centre
  double sym(String a, String b) =>
      ((controls[b]!.$1 - controlsCentre) -
          (controls[a]!.$1 - controlsCentre)) /
      2;
  void pos(String name, double x, double y) {
    final p = ctl(x, y);
    out.writeln('  static const $name = Offset(${_f(p.x)}, ${_f(p.y)});');
  }

  void len(String name, double v) =>
      out.writeln('  static const $name = ${_f(v * scale)};');

  final stickDx = sym('leftStick', 'rightStick');
  final stickY = (controls['leftStick']!.$2 + controls['rightStick']!.$2) / 2;
  pos('leftStick', controlsCentre - stickDx, stickY);
  pos('rightStick', controlsCentre + stickDx, stickY);
  len('stickCap', controls['leftStick']!.$3);
  len('stickRing', controls['stickRing']!.$3);
  len('stickDish', controls['stickDish']!.$3);
  final padDx =
      ((controls['face']!.$1 - controlsCentre) -
          (controls['dpad']!.$1 - controlsCentre)) /
      2;
  final padY = (controls['dpad']!.$2 + controls['face']!.$2) / 2;
  pos('dpadAt', controlsCentre - padDx, padY);
  len('dpadSize', controls['dpad']!.$3 * 2);
  len('dpadArm', controls['dpadArm']!.$2);
  pos('faceAt', controlsCentre + padDx, padY);
  len('faceGap', controls['faceGap']!.$2);
  len('faceButton', controls['face']!.$3);
  final smallDx = sym('minus', 'plus');
  final smallY = (controls['minus']!.$2 + controls['plus']!.$2) / 2;
  pos('minusAt', controlsCentre - smallDx, smallY);
  pos('plusAt', controlsCentre + smallDx, smallY);
  pos('homeAt', controlsCentre, controls['home']!.$2);
  pos('powerAt', controlsCentre, controls['power']!.$2);
  len('smallButton', controls['minus']!.$3);
  len('homeButton', controls['home']!.$3);
  len('powerButton', controls['power']!.$3);
  out.writeln(
    '  static const smallLabelY = '
    '${_f(ctl(0, controls['selectLabel']!.$2).y)};',
  );
  out.writeln(
    '  static const powerLabelY = '
    '${_f(ctl(0, controls['powerLabel']!.$2).y)};',
  );
  pos('batteryLabelAt', controlsCentre, controls['batteryLabel']!.$2);
  pos('batteryLedAt', controlsCentre, controls['batteryLed']!.$2);
  pos('logoAt', controlsCentre, controls['logo']!.$2);
  len('logoHeight', controls['logo']!.$3 * 2);
  final led = controls['led1']!, gap = controls['ledGap']!.$1;
  pos('ledsAt', controlsCentre, led.$2);
  len('ledGap', gap);
  out.writeln('  // ---- end generated ----');
  stdout.write(out);

  if (args.length > 1) {
    final o = img.Image.from(photo);
    final red = img.ColorRgb8(255, 40, 40), cyan = img.ColorRgb8(0, 220, 255);
    final green = img.ColorRgb8(40, 230, 40);
    _P back(_P d) => _P(
      (d.x - designWidth / 2) / scale + cx,
      (d.y - topMargin) / scale + minY,
    );
    void poly(List<_P> pts, img.Color c, {bool mirror = true}) {
      for (final m in mirror ? [false, true] : [false]) {
        for (var i = 0; i + 1 < pts.length; i++) {
          var a = back(pts[i]), b = back(pts[i + 1]);
          if (m) {
            a = _P(2 * cx - a.x, a.y);
            b = _P(2 * cx - b.x, b.y);
          }
          img.drawLine(
            o,
            x1: a.x.round(),
            y1: a.y.round(),
            x2: b.x.round(),
            y2: b.y.round(),
            color: c,
          );
        }
      }
    }

    poly(bodyPts, red);
    poly(humpPts, cyan);
    poly(bridgePts, cyan);
    void circle(double x, double y, double rad) => img.drawCircle(
      o,
      x: x.round(),
      y: y.round(),
      radius: rad.round(),
      color: green,
    );
    for (final s in [-stickDx, stickDx]) {
      circle(controlsCentre + s, stickY, controls['leftStick']!.$3);
      circle(controlsCentre + s, stickY, controls['stickRing']!.$3);
    }
    final fx = controlsCentre + padDx;
    final fg = controls['faceGap']!.$2, fr = controls['face']!.$3;
    for (final (dx, dy) in [(0, -1), (1, 0), (0, 1), (-1, 0)]) {
      circle(fx + dx * fg, padY + dy * fg, fr);
    }
    final dx0 = controlsCentre - padDx, ds = controls['dpad']!.$3;
    final arm = controls['dpadArm']!.$2 / 2;
    img.drawRect(
      o,
      x1: (dx0 - ds).round(),
      y1: (padY - arm).round(),
      x2: (dx0 + ds).round(),
      y2: (padY + arm).round(),
      color: green,
    );
    img.drawRect(
      o,
      x1: (dx0 - arm).round(),
      y1: (padY - ds).round(),
      x2: (dx0 + arm).round(),
      y2: (padY + ds).round(),
      color: green,
    );
    circle(controlsCentre - smallDx, smallY, controls['minus']!.$3);
    circle(controlsCentre + smallDx, smallY, controls['minus']!.$3);
    circle(controlsCentre, controls['home']!.$2, controls['home']!.$3);
    circle(controlsCentre, controls['power']!.$2, controls['power']!.$3);
    for (var i = 0; i < 4; i++) {
      circle(led.$1 + i * gap, led.$2, 2);
    }
    circle(controlsCentre, controls['batteryLed']!.$2, 2);
    File(args[1]).writeAsBytesSync(img.encodePng(o));
    stderr.writeln('overlay: ${args[1]}');
  }
}

class _P {
  const _P(this.x, this.y);
  final double x, y;
}

class _Px {
  const _Px(this.x, this.y);
  final int x, y;
}

String _f(double v) => v.toStringAsFixed(1);

/// The largest 4-connected dark region, as a mask.
List<List<bool>> _largestBlob(List<List<bool>> dark) {
  final h = dark.length, w = dark[0].length;
  final label = List.generate(h, (_) => List.filled(w, 0));
  var best = 0, bestSize = 0, next = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (!dark[y][x] || label[y][x] != 0) continue;
      next++;
      var size = 0;
      final stack = [_Px(x, y)];
      label[y][x] = next;
      while (stack.isNotEmpty) {
        final p = stack.removeLast();
        size++;
        for (final (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final nx = p.x + dx, ny = p.y + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          if (!dark[ny][nx] || label[ny][nx] != 0) continue;
          label[ny][nx] = next;
          stack.add(_Px(nx, ny));
        }
      }
      if (size > bestSize) {
        bestSize = size;
        best = next;
      }
    }
  }
  return [
    for (var y = 0; y < h; y++)
      [for (var x = 0; x < w; x++) label[y][x] == best],
  ];
}

/// Moore neighbour tracing of the mask's outer boundary, clockwise (in
/// image coordinates, y down) from its top-left pixel.
List<_Px> _trace(List<List<bool>> m) {
  final h = m.length, w = m[0].length;
  bool at(int x, int y) => x >= 0 && y >= 0 && x < w && y < h && m[y][x];
  late _Px start;
  outer:
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (m[y][x]) {
        start = _Px(x, y);
        break outer;
      }
    }
  }
  // Neighbours clockwise starting west.
  const dirs = [
    (-1, 0),
    (-1, -1),
    (0, -1),
    (1, -1),
    (1, 0),
    (1, 1),
    (0, 1),
    (-1, 1),
  ];
  final out = <_Px>[start];
  var cur = start;
  var first = 0; // above and left of the top-left pixel is all outside
  for (var guard = 0; guard < w * h * 4; guard++) {
    var found = false;
    for (var k = 0; k < 8; k++) {
      final d = (first + k) % 8;
      final nx = cur.x + dirs[d].$1, ny = cur.y + dirs[d].$2;
      if (at(nx, ny)) {
        cur = _Px(nx, ny);
        // Resume the clockwise sweep at the last outside pixel seen.
        first = d.isEven ? (d + 6) % 8 : (d + 5) % 8;
        found = true;
        break;
      }
    }
    if (!found || (cur.x == start.x && cur.y == start.y)) break;
    out.add(cur);
  }
  return out;
}

/// [pts] resampled to [n] points evenly spaced along its length.
List<_P> _resample(List<_P> pts, int n) {
  final cum = <double>[0];
  for (var i = 1; i < pts.length; i++) {
    final a = pts[i - 1], b = pts[i];
    cum.add(
      cum.last + math.sqrt(math.pow(b.x - a.x, 2) + math.pow(b.y - a.y, 2)),
    );
  }
  final total = cum.last;
  final out = <_P>[];
  var j = 0;
  for (var i = 0; i < n; i++) {
    final s = total * i / (n - 1);
    while (j < cum.length - 2 && cum[j + 1] < s) {
      j++;
    }
    final seg = cum[j + 1] - cum[j];
    final t = seg == 0 ? 0.0 : (s - cum[j]) / seg;
    out.add(
      _P(
        pts[j].x + (pts[j + 1].x - pts[j].x) * t,
        pts[j].y + (pts[j + 1].y - pts[j].y) * t,
      ),
    );
  }
  return out;
}

/// Douglas–Peucker simplification (open polyline, ends kept).
List<_P> _simplify(List<_P> pts, double eps) {
  if (pts.length < 3) return pts;
  final a = pts.first, b = pts.last;
  final dx = b.x - a.x, dy = b.y - a.y;
  final len = math.sqrt(dx * dx + dy * dy);
  var worst = 0.0, at = 0;
  for (var i = 1; i < pts.length - 1; i++) {
    final p = pts[i];
    final d = len == 0
        ? math.sqrt(math.pow(p.x - a.x, 2) + math.pow(p.y - a.y, 2))
        : ((p.x - a.x) * dy - (p.y - a.y) * dx).abs() / len;
    if (d > worst) {
      worst = d;
      at = i;
    }
  }
  if (worst <= eps) return [a, b];
  final l = _simplify(pts.sublist(0, at + 1), eps);
  final r = _simplify(pts.sublist(at), eps);
  return [...l.sublist(0, l.length - 1), ...r];
}
