import 'dart:io';

import 'library_scanner.dart';
import 'season.dart';

/// Walking the computer's folders from the on-screen menu, so the TV folder
/// can be chosen with a controller and no desktop file dialog.
///
/// '' stands for the top: the list of drives on Windows, or of storage
/// [roots] (internal storage, SD cards) on Android.

/// The folder above [path], '' for the list of drives or storage roots, or
/// null at the top.
String? parentFolder(
  String path, {
  required bool windows,
  List<String> roots = const [],
}) {
  if (path.isEmpty) return null;
  final separator = windows ? r'\' : '/';
  var trimmed = path;
  while (trimmed.length > 1 && trimmed.endsWith(separator)) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  // Android: above internal storage or an SD card is the list of them
  // (the folders above those can't be read).
  if (roots.contains(trimmed)) return '';
  if (windows) {
    // "E:" is a drive: above it is the list of drives.
    if (RegExp(r'^[A-Za-z]:$').hasMatch(trimmed)) return '';
    final cut = trimmed.lastIndexOf(separator);
    if (cut < 0) return '';
    final parent = trimmed.substring(0, cut);
    return RegExp(r'^[A-Za-z]:$').hasMatch(parent) ? '$parent\\' : parent;
  }
  if (trimmed == '/') return null;
  final cut = trimmed.lastIndexOf('/');
  return cut <= 0 ? '/' : trimmed.substring(0, cut);
}

/// [name] inside [folder].
String childFolder(String folder, String name, {required bool windows}) {
  final separator = windows ? r'\' : '/';
  return folder.endsWith(separator) ? '$folder$name' : '$folder$separator$name';
}

/// Whether a folder with this name would become a channel.
bool isChannelFolderName(String name) =>
    parseChannelFolder(splitSeasonTag(name).$1) != null;

/// The folders inside [path], in name order, without hidden ones. For '',
/// the storage [roots] if given (Android), else the drives (Windows).
/// Null if the folder can't be read.
List<String>? listFolders(String path, {List<String> roots = const []}) {
  if (path.isEmpty && roots.isNotEmpty) return roots;
  if (path.isEmpty) {
    return [
      for (var letter = 0x41; letter <= 0x5A; letter++)
        if (Directory('${String.fromCharCode(letter)}:\\').existsSync())
          '${String.fromCharCode(letter)}:\\',
    ];
  }
  try {
    final names = <String>[];
    for (final entry in Directory(path).listSync(followLinks: true)) {
      if (entry is! Directory) continue;
      final name = baseName(entry.path);
      if (name.startsWith('.') || name.startsWith(r'$')) continue;
      names.add(name);
    }
    names.sort(naturalCompare);
    return names;
  } on FileSystemException {
    return null;
  }
}

/// Where browsing starts: the TV folder already in use, else wherever
/// videos usually live on this kind of system. On Android ([roots] given)
/// the TV's own folder ([defaultFolder]), else internal storage.
String browseStart(
  String? current, {
  List<String> roots = const [],
  String? defaultFolder,
}) {
  if (current != null && Directory(current).existsSync()) return current;
  if (roots.isNotEmpty) {
    if (defaultFolder != null && Directory(defaultFolder).existsSync()) {
      return defaultFolder;
    }
    return Directory(roots.first).existsSync() ? roots.first : '';
  }
  if (Platform.isWindows) return '';
  final candidates = [
    '/media',
    '/run/media',
    '/userdata',
    Platform.environment['HOME'] ?? '',
  ];
  for (final candidate in candidates) {
    if (candidate.isNotEmpty && Directory(candidate).existsSync()) {
      return candidate;
    }
  }
  return '/';
}
