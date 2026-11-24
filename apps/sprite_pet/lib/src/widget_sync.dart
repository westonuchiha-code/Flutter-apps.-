import 'dart:convert';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';

import 'art/render.dart';
import 'frames.dart';
import 'mood.dart';
import 'store.dart';
import 'weather.dart';

const widgetProvider = 'com.westonuchiha.sprite_pet.PetWidgetProvider';

/// Weather is fetched again after this long.
const weatherMaxAge = Duration(minutes: 50);

WeatherLook lookAt(PetData d, DateTime t) {
  final w = d.weather;
  if (w == null || t.difference(w.fetched).inHours > 30) {
    return WeatherLook.none;
  }
  return w.at(t).look;
}

/// One entry of what the widget shows, from a time on.
class WidgetSlot {
  const WidgetSlot(this.from, this.mood, this.look, this.text);
  final DateTime from;
  final Mood mood;
  final WeatherLook look;
  final String text;
  String get key => '${mood.name}_${look.name}';
}

/// The next 24 hours of moods (with weather), merged where nothing changes.
List<WidgetSlot> widgetPlan(PetData d, DateTime now) {
  final out = <WidgetSlot>[];
  for (final (t, mood) in d.pet.forecast(
    now,
    stormAt: (t) => lookAt(d, t) == WeatherLook.storm,
  )) {
    final look = lookAt(d, t);
    final w = d.weather;
    final temp = w == null || look == WeatherLook.none
        ? ''
        : ' · ${w.at(t).temp.round()}°';
    final slot = WidgetSlot(
      t,
      mood,
      look,
      '${d.pet.name} · ${mood.label}$temp',
    );
    if (out.isEmpty || out.last.key != slot.key || out.last.text != slot.text) {
      out.add(slot);
    }
  }
  return out;
}

/// Updates the Android home-screen widget: frames for every mood coming up,
/// a schedule of when to show which, and refreshes every half hour.
Future<void> syncWidget(PetData d, Directory dir) async {
  if (!Platform.isAndroid) {
    return;
  }
  final now = DateTime.now();
  final plan = widgetPlan(d, now);
  final species = d.species;
  final framesDir = Directory('${dir.path}${Platform.pathSeparator}frames');
  await framesDir.create(recursive: true);
  final keep = <String>{};
  final stamp = now.millisecondsSinceEpoch;
  for (final key in {for (final s in plan) s.key}) {
    final s = plan.firstWhere((s) => s.key == key);
    final paths = <String>[];
    for (var f = 0; f < framesPerMood; f++) {
      final path =
          '${framesDir.path}${Platform.pathSeparator}${key}_${stamp}_$f.png';
      await File(
        path,
      ).writeAsBytes(framePng(renderPet(species, s.mood, f, weather: s.look)));
      paths.add(path);
      keep.add(path);
    }
    await HomeWidget.saveWidgetData<String>(
      'pet_frames_$key',
      jsonEncode(paths),
    );
  }
  await HomeWidget.saveWidgetData<String>(
    'pet_schedule',
    jsonEncode([
      for (final s in plan) [s.from.millisecondsSinceEpoch, s.key, s.text],
    ]),
  );
  await HomeWidget.updateWidget(qualifiedAndroidName: widgetProvider);
  await HomeWidget.scheduleWidgetUpdates([
    for (var i = 1; i <= 48; i++) now.add(Duration(minutes: 30 * i)),
  ], qualifiedAndroidName: widgetProvider);
  // Old frames (the widget has the new ones now).
  await for (final f in framesDir.list()) {
    if (f is File && !keep.contains(f.path)) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }
}

/// Reads the battery (best effort).
Future<void> readBattery(PetData d) async {
  try {
    final b = Battery();
    d.pet.battery = await b.batteryLevel;
    final s = await b.batteryState;
    d.pet.charging = s == BatteryState.charging || s == BatteryState.full;
  } catch (_) {}
}

/// Gets fresh weather if the last is old (best effort).
Future<bool> refreshWeather(PetData d, {bool force = false}) async {
  final place = d.place;
  if (place == null) {
    return false;
  }
  final w = d.weather;
  if (!force &&
      w != null &&
      w.place.label == place.label &&
      DateTime.now().difference(w.fetched) < weatherMaxAge) {
    return false;
  }
  try {
    d.weather = await fetchWeather(place);
    return true;
  } catch (_) {
    return false;
  }
}

/// Runs (in the background) when a widget button is tapped.
@pragma('vm:entry-point')
Future<void> widgetAction(Uri? uri) async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await PetStore.open();
  final d = await store.load();
  final now = DateTime.now();
  await readBattery(d);
  switch (uri?.host) {
    case 'feed':
      d.pet.feed(now);
    case 'pet':
      d.pet.pet(now);
    case 'play':
      d.pet.play(now);
    default:
      d.pet.advance(now);
  }
  await refreshWeather(d);
  await store.save(d);
  await syncWidget(d, store.dir);
}
