import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Crash-safe file storage in one directory.
///
/// Writes go to a temporary file that is then renamed over the target, and
/// the previous version is kept as `<name>.bak`. If the main file is missing
/// or unreadable, reads fall back to the backup. A crash mid-write can never
/// leave a half-written save.
class AppStorage {
  AppStorage(this.directory);

  final Directory directory;

  File file(String name) => File(p.join(directory.path, name));

  Future<void> writeBytes(String name, List<int> bytes) async {
    await directory.create(recursive: true);
    final target = file(name);
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    if (await target.exists()) {
      await target.copy('${target.path}.bak');
    }
    await tmp.rename(target.path);
  }

  /// Returns the file's bytes, the backup's if the file is missing, or null.
  Future<Uint8List?> readBytes(String name) async {
    for (final f in [file(name), File('${file(name).path}.bak')]) {
      if (await f.exists()) {
        try {
          return await f.readAsBytes();
        } catch (_) {
          // Try the next copy.
        }
      }
    }
    return null;
  }

  Future<void> writeJson(String name, Object? json) =>
      writeBytes(name, utf8.encode(jsonEncode(json)));

  /// Reads JSON, falling back to the backup if the main copy is corrupt.
  Future<Object?> readJson(String name) async {
    for (final f in [file(name), File('${file(name).path}.bak')]) {
      if (!await f.exists()) continue;
      try {
        return jsonDecode(await f.readAsString());
      } catch (_) {
        // Corrupt: try the backup.
      }
    }
    return null;
  }

  Future<void> delete(String name) async {
    for (final f in [file(name), File('${file(name).path}.bak')]) {
      if (await f.exists()) await f.delete();
    }
  }

  Future<bool> exists(String name) => file(name).exists();
}
