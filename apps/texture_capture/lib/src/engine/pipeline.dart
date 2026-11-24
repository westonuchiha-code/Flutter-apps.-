import 'dart:math' as math;

import 'formats.dart';
import 'pic.dart';
import 'surface.dart';
import 'warp.dart';

/// Everything that decides the master texture.
class MasterSettings {
  const MasterSettings({
    required this.corners,
    this.size = 1024,
    this.lighting = 0.7,
    this.seamless = true,
    this.blend = 0.2,
  });

  /// Surface corners in photo pixels: top-left, top-right, bottom-right,
  /// bottom-left of the texture.
  final List<Pt> corners;
  final int size;
  final double lighting;
  final bool seamless;
  final double blend;

  MasterSettings copyWith({
    List<Pt>? corners,
    int? size,
    double? lighting,
    bool? seamless,
    double? blend,
  }) => MasterSettings(
    corners: corners ?? this.corners,
    size: size ?? this.size,
    lighting: lighting ?? this.lighting,
    seamless: seamless ?? this.seamless,
    blend: blend ?? this.blend,
  );
}

/// A warning about the photo, with what to do about it.
class Advice {
  const Advice(this.title, this.detail, {this.serious = false});
  final String title, detail;
  final bool serious;
}

class MasterResult {
  const MasterResult(this.master, this.advice);
  final Pic master;
  final List<Advice> advice;
}

MasterResult buildMaster(Pic photo, MasterSettings s) {
  final raw = warp(photo, s.corners, s.size, s.size);
  var master = evenLighting(raw, s.lighting);
  if (s.seamless) master = makeSeamless(master, s.blend);
  return MasterResult(master, checkPhoto(photo, s, raw, master));
}

/// The console version: resized (wrapping, so tiles stay seamless) and
/// stored in [format].
Pic buildConsole(
  Pic master,
  TexFormat format,
  int size, {
  bool dither = false,
}) => applyFormat(resizeTile(master, size, size), format, dither: dither);

/// Warns about photos that will make poor textures.
List<Advice> checkPhoto(Pic photo, MasterSettings s, Pic raw, Pic master) {
  final out = <Advice>[];
  final side = quadSide(s.corners);
  if (side < 96) {
    out.add(
      Advice(
        'Too small',
        'The surface is only about ${side.round()} pixels across in the photo. '
            'Get closer or use a bigger photo.',
        serious: true,
      ),
    );
  } else if (side < s.size * 0.75) {
    final fit = pow2Floor(side * 1.25);
    out.add(
      Advice(
        'Soft at ${s.size}',
        'The surface is about ${side.round()} pixels across in the photo, so a '
            '${s.size}×${s.size} master is stretched. ${fit < 256 ? 'Get closer.' : 'Choose $fit or get closer.'}',
      ),
    );
  }
  final skew = quadSkew(s.corners);
  if (skew > 1.8) {
    out.add(
      Advice(
        'Steep angle',
        'One side is ${skew.toStringAsFixed(1)}× longer than the other, so the far '
            'side has much less detail. Shoot straight on if you can.',
      ),
    );
  }
  final stats = lumaStats(raw);
  if (stats.mean < 50) {
    out.add(
      const Advice(
        'Too dark',
        'Dark photos are noisy and lose detail. Add light or use a brighter photo.',
        serious: true,
      ),
    );
  }
  if (stats.blown > 0.03) {
    out.add(
      Advice(
        'Glare',
        '${(stats.blown * 100).round()}% of it is pure white: there is no detail '
            'there. Avoid flash and shiny reflections.',
        serious: stats.blown > 0.15,
      ),
    );
  }
  final before = LightMap(raw).unevenness;
  final after = LightMap(master).unevenness;
  if (before > 1.5 && s.lighting < 0.5) {
    out.add(
      Advice(
        'Uneven light',
        'One part is ${before.toStringAsFixed(1)}× brighter than another. Turn up '
            'Even lighting.',
      ),
    );
  } else if (after > 1.5) {
    out.add(
      const Advice(
        'Strong shadows',
        'Some shadows are still there. Soft, even light (cloudy day, no '
            'direct sun or flash) works best.',
      ),
    );
  }
  if (stats.std > 6 && sharpness(raw) < 1.5) {
    out.add(
      const Advice(
        'Blurry',
        'The photo looks out of focus or shaken. Hold still and tap to focus.',
        serious: true,
      ),
    );
  }
  if (stats.std <= 6) {
    out.add(
      const Advice(
        'Very plain',
        'There is little detail; it may look flat in a game.',
      ),
    );
  }
  if (!s.seamless && seamScore(master) > 2) {
    out.add(
      const Advice(
        'Seams',
        'The edges do not match, so tiling shows lines. Turn on Make seamless.',
      ),
    );
  }
  return out;
}

/// A good starting master size for a surface [side] pixels across.
int suggestedSize(double side) =>
    math.max(256, math.min(2048, pow2Floor(side * 1.25)));
