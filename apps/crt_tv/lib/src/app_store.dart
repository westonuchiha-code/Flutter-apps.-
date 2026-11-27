import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'channel_engine.dart';
import 'loudness.dart';
import 'models.dart';

/// Saves settings, channel progress and known video lengths to one JSON
/// file in the app's private data folder.
class AppStore {
  AppStore._(this._file, this.dataDir);

  /// A store on a file of the caller's choosing, for tests.
  AppStore.at(File file) : this._(file, file.parent);

  final File _file;

  /// The app's private data folder (also used for the static sound file).
  final Directory dataDir;

  final AppSettings settings = AppSettings();

  /// Progress per channel, keyed by the channel's folder name.
  final Map<String, ChannelState> channelStates = {};

  /// Video lengths in milliseconds, keyed by file path.
  final Map<String, int> durations = {};

  /// How loud each video measured, keyed by file path.
  final Map<String, Loudness> loudness = {};

  Timer? _saveTimer;
  bool _saving = false;
  bool _saveAgain = false;

  static Future<AppStore> open() async {
    final dir = await getApplicationSupportDirectory();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final store = AppStore._(File('${dir.path}${Platform.pathSeparator}tv_data.json'), dir);
    await store._load();
    return store;
  }

  ChannelState stateFor(String folderName) =>
      channelStates.putIfAbsent(folderName, () => ChannelState());

  Future<void> _load() async {
    try {
      if (!_file.existsSync()) return;
      final json = jsonDecode(await _file.readAsString());
      if (json is! Map) return;
      settings.loadJson(json['settings']);
      final states = json['channels'];
      if (states is Map) {
        for (final e in states.entries) {
          channelStates[e.key.toString()] = ChannelState.fromJson(e.value);
        }
      }
      final lengths = json['durations'];
      if (lengths is Map) {
        for (final e in lengths.entries) {
          final v = e.value;
          if (v is num && v > 0) durations[e.key.toString()] = v.toInt();
        }
      }
      final levels = json['loudness'];
      if (levels is Map) {
        for (final e in levels.entries) {
          final measured = Loudness.fromJson(e.value);
          if (measured != null) loudness[e.key.toString()] = measured;
        }
      }
    } catch (_) {
      // A damaged file shouldn't stop the TV from turning on. Start fresh.
    }
  }

  /// Saves a couple of seconds from now, batching quick changes together.
  /// A save that's already on its way is left alone: pushing it back on
  /// every change meant a steady stream of changes (checking the lengths of
  /// thousands of videos) kept it from ever happening.
  void scheduleSave() {
    _saveTimer ??= Timer(saveDelay, () => saveNow());
  }

  static const saveDelay = Duration(seconds: 2);

  Future<void> saveNow() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (_saving) {
      _saveAgain = true;
      return;
    }
    _saving = true;
    try {
      final json = jsonEncode({
        'version': 1,
        'settings': settings.toJson(),
        'channels': {for (final e in channelStates.entries) e.key: e.value.toJson()},
        'durations': durations,
        'loudness': {for (final e in loudness.entries) e.key: e.value.toJson()},
      });
      // Write to a temp file first so a crash mid-save can't corrupt the data.
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(_file.path);
    } catch (_) {
      // Ignore; the next save will try again.
    } finally {
      _saving = false;
      if (_saveAgain) {
        _saveAgain = false;
        unawaited(saveNow());
      }
    }
  }
}
