import 'dart:convert';
import 'dart:io';

import 'mood.dart';

/// A place to get weather for (from Open-Meteo's free geocoding, no key).
class Place {
  const Place(this.name, this.region, this.lat, this.lon);
  final String name, region;
  final double lat, lon;

  String get label => region.isEmpty ? name : '$name, $region';

  Map<String, Object?> toJson() => {
    'name': name,
    'region': region,
    'lat': lat,
    'lon': lon,
  };
  factory Place.fromJson(Map j) => Place(
    (j['name'] as String?) ?? '?',
    (j['region'] as String?) ?? '',
    (j['lat'] as num).toDouble(),
    (j['lon'] as num).toDouble(),
  );
}

class WeatherHour {
  const WeatherHour(this.time, this.code, this.temp, this.day);
  final DateTime time;
  final int code;
  final double temp;
  final bool day;

  WeatherLook get look => lookFor(code, temp, day);
}

/// Weather now and the next hours.
class Weather {
  const Weather(this.place, this.fetched, this.now, this.hours);
  final Place place;
  final DateTime fetched;
  final WeatherHour now;
  final List<WeatherHour> hours;

  /// The forecast hour covering [t] (or now).
  WeatherHour at(DateTime t) {
    WeatherHour best = now;
    for (final h in hours) {
      if (!h.time.isAfter(t)) {
        best = h;
      }
    }
    return best;
  }

  String describe() =>
      '${now.temp.round()}°C ${describeCode(now.code).toLowerCase()} · ${place.name}';

  Map<String, Object?> toJson() => {
    'place': place.toJson(),
    'fetched': fetched.toIso8601String(),
    'now': _h(now),
    'hours': [for (final h in hours) _h(h)],
  };

  static Map<String, Object?> _h(WeatherHour h) => {
    't': h.time.toIso8601String(),
    'c': h.code,
    'temp': h.temp,
    'd': h.day,
  };

  static WeatherHour _hour(Map j) => WeatherHour(
    DateTime.parse(j['t'] as String),
    (j['c'] as num).toInt(),
    (j['temp'] as num).toDouble(),
    j['d'] == true,
  );

  factory Weather.fromJson(Map j) => Weather(
    Place.fromJson(j['place'] as Map),
    DateTime.parse(j['fetched'] as String),
    _hour(j['now'] as Map),
    [for (final h in (j['hours'] as List?) ?? const []) _hour(h as Map)],
  );
}

/// WMO weather codes (what Open-Meteo reports) to what the pet shows.
WeatherLook lookFor(int code, double temp, bool day) {
  if (code >= 95) {
    return WeatherLook.storm;
  }
  if ((code >= 71 && code <= 77) || code == 85 || code == 86) {
    return WeatherLook.snow;
  }
  if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) {
    return WeatherLook.rain;
  }
  if (code == 45 || code == 48) {
    return WeatherLook.fog;
  }
  if (code == 2 || code == 3) {
    return WeatherLook.cloud;
  }
  return day && temp >= 26 ? WeatherLook.sun : WeatherLook.clear;
}

String describeCode(int code) {
  if (code >= 95) {
    return 'Thunderstorm';
  }
  if (code >= 85) {
    return 'Snow showers';
  }
  if (code >= 80) {
    return 'Rain showers';
  }
  if (code >= 71) {
    return 'Snow';
  }
  if (code >= 61) {
    return 'Rain';
  }
  if (code >= 51) {
    return 'Drizzle';
  }
  if (code >= 45) {
    return 'Fog';
  }
  if (code == 3) {
    return 'Overcast';
  }
  if (code >= 1) {
    return 'Partly cloudy';
  }
  return 'Clear';
}

List<Place> parsePlaces(String body) {
  final j = jsonDecode(body);
  final results = j is Map ? j['results'] : null;
  if (results is! List) {
    return const [];
  }
  return [
    for (final r in results)
      if (r is Map && r['latitude'] is num && r['longitude'] is num)
        Place(
          (r['name'] as String?) ?? '?',
          [
            r['admin1'],
            r['country'],
          ].whereType<String>().where((s) => s.isNotEmpty).join(', '),
          (r['latitude'] as num).toDouble(),
          (r['longitude'] as num).toDouble(),
        ),
  ];
}

/// Parses an Open-Meteo forecast (times are local to the place).
Weather parseWeather(Place place, String body, DateTime fetched) {
  final j = jsonDecode(body) as Map;
  final cur = j['current'] as Map;
  final now = WeatherHour(
    DateTime.parse(cur['time'] as String),
    (cur['weather_code'] as num).toInt(),
    (cur['temperature_2m'] as num).toDouble(),
    cur['is_day'] == 1,
  );
  final h = j['hourly'] as Map? ?? const {};
  final times = (h['time'] as List?) ?? const [];
  final codes = (h['weather_code'] as List?) ?? const [];
  final temps = (h['temperature_2m'] as List?) ?? const [];
  final days = (h['is_day'] as List?) ?? const [];
  return Weather(place, fetched, now, [
    for (var i = 0; i < times.length && i < codes.length; i++)
      if (codes[i] is num)
        WeatherHour(
          DateTime.parse(times[i] as String),
          (codes[i] as num).toInt(),
          i < temps.length && temps[i] is num
              ? (temps[i] as num).toDouble()
              : now.temp,
          i < days.length ? days[i] == 1 : now.day,
        ),
  ]);
}

Future<String> _get(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.getUrl(uri);
    final res = await req.close().timeout(const Duration(seconds: 15));
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      throw HttpException('Weather service said ${res.statusCode}');
    }
    return body;
  } finally {
    client.close();
  }
}

Future<List<Place>> searchPlaces(String query) async {
  if (query.trim().length < 2) {
    return const [];
  }
  return parsePlaces(
    await _get(
      Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
        'name': query.trim(),
        'count': '8',
        'format': 'json',
      }),
    ),
  );
}

Future<Weather> fetchWeather(Place place) async {
  final body = await _get(
    Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '${place.lat}',
      'longitude': '${place.lon}',
      'current': 'temperature_2m,weather_code,is_day',
      'hourly': 'temperature_2m,weather_code,is_day',
      'forecast_hours': '26',
      'timezone': 'auto',
    }),
  );
  return parseWeather(place, body, DateTime.now());
}
