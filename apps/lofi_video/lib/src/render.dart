import 'dart:math' as math;
import 'dart:typed_data';

import 'package:video_kit/video_kit.dart';

import 'media.dart';
import 'project.dart';
import 'transitions.dart';

/// Draws [src] into a [w]×[h] picture: whole (contain, with bars) or
/// filling it (cover, cropped). Growing uses nearest pixels (pixel art
/// stays sharp); shrinking averages. See-through pixels show [background].
/// Always returns a new frame.
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
  final out = VideoFrame(w, h)..pixels.fillRange(0, w * h, background);
  final ox = (w - dw) ~/ 2, oy = (h - dh) ~/ 2;
  final from = s < 1 ? src.resized(dw, dh) : src;
  for (var ty = math.max(0, oy); ty < math.min(h, oy + dh); ty++) {
    final row =
        math.min(from.height - 1, ((ty - oy) * from.height) ~/ dh) * from.width;
    for (var tx = math.max(0, ox); tx < math.min(w, ox + dw); tx++) {
      final v =
          from.pixels[row +
              math.min(from.width - 1, ((tx - ox) * from.width) ~/ dw)];
      out.pixels[ty * w + tx] = v >>> 24 == 0 ? background : v;
    }
  }
  return out;
}

VideoFrame solid(int w, int h, int color) =>
    VideoFrame(w, h)..pixels.fillRange(0, w * h, color);

/// Draws [pic] (see-through pixels skipped) centred at ([cx], [cy]) on
/// [dst], each pixel [scale]×[scale].
void stamp(VideoFrame dst, VideoFrame pic, double cx, double cy, double scale) {
  final w = (pic.width * scale).round(), h = (pic.height * scale).round();
  final x0 = (cx - w / 2).round(), y0 = (cy - h / 2).round();
  for (var y = math.max(0, y0); y < math.min(dst.height, y0 + h); y++) {
    final sy = math.min(pic.height - 1, ((y - y0) / scale).floor());
    for (var x = math.max(0, x0); x < math.min(dst.width, x0 + w); x++) {
      final v =
          pic.pixels[sy * pic.width +
              math.min(pic.width - 1, ((x - x0) / scale).floor())];
      if (v >>> 24 != 0) {
        dst.pixels[y * dst.width + x] = v;
      }
    }
  }
}

/// Draws the storyboard frame by frame. Effects keep state (feedback,
/// datamosh, slow-scan), so ask for times in order; going back resets them.
class Renderer {
  Renderer(this.project, this.media, this.pictures);

  final Project project;

  /// Decoded sources by asset id.
  final Map<String, Media> media;

  /// Rendered title cards (by scene id) and text overlays (by overlay id).
  final Map<String, VideoFrame> pictures;

  final _effects = <String, VideoEffect?>{};
  final _lastOut = <int, VideoFrame>{};
  int _scene = -1;
  double _last = -1;

  /// The picture at [t] seconds (each effect's output keeps its machine's
  /// own size; transitions match the incoming scene's size).
  VideoFrame frameAt(double t) {
    final (i, lt) = project.sceneAt(t);
    if (i < 0) {
      return solid(canvasWidth, canvasHeight, 0xFF000000);
    }
    if (t < _last) {
      _lastOut.clear();
    }
    final out = sceneFrame(i, lt, reset: i != _scene || t < _last);
    _scene = i;
    _last = t;
    _lastOut
      ..removeWhere((k, _) => k < i - 1)
      ..[i] = out;
    final s = project.scenes[i];
    if (i == 0 || s.transition == Transition.cut || lt >= s.transitionLength) {
      return out;
    }
    final prevScene = project.scenes[i - 1];
    final prev =
        _lastOut[i - 1] ??
        sceneFrame(
          i - 1,
          math.max(0, prevScene.duration - 0.001),
          reset: true,
          fresh: true,
        );
    final from = prev.width == out.width && prev.height == out.height
        ? prev
        : fitInto(prev, out.width, out.height);
    return applyTransition(s.transition, from, out, lt / s.transitionLength, t);
  }

  /// Scene [i] at [lt] seconds in: canvas, overlays under the effect, the
  /// effect, overlays above it. [fresh] uses a throwaway effect (so a
  /// scene's running effect keeps its state).
  VideoFrame sceneFrame(
    int i,
    double lt, {
    bool reset = false,
    bool fresh = false,
  }) {
    final s = project.scenes[i];
    final base = canvasFor(s, lt);
    for (final o in s.overlays) {
      if (!o.aboveEffect && o.visibleAt(lt)) {
        _drawOverlay(base, o, lt);
      }
    }
    final id = s.effectId;
    final effect = id == null
        ? null
        : (fresh ? _make(id) : _effects[s.id] ??= _make(id));
    var out = base;
    if (effect != null) {
      if (reset) {
        effect.reset();
      }
      effect.values.addAll(s.knobs);
      out = runEffect(effect, base, lt);
    }
    if (s.overlays.any((o) => o.aboveEffect && o.visibleAt(lt))) {
      if (identical(out, base)) {
        out = out.copy();
      }
      for (final o in s.overlays) {
        if (o.aboveEffect && o.visibleAt(lt)) {
          _drawOverlay(out, o, lt);
        }
      }
    }
    return out;
  }

  void _drawOverlay(VideoFrame dst, SceneOverlay o, double lt) {
    // Sizes are in canvas pixels; bigger outputs (effects like NTSC) scale.
    final k = dst.width / canvasWidth;
    final VideoFrame? pic;
    double scale;
    if (o.kind == OverlayKind.text) {
      pic = pictures[o.id];
      scale = k; // Text is drawn at its size already.
    } else {
      final m = o.assetId == null ? null : media[o.assetId];
      pic = switch (m) {
        AnimMedia() => m.at(lt),
        StillMedia(:final frame) => frame,
        _ => null,
      };
      scale = o.scale * k;
    }
    if (pic == null) {
      return;
    }
    stamp(dst, pic, o.x * dst.width, o.y * dst.height, scale);
  }

  static VideoEffect? _make(String id) {
    for (final e in allEffects()) {
      if (e.id == id) {
        return e;
      }
    }
    return null;
  }

  /// The scene's own picture on the 4:3 canvas (before overlays and effect).
  VideoFrame canvasFor(Scene s, double lt) {
    final m = s.assetId == null ? null : media[s.assetId];
    final src = switch (s.kind) {
      SceneKind.bars => testCard(lt, width: canvasWidth, height: canvasHeight),
      SceneKind.title => pictures[s.id],
      SceneKind.clip =>
        m is ClipMedia && m.clip.frames.isNotEmpty
            ? m.clip.frameAt(s.clipStart + lt)
            : null,
      SceneKind.picture || SceneKind.sprite => switch (m) {
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
