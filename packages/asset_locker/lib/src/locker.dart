import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'fs.dart';

/// Kinds of things apps save. The folder names show up in file managers.
enum AssetType {
  sample('Samples', 'Sample'),
  recording('Recordings', 'Recording'),
  preset('Presets', 'Preset'),
  sprite('Sprites', 'Sprite'),
  palette('Palettes', 'Palette'),
  map('Maps', 'Map'),
  picture('Pictures', 'Picture'),
  video('Videos', 'Video'),
  other('Other', 'Other');

  const AssetType(this.folder, this.label);
  final String folder;
  final String label;

  static AssetType byName(String? name) =>
      values.firstWhere((t) => t.name == name, orElse: () => other);
}

/// Description of one saved asset (stored next to it as `<id>.json`).
@immutable
class AssetInfo {
  const AssetInfo({
    required this.id,
    required this.type,
    required this.name,
    required this.extension,
    required this.app,
    required this.created,
    this.tags = const [],
    this.size = 0,
    this.hasThumbnail = false,
    this.extra = const {},
  });

  final String id;
  final AssetType type;
  final String name;

  /// File extension without the dot (wav, png, json…).
  final String extension;

  /// Id of the app that made it.
  final String app;
  final DateTime created;
  final List<String> tags;
  final int size;
  final bool hasThumbnail;

  /// App-specific details (e.g. markers of a recording). JSON values only.
  final Map<String, Object?> extra;

  String get dataPath => '${type.folder}/$id.$extension';

  /// Details file. (Version 0.1 used `<id>.json`, which collided with the
  /// data of JSON assets; those old files are still read, see
  /// [legacyMetaPath].)
  String get metaPath => '${type.folder}/$id.info.json';

  /// Where version 0.1 kept the details (only valid when the data itself is
  /// not JSON).
  String? get legacyMetaPath =>
      extension == 'json' ? null : '${type.folder}/$id.json';
  String get thumbPath => '${type.folder}/$id.thumb.png';

  AssetInfo copyWith({
    String? name,
    List<String>? tags,
    int? size,
    bool? hasThumbnail,
    Map<String, Object?>? extra,
  }) => AssetInfo(
    id: id,
    type: type,
    name: name ?? this.name,
    extension: extension,
    app: app,
    created: created,
    tags: tags ?? this.tags,
    size: size ?? this.size,
    hasThumbnail: hasThumbnail ?? this.hasThumbnail,
    extra: extra ?? this.extra,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'name': name,
    'extension': extension,
    'app': app,
    'created': created.toUtc().toIso8601String(),
    'tags': tags,
    'size': size,
    'hasThumbnail': hasThumbnail,
    if (extra.isNotEmpty) 'extra': extra,
  };

  static AssetInfo? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final ext = json['extension'];
    if (id is! String || ext is! String) return null;
    return AssetInfo(
      id: id,
      type: AssetType.byName(json['type'] as String?),
      name: (json['name'] as String?) ?? id,
      extension: ext,
      app: (json['app'] as String?) ?? '',
      created:
          DateTime.tryParse((json['created'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      tags: [
        for (final t in (json['tags'] as List?) ?? const [])
          if (t is String) t,
      ],
      size: (json['size'] as num?)?.toInt() ?? 0,
      hasThumbnail: json['hasThumbnail'] == true,
      extra: json['extra'] is Map
          ? (json['extra'] as Map).cast<String, Object?>()
          : const {},
    );
  }
}

/// A shared to-do item (Dev Dashboard).
@immutable
class TodoItem {
  const TodoItem({
    required this.id,
    required this.text,
    required this.created,
    this.done = false,
    this.tag = '',
  });

  final String id;
  final String text;
  final bool done;

  /// App id or '' for general.
  final String tag;
  final DateTime created;

  TodoItem copyWith({String? text, bool? done, String? tag}) => TodoItem(
    id: id,
    text: text ?? this.text,
    done: done ?? this.done,
    tag: tag ?? this.tag,
    created: created,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'text': text,
    'done': done,
    'tag': tag,
    'created': created.toUtc().toIso8601String(),
  };

  static TodoItem? fromJson(Object? json) {
    if (json is! Map || json['id'] is! String) return null;
    return TodoItem(
      id: json['id']! as String,
      text: (json['text'] as String?) ?? '',
      done: json['done'] == true,
      tag: (json['tag'] as String?) ?? '',
      created:
          DateTime.tryParse((json['created'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// The shared library every app saves to and loads from.
///
/// Windows/Linux: `Documents/Asset Locker`. Android: a folder the user
/// picks once per app (Android keeps apps' files apart otherwise).
class AssetLocker extends ChangeNotifier {
  AssetLocker._(this.appId, this._settingsFile, this._fs);

  static const folderName = 'Asset Locker';
  static const _devFolder = '_dev';

  final String appId;
  final File? _settingsFile;
  LockerFs? _fs;

  /// Whether the locker folder is available.
  bool get ready => _fs != null;

  /// Android needs the user to pick the folder; desktop never does.
  bool get needsConnect => !ready && _settingsFile != null;

  LockerFs get fs => _fs ?? (throw StateError('Asset Locker not connected'));

  /// Uses a plain folder (tests, or a custom location).
  factory AssetLocker.atDirectory(String appId, Directory dir) =>
      AssetLocker._(appId, null, IoLockerFs(dir));

  /// Opens the locker for [appId]. [settingsDir] holds the app's own
  /// record of the picked folder (Android).
  static Future<AssetLocker> open(
    String appId, {
    required Directory settingsDir,
  }) async {
    if (!Platform.isAndroid) {
      final docs = await getApplicationDocumentsDirectory();
      return AssetLocker.atDirectory(
        appId,
        Directory(p.join(docs.path, folderName)),
      );
    }
    final file = File(p.join(settingsDir.path, 'asset_locker.json'));
    final locker = AssetLocker._(appId, file, null);
    try {
      final json = jsonDecode(await file.readAsString());
      final uri = json is Map ? json['uri'] : null;
      if (uri is String && await SafLockerFs.hasAccess(uri)) {
        locker._fs = _safFor(uri);
      }
    } catch (_) {
      // Not connected yet.
    }
    return locker;
  }

  /// Name of the folder a tree URI points at.
  @visibleForTesting
  static String treeFolderName(String uri) {
    final i = uri.indexOf('/tree/');
    if (i < 0) return '';
    final doc = Uri.decodeComponent(uri.substring(i + 6));
    return doc.split(RegExp(r'[/:]')).last;
  }

  static SafLockerFs _safFor(String uri) => SafLockerFs(
    uri,
    // Picking Documents (or anywhere) uses an "Asset Locker" folder inside it.
    prefix: treeFolderName(uri) == folderName ? '' : folderName,
  );

  /// Android: asks the user to pick the shared folder. Returns success.
  Future<bool> connect() async {
    final settings = _settingsFile;
    if (settings == null) return ready;
    final uri = await SafLockerFs.pickFolder();
    if (uri == null) return false;
    await settings.parent.create(recursive: true);
    await settings.writeAsString(jsonEncode({'uri': uri}));
    _fs = _safFor(uri);
    notifyListeners();
    return true;
  }

  // ---- Assets ----

  Future<List<AssetInfo>> list({AssetType? type}) async {
    final types = type == null ? AssetType.values : [type];
    final out = <AssetInfo>[];
    for (final t in types) {
      final entries = await fs.list(t.folder);
      final names = {for (final e in entries) e.name};
      for (final e in entries) {
        if (e.isDir || !e.name.endsWith('.json')) continue;
        if (e.name.endsWith('.info.json')) {
          final info = await _readMeta('${t.folder}/${e.name}');
          if (info != null) out.add(info);
          continue;
        }
        // An old-style details file (`<id>.json` next to non-JSON data),
        // unless a new one exists. JSON data files never parse as details.
        final id = e.name.substring(0, e.name.length - 5);
        if (names.contains('$id.info.json')) continue;
        final info = await _readMeta('${t.folder}/${e.name}');
        if (info != null && info.extension != 'json' && info.id == id) {
          out.add(info);
        }
      }
    }
    out.sort((a, b) => b.created.compareTo(a.created));
    return out;
  }

  Future<AssetInfo?> _readMeta(String path) async {
    try {
      final bytes = await fs.read(path);
      return bytes == null
          ? null
          : AssetInfo.fromJson(jsonDecode(utf8.decode(bytes)));
    } catch (_) {
      return null;
    }
  }

  static String _slug(String name) {
    final s = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return s.isEmpty ? 'asset' : (s.length > 40 ? s.substring(0, 40) : s);
  }

  Future<AssetInfo> save({
    required AssetType type,
    required String name,
    required List<int> bytes,
    required String extension,
    List<String> tags = const [],
    Uint8List? thumbnail,
    Map<String, Object?> extra = const {},
  }) async {
    final now = DateTime.now();
    final info = AssetInfo(
      id: '${_slug(name)}-${now.microsecondsSinceEpoch.toRadixString(36)}',
      type: type,
      name: name.trim().isEmpty ? 'Untitled' : name.trim(),
      extension: extension.replaceAll('.', '').toLowerCase(),
      app: appId,
      created: now,
      tags: tags,
      size: bytes.length,
      hasThumbnail: thumbnail != null,
      extra: extra,
    );
    await fs.write(info.dataPath, bytes);
    if (thumbnail != null) await fs.write(info.thumbPath, thumbnail);
    await _writeMeta(info);
    notifyListeners();
    return info;
  }

  Future<void> _writeMeta(AssetInfo info) async {
    await fs.write(info.metaPath, utf8.encode(jsonEncode(info.toJson())));
    final legacy = info.legacyMetaPath;
    if (legacy != null) await fs.delete(legacy);
  }

  /// Saves a changed name or tags.
  Future<void> update(AssetInfo info) async {
    await _writeMeta(info);
    notifyListeners();
  }

  /// Replaces the file of an existing asset (and its thumbnail/details).
  Future<AssetInfo> replace(
    AssetInfo info,
    List<int> bytes, {
    Uint8List? thumbnail,
    Map<String, Object?>? extra,
  }) async {
    await fs.write(info.dataPath, bytes);
    if (thumbnail != null) await fs.write(info.thumbPath, thumbnail);
    final next = info.copyWith(
      size: bytes.length,
      hasThumbnail: info.hasThumbnail || thumbnail != null,
      extra: extra,
    );
    await _writeMeta(next);
    notifyListeners();
    return next;
  }

  Future<Uint8List?> read(AssetInfo info) => fs.read(info.dataPath);

  Future<Uint8List?> thumbnail(AssetInfo info) async =>
      info.hasThumbnail ? fs.read(info.thumbPath) : null;

  Future<void> delete(AssetInfo info) async {
    await fs.delete(info.dataPath);
    await fs.delete(info.thumbPath);
    await fs.delete(info.metaPath);
    final legacy = info.legacyMetaPath;
    if (legacy != null) await fs.delete(legacy);
    notifyListeners();
  }

  // ---- Dev files (errors, to-do list) ----

  Future<Object?> _readJson(String path) async {
    try {
      final b = await fs.read(path);
      return b == null ? null : jsonDecode(utf8.decode(b));
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeJson(String path, Object? json) => fs.write(
    path,
    utf8.encode(const JsonEncoder.withIndent(' ').convert(json)),
  );

  /// Publishes this app's error log so the Dev Dashboard can show it.
  Future<void> writeErrorReport(Map<String, Object?> report) =>
      _writeJson('$_devFolder/errors/$appId.json', report);

  /// Every app's published error log, keyed by app id.
  Future<Map<String, Map<String, Object?>>> readErrorReports() async {
    final out = <String, Map<String, Object?>>{};
    for (final e in await fs.list('$_devFolder/errors')) {
      if (e.isDir || !e.name.endsWith('.json')) continue;
      final json = await _readJson('$_devFolder/errors/${e.name}');
      if (json is Map) {
        out[e.name.substring(0, e.name.length - 5)] = json
            .cast<String, Object?>();
      }
    }
    return out;
  }

  Future<void> clearErrorReport(String app) async {
    if (await fs.delete('$_devFolder/errors/$app.json')) notifyListeners();
  }

  Future<List<TodoItem>> readTodos() async {
    final json = await _readJson('$_devFolder/todo.json');
    final items = json is Map ? json['items'] : null;
    return [
      for (final i in items is List ? items : const []) ?TodoItem.fromJson(i),
    ];
  }

  Future<void> writeTodos(List<TodoItem> items) =>
      _writeJson('$_devFolder/todo.json', {
        'items': [for (final i in items) i.toJson()],
      });
}
