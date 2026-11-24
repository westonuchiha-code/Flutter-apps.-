import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pixel_kit/pixel_kit.dart' as pk;

import 'quilt.dart';

typedef Picture = ({int width, int height, Uint32List pixels});

/// Decodes a photo, shrunk to at most 900 px (the quilt only needs averages).
Picture? decodePhoto(Uint8List bytes) {
  final p = pk.decodePicture(bytes);
  if (p == null) return null;
  return pk.fitPicture(p, 900, 900);
}

/// The palette made from a photo (median cut).
List<int> photoPalette((Picture, int) a) => pk.medianCut(a.$1.pixels, a.$2);

/// Quilt and picture in one go.
(Quilt, Picture) buildQuilt((Picture, QuiltSettings) a) {
  final (p, s) = a;
  final q = makeQuilt(p.width, p.height, p.pixels, s);
  return (q, renderQuilt(q, s));
}

Uint8List encodePng(Picture p) =>
    img.encodePng(pk.toImage(p.pixels, p.width, p.height));
