import 'dart:math' as math;
import 'dart:typed_data';

/// Everything that makes a landscape (a world is rebuilt exactly from it).
class LandSettings {
  const LandSettings({
    this.seed = 1,
    this.preset = 'alps',
    this.height = 0.55,
    this.roughness = 0.5,
    this.ridges = 0.6,
    this.erosion = 0.5,
    this.seaLevel = 0.18,
    this.sand = 0xFFD8C690,
    this.grass = 0xFF5E8A3E,
    this.rock = 0xFF7A7068,
    this.snow = 0xFFF2F4F8,
    this.time = 15,
    this.sunTurn = 0.35,
    this.clouds = 0.4,
    this.haze = 0.35,
  });

  final int seed;
  final String preset;

  /// 0..1 sliders.
  final double height, roughness, ridges, erosion, seaLevel;
  final int sand, grass, rock, snow;

  /// Hour of the day, 0..24.
  final double time;

  /// Where the sun rises, as a turn (0..1) around the sky.
  final double sunTurn;
  final double clouds, haze;

  static const kind = 'vista_landscape';

  /// World size (units ≈ metres ×10), and the highest possible peak.
  static const worldSize = 400.0, maxHeight = 90.0;

  bool get water => preset != 'moon';

  LandSettings copyWith({
    int? seed,
    String? preset,
    double? height,
    double? roughness,
    double? ridges,
    double? erosion,
    double? seaLevel,
    int? sand,
    int? grass,
    int? rock,
    int? snow,
    double? time,
    double? sunTurn,
    double? clouds,
    double? haze,
  }) => LandSettings(
    seed: seed ?? this.seed,
    preset: preset ?? this.preset,
    height: height ?? this.height,
    roughness: roughness ?? this.roughness,
    ridges: ridges ?? this.ridges,
    erosion: erosion ?? this.erosion,
    seaLevel: seaLevel ?? this.seaLevel,
    sand: sand ?? this.sand,
    grass: grass ?? this.grass,
    rock: rock ?? this.rock,
    snow: snow ?? this.snow,
    time: time ?? this.time,
    sunTurn: sunTurn ?? this.sunTurn,
    clouds: clouds ?? this.clouds,
    haze: haze ?? this.haze,
  );

  Map<String, Object?> toJson() => {
    'kind': kind,
    'version': 1,
    'seed': seed,
    'preset': preset,
    'height': height,
    'roughness': roughness,
    'ridges': ridges,
    'erosion': erosion,
    'seaLevel': seaLevel,
    'colors': [sand, grass, rock, snow],
    'time': time,
    'sunTurn': sunTurn,
    'clouds': clouds,
    'haze': haze,
  };

  factory LandSettings.fromJson(Object? j) {
    if (j is! Map || j['kind'] != kind) {
      throw const FormatException('Not a Vista landscape');
    }
    double d(String k, double def) => ((j[k] as num?) ?? def).toDouble();
    final c =
        (j['colors'] as List?)?.map((e) => (e as num).toInt()).toList() ??
        const [];
    const def = LandSettings();
    return LandSettings(
      seed: (j['seed'] as num?)?.toInt() ?? 1,
      preset: (j['preset'] as String?) ?? 'alps',
      height: d('height', def.height),
      roughness: d('roughness', def.roughness),
      ridges: d('ridges', def.ridges),
      erosion: d('erosion', def.erosion),
      seaLevel: d('seaLevel', def.seaLevel),
      sand: c.isNotEmpty ? c[0] : def.sand,
      grass: c.length > 1 ? c[1] : def.grass,
      rock: c.length > 2 ? c[2] : def.rock,
      snow: c.length > 3 ? c[3] : def.snow,
      time: d('time', def.time),
      sunTurn: d('sunTurn', def.sunTurn),
      clouds: d('clouds', def.clouds),
      haze: d('haze', def.haze),
    );
  }
}

/// Starting points for each kind of land.
const presets = <String, (String, LandSettings)>{
  'alps': ('Alps', LandSettings()),
  'desert': (
    'Desert',
    LandSettings(
      preset: 'desert',
      height: 0.25,
      roughness: 0.3,
      ridges: 0.2,
      erosion: 0.1,
      seaLevel: 0.0,
      sand: 0xFFE2B878,
      grass: 0xFFC99A5E,
      rock: 0xFFA0603E,
      snow: 0xFFE8C894,
      time: 17.5,
      clouds: 0.1,
      haze: 0.5,
    ),
  ),
  'islands': (
    'Islands',
    LandSettings(
      preset: 'islands',
      height: 0.45,
      roughness: 0.55,
      ridges: 0.3,
      erosion: 0.4,
      seaLevel: 0.42,
      time: 12,
      clouds: 0.5,
    ),
  ),
  'canyon': (
    'Canyon',
    LandSettings(
      preset: 'canyon',
      height: 0.5,
      roughness: 0.45,
      ridges: 0.5,
      erosion: 0.7,
      seaLevel: 0.08,
      sand: 0xFFC8855A,
      grass: 0xFF9E6A44,
      rock: 0xFFB0583A,
      snow: 0xFFE0B48C,
      time: 9,
      clouds: 0.2,
      haze: 0.3,
    ),
  ),
  'moon': (
    'Moon',
    LandSettings(
      preset: 'moon',
      height: 0.3,
      roughness: 0.4,
      ridges: 0.1,
      erosion: 0.0,
      seaLevel: 0.0,
      sand: 0xFF9A9A9A,
      grass: 0xFF888888,
      rock: 0xFF6E6E6E,
      snow: 0xFFB8B8B8,
      time: 22,
      clouds: 0,
      haze: 0,
    ),
  ),
};

/// A square grid of heights over the world.
class HeightField {
  HeightField(this.n, this.size, this.h);

  /// Points per side.
  final int n;

  /// World units per side (centred on the origin).
  final double size;
  final Float32List h;

  double get cell => size / (n - 1);

  double at(int i, int j) => h[j.clamp(0, n - 1) * n + i.clamp(0, n - 1)];

  /// Height at world (x, z), bilinear.
  double heightAt(double x, double z) {
    final fx = ((x + size / 2) / cell).clamp(0.0, n - 1.001),
        fz = ((z + size / 2) / cell).clamp(0.0, n - 1.001);
    final i = fx.floor(), j = fz.floor();
    final tx = fx - i, tz = fz - j;
    final a = h[j * n + i],
        b = h[j * n + i + 1],
        c = h[(j + 1) * n + i],
        d = h[(j + 1) * n + i + 1];
    return (a * (1 - tx) + b * tx) * (1 - tz) + (c * (1 - tx) + d * tx) * tz;
  }

  /// Unit normal at world (x, z).
  (double, double, double) normalAt(double x, double z) {
    final e = cell;
    final nx = heightAt(x - e, z) - heightAt(x + e, z),
        nz = heightAt(x, z - e) - heightAt(x, z + e),
        ny = 2 * e;
    final l = math.sqrt(nx * nx + ny * ny + nz * nz);
    return (nx / l, ny / l, nz / l);
  }

  /// A coarser copy with [m] points per side (for real-time drawing).
  HeightField resample(int m) {
    final out = Float32List(m * m);
    for (var j = 0; j < m; j++) {
      for (var i = 0; i < m; i++) {
        out[j * m + i] = heightAt(
          -size / 2 + size * i / (m - 1),
          -size / 2 + size * j / (m - 1),
        );
      }
    }
    return HeightField(m, size, out);
  }
}

// ---- Noise ----

int _hash(int x, int y, int seed) {
  var h = x * 374761393 + y * 668265263 + seed * 2147483647;
  h = (h ^ (h >> 13)) * 1274126177;
  return (h ^ (h >> 16)) & 0x7fffffff;
}

double _grad(int ix, int iy, double dx, double dy, int seed) {
  final a = _hash(ix, iy, seed) / 0x7fffffff * math.pi * 2;
  return math.cos(a) * dx + math.sin(a) * dy;
}

double _fade(double t) => t * t * t * (t * (t * 6 - 15) + 10);

/// Gradient (Perlin-style) noise, about -0.7..0.7.
double noise(double x, double y, int seed) {
  final ix = x.floor(), iy = y.floor();
  final fx = x - ix, fy = y - iy;
  final u = _fade(fx), v = _fade(fy);
  final a = _grad(ix, iy, fx, fy, seed),
      b = _grad(ix + 1, iy, fx - 1, fy, seed);
  final c = _grad(ix, iy + 1, fx, fy - 1, seed),
      d = _grad(ix + 1, iy + 1, fx - 1, fy - 1, seed);
  return (a + (b - a) * u) + ((c + (d - c) * u) - (a + (b - a) * u)) * v;
}

/// Builds the height field for [s] at [n] points per side.
HeightField generate(LandSettings s, {int n = 257}) {
  final h = Float32List(n * n);
  final seed = s.seed;
  final gain = 0.35 + s.roughness * 0.3;
  final size = LandSettings.worldSize;
  for (var j = 0; j < n; j++) {
    for (var i = 0; i < n; i++) {
      var x = (i / (n - 1) - 0.5) * 4.0, y = (j / (n - 1) - 0.5) * 4.0;
      // Warp the domain a little: less grid-like, more natural.
      final wx = noise(x * 0.7 + 11, y * 0.7, seed + 7) * 0.6,
          wy = noise(x * 0.7, y * 0.7 - 13, seed + 9) * 0.6;
      x += wx;
      y += wy;
      var amp = 1.0, freq = 1.0, smooth = 0.0, ridged = 0.0, weight = 1.0;
      for (var o = 0; o < 8; o++) {
        final nv = noise(x * freq, y * freq, seed + o * 31);
        smooth += nv * amp;
        // Ridged: sharp crests where the noise crosses zero.
        var r = 1 - (nv * 1.6).abs();
        r = r * r * weight;
        weight = (r * 1.5).clamp(0.0, 1.0);
        ridged += r * amp;
        amp *= gain;
        freq *= 2.03;
      }
      var v = (smooth * 0.9 + 0.5) * (1 - s.ridges) + ridged * 0.55 * s.ridges;
      final dx = i / (n - 1) - 0.5, dz = j / (n - 1) - 0.5;
      final r = math.sqrt(dx * dx + dz * dz) * 2; // 0 centre .. ~1.4 corners
      switch (s.preset) {
        case 'islands':
          v *= (1.25 - r * 0.9).clamp(0.0, 1.0);
        case 'desert':
          // Long dunes across the wind.
          v =
              v * 0.5 +
              0.18 *
                  math.pow(
                    math.sin((x * 3.2 + noise(x, y, seed + 3) * 2.5)).abs(),
                    2.0,
                  );
        case 'canyon':
          // Mesas: flat steps.
          v = (v * 6).floorToDouble() / 6 * 0.75 + v * 0.25;
        default:
          break;
      }
      h[j * n + i] = v.toDouble();
    }
  }
  if (s.preset == 'moon') {
    _craters(h, n, seed);
  }
  // Normalise to 0..1, then to world height.
  var lo = double.infinity, hi = -double.infinity;
  for (final v in h) {
    lo = math.min(lo, v);
    hi = math.max(hi, v);
  }
  final top = LandSettings.maxHeight * (0.2 + s.height * 0.8);
  for (var k = 0; k < h.length; k++) {
    h[k] = (h[k] - lo) / math.max(1e-6, hi - lo) * top;
  }
  final field = HeightField(n, size, h);
  if (s.erosion > 0) {
    erode(field, (s.erosion * n * n * 0.9).round(), seed);
  }
  return field;
}

void _craters(Float32List h, int n, int seed) {
  final rnd = math.Random(seed);
  for (var c = 0; c < 60; c++) {
    final cx = rnd.nextDouble() * n, cy = rnd.nextDouble() * n;
    final r = 3 + math.pow(rnd.nextDouble(), 3) * n * 0.12;
    final depth = r * 0.012;
    for (
      var j = math.max(0, (cy - r * 1.5).floor());
      j < math.min(n, (cy + r * 1.5).ceil());
      j++
    ) {
      for (
        var i = math.max(0, (cx - r * 1.5).floor());
        i < math.min(n, (cx + r * 1.5).ceil());
        i++
      ) {
        final d = math.sqrt((i - cx) * (i - cx) + (j - cy) * (j - cy)) / r;
        // Bowl, raised rim, then flat.
        final k = d < 1
            ? (d * d - 1) * depth
            : (d < 1.5
                  ? math.cos((d - 1) / 0.5 * math.pi / 2) * depth * 0.35
                  : 0);
        h[j * n + i] += k;
      }
    }
  }
}

/// Hydraulic erosion: raindrops run downhill, picking up soil where fast and
/// dropping it where they slow, carving valleys and gullies.
void erode(HeightField f, int drops, int seed) {
  final n = f.n, h = f.h;
  final rnd = math.Random(seed * 7 + 1);
  final scale = f.cell; // heights are in world units; work in cell units
  for (var d = 0; d < drops; d++) {
    var x = rnd.nextDouble() * (n - 2), y = rnd.nextDouble() * (n - 2);
    var dx = 0.0, dy = 0.0, speed = 1.0, water = 1.0, sediment = 0.0;
    for (var life = 0; life < 40; life++) {
      final i = x.floor(), j = y.floor();
      if (i < 0 || j < 0 || i >= n - 1 || j >= n - 1) {
        break;
      }
      final u = x - i, v = y - j;
      final a = h[j * n + i],
          b = h[j * n + i + 1],
          c = h[(j + 1) * n + i],
          e = h[(j + 1) * n + i + 1];
      final gx = ((b - a) * (1 - v) + (e - c) * v) / scale,
          gy = ((c - a) * (1 - u) + (e - b) * u) / scale;
      final height =
          (a * (1 - u) + b * u) * (1 - v) + (c * (1 - u) + e * u) * v;
      dx = dx * 0.3 - gx * 0.7;
      dy = dy * 0.3 - gy * 0.7;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len < 1e-6) {
        break;
      }
      dx /= len;
      dy /= len;
      final nx = x + dx, ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= n - 1 || ny >= n - 1) {
        break;
      }
      final ni = nx.floor(), nj = ny.floor(), nu = nx - ni, nv = ny - nj;
      final nh =
          (h[nj * n + ni] * (1 - nu) + h[nj * n + ni + 1] * nu) * (1 - nv) +
          (h[(nj + 1) * n + ni] * (1 - nu) + h[(nj + 1) * n + ni + 1] * nu) *
              nv;
      final dh = nh - height;
      final capacity = math.max(-dh, 0.01 * scale) * speed * water * 4;
      void deposit(double amount) {
        h[j * n + i] += amount * (1 - u) * (1 - v);
        h[j * n + i + 1] += amount * u * (1 - v);
        h[(j + 1) * n + i] += amount * (1 - u) * v;
        h[(j + 1) * n + i + 1] += amount * u * v;
      }

      if (dh > 0) {
        // Uphill: fill the hole behind.
        final amount = math.min(sediment, dh);
        sediment -= amount;
        deposit(amount);
      } else if (sediment > capacity) {
        final amount = (sediment - capacity) * 0.3;
        sediment -= amount;
        deposit(amount);
      } else {
        final amount = math.min((capacity - sediment) * 0.3, -dh);
        sediment += amount;
        deposit(-amount);
      }
      speed = math.sqrt(math.max(0, speed * speed - dh / scale * 4));
      water *= 0.97;
      x = nx;
      y = ny;
    }
  }
}

/// Surface colour from height above the sea and steepness (ny: up-ness).
int groundColor(LandSettings s, double y, double ny, double sea) {
  final top = LandSettings.maxHeight * (0.2 + s.height * 0.8);
  final above = (y - sea) / math.max(1, top - sea);
  int mix(int a, int b, double t) {
    final k = t.clamp(0.0, 1.0);
    int ch(int sh) =>
        (((a >> sh) & 255) * (1 - k) + ((b >> sh) & 255) * k).round();
    return 0xFF000000 | (ch(16) << 16) | (ch(8) << 8) | ch(0);
  }

  final steep = ((0.86 - ny) / 0.14).clamp(0.0, 1.0);
  var c = s.water && above < 0.03
      ? s.sand
      : mix(s.sand, s.grass, (above - 0.03) / 0.04);
  c = mix(c, s.rock, math.max(steep, ((above - 0.55) / 0.15).clamp(0.0, 1.0)));
  if (s.preset != 'desert' && s.preset != 'canyon') {
    final snowLine = 0.72 - (1 - ny) * 0.3;
    c = mix(
      c,
      s.snow,
      ((above - snowLine) / 0.06).clamp(0.0, 1.0) * (ny > 0.6 ? 1 : 0.3),
    );
  }
  return c;
}

/// Sea height for [s] on [f].
double seaHeight(LandSettings s) =>
    LandSettings.maxHeight * (0.2 + s.height * 0.8) * s.seaLevel;
