import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Android's side of the TV folder: "All files" access (needed to read
/// any folder by its path, which the video player works with), the
/// storage roots (internal storage and SD cards), and the TV's own folder
/// inside the XMB Frontend's, `Internal storage › XMB Frontend › TV`.
///
/// Talks to `MainActivity.kt` over the `crt_tv/android` channel.
class AndroidStorage {
  const AndroidStorage();

  static const _channel = MethodChannel('crt_tv/android');

  /// Whether the app may read every folder ("All files access").
  Future<bool> hasAllFiles() async {
    try {
      return await _channel.invokeMethod<bool>('hasAllFiles') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens Android's "All files access" page for this app (Android 11+),
  /// or asks for storage on older versions.
  Future<void> requestAllFiles() async {
    try {
      await _channel.invokeMethod<void>('requestAllFiles');
    } catch (_) {}
  }

  /// Internal storage first, then any SD cards.
  Future<List<String>> storageRoots() async {
    try {
      final roots = await _channel.invokeListMethod<String>('storageRoots');
      if (roots != null && roots.isNotEmpty) return roots;
    } catch (_) {}
    return const ['/storage/emulated/0'];
  }
}

/// The name of the guide written into the TV folder.
const howToFileName = 'HOW TO ADD SHOWS.txt';

/// What the guide says.
const howToText = '''This is CRT TV's folder. Every folder in here named
"Channel" and a number becomes a channel on the TV:

TV/
  Commercials/            plays between videos on every channel
  Channel 3/              your shows and movies
    Season 1/             (sub-folders are fine)
    Commercials/          only plays on channel 3
  Channel 5 - Cartoons/   the text after the number is the channel's name
  Channel Gojira/         no number: it gets the lowest free one

* Videos play in order (Episode 2 before Episode 10), or shuffled if you
  turn that on for the channel in the Guide.
* Most video types work: mp4, mkv, avi, mov, wmv, webm, mpg, ts and more.
* A channel without its own Commercials folder uses the main one.
* After adding videos, choose RESCAN under TV FOLDER in the TV's menu.

You can also pick another folder: Menu > TV FOLDER > CHOOSE FOLDER.
Your videos are never changed.
''';

/// The TV's default folder on Android: `<storage>/XMB Frontend/TV`, next
/// to the XMB Frontend's ROMs and Comics.
String defaultTvFolder(String storageRoot) =>
    p.join(storageRoot, 'XMB Frontend', 'TV');

/// Makes [dir] (and its parents) and writes [howToFileName] into it if it
/// isn't there yet. Returns false if the folder couldn't be made (no
/// storage access).
bool prepareTvFolder(String dir) {
  try {
    Directory(dir).createSync(recursive: true);
    final guide = File(p.join(dir, howToFileName));
    if (!guide.existsSync()) guide.writeAsStringSync(howToText);
    return true;
  } on FileSystemException {
    return false;
  }
}

/// The folder the TV should start using by itself, or null to leave things
/// as they are: with storage access and no folder [chosen] yet, the
/// default folder on the first storage root, made (with its guide) if
/// needed.
String? startFolder({
  required String? chosen,
  required bool access,
  required List<String> roots,
}) {
  if (chosen != null || !access || roots.isEmpty) return null;
  final dir = defaultTvFolder(roots.first);
  return prepareTvFolder(dir) ? dir : null;
}

/// A folder as the phone's file manager (Samsung's My Files, Files by
/// Google) shows it: `/storage/emulated/0/XMB Frontend/TV` is
/// "Internal storage › XMB Frontend › TV", an SD card's
/// `/storage/1234-ABCD/TV` is "SD card › TV". Anything else stays as is.
String myFilesPath(String dir) {
  final parts = dir
      .replaceAll(r'\', '/')
      .split('/')
      .where((s) => s.isNotEmpty)
      .toList();
  List<String>? rest;
  var where = '';
  if (parts.length >= 3 && parts[0] == 'storage' && parts[1] == 'emulated') {
    where = 'Internal storage';
    rest = parts.sublist(3);
  } else if (parts.length >= 2 &&
      parts[0] == 'storage' &&
      RegExp(r'^[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}$').hasMatch(parts[1])) {
    where = 'SD card';
    rest = parts.sublist(2);
  } else if (parts.isNotEmpty && parts[0] == 'sdcard') {
    where = 'Internal storage';
    rest = parts.sublist(1);
  }
  if (rest == null) return dir;
  return [where, ...rest].join(' › ');
}
