import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/settings.dart';

/// Saves settings between launches.
abstract class SettingsStore {
  Future<ThereminSettings?> load();
  Future<void> save(ThereminSettings settings);
}

class FileSettingsStore implements SettingsStore {
  FileSettingsStore(this.directory);

  final Directory directory;

  File get _file => File(p.join(directory.path, 'settings.json'));

  @override
  Future<ThereminSettings?> load() async {
    try {
      if (!await _file.exists()) return null;
      final json = jsonDecode(await _file.readAsString());
      return ThereminSettings.fromJson((json as Map).cast<String, Object?>());
    } catch (_) {
      return null; // Corrupt or old file: start from defaults.
    }
  }

  @override
  Future<void> save(ThereminSettings settings) async {
    await directory.create(recursive: true);
    final temp = File('${_file.path}.tmp');
    await temp.writeAsString(jsonEncode(settings.toJson()));
    await temp.rename(_file.path);
  }
}

class MemorySettingsStore implements SettingsStore {
  ThereminSettings? saved;

  @override
  Future<ThereminSettings?> load() async => saved;

  @override
  Future<void> save(ThereminSettings settings) async => saved = settings;
}
