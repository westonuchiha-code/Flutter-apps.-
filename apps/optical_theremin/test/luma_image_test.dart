import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:optical_theremin/src/core/luma_image.dart';

import 'fakes.dart';

void main() {
  test('fromPlane averages blocks and honours row/pixel stride', () {
    // 4x2 image stored with pixelStride 2 and rowStride 10 (padding).
    final bytes = Uint8List.fromList([
      10, 0, 30, 0, 100, 0, 100, 0, 9, 9, //
      10, 0, 30, 0, 200, 0, 200, 0, 9, 9,
    ]);
    final image = LumaImage.fromPlane(
      bytes,
      width: 4,
      height: 2,
      rowStride: 10,
      pixelStride: 2,
      targetWidth: 2,
    );
    expect(image.width, 2);
    expect(image.height, 1);
    expect(image.pixels, [20, 150]);
  });

  test('fromPlane keeps the aspect ratio', () {
    final image = LumaImage.fromPlane(
      Uint8List(320 * 240),
      width: 320,
      height: 240,
      rowStride: 320,
    );
    expect(image.width, 160);
    expect(image.height, 120);
  });

  test('rotated and mirrored', () {
    // 2x1: [1, 2]
    final image = LumaImage(2, 1, Uint8List.fromList([1, 2]));
    final cw = image.rotated(1);
    expect((cw.width, cw.height), (1, 2));
    expect(cw.pixels, [1, 2]);
    final ccw = image.rotated(3);
    expect((ccw.width, ccw.height), (1, 2));
    expect(ccw.pixels, [2, 1]);
    expect(image.rotated(2).pixels, [2, 1]);
    expect(image.mirrored().pixels, [2, 1]);
    expect(identical(image.rotated(4), image), isTrue);
  });

  test('rotation of a 2x2 image', () {
    // 1 2
    // 3 4  -> clockwise -> 3 1 / 4 2
    final image = LumaImage(2, 2, Uint8List.fromList([1, 2, 3, 4]));
    expect(image.rotated(1).pixels, [3, 1, 4, 2]);
  });

  test('meanIn measures regions', () {
    final image = splitImage(40, 200);
    expect(image.meanIn(const Rect.fromLTRB(0, 0, 0.5, 1)), 40);
    expect(image.meanIn(const Rect.fromLTRB(0.5, 0, 1, 1)), 200);
    expect(image.meanIn(const Rect.fromLTRB(0, 0, 1, 1)), 120);
  });
}
