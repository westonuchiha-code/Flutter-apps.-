import 'dart:convert';
import 'dart:typed_data';

import 'package:app_shell/app_shell.dart';
import 'package:pixel_kit/pixel_kit.dart';

import 'editor.dart';

const pictureExtensions = ['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp'];

/// Asset Locker work for Pixel Forge.
class ForgeLibrary {
  ForgeLibrary(this.locker);

  final AssetLocker locker;

  /// A small PNG preview (at least ~96 px on its long side).
  static Uint8List thumbnail(Sprite s) {
    final longest = s.width > s.height ? s.width : s.height;
    final scale = (128 / longest).floor().clamp(1, 16);
    return spriteToPng(s, scale: scale);
  }

  Future<AssetInfo> saveSprite(Editor e, {AssetInfo? replace}) async {
    final bytes = utf8.encode(jsonEncode(e.sprite.toJson()));
    final extra = {
      'kind': Sprite.kind,
      'width': e.sprite.width,
      'height': e.sprite.height,
      'layers': e.sprite.layers.length,
      'frames': e.sprite.frames.length,
    };
    final thumb = thumbnail(e.sprite);
    if (replace != null) {
      final next = await locker.replace(
        replace,
        bytes,
        thumbnail: thumb,
        extra: extra,
      );
      await locker.update(next.copyWith(name: e.name));
      return next.copyWith(name: e.name);
    }
    return locker.save(
      type: AssetType.sprite,
      name: e.name,
      bytes: bytes,
      extension: 'json',
      thumbnail: thumb,
      tags: const ['pixel forge'],
      extra: extra,
    );
  }

  /// Opens a Pixel Forge sprite, or any picture as a one-layer sprite.
  Future<Sprite> open(AssetInfo info) async {
    final bytes = await locker.read(info);
    if (bytes == null) throw StateError('The file is missing.');
    if (info.extension == 'json') {
      return Sprite.fromJson(jsonDecode(utf8.decode(bytes)));
    }
    if (pictureExtensions.contains(info.extension)) {
      return pictureToSprite(bytes);
    }
    throw FormatException('Pixel Forge can\'t open .${info.extension} files.');
  }

  Future<AssetInfo> exportPng(Editor e, int scale) => locker.save(
    type: AssetType.sprite,
    name: scale == 1 ? e.name : '${e.name} ×$scale',
    bytes: spriteToPng(e.sprite, frame: e.frame, scale: scale),
    extension: 'png',
    thumbnail: thumbnail(e.sprite),
    tags: const ['pixel forge', 'png'],
    extra: {'width': e.sprite.width * scale, 'height': e.sprite.height * scale},
  );

  Future<AssetInfo> savePalette(Palette p) => locker.save(
    type: AssetType.palette,
    name: p.name,
    bytes: utf8.encode(jsonEncode(p.toJson())),
    extension: 'json',
    tags: const ['pixel forge'],
    extra: {'kind': Palette.kind, 'colors': p.colors.length},
  );

  Future<Palette> openPalette(AssetInfo info) async {
    final bytes = await locker.read(info);
    if (bytes == null) throw StateError('The file is missing.');
    final text = utf8.decode(bytes, allowMalformed: true);
    if (info.extension == 'gpl') return Palette.fromGpl(text, name: info.name);
    return Palette.fromJson(jsonDecode(text));
  }
}

/// A picture as a sprite (shrunk to fit [Sprite.maxSize] if needed).
Sprite pictureToSprite(Uint8List bytes) {
  final pic = decodePicture(bytes);
  if (pic == null) {
    throw const FormatException('That picture could not be read.');
  }
  var w = pic.width, h = pic.height;
  final shrink = (w > Sprite.maxSize || h > Sprite.maxSize)
      ? Sprite.maxSize / (w > h ? w : h)
      : 1.0;
  w = (w * shrink).floor().clamp(1, Sprite.maxSize);
  h = (h * shrink).floor().clamp(1, Sprite.maxSize);
  final s = Sprite.blank(w, h);
  final cel = s.cel(0, 0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final sx = (x / shrink).floor().clamp(0, pic.width - 1);
      final sy = (y / shrink).floor().clamp(0, pic.height - 1);
      cel[y * w + x] = pic.pixels[sy * pic.width + sx];
    }
  }
  return s;
}
