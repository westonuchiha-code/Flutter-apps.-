import 'dart:typed_data';

import 'color.dart';
import 'palette.dart';

/// The [count] colours that best represent [pixels] (median cut).
/// Transparent pixels are ignored. Results are sorted dark to light.
List<int> medianCut(Uint32List pixels, int count) {
  // Sample at most ~64k pixels so big photos stay fast.
  final step = (pixels.length / 65536).ceil().clamp(1, 1 << 20);
  final colors = <int>[];
  for (var i = 0; i < pixels.length; i += step) {
    final c = pixels[i];
    if (alphaOf(c) >= 128) colors.add(c | 0xFF000000);
  }
  if (colors.isEmpty) return const [];
  var boxes = <List<int>>[colors];
  while (boxes.length < count) {
    // Split the box with the widest colour range.
    var best = -1, bestRange = 0, bestChannel = 0;
    for (var b = 0; b < boxes.length; b++) {
      final box = boxes[b];
      if (box.length < 2) continue;
      for (var ch = 0; ch < 3; ch++) {
        var lo = 255, hi = 0;
        for (final c in box) {
          final v = (c >> (16 - ch * 8)) & 255;
          if (v < lo) lo = v;
          if (v > hi) hi = v;
        }
        if (hi - lo > bestRange) {
          bestRange = hi - lo;
          best = b;
          bestChannel = ch;
        }
      }
    }
    if (best < 0 || bestRange == 0) break;
    final box = boxes.removeAt(best);
    final shift = 16 - bestChannel * 8;
    int v(int c) => (c >> shift) & 255;
    box.sort((a, b) => v(a).compareTo(v(b)));
    // Split near the middle, but only where the value changes, so a block
    // of one colour is never cut in two.
    final mid = box.length ~/ 2;
    var cut = -1;
    for (var d = 0; d < box.length; d++) {
      for (final k in [mid - d, mid + d]) {
        if (k > 0 && k < box.length && v(box[k - 1]) != v(box[k])) {
          cut = k;
          break;
        }
      }
      if (cut > 0) break;
    }
    if (cut <= 0) {
      boxes.add(box);
      break;
    }
    boxes = [...boxes, box.sublist(0, cut), box.sublist(cut)];
  }
  final out = <int>{};
  for (final box in boxes) {
    var r = 0, g = 0, b = 0;
    for (final c in box) {
      r += redOf(c);
      g += greenOf(c);
      b += blueOf(c);
    }
    final n = box.length;
    out.add(argb(255, (r / n).round(), (g / n).round(), (b / n).round()));
  }
  final list = out.toList()
    ..sort(
      (a, b) => (redOf(a) * 3 + greenOf(a) * 6 + blueOf(a)).compareTo(
        redOf(b) * 3 + greenOf(b) * 6 + blueOf(b),
      ),
    );
  return list;
}

/// A palette made from a picture.
Palette paletteFromPixels(
  Uint32List pixels,
  int count, {
  String name = 'From picture',
}) => Palette(name, medianCut(pixels, count));

const _bayer4 = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];

/// Snaps [pixels] to [palette]; with [dither], uses a 4×4 ordered (Bayer)
/// pattern like old hardware did, instead of flat bands.
Uint32List reduceToPalette(
  Uint32List pixels,
  int width,
  Palette palette, {
  bool dither = false,
  double strength = 32,
}) {
  final out = Uint32List(pixels.length);
  for (var i = 0; i < pixels.length; i++) {
    var c = pixels[i];
    if (alphaOf(c) < 128) continue;
    if (dither) {
      final x = i % width, y = i ~/ width;
      final t = (_bayer4[(y & 3) * 4 + (x & 3)] / 16 - 0.5) * strength;
      int ch(int v) => (v + t).round().clamp(0, 255);
      c = argb(255, ch(redOf(c)), ch(greenOf(c)), ch(blueOf(c)));
    }
    out[i] = palette.nearest(c);
  }
  return out;
}

/// Scales a picture to fit inside [maxW]×[maxH] (nearest pixel, keeps the
/// aspect ratio; never enlarges).
({int width, int height, Uint32List pixels}) fitPicture(
  ({int width, int height, Uint32List pixels}) pic,
  int maxW,
  int maxH,
) {
  final scale = [
    maxW / pic.width,
    maxH / pic.height,
    1.0,
  ].reduce((a, b) => a < b ? a : b);
  final w = (pic.width * scale).floor().clamp(1, maxW);
  final h = (pic.height * scale).floor().clamp(1, maxH);
  final out = Uint32List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final sx = ((x + 0.5) / scale).floor().clamp(0, pic.width - 1);
      final sy = ((y + 0.5) / scale).floor().clamp(0, pic.height - 1);
      out[y * w + x] = pic.pixels[sy * pic.width + sx];
    }
  }
  return (width: w, height: h, pixels: out);
}
