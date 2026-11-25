import 'dart:math' as math;
import 'dart:typed_data';

import 'land.dart';
import 'sky.dart';

/// A camera for stills and flyovers (plain data, sendable to isolates).
class Shot {
  const Shot(this.x, this.y, this.z, this.yaw, this.pitch, {this.fov = 60});
  final double x, y, z, yaw, pitch, fov;
}

/// Everything a worker needs to trace part of a picture.
class TraceJob {
  const TraceJob(this.settings, this.field, this.shot, this.width, this.height);
  final LandSettings settings;
  final HeightField field;
  final Shot shot;
  final int width, height;
}

/// One worker's share of a pass: every [step]-th pixel on rows
/// y = step·(worker + k·workers). Returns the traced colours in order.
Uint32List tracePass((TraceJob, int, int, int) a) {
  final (job, worker, workers, step) = a;
  final t = _Tracer(job);
  final out = <int>[];
  for (var y = worker * step; y < job.height; y += step * workers) {
    for (var x = 0; x < job.width; x += step) {
      out.add(t.pixel(x + step / 2, y + step / 2));
    }
  }
  return Uint32List.fromList(out);
}

class _Tracer {
  _Tracer(this.job)
    : s = job.settings,
      f = job.field,
      sky = skyFor(job.settings) {
    final sh = job.shot;
    fx = -math.sin(sh.yaw) * math.cos(sh.pitch);
    fy = math.sin(sh.pitch);
    fz = -math.cos(sh.yaw) * math.cos(sh.pitch);
    rx = math.cos(sh.yaw);
    rz = -math.sin(sh.yaw);
    // up = right × forward
    ux = 0 * fz - rz * fy;
    uy = rz * fx - rx * fz;
    uz = rx * fy - 0 * fx;
    tanY = math.tan(sh.fov * math.pi / 360);
    tanX = tanY * job.width / job.height;
    sea = seaHeight(s);
    top = LandSettings.maxHeight * (0.2 + s.height * 0.8);
    final night = sky.sunHeight < 0.02;
    final light = night ? sky.moon : sky.sun;
    lx = light.$1;
    ly = light.$2;
    lz = light.$3;
    lightColor = night
        ? (s.preset == 'moon' ? 0xFF303644 : 0xFF5A6A90)
        : sky.sunColor;
    lightPower = night ? 0.55 : 1.15;
  }

  final TraceJob job;
  final LandSettings s;
  final HeightField f;
  final SkyState sky;
  late final double fx, fy, fz, rx, rz, ux, uy, uz, tanX, tanY, sea, top;
  late double lx, ly, lz;
  late final int lightColor;
  late final double lightPower;

  double get far => LandSettings.worldSize * 1.6;

  double h(double x, double z) {
    final half = f.size / 2;
    if (x < -half || x > half || z < -half || z > half) {
      // Beyond the map: the land sinks gently to a plain.
      final d = math.max(x.abs(), z.abs()) - half;
      return f.heightAt(x.clamp(-half, half), z.clamp(-half, half)) *
          math.max(0.0, 1 - d / 60);
    }
    return f.heightAt(x, z);
  }

  int pixel(double px, double py) {
    final sx = (px / job.width * 2 - 1) * tanX,
        sy = (1 - py / job.height * 2) * tanY;
    var dx = fx + rx * sx + ux * sy,
        dy = fy + uy * sy,
        dz = fz + rz * sx + uz * sy;
    final l = math.sqrt(dx * dx + dy * dy + dz * dz);
    dx /= l;
    dy /= l;
    dz /= l;
    final sh = job.shot;
    final c = trace(sh.x, sh.y, sh.z, dx, dy, dz, 0);
    return 0xFF000000 | (_to8(c.$1) << 16) | (_to8(c.$2) << 8) | _to8(c.$3);
  }

  static int _to8(double v) {
    // Gentle filmic shoulder.
    final x = v / (1 + v * 0.15) * 1.15;
    return (x * 255).round().clamp(0, 255);
  }

  /// March to the ground: distance, or -1 for none.
  double march(
    double ox,
    double oy,
    double oz,
    double dx,
    double dy,
    double dz,
    double maxT, {
    double minStep = 0.3,
  }) {
    var t = 0.5, prev = 0.0;
    while (t < maxT) {
      final x = ox + dx * t, y = oy + dy * t, z = oz + dz * t;
      if (y > top + 2 && dy >= 0) {
        return -1;
      }
      final gh = h(x, z);
      if (y < gh) {
        // Refine between the last two samples.
        var a = prev, b = t;
        for (var i = 0; i < 6; i++) {
          final m = (a + b) / 2;
          if (oy + dy * m < h(ox + dx * m, oz + dz * m)) {
            b = m;
          } else {
            a = m;
          }
        }
        return b;
      }
      prev = t;
      t += math.max(minStep, (y - gh) * 0.42) * (1 + t / 900);
    }
    return -1;
  }

  (double, double, double) trace(
    double ox,
    double oy,
    double oz,
    double dx,
    double dy,
    double dz,
    int depth,
  ) {
    var tHit = march(
      ox,
      oy,
      oz,
      dx,
      dy,
      dz,
      far,
      minStep: depth > 0 ? 1.0 : 0.3,
    );
    // Water first if the ray meets the sea before the land.
    if (s.water && dy < 0 && oy > sea) {
      final tw = (sea - oy) / dy;
      if (tw < far && (tHit < 0 || tw < tHit)) {
        return _fog(
          _water(
            ox + dx * tw,
            sea,
            oz + dz * tw,
            dx,
            dy,
            dz,
            tHit < 0 ? 30.0 : tHit - tw,
            depth,
          ),
          tw,
          dx,
          dy,
          dz,
        );
      }
    }
    if (tHit < 0) {
      return _sky(dx, dy, dz, ox, oy, oz);
    }
    final x = ox + dx * tHit, y = oy + dy * tHit, z = oz + dz * tHit;
    return _fog(_ground(x, y, z), tHit, dx, dy, dz);
  }

  (double, double, double) _ground(double x, double y, double z) {
    final (nx, ny, nz) = f.normalAt(x, z);
    var albedo = groundColor(s, y, ny, sea);
    // Small surface variation so flat areas are not plastic.
    final grain =
        1 +
        noise(x * 0.9, z * 0.9, 3) * 0.12 +
        noise(x * 0.17, z * 0.17, 5) * 0.1;
    final lit = math.max(0.0, nx * lx + ny * ly + nz * lz);
    final shadow = lit > 0
        ? _shadow(x + nx * 0.4, y + ny * 0.4, z + nz * 0.4)
        : 0.0;
    final amb = 0.55 + 0.45 * ny;
    double ch(int c, int sh) => ((c >> sh) & 255) / 255;
    final r = ch(albedo, 16) * grain,
        g = ch(albedo, 8) * grain,
        b = ch(albedo, 0) * grain;
    return (
      r *
          (ch(lightColor, 16) * lit * shadow * lightPower +
              ch(sky.ambient, 16) * amb),
      g *
          (ch(lightColor, 8) * lit * shadow * lightPower +
              ch(sky.ambient, 8) * amb),
      b *
          (ch(lightColor, 0) * lit * shadow * lightPower +
              ch(sky.ambient, 0) * amb),
    );
  }

  /// Soft shadow towards the light: 0 dark .. 1 lit.
  double _shadow(double ox, double oy, double oz) {
    var t = 0.6, res = 1.0;
    while (t < 220) {
      final y = oy + ly * t;
      if (y > top + 2) {
        break;
      }
      final d = y - h(ox + lx * t, oz + lz * t);
      if (d < 0) {
        return 0;
      }
      res = math.min(res, 6 * d / t);
      t += math.max(0.8, d * 0.6);
    }
    return res.clamp(0.0, 1.0);
  }

  (double, double, double) _water(
    double x,
    double y,
    double z,
    double dx,
    double dy,
    double dz,
    double depthBelow,
    int depth,
  ) {
    // Ripples: a slightly tilted normal.
    final e = 0.6;
    final w0 =
        noise(x * 0.35, z * 0.35, 21) + noise(x * 0.9, z * 0.9, 22) * 0.4;
    final nxr = (noise((x + e) * 0.35, z * 0.35, 21) - w0) * 0.25,
        nzr = (noise(x * 0.35, (z + e) * 0.35, 21) - w0) * 0.25;
    var nx = -nxr, ny = 1.0, nz = -nzr;
    final nl = math.sqrt(nx * nx + ny * ny + nz * nz);
    nx /= nl;
    ny /= nl;
    nz /= nl;
    final dn = dx * nx + dy * ny + dz * nz;
    var rx = dx - 2 * dn * nx, ry = dy - 2 * dn * ny, rz = dz - 2 * dn * nz;
    if (ry < 0.01) {
      ry = 0.01;
    }
    final cosT = (-dn).clamp(0.0, 1.0);
    final fresnel = 0.02 + 0.98 * math.pow(1 - cosT, 5);
    final refl = depth < 1
        ? trace(x, y + 0.05, z, rx, ry, rz, depth + 1)
        : _sky(rx, ry, rz, x, y, z);
    // Deep water darker, shallows show turquoise.
    final ground = h(x, z);
    final deep = ((sea - ground) / 12).clamp(0.0, 1.0);
    final base = (
      0.05 + 0.12 * (1 - deep),
      0.16 + 0.22 * (1 - deep),
      0.24 + 0.12 * (1 - deep),
    );
    double ch(int c, int s) => ((c >> s) & 255) / 255;
    final light = math.max(0.15, ly) * 0.8 + 0.2;
    final k = fresnel * 0.85 + 0.1;
    return (
      base.$1 * light * (1 - k) +
          refl.$1 * k +
          ch(lightColor, 16) * _glint(rx, ry, rz),
      base.$2 * light * (1 - k) +
          refl.$2 * k +
          ch(lightColor, 8) * _glint(rx, ry, rz),
      base.$3 * light * (1 - k) +
          refl.$3 * k +
          ch(lightColor, 0) * _glint(rx, ry, rz),
    );
  }

  double _glint(double rx, double ry, double rz) {
    final d = rx * lx + ry * ly + rz * lz;
    return d > 0.995 ? math.pow((d - 0.995) / 0.005, 3).toDouble() * 1.5 : 0;
  }

  (double, double, double) _fog(
    (double, double, double) c,
    double t,
    double dx,
    double dy,
    double dz,
  ) {
    final density = 0.0006 + s.haze * 0.0045;
    final k = 1 - math.exp(-t * density);
    final hz = _horizonGlow(dx, dy, dz);
    return (
      c.$1 + (hz.$1 - c.$1) * k,
      c.$2 + (hz.$2 - c.$2) * k,
      c.$3 + (hz.$3 - c.$3) * k,
    );
  }

  /// Haze colour: the horizon, warmer towards the sun.
  (double, double, double) _horizonGlow(double dx, double dy, double dz) {
    double ch(int c, int s) => ((c >> s) & 255) / 255;
    final sunDot = math.max(
      0.0,
      dx * sky.sun.$1 + dy * sky.sun.$2 + dz * sky.sun.$3,
    );
    final glow = math.pow(sunDot, 8).toDouble() * (1 - sky.night) * 0.6;
    return (
      ch(sky.horizon, 16) + ch(sky.sunColor, 16) * glow,
      ch(sky.horizon, 8) + ch(sky.sunColor, 8) * glow,
      ch(sky.horizon, 0) + ch(sky.sunColor, 0) * glow * 0.7,
    );
  }

  (double, double, double) _sky(
    double dx,
    double dy,
    double dz,
    double ox,
    double oy,
    double oz,
  ) {
    double ch(int c, int s) => ((c >> s) & 255) / 255;
    final up = math.pow(math.max(0.0, dy), 0.45).toDouble();
    final hz = _horizonGlow(dx, dy, dz);
    var r = hz.$1 + (ch(sky.zenith, 16) - hz.$1) * up;
    var g = hz.$2 + (ch(sky.zenith, 8) - hz.$2) * up;
    var b = hz.$3 + (ch(sky.zenith, 0) - hz.$3) * up;
    // Stars.
    if (sky.night > 0 && dy > 0) {
      final sx = (dx * 600).floor(),
          sy = (dy * 600).floor(),
          sz = (dz * 600).floor();
      final hsh =
          ((sx * 73856093) ^ (sy * 19349663) ^ (sz * 83492791)) & 0xffff;
      if (hsh < 18) {
        final k = sky.night * (0.4 + (hsh % 7) / 10) * math.min(1, dy * 6);
        r += k;
        g += k;
        b += k;
      }
    }
    // Sun and moon discs.
    final sd = dx * sky.sun.$1 + dy * sky.sun.$2 + dz * sky.sun.$3;
    if (sd > 0.99975 && sky.sun.$2 > -0.03) {
      r += 3;
      g += 2.7;
      b += 2.2;
    }
    final md = dx * sky.moon.$1 + dy * sky.moon.$2 + dz * sky.moon.$3;
    if (md > 0.9997 && sky.night > 0.2) {
      final k = s.preset == 'moon' ? (0.4, 0.6, 0.95) : (0.95, 0.96, 1.0);
      r = r * 0.2 + k.$1;
      g = g * 0.2 + k.$2;
      b = b * 0.2 + k.$3;
    }
    // Clouds: a noise layer high up.
    if (s.clouds > 0.01 && dy > 0.01) {
      final hgt = LandSettings.maxHeight * 1.6;
      final t = (hgt - oy) / dy;
      if (t > 0 && t < 4000) {
        final cx = ox + dx * t, cz = oz + dz * t;
        var d =
            noise(cx / 140, cz / 140, 41) +
            noise(cx / 60, cz / 60, 42) * 0.5 +
            noise(cx / 25, cz / 25, 43) * 0.25;
        d = ((d + 0.35 - (1 - s.clouds) * 0.9) * 2).clamp(0.0, 1.0);
        final fade = math.min(1.0, dy * 8) * d * 0.9;
        final light = 0.55 + 0.45 * (1 - sky.night);
        final cr =
            (0.95 * light + ch(sky.sunColor, 16) * 0.25) *
            (1 - sky.night * 0.7);
        final cg =
            (0.95 * light + ch(sky.sunColor, 8) * 0.2) * (1 - sky.night * 0.7);
        final cb =
            (0.97 * light + ch(sky.sunColor, 0) * 0.15) * (1 - sky.night * 0.6);
        r += (cr - r) * fade;
        g += (cg - g) * fade;
        b += (cb - b) * fade;
      }
    }
    return (r, g, b);
  }
}

/// Puts a pass's traced pixels into the picture, filling each [step]²
/// block (so the picture sharpens pass by pass).
void placePass(
  Uint32List image,
  int w,
  int h,
  Uint32List data,
  int worker,
  int workers,
  int step,
) {
  var k = 0;
  for (var y = worker * step; y < h; y += step * workers) {
    for (var x = 0; x < w; x += step) {
      final c = data[k++];
      for (var yy = y; yy < math.min(h, y + step); yy++) {
        for (var xx = x; xx < math.min(w, x + step); xx++) {
          image[yy * w + xx] = c;
        }
      }
    }
  }
}
