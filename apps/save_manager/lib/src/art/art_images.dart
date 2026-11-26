/// Pictures from save_kit's [Pixels] turned into GPU images once and kept
/// (one per picture), so a grid of icons never decodes the same frame twice.
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:save_kit/save_kit.dart';

abstract final class ArtImages {
  /// What a PS1 icon's see-through pixels show (the PC's PS1_BACK).
  static const ps1Back = 0xFF05050C;

  /// Bumps whenever an image finishes, so painters waiting on one repaint.
  static final loaded = ValueNotifier<int>(0);

  static final _plain = Expando<ui.Image>('plain');
  static final _solid = Expando<ui.Image>('solid');
  static final _busy = Expando<Future<ui.Image>>('busy');
  static final _busySolid = Expando<Future<ui.Image>>('busySolid');

  /// The image for [px], or null while it's being made (it starts then).
  /// [solid]: see-through pixels are laid over [ps1Back], like the PC.
  static ui.Image? peek(Pixels px, {bool solid = false}) {
    final have = solid ? _solid[px] : _plain[px];
    if (have != null) return have;
    load(px, solid: solid);
    return null;
  }

  /// The image for [px], made on first ask.
  static Future<ui.Image> load(Pixels px, {bool solid = false}) {
    final have = solid ? _solid[px] : _plain[px];
    if (have != null) return Future.value(have);
    final busy = solid ? _busySolid : _busy;
    // Made in the root zone: whoever asks first (a painter inside a test's
    // fake clock, say) mustn't strand everyone else waiting on it.
    return busy[px] ??= Zone.root.run<Future<ui.Image>>(
      () => _make(px, solid).then((img) {
        if (solid) {
          _solid[px] = img;
        } else {
          _plain[px] = img;
        }
        busy[px] = null;
        loaded.value++;
        return img;
      }),
    );
  }

  /// Every picture [saves] and [cards] show, ready to draw (for tests and
  /// screenshots; the widgets load their own as they go).
  static Future<void> preload(
    Iterable<CardSave> saves, [
    Iterable<MemoryCard> cards = const [],
  ]) async {
    final jobs = <Future<ui.Image>>[];
    for (final s in saves) {
      for (final f in s.frames) {
        jobs.add(load(f, solid: true));
      }
      if (s.wide != null) jobs.add(load(s.wide!, solid: true));
      for (final i in s.icons) {
        if (i?.texture != null) jobs.add(load(i!.texture!));
      }
    }
    for (final c in cards) {
      if (c.stickerImage != null) jobs.add(load(c.stickerImage!));
    }
    await Future.wait(jobs);
  }

  static Future<ui.Image> _make(Pixels px, bool solid) {
    final n = px.w * px.h;
    final out = Uint8List(n * 4);
    const br = ps1Back >> 16 & 255, bg = ps1Back >> 8 & 255, bb = ps1Back & 255;
    final src = px.rgba;
    for (var i = 0; i < n * 4; i += 4) {
      final a = src[i + 3];
      if (solid) {
        out[i] = (src[i] * a + br * (255 - a)) ~/ 255;
        out[i + 1] = (src[i + 1] * a + bg * (255 - a)) ~/ 255;
        out[i + 2] = (src[i + 2] * a + bb * (255 - a)) ~/ 255;
        out[i + 3] = 255;
      } else {
        // decodeImageFromPixels wants premultiplied colours.
        out[i] = src[i] * a ~/ 255;
        out[i + 1] = src[i + 1] * a ~/ 255;
        out[i + 2] = src[i + 2] * a ~/ 255;
        out[i + 3] = a;
      }
    }
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      out,
      px.w,
      px.h,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }
}
