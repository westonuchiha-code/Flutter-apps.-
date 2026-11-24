import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'art/canvas.dart' show petSize;
import 'art/render.dart';
import 'art/species.dart';
import 'mood.dart';
import 'store.dart';
import 'weather.dart';
import 'widget_sync.dart';

/// The pet on screen: its state, what it looks like now, and keeping the
/// home-screen widget in step.
class PetController extends ChangeNotifier {
  PetController({required this.store, this.lockerItems, this.online = true});

  final PetStore store;

  /// Asset Locker items (id → type, name), or null when not connected.
  final Future<Map<String, (String, String)>?> Function()? lockerItems;

  /// Fetch weather, use the battery and the widget (off in tests).
  final bool online;

  PetData data = PetData();
  bool loaded = false;
  Mood mood = Mood.idle;
  WeatherLook look = WeatherLook.none;
  List<ui.Image> frames = const [];
  String? weatherError;
  Timer? _tick;
  String _framesKey = '';

  PetSpecies get species => data.species;

  Future<void> init() async {
    data = await store.load();
    loaded = true;
    if (online && Platform.isAndroid) {
      try {
        await HomeWidget.registerInteractivityCallback(widgetAction);
      } catch (_) {}
    }
    await refresh(full: true);
    _tick = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(refresh()),
    );
  }

  @override
  void dispose() {
    _tick?.cancel();
    for (final f in frames) {
      f.dispose();
    }
    super.dispose();
  }

  /// Lets time pass, picks up battery, weather and new creations, and
  /// redraws. [full]: also save and update the widget.
  Future<void> refresh({bool full = false}) async {
    final now = DateTime.now();
    // Changes made by the widget while the app was open.
    final disk = await store.load();
    if (disk.pet.updated.isAfter(data.pet.updated)) {
      data = disk;
    }
    if (online) {
      await readBattery(data);
      if (await refreshWeather(data)) {
        full = true;
      }
    }
    final items = await lockerItems?.call();
    if (items != null && data.pet.treats(now, items) > 0) {
      full = true;
    }
    data.pet.advance(now);
    await _show(now);
    if (full) {
      await _save();
    }
  }

  Future<void> _save() async {
    await store.save(data);
    if (online) {
      try {
        await syncWidget(data, store.dir);
      } catch (_) {
        // No widget placed, or not Android.
      }
    }
  }

  Future<void> _show(DateTime now) async {
    look = lookAt(data, now);
    mood = data.pet.moodAt(now, storm: look == WeatherLook.storm);
    final key = '${species.id}:${data.custom?.name}:${mood.name}:${look.name}';
    if (key != _framesKey) {
      final next = [
        for (var f = 0; f < framesPerMood; f++)
          await petImage(renderPet(species, mood, f, weather: look)),
      ];
      for (final f in frames) {
        f.dispose();
      }
      frames = next;
      _framesKey = key;
    }
    notifyListeners();
  }

  Future<void> _act(void Function(DateTime now) action) async {
    final now = DateTime.now();
    action(now);
    await _show(now);
    await _save();
  }

  Future<void> feed() => _act(data.pet.feed);
  Future<void> pet() => _act(data.pet.pet);
  Future<void> play() => _act(data.pet.play);
  Future<void> toBed() => _act(data.pet.toBed);
  Future<void> wakeUp() => _act(data.pet.wakeUp);

  Future<void> setSpecies(String id, {CustomSprite? custom}) => _act((_) {
    data.pet.species = id;
    if (custom != null) {
      data.custom = custom;
    }
    _framesKey = '';
  });

  Future<void> rename(String name) => _act((_) => data.pet.name = name);

  Future<void> setTimes({int? bed, int? wake}) => _act((_) {
    if (bed != null) {
      data.pet.bedMinutes = bed;
    }
    if (wake != null) {
      data.pet.wakeMinutes = wake;
    }
  });

  Future<void> setPlace(Place? place) async {
    data.place = place;
    data.weather = null;
    weatherError = null;
    if (place != null && online) {
      if (!await refreshWeather(data, force: true)) {
        weatherError = 'Could not get the weather right now.';
      }
    }
    await _act((_) {});
  }
}

/// A 32×32 ARGB frame as an image for the screen.
Future<ui.Image> petImage(Uint32List px) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    px.buffer.asUint8List(),
    petSize,
    petSize,
    ui.PixelFormat.bgra8888,
    c.complete,
  );
  return c.future;
}
