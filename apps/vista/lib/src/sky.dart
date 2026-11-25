import 'dart:math' as math;

import 'land.dart';

typedef V3 = (double, double, double);

/// Light and colours of the sky at a time of day.
class SkyState {
  const SkyState({
    required this.sun,
    required this.moon,
    required this.zenith,
    required this.horizon,
    required this.sunColor,
    required this.ambient,
    required this.night,
  });

  /// Unit vectors towards the sun and moon (y up).
  final V3 sun, moon;
  final int zenith, horizon, sunColor, ambient;

  /// 0 day .. 1 full night.
  final double night;

  double get sunHeight => sun.$2;
}

int mixColor(int a, int b, double t) {
  final k = t.clamp(0.0, 1.0);
  int ch(int s) => (((a >> s) & 255) * (1 - k) + ((b >> s) & 255) * k).round();
  return 0xFF000000 | (ch(16) << 16) | (ch(8) << 8) | ch(0);
}

int scaleColor(int c, double k) {
  int ch(int s) => (((c >> s) & 255) * k).round().clamp(0, 255);
  return 0xFF000000 | (ch(16) << 16) | (ch(8) << 8) | ch(0);
}

V3 _dir(double elevation, double azimuth) => (
  math.cos(elevation) * math.sin(azimuth),
  math.sin(elevation),
  -math.cos(elevation) * math.cos(azimuth),
);

/// The sky for [s] (time of day, sun direction; the moon has its own sky).
SkyState skyFor(LandSettings s) {
  final t = s.time;
  // Sun: rises at 6, highest (60°) at 12, sets at 18; below at night.
  final elev = math.sin((t - 6) / 12 * math.pi) * (60 * math.pi / 180);
  final az = s.sunTurn * 2 * math.pi + (t - 12) / 12 * math.pi;
  final sun = _dir(elev, az);
  final moon = _dir(math.max(0.25, -elev * 0.8 + 0.3), az + math.pi * 0.8);
  final e = sun.$2; // -1..1
  final day = ((e + 0.05) / 0.3).clamp(0.0, 1.0);
  final dusk = (1 - ((e - 0.12).abs() / 0.16)).clamp(0.0, 1.0);
  final night = 1 - ((e + 0.18) / 0.2).clamp(0.0, 1.0);
  if (s.preset == 'moon') {
    // No air: black sky, harsh light, the Earth instead of a moon.
    return SkyState(
      sun: sun,
      moon: moon,
      zenith: 0xFF02030A,
      horizon: 0xFF0A0C14,
      sunColor: e > 0 ? 0xFFFFFFFF : 0xFF2A2E3A,
      ambient: 0xFF22242C,
      night: 1,
    );
  }
  var zenith = mixColor(0xFF0A1030, 0xFF3A78D0, day);
  var horizon = mixColor(0xFF1A2448, 0xFFB8D4F0, day);
  horizon = mixColor(horizon, 0xFFF0904A, dusk * 0.85);
  zenith = mixColor(zenith, 0xFF3A3A7A, dusk * 0.4);
  final sunColor = mixColor(
    mixColor(0xFF223050, 0xFFFFF2DC, day),
    0xFFFFA860,
    dusk,
  );
  final ambient = mixColor(0xFF1E2438, 0xFF6A7488, day);
  return SkyState(
    sun: sun,
    moon: moon,
    zenith: zenith,
    horizon: horizon,
    sunColor: sunColor,
    ambient: ambient,
    night: night,
  );
}
