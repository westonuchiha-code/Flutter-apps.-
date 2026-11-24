import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sprite_pet/src/art/render.dart';
import 'package:sprite_pet/src/art/species.dart';
import 'package:sprite_pet/src/mood.dart';
import 'package:sprite_pet/src/pet.dart';
import 'package:sprite_pet/src/weather.dart';

/// A Wednesday.
DateTime at(int h, [int m = 0, int day = 25]) => DateTime(2026, 11, day, h, m);

void main() {
  test('needs drift with time, faster awake than asleep', () {
    final p = PetState(food: 1, energy: 1, fun: 1, updated: at(9));
    p.advance(at(15));
    expect(p.food, closeTo(1 - 0.11 * 6, 0.01));
    expect(p.energy, closeTo(1 - 0.06 * 6, 0.01));
    expect(p.fun, lessThan(0.6));
    final q = PetState(food: 1, energy: 0.2, updated: at(23));
    q.advance(at(6, 0, 26));
    expect(q.energy, greaterThan(0.9)); // a night's sleep
    expect(q.food, greaterThan(0.75)); // eats little asleep
  });

  test('sleeps at night, an hour longer at weekends', () {
    final p = PetState();
    expect(p.asleepAt(at(23)), isTrue);
    expect(p.asleepAt(at(7, 0)), isTrue);
    expect(p.asleepAt(at(8, 0)), isFalse);
    expect(p.asleepAt(at(8, 0, 28)), isTrue); // Saturday
    expect(p.moodAt(at(22, 0)), Mood.sleepy); // near bedtime
  });

  test('moods follow needs and what you do', () {
    final p = PetState(food: 0.6, energy: 0.8, fun: 0.6, updated: at(12));
    expect(p.moodAt(at(12)), Mood.idle);
    p.feed(at(12));
    expect(p.moodAt(at(12, 5)), Mood.eating);
    expect(p.moodAt(at(12, 20)), Mood.idle);
    p.pet(at(12, 20));
    expect(p.moodAt(at(12, 25)), Mood.happy);
    p.food = 0.1;
    expect(p.moodAt(at(13)), Mood.hungry);
    p
      ..food = 0.8
      ..fun = 0.1;
    expect(p.moodAt(at(14)), Mood.bored);
    expect(p.moodAt(at(14), storm: true), Mood.scared);
    p.play(at(14));
    expect(p.fun, closeTo(0.3, 0.01)); // 0 after the wait, +0.3
    expect(p.log.first, contains('played'));
  });

  test('bed and wake override the clock; exhaustion means a nap', () {
    final p = PetState(updated: at(15));
    p.toBed(at(15));
    expect(p.asleepAt(at(16)), isTrue);
    p.wakeUp(at(16));
    expect(p.asleepAt(at(16, 30)), isFalse);
    final n = PetState(energy: 0.1, updated: at(10));
    n.advance(at(11));
    expect(n.napping, isTrue);
    expect(n.moodAt(at(11)), Mood.asleep);
    n.advance(at(15));
    expect(n.napping, isFalse);
  });

  test('new Asset Locker items are treats, a few a day', () {
    final p = PetState(food: 0.5, fun: 0.4, updated: at(10));
    expect(
      p.treats(at(10), {'a': ('Sprite', 'Old')}),
      0,
    ); // first look: just seen
    final items = {
      'a': ('Sprite', 'Old'),
      for (var i = 0; i < 9; i++) 'n$i': ('Video', 'New $i'),
    };
    expect(p.treats(at(11), items), maxTreatsPerDay);
    expect(p.treats(at(12), items), 0);
    expect(p.fun, greaterThan(0.9));
    expect(p.log.first, contains('video'));
  });

  test('forecast for the widget and saving', () {
    final p = PetState(updated: at(20));
    final f = p.forecast(at(20), stormAt: (t) => t.hour == 21);
    expect(f.length, 97);
    expect(f.firstWhere((e) => e.$1.hour == 21).$2, Mood.scared);
    expect(f.firstWhere((e) => e.$1.hour == 23).$2, Mood.asleep);
    expect(p.updated, at(20)); // the pet itself is untouched
    final q = PetState.fromJson(jsonDecode(jsonEncode(p.toJson())) as Map);
    expect(q.name, p.name);
    expect(q.bedMinutes, p.bedMinutes);
  });

  test('weather parsing and looks', () {
    final places = parsePlaces(
      '{"results":[{"name":"Leeds","latitude":53.8,"longitude":-1.55,"admin1":"England","country":"United Kingdom"}]}',
    );
    expect(places.single.label, 'Leeds, England, United Kingdom');
    final w = parseWeather(
      places.single,
      '{"current":{"time":"2026-11-25T10:00","temperature_2m":6.4,"weather_code":61,"is_day":1},'
      '"hourly":{"time":["2026-11-25T10:00","2026-11-25T11:00"],"temperature_2m":[6.4,7],'
      '"weather_code":[61,95],"is_day":[1,1]}}',
      at(10),
    );
    expect(w.now.look, WeatherLook.rain);
    expect(w.at(at(11, 30)).look, WeatherLook.storm);
    expect(w.describe(), '6°C rain · Leeds');
    expect(
      Weather.fromJson(jsonDecode(jsonEncode(w.toJson())) as Map).hours.length,
      2,
    );
    expect(lookFor(0, 30, true), WeatherLook.sun);
    expect(lookFor(0, 30, false), WeatherLook.clear);
    expect(lookFor(73, 0, true), WeatherLook.snow);
  });

  test('every pet draws every mood and weather inside its frame', () {
    for (final s in builtInSpecies) {
      for (final m in Mood.values) {
        for (final w in WeatherLook.values) {
          for (var f = 0; f < framesPerMood; f++) {
            final px = renderPet(s, m, f, weather: w);
            expect(px.length, 32 * 32);
            expect(
              px.where((c) => c >>> 24 == 255).length,
              greaterThan(100),
              reason: '${s.id} ${m.name}',
            );
          }
        }
      }
    }
  });
}
