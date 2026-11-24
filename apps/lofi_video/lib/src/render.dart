import 'dart:math' as math;
import 'dart:typed_data';

import 'package:video_kit/video_kit.dart';

import 'media.dart';
import 'project.dart';

/// Draws [src] into a [w]×[h] picture: whole (contain, with bars) or
/// filling it (cover, cropped). Growing uses nearest pixels (pixel art
/// stays sharp); shrinking averages.
VideoFrame fitInto(
  VideoFrame src,
  int w,
  int h, {
  Fit fit = Fit.contain,
  int background = 0xFF000000,
}) {
  final sx = w / src.width, sy = h / src.height;
  final s = fit == Fit.contain ? math.min(sx, sy) : math.max(sx, sy);
  final dw = math.max(1, (src.width * s).round()),
      dh = math.max(1, (src.height * s).round());
  if (dw == w && dh == h && src.width == w && src.height == h) {
    return src;
  }
  final out = VideoFrame(w, h)..pixels.fillRange(0, w * h, background);
  final ox = (w - dw) ~/ 2, oy = (h - dh) ~/ 2;
  if (s < 1) {
    final small = src.resized(dw, dh);
    for (var y = 0; y < dh; y++) {
      final ty = y + oy;
      if (ty < 0 || ty >= h) {
        continue;
      }
      for (var x = 0; x < dw; x++) {
        final tx = x + ox;
        if (tx < 0 || tx >= w) {
          continue;
        }
        out.pixels[ty * w + tx] = small.pixels[y * dw + x];
      }
    }
    return out;
  }
  for (var ty = math.max(0, oy); ty < math.min(h, oy + dh); ty++) {
    final syy = math.min(src.height - 1, ((ty - oy) * src.height) ~/ dh);
    final row = syy * src.width;
    for (var tx = math.max(0, ox); tx < math.min(w, ox + dw); tx++) {
      out.pixels[ty * w + tx] = src
          .pixels[row + math.min(src.width - 1, ((tx - ox) * src.width) ~/ dw)];
    }
  }
  return out;
}

VideoFrame solid(int w, int h, int color) =>
    VideoFrame(w, h)..pixels.fillRange(0, w * h, color);

/// Draws the storyboard frame by frame. Effects keep state (feedback,
/// datamosh, slow-scan), so ask for times in order; going back resets them.
class Renderer {
  Renderer(this.project, this.media, this.titles);

  final Project project;

  /// Decoded sources by asset id.
  final Map<String, Media> media;

  /// Rendered title cards by scene id.
  final Map<String, VideoFrame> titles;

  final _effects = <String, VideoEffect?>{};
  int _scene = -1;
  double _last = -1;

  /// The picture at [t] seconds: the scene's canvas, through its effect
  /// (whose output keeps the machine's own size).
  VideoFrame frameAt(double t) {
    final (i, lt) = project.sceneAt(t);
    if (i < 0) {
      return solid(canvasWidth, canvasHeight, 0xFF000000);
    }
    final s = project.scenes[i];
    final base = canvasFor(s, lt);
    final id = s.effectId;
    final effect = id == null ? null : _effects[s.id] ??= _make(id);
    if (i != _scene || t < _last) {
      effect?.reset();
    }
    _scene = i;
    _last = t;
    if (effect == null) {
      return base;
    }
    effect.values.addAll(s.knobs);
    return runEffect(effect, base, lt);
  }

  static VideoEffect? _make(String id) {
    for (final e in allEffects()) {
      if (e.id == id) {
        return e;
      }
    }
    return null;
  }

  /// The scene's own picture on the 4:3 canvas (before its effect).
  VideoFrame canvasFor(Scene s, double lt) {
    final m = s.assetId == null ? null : media[s.assetId];
    final src = switch (s.kind) {
      SceneKind.bars => testCard(lt, width: canvasWidth, height: canvasHeight),
      SceneKind.title => titles[s.id],
      SceneKind.clip =>
        m is ClipMedia && m.clip.frames.isNotEmpty
            ? m.clip.frameAt(s.clipStart + lt)
            : null,
      SceneKind.picture => switch (m) {
        StillMedia(:final frame) => frame,
        AnimMedia() => m.at(lt),
        _ => null,
      },
      SceneKind.sprite => switch (m) {
        AnimMedia() => m.at(lt),
        StillMedia(:final frame) => frame,
        _ => null,
      },
    };
    if (src == null) {
      return solid(
        canvasWidth,
        canvasHeight,
        s.kind == SceneKind.title ? s.background : 0xFF202020,
      );
    }
    return fitInto(
      src,
      canvasWidth,
      canvasHeight,
      fit: s.fit,
      background: s.background,
    );
  }
}

/// The finished picture at the export size (keeps 4:3, sharp pixels).
Uint32List outputPixels(VideoFrame f, int width, int height) =>
    fitInto(f, width, height).pixels;
