/// Film looks for exported frames: black and white or tinted, crushed
/// contrast, film grain, flicker, vignette, letterbox and a fisheye lens.
/// Applied to ARGB frames (pure Dart); the preview shows an approximation.
library;

import 'dart:math' as math;
import 'dart:typed_data';

class FilmLook {
  const FilmLook({
    this.mono = false,
    this.tint = 0,
    this.contrast = 0,
    this.grain = 0,
    this.flicker = 0,
    this.vignette = 0,
    this.letterbox = false,
    this.fisheye = 0,
    this.saturation = 0,
    this.exposure = 0,
    this.hueSpin = 0,
    this.hold = 0,
  });

  /// Black and white.
  final bool mono;

  /// 0 none, 1 sepia, 2 cold blue, 3 green night, 4 warm 70s film,
  /// 5 bile (sick green-brown), 6 red and black (on mono or colour).
  final int tint;

  /// 0..1: how hard the blacks and whites are pushed.
  final double contrast;
  final double grain, flicker, vignette;

  /// 2.35:1 black bars.
  final bool letterbox;

  /// 0..1: barrel distortion, like a fisheye lens.
  final double fisheye;

  /// -1..1: washed out to vivid.
  final double saturation;

  /// -1..1: darker to brighter (stops / 2).
  final double exposure;

  /// 0..1: colours cycle round the hue wheel (psychedelic).
  final double hueSpin;

  /// Stop motion: each picture held for this many more frames (0..4).
  final int hold;

  static const none = FilmLook();

  /// The looks offered in the app.
  static const presets = <String, FilmLook>{
    'Clean': none,
    'Black & White': FilmLook(
      mono: true,
      contrast: 0.35,
      grain: 0.25,
      vignette: 0.35,
    ),
    'Noir': FilmLook(
      mono: true,
      contrast: 0.75,
      grain: 0.35,
      flicker: 0.3,
      vignette: 0.6,
      letterbox: true,
    ),
    'Sepia Film': FilmLook(
      mono: true,
      tint: 1,
      contrast: 0.3,
      grain: 0.4,
      flicker: 0.4,
      vignette: 0.5,
    ),
    'Night Blue': FilmLook(tint: 2, contrast: 0.4, grain: 0.2, vignette: 0.5),
    '90s Video': FilmLook(contrast: 0.25, grain: 0.15, vignette: 0.25),
    'Fisheye': FilmLook(
      contrast: 0.3,
      grain: 0.15,
      vignette: 0.45,
      fisheye: 0.8,
    ),
    '70s Film': FilmLook(
      tint: 4,
      contrast: 0.2,
      grain: 0.35,
      vignette: 0.35,
      saturation: 0.25,
      exposure: 0.2,
    ),
    'Bile': FilmLook(
      tint: 5,
      contrast: 0.55,
      grain: 0.5,
      flicker: 0.6,
      vignette: 0.7,
      saturation: -0.6,
      hold: 2,
    ),
    'Red & Black': FilmLook(
      mono: true,
      tint: 6,
      contrast: 0.7,
      grain: 0.3,
      vignette: 0.5,
    ),
    'Flat Bright': FilmLook(saturation: 0.6, exposure: 0.35, contrast: 0.1),
    'Cosmic': FilmLook(
      saturation: 0.9,
      contrast: 0.3,
      vignette: 0.4,
      hueSpin: 0.5,
      fisheye: 0.35,
    ),
    'Stop Motion': FilmLook(contrast: 0.3, grain: 0.3, flicker: 0.4, hold: 2),
  };

  bool get isNone =>
      !mono &&
      tint == 0 &&
      contrast == 0 &&
      grain == 0 &&
      flicker == 0 &&
      vignette == 0 &&
      !letterbox &&
      fisheye == 0 &&
      saturation == 0 &&
      exposure == 0 &&
      hueSpin == 0 &&
      hold == 0;

  FilmLook copyWith({
    bool? mono,
    int? tint,
    double? contrast,
    double? grain,
    double? flicker,
    double? vignette,
    bool? letterbox,
    double? fisheye,
    double? saturation,
    double? exposure,
    double? hueSpin,
    int? hold,
  }) => FilmLook(
    mono: mono ?? this.mono,
    tint: tint ?? this.tint,
    contrast: contrast ?? this.contrast,
    grain: grain ?? this.grain,
    flicker: flicker ?? this.flicker,
    vignette: vignette ?? this.vignette,
    letterbox: letterbox ?? this.letterbox,
    fisheye: fisheye ?? this.fisheye,
    saturation: saturation ?? this.saturation,
    exposure: exposure ?? this.exposure,
    hueSpin: hueSpin ?? this.hueSpin,
    hold: hold ?? this.hold,
  );

  Map<String, Object?> toJson() => {
    if (mono) 'mono': true,
    if (tint != 0) 'tint': tint,
    if (contrast != 0) 'contrast': contrast,
    if (grain != 0) 'grain': grain,
    if (flicker != 0) 'flicker': flicker,
    if (vignette != 0) 'vignette': vignette,
    if (letterbox) 'letterbox': true,
    if (fisheye != 0) 'fisheye': fisheye,
    if (saturation != 0) 'saturation': saturation,
    if (exposure != 0) 'exposure': exposure,
    if (hueSpin != 0) 'hueSpin': hueSpin,
    if (hold != 0) 'hold': hold,
  };

  factory FilmLook.fromJson(Object? j) {
    if (j is! Map) return none;
    double d(String k) => ((j[k] as num?) ?? 0).toDouble().clamp(0, 1);
    return FilmLook(
      mono: j['mono'] == true,
      tint: ((j['tint'] as num?) ?? 0).toInt().clamp(0, 6),
      contrast: d('contrast'),
      grain: d('grain'),
      flicker: d('flicker'),
      vignette: d('vignette'),
      letterbox: j['letterbox'] == true,
      fisheye: d('fisheye'),
      saturation: ((j['saturation'] as num?) ?? 0).toDouble().clamp(-1, 1),
      exposure: ((j['exposure'] as num?) ?? 0).toDouble().clamp(-1, 1),
      hueSpin: d('hueSpin'),
      hold: ((j['hold'] as num?) ?? 0).toInt().clamp(0, 4),
    );
  }
}

/// Applies [look] to [px] (ARGB, [w]×[h]) for frame number [frame].
Uint32List applyLook(Uint32List px, int w, int h, FilmLook look, int frame) {
  if (look.isNone) return px;
  var src = px;
  if (look.fisheye > 0) src = _fisheye(px, w, h, look.fisheye);
  final out = Uint32List(w * h);
  final rnd = math.Random(frame * 7919 + 17);
  final flick = 1 + (rnd.nextDouble() - 0.5) * 0.18 * look.flicker;
  final barH = look.letterbox
      ? ((h - w / 2.35) / 2).round().clamp(0, h ~/ 3)
      : 0;
  final cx = w / 2, cy = h / 2;
  final maxR = math.sqrt(cx * cx + cy * cy);
  final k = 1 + look.contrast * 1.6;
  final sat = 1 + look.saturation;
  final expo = math.pow(2, look.exposure * 0.5).toDouble();
  // Hue rotation (a matrix round the grey axis).
  final ang = frame * look.hueSpin * 0.08;
  final ca = math.cos(ang), sa = math.sin(ang);
  const t3 = 1 / 3, s3 = 0.57735026919;
  final h00 = ca + (1 - ca) * t3, h01 = t3 * (1 - ca) - s3 * sa;
  final h02 = t3 * (1 - ca) + s3 * sa;
  for (var y = 0; y < h; y++) {
    if (y < barH || y >= h - barH) {
      out.fillRange(y * w, (y + 1) * w, 0xFF000000);
      continue;
    }
    for (var x = 0; x < w; x++) {
      final c = src[y * w + x];
      var r = ((c >> 16) & 255) / 255,
          g = ((c >> 8) & 255) / 255,
          b = (c & 255) / 255;
      if (look.mono) {
        final l = 0.299 * r + 0.587 * g + 0.114 * b;
        r = g = b = l;
      } else if (sat != 1) {
        final l = 0.299 * r + 0.587 * g + 0.114 * b;
        r = l + (r - l) * sat;
        g = l + (g - l) * sat;
        b = l + (b - l) * sat;
      }
      if (look.hueSpin > 0) {
        final nr = r * h00 + g * h01 + b * h02;
        final ng = r * h02 + g * h00 + b * h01;
        final nb = r * h01 + g * h02 + b * h00;
        r = nr;
        g = ng;
        b = nb;
      }
      r *= expo;
      g *= expo;
      b *= expo;
      // Contrast around the middle grey (an S-ish curve).
      r = ((r - 0.5) * k + 0.5);
      g = ((g - 0.5) * k + 0.5);
      b = ((b - 0.5) * k + 0.5);
      switch (look.tint) {
        case 1: // sepia
          final l = (r + g + b) / 3;
          r = l * 1.08 + 0.03;
          g = l * 0.92 + 0.02;
          b = l * 0.72;
        case 2: // cold blue
          r *= 0.8;
          g *= 0.95;
          b = b * 1.1 + 0.04;
        case 3: // green night
          r *= 0.7;
          g = g * 1.1 + 0.02;
          b *= 0.75;
        case 4: // warm 70s film: lifted blacks, orange skin, faded blue
          r = r * 1.06 + 0.04;
          g = g * 0.98 + 0.03;
          b = b * 0.78 + 0.05;
        case 5: // bile
          final l = (r + g + b) / 3;
          r = l * 0.85 + r * 0.15;
          g = l * 0.95 + 0.02;
          b = l * 0.55;
        case 6: // red and black: shadows black, mids blood red
          final l = (r + g + b) / 3;
          r = l * 1.25;
          g = l * l * 0.55;
          b = l * l * 0.45;
      }
      var m = flick;
      if (look.vignette > 0) {
        final dx = x - cx, dy = y - cy;
        final d = math.sqrt(dx * dx + dy * dy) / maxR;
        m *= 1 - look.vignette * d * d * 0.9;
      }
      if (look.grain > 0) {
        m *= 1 + (rnd.nextDouble() - 0.5) * 0.35 * look.grain;
      }
      int ch(double v) => (v * m * 255).round().clamp(0, 255);
      out[y * w + x] = 0xFF000000 | (ch(r) << 16) | (ch(g) << 8) | ch(b);
    }
  }
  return out;
}

/// Barrel distortion: the middle bulges toward the viewer, the edges bend.
Uint32List _fisheye(Uint32List px, int w, int h, double amount) {
  final out = Uint32List(w * h);
  final cx = w / 2, cy = h / 2;
  final norm = math.sqrt(cx * cx + cy * cy);
  final k = amount * 0.55;
  // Zoom in so the corners stay filled.
  final zoom = 1 / (1 + k);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final dx = (x - cx) / norm, dy = (y - cy) / norm;
      final r2 = dx * dx + dy * dy;
      final f = (1 + k * r2) * zoom;
      final sx = (cx + dx * f * norm).round(),
          sy = (cy + dy * f * norm).round();
      out[y * w + x] = sx >= 0 && sy >= 0 && sx < w && sy < h
          ? px[sy * w + sx]
          : 0xFF000000;
    }
  }
  return out;
}

/// A 5×4 colour matrix for the preview (mono, tint and contrast only).
List<double> previewMatrix(FilmLook look) {
  final k = 1 + look.contrast * 1.6;
  final o = (0.5 - 0.5 * k) * 255;
  List<double> m = look.mono
      ? [
          0.299 * k, 0.587 * k, 0.114 * k, 0, o, //
          0.299 * k, 0.587 * k, 0.114 * k, 0, o,
          0.299 * k, 0.587 * k, 0.114 * k, 0, o,
          0, 0, 0, 1, 0,
        ]
      : [
          k, 0, 0, 0, o, //
          0, k, 0, 0, o,
          0, 0, k, 0, o,
          0, 0, 0, 1, 0,
        ];
  final (tr, tg, tb) = switch (look.tint) {
    1 => (1.08, 0.92, 0.72),
    2 => (0.8, 0.95, 1.1),
    3 => (0.7, 1.1, 0.75),
    4 => (1.06, 0.98, 0.78),
    5 => (0.9, 0.95, 0.55),
    6 => (1.25, 0.45, 0.4),
    _ => (1.0, 1.0, 1.0),
  };
  for (var i = 0; i < 5; i++) {
    m[i] *= tr;
    m[5 + i] *= tg;
    m[10 + i] *= tb;
  }
  return m;
}
