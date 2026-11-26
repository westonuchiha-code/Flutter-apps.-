/// Where this app keeps things on each platform, and the controller's
/// config built from them. Android's storage root and all-files access
/// come from MainActivity's channel ([androidChannel]).
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:save_kit/save_kit.dart';

import 'controller.dart';
import 'folders.dart';

/// MainActivity's channel: `hasAllFiles`, `requestAllFiles`, `storageRoot`.
/// The Save Manager app's own; a host app with its own channel offering
/// the same three methods sets it before use (the XMB: `xmb/android`).
MethodChannel androidChannel = const MethodChannel('save_manager/android');

/// The app's own files, kept in Documents so they outlive an uninstall.
class AppFiles {
  /// Everything under [dataDir] (Documents/Save Manager).
  AppFiles(this.dataDir);

  /// The folder's name in Documents.
  static const folderName = 'Save Manager';

  /// Documents/Save Manager.
  final String dataDir;

  /// Backups of every change.
  String get backups => p.join(dataDir, 'Backups');

  /// The starred saves.
  String get favorites => p.join(dataDir, 'favorites.json');

  /// Names given to cards here.
  String get names => p.join(dataDir, 'names.json');

  /// Card colours, stickers and order.
  String get looks => p.join(dataDir, 'looks.json');

  /// Your own sticker pictures.
  String get stickers => p.join(dataDir, 'Stickers');
}

/// The folders the user typed in settings: one per line, or split by `;`.
List<String> splitFolders(String text) => [
  for (final part in text.split(RegExp(r'[;\r\n]+')))
    if (part.trim().isNotEmpty) part.trim(),
];

/// 'windows', 'linux' or 'android' (Linux for anything else).
String platformName() {
  if (Platform.isWindows) return 'windows';
  if (Platform.isAndroid) return 'android';
  return 'linux';
}

/// This device's [Places].
Future<Places> resolvePlaces() async {
  final env = Platform.environment;
  if (Platform.isAndroid) {
    var storage = '';
    try {
      storage = await androidChannel.invokeMethod<String>('storageRoot') ?? '';
    } catch (_) {}
    if (storage.isEmpty) {
      storage = p.join(p.separator, 'storage', 'emulated', '0');
    }
    return Places(
      home: storage,
      documents: p.join(storage, 'Documents'),
      storage: storage,
    );
  }
  final home = (Platform.isWindows ? env['USERPROFILE'] : env['HOME']) ?? '';
  var documents = '';
  try {
    documents = (await getApplicationDocumentsDirectory()).path;
  } catch (_) {}
  if (documents.isEmpty) documents = p.join(home, 'Documents');
  return Places(
    home: home,
    documents: documents,
    appData: Platform.isWindows ? env['APPDATA'] ?? '' : '',
  );
}

/// The installed app's config: the emulators' card folders plus [extra],
/// its own files in Documents/Save Manager. [check] = Android's
/// emulators-closed question.
SaveManagerConfig appConfigFor(
  Places at, {
  List<String> extra = const [],
  EmulatorCheck? check,
  String platform = '',
  List<LibraryGame> games = const [],
  Map<String, PlayStats> played = const {},
}) {
  final files = AppFiles(p.join(at.documents, AppFiles.folderName));
  final exports = CardFolders.exports(at);
  final downloads = CardFolders.downloads(at);
  final on = platform.isNotEmpty ? platform : platformName();
  return SaveManagerConfig(
    cardDirs: CardFolders.toRead(on, at, extra),
    backupRoot: files.backups,
    exportDir: exports,
    namesFile: files.names,
    looksFile: files.looks,
    favoritesFile: files.favorites,
    isApp: true,
    looseDir: downloads,
    importFolders: [exports, downloads],
    stickerFolder: files.stickers,
    // Windows / Linux: null asks the system (save_kit's process check)
    running: check?.running,
    games: games,
    played: played,
  );
}

/// Android's all-files access (true elsewhere).
Future<bool> hasAllFiles() async {
  if (!Platform.isAndroid) return true;
  try {
    return await androidChannel.invokeMethod<bool>('hasAllFiles') ?? false;
  } catch (e) {
    debugPrint('hasAllFiles: $e');
    return false;
  }
}

/// Opens Android's "All files access" page for this app.
Future<void> requestAllFiles() async {
  if (!Platform.isAndroid) return;
  try {
    await androidChannel.invokeMethod<void>('requestAllFiles');
  } catch (e) {
    debugPrint('requestAllFiles: $e');
  }
}
