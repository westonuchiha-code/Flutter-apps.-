import 'dart:async';

import 'package:flutter/foundation.dart';

import 'storage.dart';

/// Declares one setting. The settings screen is built from these.
sealed class Setting<T> {
  const Setting({
    required this.key,
    required this.title,
    required this.defaultValue,
    this.subtitle,
    this.section = 'General',
  });

  /// Saved under this key; never rename.
  final String key;
  final String title;
  final String? subtitle;
  final String section;
  final T defaultValue;

  /// Converts a saved JSON value (or null) to T, falling back to the default.
  T decode(Object? json);
  Object? encode(T value) => value;
}

class BoolSetting extends Setting<bool> {
  const BoolSetting({
    required super.key,
    required super.title,
    super.defaultValue = false,
    super.subtitle,
    super.section,
  });

  @override
  bool decode(Object? json) => json is bool ? json : defaultValue;
}

class ChoiceSetting extends Setting<String> {
  const ChoiceSetting({
    required super.key,
    required super.title,
    required super.defaultValue,
    required this.choices,
    super.subtitle,
    super.section,
  });

  /// Value → label.
  final Map<String, String> choices;

  @override
  String decode(Object? json) =>
      json is String && choices.containsKey(json) ? json : defaultValue;
}

class SliderSetting extends Setting<double> {
  const SliderSetting({
    required super.key,
    required super.title,
    required super.defaultValue,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.format,
    super.subtitle,
    super.section,
  });

  final double min, max;
  final int? divisions;
  final String Function(double value)? format;

  @override
  double decode(Object? json) =>
      json is num ? json.toDouble().clamp(min, max) : defaultValue;
}

class TextSetting extends Setting<String> {
  const TextSetting({
    required super.key,
    required super.title,
    super.defaultValue = '',
    super.subtitle,
    super.section,
  });

  @override
  String decode(Object? json) => json is String ? json : defaultValue;
}

/// Built-in settings every app gets.
const themeModeSetting = ChoiceSetting(
  key: 'shell.themeMode',
  title: 'Theme',
  defaultValue: 'system',
  choices: {'system': 'System', 'light': 'Light', 'dark': 'Dark'},
  section: 'Appearance',
);

const hapticsSetting = BoolSetting(
  key: 'shell.haptics',
  title: 'Vibration feedback',
  defaultValue: true,
  section: 'Appearance',
);

/// Holds and saves setting values. Listen to it to rebuild on changes.
class SettingsStore extends ChangeNotifier {
  SettingsStore(this.storage, this.settings, {this.fileName = 'settings.json'});

  final AppStorage storage;
  final List<Setting<Object?>> settings;
  final String fileName;
  final Map<String, Object?> _values = {};
  Timer? _saveTimer;

  Future<void> load() async {
    final json = await storage.readJson(fileName);
    if (json is Map) {
      _values.addAll(json.cast<String, Object?>());
    }
    notifyListeners();
  }

  T get<T>(Setting<T> s) => s.decode(_values[s.key]);

  void set<T>(Setting<T> s, T value) {
    _values[s.key] = s.encode(value);
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), save);
  }

  void reset(Setting<Object?> s) {
    _values.remove(s.key);
    notifyListeners();
    unawaited(save());
  }

  Future<void> save() async {
    _saveTimer?.cancel();
    await storage.writeJson(fileName, _values);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
