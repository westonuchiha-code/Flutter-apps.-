/// PS2 save icons (.ico / .icn), ported from the PC's Ps2Icon.gd.
///
/// Header (20 bytes): 0x10000, shape count, texture type (4 = has one,
/// 8 = run-length packed), -, vertex count. Then per vertex: one s16
/// x/y/z/w per shape, a normal, a uv and an RGBA colour (4096 = 1.0).
/// Then the animation (length in ticks, speed, frames of morph keys) and a
/// 128×128 texture of 15-bit colours. Read into the menu's axes (Y up,
/// Z toward the viewer), centred and scaled to fit.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../bytes.dart';
import '../model.dart';

abstract final class Ps2IconFile {
  static const maxShapes = 32;
  static const maxVertices = 30000;
  static const maxFrames = 256;
  static const maxKeys = 1024;
  static const texSize = 128;
  static const texPresent = 4;
  static const texPacked = 8;
  static const unit = 4096.0;

  /// The tallest half (or widest, with depth counted at 0.7) after fitting.
  static const fit = 0.74;
  static const ticksPerSecond = 60.0;

  /// null = not an icon (or one too broken to show).
  static Ps2Icon? parse(List<int> b) {
    if (!Bytes.has(b, 0, 20) || Bytes.u32(b, 0) != 0x10000) return null;
    final shapeCount = Bytes.u32(b, 4);
    final texType = Bytes.u32(b, 8);
    final count = Bytes.u32(b, 16);
    if (shapeCount < 1 ||
        shapeCount > maxShapes ||
        count < 3 ||
        count > maxVertices) {
      return null;
    }
    final stride = shapeCount * 8 + 16;
    final animAt = 20 + stride * count;
    if (!Bytes.has(b, 20, stride * count)) return null;
    final ico = Ps2Icon();
    _readVertices(ico, b, shapeCount, count - count % 3, stride);
    final texAt = _readAnimation(ico, b, animAt);
    if (texType & texPresent != 0 && texAt > 0 && texAt < b.length) {
      ico.texture = readTexture(b, texAt, texType & texPacked != 0);
    }
    var brightest = 0.0;
    for (final c in ico.colors) {
      brightest = math.max(brightest, math.max(c.r, math.max(c.g, c.b)));
    }
    if (ico.texture != null && brightest <= 128.5 / 255) {
      ico.colorScale = 255 / 128;
    }
    _fit(ico);
    return ico;
  }

  /// 16-bit pixels, plain or run-length packed: (count, pixel) repeats one,
  /// (0x10000 - count, pixels...) copies that many.
  static Pixels readTexture(List<int> b, int start, bool packed) {
    const want = texSize * texSize;
    final out = Pixels(texSize, texSize);
    final px = out.rgba;
    for (var i = 3; i < px.length; i += 4) {
      px[i] = 255;
    }
    var got = 0;
    void put(int v) {
      final i = got * 4;
      final r = v & 31, g = v >> 5 & 31, bl = v >> 10 & 31;
      px[i] = r << 3 | r >> 2;
      px[i + 1] = g << 3 | g >> 2;
      px[i + 2] = bl << 3 | bl >> 2;
      got++;
    }

    if (packed) {
      final end = math.min(b.length, start + 4 + Bytes.u32(b, start));
      var at = start + 4;
      while (at + 2 <= end && got < want) {
        final code = Bytes.u16(b, at);
        at += 2;
        if (code >= 0xFF00) {
          final n = math.min(0x10000 - code, want - got);
          for (var i = 0; i < n; i++) {
            if (at + 2 > end) break;
            put(Bytes.u16(b, at));
            at += 2;
          }
        } else if (at + 2 <= end) {
          final v = Bytes.u16(b, at);
          at += 2;
          final n = math.min(code, want - got);
          for (var i = 0; i < n; i++) {
            put(v);
          }
        }
      }
    } else {
      final n = math.min(want, (b.length - start) ~/ 2);
      for (var i = 0; i < n; i++) {
        put(Bytes.u16(b, start + i * 2));
      }
    }
    return out;
  }

  static void _readVertices(
    Ps2Icon ico,
    List<int> b,
    int shapeCount,
    int count,
    int stride,
  ) {
    for (var s = 0; s < shapeCount; s++) {
      final pts = <Vec3>[];
      for (var i = 0; i < count; i++) {
        final at = 20 + stride * i + s * 8;
        pts.add(
          Vec3(
            Bytes.s16(b, at) / unit,
            -Bytes.s16(b, at + 2) / unit,
            -Bytes.s16(b, at + 4) / unit,
          ),
        );
      }
      ico.shapes.add(pts);
    }
    for (var i = 0; i < count; i++) {
      final at = 20 + stride * i + shapeCount * 8;
      final n = Vec3(
        Bytes.s16(b, at).toDouble(),
        -Bytes.s16(b, at + 2).toDouble(),
        -Bytes.s16(b, at + 4).toDouble(),
      );
      ico.normals.add(n.length > 0 ? n.normalized() : Vec3.back);
      ico.uvs.add((Bytes.s16(b, at + 8) / unit, Bytes.s16(b, at + 10) / unit));
      ico.colors.add(
        Rgb.from8(
          Bytes.u8(b, at + 12),
          Bytes.u8(b, at + 13),
          Bytes.u8(b, at + 14),
        ),
      );
    }
  }

  /// Where the texture starts (0 = the animation section is unreadable;
  /// tracks read before the damage are kept).
  static int _readAnimation(Ps2Icon ico, List<int> b, int start) {
    if (!Bytes.has(b, start, 20)) return 0;
    ico.length = Bytes.u32(b, start + 4).toDouble();
    ico.speed = Bytes.f32(b, start + 8);
    final frames = Bytes.u32(b, start + 16);
    if (frames > maxFrames) return 0;
    var at = start + 20;
    for (var f = 0; f < frames; f++) {
      if (!Bytes.has(b, at, 16)) return 0;
      final shape = Bytes.u32(b, at);
      final keyCount = Bytes.u32(b, at + 4);
      if (keyCount > maxKeys) return 0;
      // The key count includes one pair that sits inside the frame header.
      final keys = <(double, double)>[
        (Bytes.f32(b, at + 8), Bytes.f32(b, at + 12)),
      ];
      at += 16;
      for (var k = 0; k < math.max(keyCount - 1, 0); k++) {
        keys.add((Bytes.f32(b, at), Bytes.f32(b, at + 4)));
        at += 8;
      }
      ico.tracks.add((shape: shape, keys: keys));
    }
    return at;
  }

  static void _fit(Ps2Icon ico) {
    var lo = ico.shapes[0][0], hi = lo;
    for (final pts in ico.shapes) {
      for (final p in pts) {
        lo = Vec3(
          math.min(lo.x, p.x),
          math.min(lo.y, p.y),
          math.min(lo.z, p.z),
        );
        hi = Vec3(
          math.max(hi.x, p.x),
          math.max(hi.y, p.y),
          math.max(hi.z, p.z),
        );
      }
    }
    final mid = (lo + hi) * 0.5;
    final half = (hi - lo) * 0.5;
    final flat = math.sqrt(half.x * half.x + half.z * 0.7 * (half.z * 0.7));
    final k = fit / math.max(math.max(half.y, flat), 0.0001);
    for (final pts in ico.shapes) {
      for (var i = 0; i < pts.length; i++) {
        pts[i] = (pts[i] - mid) * k;
      }
    }
  }

  /// A track's weight at [tick]: straight lines between its keys, held
  /// flat before the first and after the last.
  static double keyValue(List<(double, double)> keys, double tick) {
    if (keys.isEmpty) return 0;
    if (tick <= keys[0].$1) return keys[0].$2;
    for (var i = 1; i < keys.length; i++) {
      if (tick <= keys[i].$1) {
        final a = keys[i - 1], b = keys[i];
        final t = (tick - a.$1) / math.max(b.$1 - a.$1, 0.0001);
        return a.$2 + (b.$2 - a.$2) * t;
      }
    }
    return keys.last.$2;
  }
}

/// Playing an icon's animation (Ps2Icon.gd's `weights`).
extension Ps2IconMotion on Ps2Icon {
  /// How much of each shape to mix at [seconds]. Always adds up to 1.
  Float64List weights(double seconds) {
    final out = Float64List(shapes.length);
    if (out.isEmpty) return out;
    var sum = 0.0;
    if (shapes.length > 1) {
      final loop = seconds / loopSeconds;
      final tick = (loop - loop.floorToDouble()) * math.max(length, 1);
      for (final t in tracks) {
        if (t.shape >= 0 && t.shape < out.length) {
          final w = math.max(Ps2IconFile.keyValue(t.keys, tick), 0.0);
          out[t.shape] += w;
          sum += w;
        }
      }
    }
    if (!(sum > 0.0005)) {
      out.fillRange(0, out.length, 0);
      out[0] = 1;
      return out;
    }
    for (var i = 0; i < out.length; i++) {
      out[i] /= sum;
    }
    return out;
  }
}
