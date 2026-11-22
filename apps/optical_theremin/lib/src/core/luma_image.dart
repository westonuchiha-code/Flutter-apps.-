import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

/// Small grayscale (brightness) image: one byte per pixel, row-major.
class LumaImage {
  LumaImage(this.width, this.height, this.pixels)
    : assert(pixels.length >= width * height);

  final int width;
  final int height;
  final Uint8List pixels;

  /// Default width that camera frames are shrunk to.
  static const thumbnailWidth = 160;

  /// Builds a thumbnail [targetWidth] pixels wide from an 8-bit plane, e.g.
  /// the Y (brightness) plane of a YUV camera frame, averaging blocks of
  /// source pixels.
  factory LumaImage.fromPlane(
    Uint8List bytes, {
    required int width,
    required int height,
    required int rowStride,
    int pixelStride = 1,
    int targetWidth = thumbnailWidth,
  }) {
    final tw = width < targetWidth ? width : targetWidth;
    final th = (tw * height / width).round().clamp(1, height);
    final out = Uint8List(tw * th);
    for (var ty = 0; ty < th; ty++) {
      final y0 = ty * height ~/ th;
      var y1 = (ty + 1) * height ~/ th;
      if (y1 <= y0) y1 = y0 + 1;
      for (var tx = 0; tx < tw; tx++) {
        final x0 = tx * width ~/ tw;
        var x1 = (tx + 1) * width ~/ tw;
        if (x1 <= x0) x1 = x0 + 1;
        var sum = 0;
        var count = 0;
        for (var y = y0; y < y1; y++) {
          final row = y * rowStride;
          for (var x = x0; x < x1; x++) {
            final i = row + x * pixelStride;
            if (i < bytes.length) {
              sum += bytes[i];
              count++;
            }
          }
        }
        out[ty * tw + tx] = count == 0 ? 0 : sum ~/ count;
      }
    }
    return LumaImage(tw, th, out);
  }

  /// Rotated clockwise by [quarterTurns] × 90°.
  LumaImage rotated(int quarterTurns) {
    final turns = quarterTurns % 4;
    if (turns == 0) return this;
    final w2 = turns.isOdd ? height : width;
    final h2 = turns.isOdd ? width : height;
    final out = Uint8List(w2 * h2);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final int nx;
        final int ny;
        switch (turns) {
          case 1:
            nx = height - 1 - y;
            ny = x;
          case 2:
            nx = width - 1 - x;
            ny = height - 1 - y;
          default:
            nx = y;
            ny = width - 1 - x;
        }
        out[ny * w2 + nx] = pixels[y * width + x];
      }
    }
    return LumaImage(w2, h2, out);
  }

  /// Flipped left-to-right.
  LumaImage mirrored() {
    final out = Uint8List(width * height);
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        out[row + x] = pixels[row + width - 1 - x];
      }
    }
    return LumaImage(width, height, out);
  }

  /// Average brightness (0–255) inside [region], given in fractions of the
  /// image size (0–1).
  double meanIn(Rect region) {
    final x0 = (region.left * width).floor().clamp(0, width - 1);
    final x1 = (region.right * width).ceil().clamp(x0 + 1, width);
    final y0 = (region.top * height).floor().clamp(0, height - 1);
    final y1 = (region.bottom * height).ceil().clamp(y0 + 1, height);
    var sum = 0;
    for (var y = y0; y < y1; y++) {
      final row = y * width;
      for (var x = x0; x < x1; x++) {
        sum += pixels[row + x];
      }
    }
    return sum / ((x1 - x0) * (y1 - y0));
  }
}
